import 'dart:async';
import 'dart:convert';
import 'package:antitourist/place_details_service.dart';
import 'package:antitourist/places.dart';
import 'package:antitourist/google_place_links.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Place linkedPlace(Map<String, String> tags) => Place(id: 'node/12', name: 'Place',
  category: 'history', lat: 59.437, lon: 24.75, description: 'OSM', score: 70,
  legalAccess: true, tags: tags, osmUrl: Uri.parse('https://www.openstreetmap.org/node/12'));
Map<String, dynamic> photoFixture({String url = 'https://upload.wikimedia.org/example.jpg',
  bool credit = true}) => {'query': {'pages': [{'imageinfo': [{
    'thumburl': url, 'descriptionurl': 'https://commons.wikimedia.org/wiki/File:Place.jpg',
    'mime': 'image/jpeg', 'extmetadata': {
      if (credit) 'Artist': {'value': '<a href="https://example.org">Photo Author</a>'},
      'Credit': {'value': ''}, 'LicenseShortName': {'value': 'CC BY-SA 4.0'},
      'LicenseUrl': {'value': 'https://creativecommons.org/licenses/by-sa/4.0/'},
    },
  }]}]}};
http.Response jsonResponse(Map<String, dynamic> data) => http.Response(jsonEncode(data), 200,
  headers: {'content-type': 'application/json; charset=utf-8'});
Place unlinkedLandmark({String name = 'Raeapteek', Map<String, String> tags = const {}}) => Place(
  id: 'node/345', name: name, category: 'history', lat: 59.437, lon: 24.75,
  description: 'OSM', score: 70, legalAccess: true, tags: tags,
  osmUrl: Uri.parse('https://www.openstreetmap.org/node/345'));
Map<String, dynamic> nearbyArticle({int id = 123, String title = 'Raeapteek',
  String entity = 'Q1841234', double lat = 59.4371, List<String> aliases = const []}) => {
  'pageid': id, 'ns': 0, 'title': title,
  'coordinates': [{'lat': lat, 'lon': 24.75, 'globe': 'earth'}],
  'pageprops': {'wikibase_item': entity},
  'redirects': [for (final alias in aliases) {'title': alias}],
};

