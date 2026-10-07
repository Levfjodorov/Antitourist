import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'places.dart';
import 'language_settings.dart';
import 'saved_data.dart';

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
        if (value is Map && value['version'] == 1 && value['walks'] is List && value['favorites'] is List) {
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
        valid = previous is Map && previous['version'] == 1 &&
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
      if (data['version'] != 1 || data['walks'] is! List || data['favorites'] is! List) {
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
    final snapshot = jsonEncode({'version': 1,
      'walks': _walks.map((w) => w.toJson()).toList(),
      'favorites': _favorites.map((p) => p.toJson()).toList()});
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
