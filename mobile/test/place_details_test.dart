import 'dart:convert';
import 'package:antitourist/place_details_service.dart';
import 'package:antitourist/places.dart';
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
  test('Unlinked places and brand identifiers do not trigger guessed photo searches', () async {
    var requests = 0;
    final service = PlaceDetailsService(client: MockClient((_) async {
      requests++; return jsonResponse({});
    }));
    final details = await service.load(linkedPlace({'brand:wikidata': 'Q12',
      'image': 'https://random.example/photo.jpg'}), 'en');
    expect(details.photo, isNull); expect(requests, 0); service.close();
  });
  test('A partial network failure is reported and permits retry', () async {
    var requests = 0;
    final service = PlaceDetailsService(client: MockClient((_) async {
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
}