void main() {
  test('Coordinate discovery requires a matching title or alias and rejects unrelated or invalid articles', () {
    final place = unlinkedLandmark(tags: {'alt_name': 'Tallinna Raeapteek;Revali Raeapteek'});
    final good = nearbyArticle(title: 'Town Hall Pharmacy', aliases: ['TALLINNA_RAEAPTEEK']);
    final candidates = [
      nearbyArticle(title: 'Nearby Church'), nearbyArticle(lat: 60),
      {...nearbyArticle(id: 2), 'coordinates': []},
      {...nearbyArticle(id: 3), 'pageprops': {'disambiguation': ''}},
      {...nearbyArticle(id: 4), 'ns': 1},
      {...nearbyArticle(id: 5), 'missing': true},
      {...nearbyArticle(id: 6), 'coordinates': [{'lat': 59.437, 'lon': 24.75, 'globe': 'moon'}]},
      {'malformed': true}, good, good,
    ];
    final matches = matchingNearbyArticles({'query': {'pages': candidates}}, place, 'en');
    expect(matches.length, 1); expect(matches.single.title, 'Town Hall Pharmacy');
    expect(matches.single.distance, closeTo(11.1, 1));
    expect(matches.single.wikidata, 'Q1841234');
    expect(matchingNearbyArticles({'query': {'pages': [nearbyArticle(title: 'Monument')]}},
      unlinkedLandmark(name: 'Monument'), 'en'), isEmpty);
  });
  test('An unlinked landmark discovers history and its photo, then prefers the chosen-language article', () async {
    final calls = <Uri>[];
    final service = PlaceDetailsService(client: MockClient((request) async {
      final uri = request.url; calls.add(uri);
      if (uri.host == 'www.wikidata.org') {
        return jsonResponse({'entities': {'Q1841234': {'claims': {'P18': [
          {'rank': 'normal', 'mainsnak': {'datavalue': {'value': 'Place.jpg'}}},
        ]}}}});
      }
      if (uri.host.endsWith('.wikipedia.org') && uri.queryParameters['generator'] == 'geosearch') {
        expect(uri.queryParameters['ggsnamespace'], '0');
        expect(uri.queryParameters['colimit'], '50');
        return jsonResponse({'query': {'pages': uri.host == 'et.wikipedia.org'
          ? [nearbyArticle(), nearbyArticle(id: 9, title: 'Nearby Church', entity: 'Q9')]
          : []}});
      }
      if (uri.host == 'et.wikipedia.org') {
        expect(uri.queryParameters['titles'], 'Raeapteek');
        return jsonResponse({'query': {'pages': [{'title': 'Raeapteek', 'extract': 'Vana apteek.',
          'pageimage': 'Place.jpg', 'langlinks': [{'lang': 'ru', 'title': 'Ратушная аптека'}]}]}});
      }
      if (uri.host == 'ru.wikipedia.org') {
        expect(uri.queryParameters['titles'], 'Ратушная аптека');
        return jsonResponse({'query': {'pages': [{'title': 'Ратушная аптека',
          'fullurl': 'https://ru.wikipedia.org/wiki/Ратушная_аптека',
          'extract': 'Старинная аптека.\n\n== История ==\nРаботает с XV века.'}]}});
      }
      expect(uri.host, 'commons.wikimedia.org');
      expect(uri.queryParameters['titles'], 'File:Place.jpg');
      return jsonResponse(photoFixture());
    }));
    final details = await service.load(unlinkedLandmark(), 'ru');
    expect(details.description, 'Старинная аптека.'); expect(details.textLanguage, 'ru');
    expect(details.sections.single.text, 'Работает с XV века.');
    expect(details.article!.host, 'ru.wikipedia.org'); expect(details.photo, isNotNull);
    expect(details.articleDistanceMeters, closeTo(11.1, 1)); expect(details.partial, isFalse);
    expect(calls.length, 7);
    await service.load(unlinkedLandmark(), 'ru'); expect(calls.length, 7);
    service.close();
  });
  test('Two different matching objects are ambiguous; versions of one entity prefer the app language', () async {
    var ambiguous = true;
    final articleRequests = <Uri>[];
    final service = PlaceDetailsService(client: MockClient((request) async {
      final uri = request.url;
      if (uri.host == 'www.wikidata.org') { return jsonResponse({'entities': {}}); }
      if (uri.host == 'commons.wikimedia.org') { return jsonResponse({'query': {'pages': []}}); }
      if (uri.queryParameters['generator'] == 'geosearch') {
        return jsonResponse({'query': {'pages': [nearbyArticle(
          id: uri.host == 'et.wikipedia.org' ? 2 : 1,
          entity: ambiguous && uri.host == 'et.wikipedia.org' ? 'Q99' : 'Q1841234')]}});
      }
      articleRequests.add(uri);
      return jsonResponse({'query': {'pages': [{'extract': 'Description'}]}});
    }));
    final first = await service.load(unlinkedLandmark(), 'ru');
    expect(first.description, isNull); expect(first.articleDistanceMeters, isNull);
    expect(articleRequests, isEmpty);
    ambiguous = false;
    final second = await service.load(unlinkedLandmark(), 'en');
    expect(second.textLanguage, 'en'); expect(second.articleDistanceMeters, isNotNull);
    expect(articleRequests.single.host, 'en.wikipedia.org'); service.close();
  });
  test('A linked foreign article uses a language link without geographic discovery', () async {
    final service = PlaceDetailsService(client: MockClient((request) async {
      if (request.url.host == 'et.wikipedia.org') {
        expect(request.url.queryParameters['lllang'], 'ru');
        return jsonResponse({'query': {'pages': [{'extract': 'Algtekst.',
          'langlinks': [{'lang': 'ru', 'title': 'Русская статья'}]}]}});
      }
      if (request.url.host == 'ru.wikipedia.org') {
        expect(request.url.queryParameters.containsKey('generator'), isFalse);
        return jsonResponse({'query': {'pages': [{'title': 'Русская статья', 'extract': 'Русский текст.'}]}});
      }
      return jsonResponse({'query': {'pages': []}});
    }));
    final details = await service.load(linkedPlace({'wikipedia': 'et:Koht'}), 'ru');
    expect(details.description, 'Русский текст.'); expect(details.textLanguage, 'ru');
    expect(details.articleDistanceMeters, isNull); service.close();
  });
  test('Localized article failure keeps the original and allows a source retry', () async {
    var russianRequests = 0;
    final service = PlaceDetailsService(client: MockClient((request) async {
      if (request.url.host == 'et.wikipedia.org') {
        return jsonResponse({'query': {'pages': [{'extract': 'Algtekst.',
          'langlinks': [{'lang': 'ru', 'title': 'Русская статья'}]}]}});
      }
      if (request.url.host == 'ru.wikipedia.org') {
        russianRequests++;
        return russianRequests == 1 ? http.Response('unavailable', 503)
          : jsonResponse({'query': {'pages': [{'extract': 'Русский текст.'}]}});
      }
      return jsonResponse({'query': {'pages': []}});
    }));
    final place = linkedPlace({'wikipedia': 'et:Koht'});
    final first = await service.load(place, 'ru');
    expect(first.description, 'Algtekst.'); expect(first.textLanguage, 'et'); expect(first.partial, isTrue);
    final second = await service.load(place, 'ru');
    expect(second.description, 'Русский текст.'); expect(second.partial, isFalse); service.close();
  });
  test('Discovery failure leaves nearby photos available and does not cache the failed lookup', () async {
    var failures = 0;
    final service = PlaceDetailsService(client: MockClient((request) async {
      if (request.url.host == 'ru.wikipedia.org') { failures++; return http.Response('', 503); }
      return jsonResponse({'query': {'pages': request.url.host == 'commons.wikimedia.org'
        ? [{...(photoFixture()['query']['pages'] as List).single as Map, 'ns': 6,
            'coordinates': [{'lat': 59.4371, 'lon': 24.75, 'globe': 'earth'}]}] : []}});
    }));
    final first = await service.load(unlinkedLandmark(), 'ru');
    expect(first.partial, isTrue); expect(first.nearbyPhotos.length, 1);
    expect(first.photo, isNull); expect(first.description, isNull);
    await service.load(unlinkedLandmark(), 'ru'); expect(failures, 2); service.close();
  });
  test('Full linked article includes history and preserves its source language', () async {
    final service = PlaceDetailsService(client: MockClient((request) async {
      if (request.url.host == 'www.wikidata.org') {
        return jsonResponse({'entities': {'Q12': {'sitelinks': {'etwiki': {'title': 'Koht'}}}}});
      }
      if (request.url.host == 'et.wikipedia.org') {
        expect(request.url.queryParameters.containsKey('exintro'), isFalse);
        expect(request.url.queryParameters.containsKey('exchars'), isFalse);
        expect(request.url.queryParameters['exsectionformat'], 'wiki');
        return jsonResponse({'query': {'pages': [{
          'title': 'Koha nimi', 'fullurl': 'https://et.wikipedia.org/wiki/Koha_nimi',
          'extract': 'Koha kirjeldus.\n\n== Ajalugu ==\nEhitatud 1890. aastal.\n\n=== Taastamine ===\nTaastatud 1990. aastal.',
        }]}});
      }
      return jsonResponse({'query': {'pages': []}});
    }));
    final details = await service.load(linkedPlace({'wikidata': 'Q12'}), 'ru');
    expect(details.description, 'Koha kirjeldus.');
    expect(details.sections.map((section) => section.title), ['Ajalugu', 'Taastamine']);
    expect(details.sections.first.text, 'Ehitatud 1890. aastal.');
    expect(details.textLanguage, 'et'); expect(details.articleTitle, 'Koha nimi');
    expect(details.article.toString(), 'https://et.wikipedia.org/wiki/Koha_nimi');
    expect(details.textTruncated, isFalse);
    service.close();
  });
  test('Concurrent openings share downloads while other languages have their own cache', () async {
    var requests = 0;
    final response = Completer<http.Response>();
    final service = PlaceDetailsService(client: MockClient((request) async {
      requests++; return response.future;
    }));
    final place = linkedPlace({});
    final first = service.load(place, 'ru');
    final second = service.load(place, 'ru');
    response.complete(jsonResponse({'query': {'pages': []}}));
    await Future.wait([first, second]);
    await service.load(place, 'ru'); expect(requests, 1);
    await service.load(place, 'et'); expect(requests, 2);
    service.close();
  });
  test('Long article text is bounded without breaking Unicode and marks shortening', () {
    final text = parseArticleText('Intro\n\n== History ==\n${List.filled(25000, '😀').join()}');
    expect(text.lead, 'Intro'); expect(text.sections.single.title, 'History');
    expect(text.truncated, isTrue);
    expect(text.sections.single.text.runes.every((rune) => rune == 0x1f600), isTrue);
  });
  test('Photos require Commons source, Wikimedia image host and attribution', () {
    final photo = parseCommonsPhoto(photoFixture())!;
    expect(photo.credit, 'Photo Author'); expect(photo.license, 'CC BY-SA 4.0');
    expect(parseCommonsPhoto(photoFixture(credit: false)), isNull);
    final withoutAuthor = photoFixture(credit: false);
    (withoutAuthor['query']['pages'][0]['imageinfo'][0]['extmetadata'] as Map)['Credit'] = {'value': 'Own work'};
    expect(parseCommonsPhoto(withoutAuthor), isNull);
    expect(parseCommonsPhoto(photoFixture(url: 'https://unrelated.example/photo.jpg')), isNull);
    final attribution = photoFixture();
    (attribution['query']['pages'][0]['imageinfo'][0]['extmetadata'] as Map)['Attribution'] = {'value': 'Required &amp; custom credit'};
    expect(parseCommonsPhoto(attribution)!.credit, 'Required & custom credit');
  });
  test('Exact Wikidata link supplies P18 and the article in the chosen language', () async {
    final calls = <Uri>[];
    final service = PlaceDetailsService(client: MockClient((request) async {
      calls.add(request.url);
      if (request.url.host == 'www.wikidata.org') {
        return jsonResponse({'entities': {'Q12': {'claims': {'P18': [
          {'rank': 'normal', 'mainsnak': {'datavalue': {'value': 'Place.jpg'}}},
        ]}, 'sitelinks': {'etwiki': {'title': 'Koht'}}}}});
      }
      if (request.url.host == 'et.wikipedia.org') {
        expect(request.url.queryParameters['titles'], 'Koht');
        return jsonResponse({'query': {'pages': [{'extract': 'Koha kirjeldus.'}]}});
      }
      expect(request.url.host, 'commons.wikimedia.org');
      expect(request.url.queryParameters['titles'], 'File:Place.jpg');
      return jsonResponse(photoFixture());
    }));
    final place = linkedPlace({'wikidata': 'Q12'});
    final details = await service.load(place, 'et');
    expect(details.description, 'Koha kirjeldus.');
    expect(details.article!.host, 'et.wikipedia.org');
    expect(details.photo, isNotNull); expect(details.partial, isFalse);
    expect(calls.length, 3);
    await service.load(place, 'et'); expect(calls.length, 3);
    expect(calls.every((u) => !u.toString().contains('59.437')), isTrue);
    service.close();
  });
  test('Unlinked places use geographic nearby photos without guessed brand or name matches', () async {
    var requests = 0;
    final service = PlaceDetailsService(client: MockClient((request) async {
      requests++;
      expect(request.url.queryParameters['generator'], 'geosearch');
      expect(request.url.queryParameters['ggscoord'], '59.437|24.75');
      return jsonResponse({'query': {'pages': []}});
    }));
    final details = await service.load(linkedPlace({'brand:wikidata': 'Q12',
      'image': 'https://random.example/photo.jpg'}), 'en');
    expect(details.photo, isNull); expect(details.nearbyPhotos, isEmpty); expect(requests, 1); service.close();
  });
  test('A partial network failure is reported and permits retry', () async {
    var requests = 0;
    final service = PlaceDetailsService(client: MockClient((request) async {
      if (request.url.queryParameters['generator'] == 'geosearch') {
        return jsonResponse({'query': {'pages': []}});
      }
      requests++;
      return requests == 1 ? http.Response('unavailable', 503) : jsonResponse(photoFixture());
    }));
    final place = linkedPlace({'wikimedia_commons': 'File:Place.jpg'});
    expect((await service.load(place, 'ru')).partial, isTrue);
    final again = await service.load(place, 'ru');
    expect(again.photo, isNotNull); expect(again.partial, isFalse); expect(requests, 2);
    service.close();
  });
  test('Metadata is plain text and unsafe links are not used', () {
    expect(metadataText('<b>A &amp; B</b>'), 'A & B');
    expect(safeWebUrl('javascript:alert(1)'), isNull);
    expect(safeWebUrl('https://user:password@example.com/'), isNull);
  });
  test('Wikipedia page images work even when the OSM object has no Wikidata tag', () async {
    var calls = 0;
    final service = PlaceDetailsService(client: MockClient((request) async {
      calls++;
      if (request.url.host == 'en.wikipedia.org') {
        expect(request.url.queryParameters['prop'], 'extracts|pageimages|info|langlinks|pageprops');
        return jsonResponse({'query': {'pages': [{'extract': 'Description', 'pageimage': 'Place.jpg'}]}});
      }
      expect(request.url.queryParameters['titles'], 'File:Place.jpg');
      return jsonResponse(photoFixture());
    }));
    final details = await service.load(linkedPlace({'wikipedia': 'en:Place'}), 'en');
    expect(details.photo, isNotNull); expect(details.nearbyPhotos, isEmpty); expect(calls, 2);
    service.close();
  });
  test('Nearby images keep their distance and attribution and reject distant or unlocated files', () {
    final page = (photoFixture()['query']['pages'] as List).first as Map;
    Map<String, dynamic> located(int id, double latitude) => {
      ...Map<String, dynamic>.from(page), 'ns': 6, 'pageid': id,
      'coordinates': [{'lat': latitude, 'lon': 24.7536, 'globe': 'earth'}],
    };
    final result = parseNearbyPhotos({'query': {'pages': [
      {'ns': 6}, located(1, 60), located(2, 59.4371),
    ]}}, tallinnStart);
    expect(result.length, 1); expect(result.single.nearbyMeters, closeTo(11.1, 1));
    expect(result.single.credit, 'Photo Author'); expect(result.single.license, 'CC BY-SA 4.0');
  });
  test('Google Maps links encode names and addresses without API keys', () {
    final uri = googlePlaceSearch(linkedPlace({'addr:street': 'Pikk', 'addr:housenumber': '1',
      'addr:city': 'Tallinn'}), 'Место & café');
    expect(uri.host, 'www.google.com'); expect(uri.queryParameters['api'], '1');
    expect(uri.queryParameters['query'], 'Место & café, Pikk, 1, Tallinn');
    expect(uri.queryParameters.containsKey('key'), isFalse);
    expect(googlePlaceSearch(linkedPlace({}), 'Place').queryParameters['query'], contains('59.437000,24.750000'));
  });

}
