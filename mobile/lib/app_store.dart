import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'places.dart';
import 'language_settings.dart';
import 'saved_data.dart';
import 'place_memory.dart';
import 'walk_session.dart';

abstract interface class AppStorage {
  Future<String?> read();
  Future<void> write(String contents);
}

// Keep the previous complete file until the flushed replacement is ready.
class FileAppStorage implements AppStorage {
  FileAppStorage(this.file);
  final File file;
  bool recovered = false;
  File get backup => File('${file.path}.bak');
  @override
  Future<String?> read() async {
    recovered = false;
    for (final candidate in [file, backup]) {
      if (!await candidate.exists()) { continue; }
      try {
        final contents = await candidate.readAsString();
        final value = jsonDecode(contents);
        if (value is Map && [1, 2].contains(value['version']) && value['walks'] is List && value['favorites'] is List) {
          recovered = candidate.path == backup.path;
          return contents;
        }
      } catch (_) { /* Try the last successful file. */ }
    }
    if (await file.exists() || await backup.exists()) {
      throw const FormatException('Unreadable saved data');
    }
    return null;
  }
  @override
  Future<void> write(String contents) async {
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(contents, flush: true);
    if (await file.exists()) {
      var valid = false;
      try {
        final previous = jsonDecode(await file.readAsString());
        valid = previous is Map && [1, 2].contains(previous['version']) &&
          previous['walks'] is List && previous['favorites'] is List;
      } catch (_) { /* Preserve a healthy backup after recovering a damaged file. */ }
      if (valid) { await file.copy(backup.path); }
    }
    await temporary.rename(file.path);
  }
}

