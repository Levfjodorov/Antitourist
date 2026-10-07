import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:antitourist/app_store.dart';
import 'package:antitourist/places.dart';
import 'package:antitourist/saved_data.dart';
import 'package:antitourist/walk_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'route_fixtures.dart';

class MemoryAppStorage implements AppStorage {
  String? contents;
  bool failWrites = false;
  final writes = <String>[];
  Completer<void>? gate;
  @override
  Future<String?> read() async => contents;
  @override
  Future<void> write(String value) async {
    final wait = gate; gate = null;
    if (wait != null) { await wait.future; }
    if (failWrites) { throw StateError('disk full'); }
    writes.add(value); contents = value;
  }
}
SavedWalk savedFixture(WalkSession session) => SavedWalk(id: 'walk-1', start: tallinnStart,
  places: session.route.places, candidates: routePlaces, demo: false, requestedMinutes: 60,
  created: DateTime.utc(2026, 10, 7), updated: DateTime.utc(2026, 10, 7), session: session);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Cold restart restores geometry, stops, favorites and undo history', () async {
    final disk = MemoryAppStorage();
    final store = await AppStore.load(storage: disk);
    final session = WalkSession(sampleRoute())..advance(StopStatus.visited);
    expect(await store.put(savedFixture(session)), isTrue);
    await store.toggleFavorite(routePlaces.first);
    final restored = await AppStore.load(storage: disk);
    expect(restored.active!.session!.currentIndex, 1);
    expect(restored.active!.session!.visited, 1);
    expect(restored.active!.session!.route.geometry.length, sampleRoute().geometry.length);
    expect(restored.isFavorite(routePlaces.first), isTrue);
    restored.active!.session!.undo();
    expect(restored.active!.session!.currentIndex, 0);
    expect(restored.active!.session!.canUndo, isFalse);
    store.dispose(); restored.dispose();
  });
  test('Completion enters history once; undo returns it to saved walks', () async {
    final disk = MemoryAppStorage();
    final store = await AppStore.load(storage: disk);
    final session = WalkSession(sampleRoute())
      ..advance(StopStatus.visited)..advance(StopStatus.skipped);
    await store.put(savedFixture(session)); await store.put(savedFixture(session));
    final restored = await AppStore.load(storage: disk);
    expect(restored.history.length, 1);
    expect(restored.saved, isEmpty);
    final again = restored.history.single.session!..undo();
    await restored.put(savedFixture(again));
    expect(restored.history, isEmpty); expect(restored.saved.length, 1);
    await restored.remove('walk-1');
    expect((await AppStore.load(storage: disk)).walks, isEmpty);
    store.dispose(); restored.dispose();
  });
  test('Failed writes are visible and can be retried', () async {
    final disk = MemoryAppStorage()..failWrites = true;
    final store = await AppStore.load(storage: disk);
    expect(await store.toggleFavorite(routePlaces.first), isFalse);
    expect(store.saveFailed, isTrue);
    disk.failWrites = false;
    expect(await store.retry(), isTrue);
    expect((await AppStore.load(storage: disk)).favorites.length, 1);
    store.dispose();
  });
  test('Queued writes cannot overwrite a newer snapshot with an older one', () async {
    final disk = MemoryAppStorage();
    final store = await AppStore.load(storage: disk);
    final gate = Completer<void>(); disk.gate = gate;
    final first = store.toggleFavorite(routePlaces.first);
    final second = store.toggleFavorite(routePlaces.last);
    gate.complete();
    await Future.wait([first, second]);
    expect(disk.writes.length, 2);
    expect((await AppStore.load(storage: disk)).favorites.length, 2);
    store.dispose();
  });
  test('An invalid record is isolated without losing healthy saved data', () async {
    final disk = MemoryAppStorage()..contents = jsonEncode({'version': 1,
      'walks': [{'id': 'broken'}, savedFixture(WalkSession(sampleRoute())).toJson()],
      'favorites': [routePlaces.first.toJson()]});
    final store = await AppStore.load(storage: disk);
    expect(store.walks.length, 1); expect(store.favorites.length, 1);
    expect(store.loadFailed, isTrue); store.dispose();
  });
  test('Corrupt route dimensions and undo indexes are rejected', () {
    final raw = encodeSession(WalkSession(sampleRoute()));
    raw['snapped'] = [];
    expect(() => decodeSession(raw), throwsFormatException);
    expect(() => WalkSession.restore(sampleRoute(), ['visited', 'pending'], [5]), throwsFormatException);
  });
  test('File storage recovers the previous valid file after a damaged write', () async {
    final directory = await Directory.systemTemp.createTemp('antitourist-test-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/state.json');
    final storage = FileAppStorage(file);
    final first = jsonEncode({'version': 1, 'walks': [], 'favorites': []});
    final second = jsonEncode({'version': 1, 'walks': [], 'favorites': [routePlaces.first.toJson()]});
    await storage.write(first); await storage.write(second);
    await file.writeAsString('{broken');
    expect(await storage.read(), first);
  });
  test('Saved places preserve source facts and translations', () {
    final place = Place(id: 'node/99', name: 'Name', category: 'history', lat: 59.437,
      lon: 24.75, description: 'Text', score: 70, legalAccess: true, distance: 40,
      coordinateIsCenter: true, osmUrl: Uri.parse('https://www.openstreetmap.org/node/99'),
      tags: const {'opening_hours': '24/7', 'wikidata': 'Q99', 'name:et': 'Nimi'},
      localizedNames: const {'en': 'English name'});
    final copy = Place.fromJson(jsonDecode(jsonEncode(place.toJson())) as Map<String, dynamic>);
    expect(copy.tags, place.tags); expect(copy.osmUrl, place.osmUrl);
    expect(copy.localizedNames, place.localizedNames); expect(copy.distance, 40);
    expect(copy.coordinateIsCenter, isTrue);
  });
}
