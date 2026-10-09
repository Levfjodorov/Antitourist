import 'dart:convert';
import 'dart:io';
import 'package:antitourist/app_store.dart';
import 'package:antitourist/personal_photos.dart';
import 'package:antitourist/place_memory.dart';
import 'package:antitourist/selection.dart';
import 'package:antitourist/walk_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'app_store_test.dart' show MemoryAppStorage, savedFixture;
import 'route_fixtures.dart';

class TestPicker extends ImagePicker {
  TestPicker({this.picked, this.lost});
  final XFile? picked;
  final LostDataResponse? lost;
  int calls = 0;
  @override
  Future<XFile?> pickImage({required ImageSource source, double? maxWidth,
    double? maxHeight, int? imageQuality, CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true}) async { calls++; return picked; }
  @override
  Future<LostDataResponse> retrieveLostData() async => lost ?? LostDataResponse.empty();
}
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Version-one history migrates visits without losing favorites, route or undo', () async {
    final session = WalkSession(sampleRoute())..advance(StopStatus.visited)..advance(StopStatus.skipped);
    final disk = MemoryAppStorage()..contents = jsonEncode({'version': 1,
      'walks': [savedFixture(session).toJson()], 'favorites': [routePlaces.last.toJson()]});
    final store = await AppStore.load(storage: disk);
    expect(store.isVisited(routePlaces.first), isTrue);
    expect(store.isVisited(routePlaces.last), isFalse);
    expect(store.isFavorite(routePlaces.last), isTrue);
    await store.setOnlyNew(true);
    expect(store.canSuggest(routePlaces.first), isFalse);
    expect(store.canSuggest(routePlaces.last), isTrue);
    final restored = await AppStore.load(storage: disk);
    expect(restored.active, isNull);
    expect(restored.history.single.session!.canUndo, isTrue);
    expect(restored.onlyNewPlaces, isTrue);
    expect(jsonDecode(disk.contents!)['version'], 2);
  });
  test('Undo removes walk visits, retains manual marks and deleting a walk retains visits', () async {
    final store = AppStore(storage: MemoryAppStorage());
    final session = WalkSession(sampleRoute())..advance(StopStatus.visited);
    await store.put(savedFixture(session));
    await store.setVisited(routePlaces.first, true);
    session.undo(); await store.put(savedFixture(session));
    expect(store.memory(routePlaces.first)!.walkVisits, isEmpty);
    expect(store.isVisited(routePlaces.first), isTrue);
    await store.setVisited(routePlaces.first, false);
    expect(store.isVisited(routePlaces.first), isFalse);
    session.advance(StopStatus.visited); await store.put(savedFixture(session));
    await store.remove('walk-1');
    expect(store.isVisited(routePlaces.first), isTrue);
  });
  test('Excluded and visited points never return through another-selection fallback', () async {
    final store = AppStore();
    await store.setVisited(routePlaces.first, true); await store.setOnlyNew(true);
    final eligible = routePlaces.where(store.canSuggest).toList();
    final result = anotherSelection(eligible, [routePlaces.first]);
    expect(result, [routePlaces.last]);
    await store.setExcluded(routePlaces.last, true);
    expect(routePlaces.where(store.canSuggest), isEmpty);
    expect(store.canSuggest(routePlaces.last, newOnly: false), isFalse);
  });
  test('Photo survives gallery-cache deletion and cold restart with its note and exclusion', () async {
    final directory = await Directory.systemTemp.createTemp('antitourist-photos-');
    addTearDown(() => directory.delete(recursive: true));
    final temporary = File('${directory.path}/camera.jpg')..writeAsBytesSync([255, 216, 255, 0]);
    final managed = Directory('${directory.path}/managed')..createSync();
    final disk = MemoryAppStorage(), store = AppStore(storage: MemoryAppStorage());
    final persisted = AppStore(storage: disk);
    final photos = PersonalPhotos(directory: managed, picker: TestPicker(picked: XFile(temporary.path)));
    await persisted.saveNote(routePlaces.first, 'Мой вход во двор');
    await persisted.setExcluded(routePlaces.first, true);
    expect(await photos.pick(persisted, routePlaces.first, ImageSource.gallery), isTrue);
    await temporary.delete();
    final restored = await AppStore.load(storage: disk);
    final memory = restored.memory(routePlaces.first)!;
    expect(memory.note, 'Мой вход во двор'); expect(memory.excluded, isTrue);
    expect(await photos.file(memory.photos.single)!.readAsBytes(), [255, 216, 255, 0]);
    expect(photos.file('../camera.jpg'), isNull);
    expect(() => PlaceMemory.fromJson({...memory.toJson(), 'photos': ['../../outside.jpg']}), throwsFormatException);
    store.dispose();
  });
  test('Lost Android photo attaches only to the persisted pending place', () async {
    final directory = await Directory.systemTemp.createTemp('antitourist-lost-');
    addTearDown(() => directory.delete(recursive: true));
    final picked = XFile.fromData(base64Decode('/9j/AA=='), name: 'photo.jpg');
    final disk = MemoryAppStorage(), before = AppStore(storage: MemoryAppStorage());
    final store = AppStore(storage: disk); await store.beginPhoto(routePlaces.last);
    final restored = await AppStore.load(storage: disk);
    final photos = PersonalPhotos(directory: directory,
      picker: TestPicker(lost: LostDataResponse(files: [picked], type: RetrieveType.image)));
    await photos.recover(restored);
    expect(restored.memory(routePlaces.last)!.photos.length, 1);
    expect(restored.memory(routePlaces.first), isNull); expect(restored.pendingPhotoPlace, isNull);
    before.dispose();
  });
  test('Failed state write does not launch gallery; notes remain retryable', () async {
    final disk = MemoryAppStorage()..failWrites = true;
    final store = AppStore(storage: disk), picker = TestPicker();
    final directory = await Directory.systemTemp.createTemp('antitourist-failed-');
    addTearDown(() => directory.delete(recursive: true));
    expect(await PersonalPhotos(directory: directory, picker: picker)
      .pick(store, routePlaces.first, ImageSource.gallery), isFalse);
    expect(picker.calls, 0);
    expect(await store.saveNote(routePlaces.first, 'Сохранить позже'), isFalse);
    disk.failWrites = false; expect(await store.retry(), isTrue);
    expect((await AppStore.load(storage: disk)).memory(routePlaces.first)!.note, 'Сохранить позже');
  });
}