class AppStore extends ChangeNotifier {
  AppStore({this.storage});
  final AppStorage? storage;
  final _walks = <SavedWalk>[];
  final _favorites = <Place>[];
  final _memories = <String, PlaceMemory>{};
  String? pendingPhotoPlace;
  bool onlyNewPlaces = false;
  Future<void> _writes = Future<void>.value();
  bool saveFailed = false, loadFailed = false;
  static Future<AppStore> load({AppStorage? storage}) async {
    AppStore result;
    AppStorage? target = storage;
    try {
      target ??= FileAppStorage(File(
        '${(await getApplicationSupportDirectory()).path}/antitourist-state.json'));
      result = AppStore(storage: target);
      final contents = await target.read();
      if (contents == null) { return result; }
      result.loadFailed = target is FileAppStorage && target.recovered;
      final data = jsonDecode(contents) as Map<String, dynamic>;
      if (![1, 2].contains(data['version']) || data['walks'] is! List || data['favorites'] is! List) {
        throw const FormatException('Unsupported saved data');
      }
      for (final raw in data['walks'] as List) {
        try {
          final walk = SavedWalk.fromJson(Map<String, dynamic>.from(raw as Map));
          if (!result._walks.any((w) => w.id == walk.id)) { result._walks.add(walk); }
        } catch (_) { result.loadFailed = true; }
      }
      for (final raw in data['favorites'] as List) {
        try {
          final place = readPlaces([raw]).single;
          if (!result.isFavorite(place)) { result._favorites.add(place); }
        } catch (_) { result.loadFailed = true; }
      }
      final memories = data['memories'];
      if (memories is List) {
        for (final raw in memories.take(10000)) {
          try {
            final memory = PlaceMemory.fromJson(Map<String, dynamic>.from(raw as Map));
            result._memories[memory.place.key] = memory;
          } catch (_) { result.loadFailed = true; }
        }
      }
      result.onlyNewPlaces = data['onlyNewPlaces'] == true;
      final pending = data['pendingPhotoPlace'];
      if (pending is String && result._memories.containsKey(pending)) { result.pendingPhotoPlace = pending; }
      // Migrate older walk history and keep undo consistent with personal marks.
      for (final walk in result._walks) { result._syncVisits(walk); }
      return result;
    } catch (_) {
      // Never silently report a successful save if the app directory is unavailable.
      result = AppStore(storage: target);
      result.loadFailed = true;
      result.saveFailed = target == null;
      return result;
    }
  }
  List<SavedWalk> get walks => List.unmodifiable(_walks);
  List<SavedWalk> get saved => walks.where((w) => !w.complete).toList();
  List<SavedWalk> get history => walks.where((w) => w.complete).toList();
  List<Place> get favorites => List.unmodifiable(_favorites);
  List<PlaceMemory> get memories => List.unmodifiable(_memories.values);
  List<Place> get visitedPlaces => memories.where((m) => m.visited).map((m) => m.place).toList();
  Set<String> get excludedKeys => memories.where((m) => m.excluded).map((m) => m.place.key).toSet();
  Set<String> get visitedKeys => memories.where((m) => m.visited).map((m) => m.place.key).toSet();
  PlaceMemory? memory(Place place) => _memories[place.key];
  bool isVisited(Place place) => memory(place)?.visited ?? false;
  bool isExcluded(Place place) => memory(place)?.excluded ?? false;
  bool canSuggest(Place place, {bool? newOnly}) => !isExcluded(place) &&
    (!(newOnly ?? onlyNewPlaces) || !isVisited(place));
  PlaceMemory _remember(Place place) => _memories.putIfAbsent(place.key, () => PlaceMemory(place: place));
  Future<bool> setOnlyNew(bool value) { onlyNewPlaces = value; return _persist(); }
  Future<bool> setVisited(Place place, bool value) {
    _remember(place).manualVisit = value ? DateTime.now().toUtc() : null;
    return _persist();
  }
  Future<bool> setExcluded(Place place, bool value) { _remember(place).excluded = value; return _persist(); }
  Future<bool> saveNote(Place place, String note) {
    if (note.runes.length > 6000) { throw const FormatException('Note too long'); }
    _remember(place).note = note.trim(); return _persist();
  }
  Future<bool> beginPhoto(Place place) {
    _remember(place); pendingPhotoPlace = place.key; return _persist();
  }
  Future<bool> cancelPhoto() { pendingPhotoPlace = null; return _persist(); }
  Future<bool> finishPhoto(String name) {
    if (!validPhotoName(name)) { throw const FormatException('Invalid personal photo'); }
    final record = _memories[pendingPhotoPlace];
    if (record == null || record.photos.length >= 20) { throw StateError('Photo target unavailable'); }
    if (!record.photos.contains(name)) { record.photos.add(name); }
    pendingPhotoPlace = null; return _persist();
  }
  Future<bool> removePhoto(Place place, String name) {
    _remember(place).photos.remove(name); return _persist();
  }
  void _syncVisits(SavedWalk walk) {
    final session = walk.session;
    final visited = <String>{};
    if (session != null) {
      for (var i = 0; i < session.route.places.length; i++) {
        if (session.statuses[i] == StopStatus.visited) {
          final memory = _remember(session.route.places[i]);
          memory.walkVisits.putIfAbsent(walk.id, () => walk.updated.toUtc());
          visited.add(memory.place.key);
        }
      }
    }
    for (final memory in _memories.values) {
      if (!visited.contains(memory.place.key)) { memory.walkVisits.remove(walk.id); }
    }
  }
  SavedWalk? get active {
    for (final walk in _walks) {
      if (!walk.complete && walk.session != null) { return walk; }
    }
    return null;
  }
  SavedWalk? byId(String id) {
    for (final walk in _walks) { if (walk.id == id) { return walk; } }
    return null;
  }
  bool isFavorite(Place place) => _favorites.any((p) => p.key == place.key);
  Future<bool> toggleFavorite(Place place) {
    if (isFavorite(place)) { _favorites.removeWhere((p) => p.key == place.key); }
    else { _favorites.insert(0, place); }
    return _persist();
  }
  Future<bool> put(SavedWalk walk) {
    _syncVisits(walk);
    _walks.removeWhere((w) => w.id == walk.id);
    _walks.insert(0, walk);
    return _persist();
  }
  Future<bool> remove(String id) {
    _walks.removeWhere((w) => w.id == id);
    return _persist();
  }
  Future<bool> retry() => _persist();
  Future<bool> _persist() {
    final snapshot = jsonEncode({'version': 2,
      'walks': _walks.map((w) => w.toJson()).toList(),
      'favorites': _favorites.map((p) => p.toJson()).toList(),
      'memories': _memories.values.map((m) => m.toJson()).toList(),
      'onlyNewPlaces': onlyNewPlaces, 'pendingPhotoPlace': pendingPhotoPlace});
    notifyListeners();
    final operation = _writes.then((_) async {
      try {
        if (storage == null && saveFailed) { throw StateError('Storage unavailable'); }
        await storage?.write(snapshot);
        saveFailed = false;
        loadFailed = false;
        notifyListeners();
        return true;
      } catch (_) {
        saveFailed = true;
        notifyListeners();
        return false;
      }
    });
    _writes = operation.then<void>((_) {});
    return operation;
  }
}

class AppStoreScope extends InheritedNotifier<AppStore> {
  const AppStoreScope({super.key, required AppStore store, required super.child}) : super(notifier: store);
  static AppStore? of(BuildContext context) =>
    context.dependOnInheritedWidgetOfExactType<AppStoreScope>()?.notifier;
}

class StorageNotice extends StatelessWidget {
  const StorageNotice({super.key});
  @override
  Widget build(BuildContext context) {
    final store = AppStoreScope.of(context);
    if (store == null || (!store.saveFailed && !store.loadFailed)) { return const SizedBox.shrink(); }
    return Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (store.loadFailed) Text(context.strings.t('dataLoadError')),
        if (store.saveFailed) Text(context.strings.t('dataSaveError')),
        if (store.saveFailed) TextButton(onPressed: store.retry,
          child: Text(context.strings.t('retrySave'))),
      ])));
  }
}
