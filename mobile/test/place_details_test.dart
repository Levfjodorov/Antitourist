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

void main() {
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
        expect(request.url.queryParameters['prop'], 'extracts|pageimages|info');
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
