import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'offline_map.dart';
import 'place_details_service.dart';
import 'place_information.dart';
import 'place_translation_service.dart';
import 'places.dart';
import 'saved_data.dart';
import 'walking_route.dart';

String routeFingerprint(WalkingRoute route) => sha256.convert(utf8.encode(jsonEncode({
  'places': route.places.map((p) => p.key).toList(),
  'geometry': [for (final p in route.geometry) [p.lat, p.lon]],
}))).toString();

class OfflinePlace {
  const OfflinePlace(this.details, this.translated, this.saved, this.complete);
  final PlaceDetails details;
  final TranslatedPlaceText? translated;
  final DateTime saved;
  final bool complete;
}

// All file paths come from this store; downloaded JSON never provides a path.
class OfflineStore extends ChangeNotifier {
  OfflineStore({this.directory, http.Client? client, PlaceDetailsService? detailsService,
    PlaceTextTranslator? translator, OfflineMapService? mapService})
    : client = client ?? http.Client(), detailsService = detailsService ?? PlaceDetailsService.shared,
      translator = translator ?? PlaceTranslationService.shared, mapService = mapService ?? OfflineMapService();
  final Directory? directory;
  final http.Client client;
  final PlaceDetailsService detailsService;
  final PlaceTextTranslator translator;
  final OfflineMapService mapService;
  final _entries = <String, Map<String, dynamic>>{};
  final _maps = <String, List<OfflineStreet>>{};
  final _walks = <String, Map<String, dynamic>>{};
  bool busy = false, saveFailed = false, loadFailed = false;
  int done = 0, total = 0;
  Future<void> _writes = Future.value();
  bool get available => directory != null;
  static Future<OfflineStore> load({Directory? directory}) async {
    OfflineStore result;
    try {
      directory ??= Directory('${(await getApplicationSupportDirectory()).path}/offline');
      await directory.create(recursive: true);
      result = OfflineStore(directory: directory);
      for (final name in ['index.json', 'index.json.bak']) {
        final file = File('${directory.path}/$name');
        if (!await file.exists()) { continue; }
        try {
          final data = jsonDecode(await file.readAsString()) as Map;
          if (data['version'] != 1 || data['entries'] is! Map || data['maps'] is! Map || data['walks'] is! Map) {
            throw const FormatException('Unsupported offline index');
          }
          for (final entry in (data['entries'] as Map).entries.take(10000)) {
            try {
              final value = Map<String, dynamic>.from(entry.value as Map);
              result._decode(value); result._entries[entry.key as String] = value;
            } catch (_) { result.loadFailed = true; }
          }
          for (final entry in (data['maps'] as Map).entries.take(100)) {
            try {
              if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(entry.key as String) ||
                  entry.value is! List || (entry.value as List).length > 12000) { continue; }
              result._maps[entry.key as String] = (entry.value as List).map((v) =>
                OfflineStreet.fromJson(Map<String, dynamic>.from(v as Map))).toList();
            } catch (_) { result.loadFailed = true; }
          }
          for (final entry in (data['walks'] as Map).entries.take(1000)) {
            result._walks[entry.key as String] = Map<String, dynamic>.from(entry.value as Map);
          }
          result.loadFailed = result.loadFailed || name.endsWith('.bak');
          return result;
        } catch (_) { result.loadFailed = true; }
      }
      return result;
    } catch (_) { result = OfflineStore(); result.loadFailed = true; return result; }
  }
  String _key(Place place, String language) => '${place.key}:$language';
  File? photoFile(String? name) => directory != null && name != null &&
    RegExp(r'^[a-f0-9]{64}\.img$').hasMatch(name) ? File('${directory!.path}/$name') : null;
  OfflinePlace? place(Place place, String language) {
    final data = _entries[_key(place, language)];
    if (data == null) { return null; }
    try { return _decode(data); } catch (_) { return null; }
  }
  List<OfflineStreet>? streets(WalkingRoute route) => _maps[routeFingerprint(route)];
  bool ready(String? id, WalkingRoute route, String language) {
    if (saveFailed) { return false; }
    final manifest = _walks[id];
    return manifest?['route'] == routeFingerprint(route) && manifest?['language'] == language &&
      manifest?['complete'] == true && streets(route)?.isNotEmpty == true &&
      route.places.every((p) => place(p, language)?.complete == true);
  }
  Map<String, dynamic> _photo(PlacePhoto p, String? file) => {
    'url': p.url.toString(), 'source': p.source.toString(), 'credit': p.credit,
    'license': p.license, 'licenseUrl': p.licenseUrl?.toString(), 'caption': p.caption,
    'nearbyMeters': p.nearbyMeters, 'file': file,
  };
  PlacePhoto _readPhoto(Map data) {
    final url = safeWebUrl(data['url'] as String?), source = safeWebUrl(data['source'] as String?);
    if (url == null || source == null || data['credit'] is! String || data['license'] is! String) {
      throw const FormatException('Invalid cached photo');
    }
    final file = photoFile(data['file'] as String?) ?? photoFile('${sha256.convert(utf8.encode(url.toString()))}.img');
    return PlacePhoto(url: url, source: source, credit: data['credit'] as String,
      license: data['license'] as String, licenseUrl: safeWebUrl(data['licenseUrl'] as String?),
      caption: data['caption'] as String?, nearbyMeters: (data['nearbyMeters'] as num?)?.toDouble(),
      localPath: file?.path);
  }
  List<PlaceArticleSection> _sections(dynamic data) {
    if (data is! List || data.length > 200) { throw const FormatException('Invalid cached sections'); }
    return data.map((s) => PlaceArticleSection(s['title'] as String, s['text'] as String)).toList();
  }
  List<Map<String, String>> _writeSections(List<PlaceArticleSection> sections) =>
    [for (final s in sections) {'title': s.title, 'text': s.text}];
  OfflinePlace _decode(Map<String, dynamic> data) {
    final info = data['details'] as Map;
    final translated = data['translated'] as Map?;
    final details = PlaceDetails(description: info['description'] as String?,
      article: safeWebUrl(info['article'] as String?), articleTitle: info['articleTitle'] as String?,
      textLanguage: info['textLanguage'] as String?, sections: _sections(info['sections']),
      textTruncated: info['textTruncated'] == true, partial: info['partial'] == true,
      articleDistanceMeters: (info['articleDistanceMeters'] as num?)?.toDouble(),
      photo: info['photo'] == null ? null : _readPhoto(info['photo'] as Map),
      nearbyPhotos: (info['nearbyPhotos'] as List).map((p) => _readPhoto(p as Map)).toList(),
      facts: (info['facts'] as List).map((f) => PlaceFact(key: f['key'] as String,
        value: f['value'] as String, source: safeWebUrl(f['source'] as String?)!)).toList(),
      localRecords: (info['localRecords'] as List).map((r) => LocalPlaceRecord(
        title: r['title'] as String, type: r['type'] as String, number: r['number'] as String,
        source: safeWebUrl(r['source'] as String?)!, distance: (r['distance'] as num).toDouble())).toList());
    final photos = [if (details.photo != null) details.photo!, ...details.nearbyPhotos];
    return OfflinePlace(details, translated == null ? null : TranslatedPlaceText(
      title: translated['title'] as String?, description: translated['description'] as String?,
      sections: _sections(translated['sections'])), DateTime.parse(data['saved'] as String),
      data['complete'] == true && photos.every((p) => p.localPath != null && File(p.localPath!).existsSync()));
  }
  Future<String> _download(PlacePhoto photo) async {
    if (!{'upload.wikimedia.org', 'thumb.wikimedia.org'}.contains(photo.url.host) || photo.url.scheme != 'https') {
      throw const FormatException('Unsupported photo host');
    }
    final name = '${sha256.convert(utf8.encode(photo.url.toString()))}.img';
    final target = photoFile(name)!;
    if (await target.exists() && await target.length() > 0) { return name; }
    final response = await client.send(http.Request('GET', photo.url)
      ..headers['User-Agent'] = wikimediaUserAgent).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200 || (response.contentLength ?? 0) > 12 * 1024 * 1024 ||
        !RegExp(r'^image/(jpeg|png|webp)(;|$)').hasMatch(response.headers['content-type'] ?? '')) {
      throw const FormatException('Photo unavailable');
    }
    final bytes = <int>[];
    await for (final chunk in response.stream.timeout(const Duration(seconds: 20))) {
      bytes.addAll(chunk);
      if (bytes.length > 12 * 1024 * 1024) { throw const FormatException('Photo too large'); }
    }
    final jpeg = bytes.length > 3 && bytes[0] == 255 && bytes[1] == 216 && bytes[2] == 255;
    final png = bytes.length > 8 && bytes.take(8).join(',') == '137,80,78,71,13,10,26,10';
    final webp = bytes.length > 12 && String.fromCharCodes(bytes.take(4)) == 'RIFF' &&
      String.fromCharCodes(bytes.skip(8).take(4)) == 'WEBP';
    if (!jpeg && !png && !webp) { throw const FormatException('Invalid downloaded photo'); }
    final temporary = File('${target.path}.tmp');
    await temporary.writeAsBytes(bytes, flush: true); await temporary.rename(target.path);
    return name;
  }
  Future<bool> _save() async {
    if (directory == null) { saveFailed = true; notifyListeners(); return false; }
    final snapshot = jsonEncode({'version': 1, 'entries': _entries,
      'maps': {for (final m in _maps.entries) m.key: m.value.map((s) => s.toJson()).toList()}, 'walks': _walks});
    var success = false;
    _writes = _writes.catchError((Object e) {}).then((_) async {
      try {
        final file = File('${directory!.path}/index.json'), temp = File('${directory!.path}/index.json.tmp');
        await temp.writeAsString(snapshot, flush: true);
        if (await file.exists()) {
          try {
            final previous = jsonDecode(await file.readAsString());
            if (previous is Map && previous['version'] == 1 && previous['entries'] is Map) {
              await file.copy('${file.path}.bak');
            }
          } catch (_) { /* Preserve the healthy backup. */ }
        }
        await temp.rename(file.path); saveFailed = false; success = true;
      } catch (_) { saveFailed = true; }
    });
    await _writes; notifyListeners(); return success;
  }
  Future<bool> prepare(SavedWalk walk, String language, {bool allowMobileData = false}) async {
    if (busy || directory == null || walk.session == null) { return false; }
    busy = true; done = 0; total = walk.places.length + 1; notifyListeners();
    final route = walk.session!.route, fingerprint = routeFingerprint(walk.session!.route);
    var complete = true;
    try {
      if (_maps[fingerprint] == null) {
        try { _maps[fingerprint] = await mapService.load(route); if (!await _save()) { complete = false; } }
        catch (_) { complete = false; }
      }
      done++; notifyListeners();
      for (final p in walk.places) {
        final key = _key(p, language);
        if (place(p, language)?.complete != true) {
          try {
            final info = await detailsService.load(p, language);
            var valid = !info.partial;
            TranslatedPlaceText? translation;
            if (info.textLanguage != null && info.textLanguage != language &&
                (info.description != null || info.sections.isNotEmpty)) {
              try { translation = await translator.translate(info, language, allowMobileData: allowMobileData); }
              catch (_) { valid = false; }
            }
            final photos = <Uri, String>{};
            for (final photo in [if (info.photo != null) info.photo!, ...info.nearbyPhotos]) {
              try { photos[photo.url] = await _download(photo); } catch (_) { valid = false; }
            }
            final value = <String, dynamic>{'saved': DateTime.now().toUtc().toIso8601String(), 'complete': valid,
              'translated': translation == null ? null : {'title': translation.title,
                'description': translation.description, 'sections': _writeSections(translation.sections)},
              'details': {'description': info.description, 'article': info.article?.toString(),
                'articleTitle': info.articleTitle, 'textLanguage': info.textLanguage,
                'textTruncated': info.textTruncated, 'partial': info.partial,
                'articleDistanceMeters': info.articleDistanceMeters, 'sections': _writeSections(info.sections),
                'photo': info.photo == null ? null : _photo(info.photo!, photos[info.photo!.url]),
                'nearbyPhotos': [for (final photo in info.nearbyPhotos) _photo(photo, photos[photo.url])],
                'facts': [for (final f in info.facts) {'key': f.key, 'value': f.value, 'source': f.source.toString()}],
                'localRecords': [for (final r in info.localRecords) {'title': r.title, 'type': r.type,
                  'number': r.number, 'source': r.source.toString(), 'distance': r.distance}],
              }};
            _entries[key] = value;
            if (!await _save() || !valid) { complete = false; }
          } catch (_) { complete = false; }
        }
        done++; notifyListeners();
      }
      complete = complete && streets(route)?.isNotEmpty == true &&
        walk.places.every((p) => place(p, language)?.complete == true);
      _walks[walk.id] = {'route': fingerprint, 'language': language, 'complete': complete,
        'keys': walk.places.map((p) => _key(p, language)).toList()};
      return await _save() && complete;
    } finally { busy = false; notifyListeners(); }
  }
  Future<bool> remove(String id) async {
    if (busy) { return false; }
    _walks.remove(id);
    final keys = {for (final walk in _walks.values) ...List<String>.from(walk['keys'] as List)};
    _entries.removeWhere((key, _) => !keys.contains(key));
    final routes = _walks.values.map((w) => w['route']).toSet();
    _maps.removeWhere((key, _) => !routes.contains(key));
    // Keep files until the new index is durable; never remove another walk's photos.
    if (!await _save()) { return false; }
    final used = <String>{};
    for (final entry in _entries.values) {
      final info = entry['details'] as Map;
      for (final p in [if (info['photo'] != null) info['photo'], ...(info['nearbyPhotos'] as List)]) {
        if (p['file'] is String) { used.add(p['file'] as String); }
      }
    }
    try {
      if (directory != null) {
        await for (final entity in directory!.list()) {
          final name = entity.uri.pathSegments.last;
          if (entity is File && photoFile(name) != null && !used.contains(name)) { await entity.delete(); }
        }
      }
    } catch (_) { saveFailed = true; notifyListeners(); return false; }
    return true;
  }
}

class OfflineScope extends InheritedNotifier<OfflineStore> {
  const OfflineScope({super.key, required OfflineStore store, required super.child}) : super(notifier: store);
  static OfflineStore? of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<OfflineScope>()?.notifier;
}
