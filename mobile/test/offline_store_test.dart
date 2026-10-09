import 'dart:convert';
import 'dart:io';
import 'package:antitourist/offline_map.dart';
import 'package:antitourist/offline_store.dart';
import 'package:antitourist/place_details_screen.dart';
import 'package:antitourist/place_details_service.dart';
import 'package:antitourist/place_translation_service.dart';
import 'package:antitourist/places.dart';
import 'package:antitourist/route_map.dart';
import 'package:antitourist/saved_data.dart';
import 'package:antitourist/walking_route.dart';
import 'package:antitourist/walk_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'app_store_test.dart' show savedFixture;
import 'route_fixtures.dart';

final photo = PlacePhoto(url: Uri.parse('https://upload.wikimedia.org/wikipedia/commons/a/a1/Test.png'),
  source: Uri.parse('https://commons.wikimedia.org/wiki/File:Test.png'), credit: 'Original photographer',
  license: 'CC BY-SA 4.0', licenseUrl: Uri.parse('https://creativecommons.org/licenses/by-sa/4.0/'));
final png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=');
class FixtureDetails extends PlaceDetailsService {
  int calls = 0;
  bool fail = false;
  @override
  Future<PlaceDetails> load(Place place, String language) async {
    calls++; if (fail) { throw StateError('network must remain unused'); }
    return PlaceDetails(description: 'Ajalugu', textLanguage: 'et', photo: photo,
      article: Uri.parse('https://et.wikipedia.org/wiki/Test'), articleTitle: 'Test');
  }
}
class FixtureTranslator implements PlaceTextTranslator {
  int calls = 0;
  @override
  Future<TranslatedPlaceText> translate(PlaceDetails original, String targetLanguage, {bool allowMobileData = false}) async {
    calls++; return const TranslatedPlaceText(description: 'Сохранённая история', sections: []);
  }
}
class FixtureMap extends OfflineMapService {
  int calls = 0;
  @override
  Future<List<OfflineStreet>> load(WalkingRoute route) async {
    calls++; return [OfflineStreet('road', route.geometry)];
  }
}
Future<Directory> temporary() async => Directory.systemTemp.createTemp('antitourist-offline-');
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Cold restart restores translated text, photo credits, local image and street geometry', () async {
    final directory = await temporary(); addTearDown(() => directory.delete(recursive: true));
    var downloads = 0;
    final details = FixtureDetails(), map = FixtureMap(), translator = FixtureTranslator();
    final store = OfflineStore(directory: directory, detailsService: details, mapService: map, translator: translator,
      client: MockClient((_) async { downloads++; return http.Response.bytes(png, 200, headers: {'content-type': 'image/png'}); }));
    final walk = savedFixture(WalkSession(sampleRoute()));
    expect(await store.prepare(walk, 'ru'), isTrue); expect(downloads, 1);
    final restored = await OfflineStore.load(directory: directory);
    expect(restored.ready(walk.id, sampleRoute(), 'ru'), isTrue);
    expect(restored.ready(walk.id, sampleRoute(), 'en'), isFalse);
    final cached = restored.place(routePlaces.first, 'ru')!;
    expect(cached.translated!.description, 'Сохранённая история');
    expect(cached.details.photo!.credit, 'Original photographer');
    expect(cached.details.photo!.license, 'CC BY-SA 4.0');
    expect(await File(cached.details.photo!.localPath!).readAsBytes(), png);
    expect(restored.streets(sampleRoute())!.single.points.length, sampleRoute().geometry.length);
    expect(details.calls, 2); expect(translator.calls, 2); expect(map.calls, 1);
  });
  testWidgets('Restored place and map work with a service that throws on every network call', (tester) async {
    final setup = await tester.runAsync(() async {
      final directory = await temporary();
      final store = OfflineStore(directory: directory, detailsService: FixtureDetails(),
        translator: FixtureTranslator(), mapService: FixtureMap(),
        client: MockClient((_) async => http.Response.bytes(png, 200, headers: {'content-type': 'image/png'})));
      final walk = savedFixture(WalkSession(sampleRoute()));
      expect(await store.prepare(walk, 'ru'), isTrue);
      return (directory: directory, walk: walk, store: await OfflineStore.load(directory: directory));
    });
    final directory = setup!.directory, walk = setup.walk, restored = setup.store;
    addTearDown(() => directory.delete(recursive: true));
    final offlineService = FixtureDetails()..fail = true;
    await tester.pumpWidget(OfflineScope(store: restored, child: MaterialApp(home: PlaceDetailsScreen(
      place: routePlaces.first, demo: false, service: offlineService))));
    await tester.pumpAndSettle();
    final scroll = find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(find.text('Сохранённая история'), 150, scrollable: scroll);
    expect(find.text('Сохранённая история'), findsOneWidget); expect(offlineService.calls, 0);
    await tester.pumpWidget(OfflineScope(store: restored, child: MaterialApp(home: RouteMap(
      places: walk.places, demo: false, start: walk.start, route: sampleRoute()))));
    await tester.pumpAndSettle(); expect(find.byType(TileLayer), findsNothing);
    expect(find.byType(PolylineLayer), findsNWidgets(2)); expect(tester.takeException(), isNull);
  });
  test('Missing photo reports partial preparation and retry downloads the missing content', () async {
    final directory = await temporary(); addTearDown(() => directory.delete(recursive: true));
    var fail = true;
    final map = FixtureMap();
    final store = OfflineStore(directory: directory, detailsService: FixtureDetails(), mapService: map,
      translator: FixtureTranslator(), client: MockClient((_) async => fail ? http.Response('unavailable', 503)
        : http.Response.bytes(png, 200, headers: {'content-type': 'image/png'})));
    final walk = savedFixture(WalkSession(sampleRoute()));
    expect(await store.prepare(walk, 'ru'), isFalse);
    expect(store.place(routePlaces.first, 'ru'), isNotNull);
    expect(store.ready(walk.id, sampleRoute(), 'ru'), isFalse);
    fail = false; expect(await store.prepare(walk, 'ru'), isTrue);
    expect(map.calls, 1); expect(store.ready(walk.id, sampleRoute(), 'ru'), isTrue);
  });
  test('Deleting one offline walk preserves shared photo files and the other walk', () async {
    final directory = await temporary(); addTearDown(() => directory.delete(recursive: true));
    final store = OfflineStore(directory: directory, detailsService: FixtureDetails(), mapService: FixtureMap(),
      translator: FixtureTranslator(), client: MockClient((_) async => http.Response.bytes(png, 200, headers: {'content-type': 'image/png'})));
    final first = savedFixture(WalkSession(sampleRoute()));
    final second = SavedWalk.fromJson({...first.toJson(), 'id': 'walk-2'});
    expect(await store.prepare(first, 'ru'), isTrue);
    expect(await store.prepare(second, 'ru'), isTrue);
    final file = store.place(routePlaces.first, 'ru')!.details.photo!.localPath!;
    final restored = await OfflineStore.load(directory: directory);
    expect(await restored.remove(first.id), isTrue); expect(File(file).existsSync(), isTrue);
    expect(await restored.remove('walk-2'), isTrue); expect(File(file).existsSync(), isFalse);
  });
  test('Unreadable index recovers the last successful index without trusting arbitrary paths', () async {
    final directory = await temporary(); addTearDown(() => directory.delete(recursive: true));
    final store = OfflineStore(directory: directory, detailsService: FixtureDetails(), mapService: FixtureMap(),
      translator: FixtureTranslator(), client: MockClient((_) async => http.Response.bytes(png, 200, headers: {'content-type': 'image/png'})));
    await store.prepare(savedFixture(WalkSession(sampleRoute())), 'ru');
    expect(store.photoFile('../secret'), isNull);
    await File('${directory.path}/index.json').writeAsString('{broken');
    final restored = await OfflineStore.load(directory: directory);
    expect(restored.loadFailed, isTrue); expect(restored.place(routePlaces.first, 'ru'), isNotNull);
  });
  test('Overpass partial responses and malformed map coordinates are rejected', () {
    expect(() => parseOfflineStreets({'elements': [], 'remark': 'timed out'}), throwsFormatException);
    expect(() => OfflineStreet.fromJson({'kind': 'road', 'points': [[999, 24], [59, 24]]}), throwsFormatException);
  });
}
