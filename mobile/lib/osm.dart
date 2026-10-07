import 'places.dart';

const _selectors = <String, List<String>>{
  'history': [r'[historic~"^(memorial|monument|ruins|archaeological_site|boundary_stone)$"]'],
  'weird': [r'[tourism=artwork]'],
  'views': [r'[tourism=viewpoint]'],
  'food': [r'[amenity~"^(cafe|restaurant)$"]'],
  'industrial': [r'[historic~"^(bunker|industrial)$"]', r'[man_made~"^(crane|water_tower)$"]'],
};

String buildOverpassQuery(GeoPoint start, int radius, Set<String> interests) {
  if (!start.valid || radius < 500 || radius > 5000 || interests.isEmpty ||
      interests.any((key) => !_selectors.containsKey(key))) {
    throw const FormatException('Некорректные параметры поиска');
  }
  final around = '(around:$radius,${start.lat.toStringAsFixed(6)},${start.lon.toStringAsFixed(6)})';
  final keys = interests.toList()..sort();
  final rows = [for (final key in keys)
    for (final selector in _selectors[key]!) 'nwr$selector$around;'];
  return '[out:json][timeout:25][maxsize:16777216];(${rows.join()} );out body center;';
}

String? _category(Map<String, String> tags) {
  if (tags['tourism'] == 'viewpoint') { return 'views'; }
  if (tags['tourism'] == 'artwork') { return 'weird'; }
  if (['bunker', 'industrial'].contains(tags['historic']) ||
      ['crane', 'water_tower'].contains(tags['man_made'])) { return 'industrial'; }
  if (['memorial', 'monument', 'ruins', 'archaeological_site', 'boundary_stone']
      .contains(tags['historic'])) { return 'history'; }
  if (['cafe', 'restaurant'].contains(tags['amenity'])) { return 'food'; }
  return null;
}

bool _restricted(Map<String, String> tags) {
  const blocked = {'no', 'private', 'customers', 'permit', 'destination', 'delivery', 'military'};
  if (blocked.contains(tags['access']) || blocked.contains(tags['foot'])) { return true; }
  if (tags['military'] != null || tags['landuse'] == 'military' ||
      tags['construction'] != null || tags['proposed'] != null) { return true; }
  return false;
}

bool _publicAccess(Map<String, String> tags) =>
    tags['access:conditional'] == null && tags['foot:conditional'] == null &&
    ['yes', 'permissive', 'designated'].contains(tags['foot'] ?? tags['access']);

double _novelty(Map<String, String> tags, String category) {
  var value = switch (category) {
    'industrial' => 82.0, 'weird' => 77.0, 'history' => 68.0,
    'views' => 60.0, _ => 43.0,
  };
  if (['boundary_stone', 'ruins'].contains(tags['historic'])) { value += 8; }
  if (tags['artwork_type'] == 'mural') { value += 5; }
  if (tags['tourism'] == 'attraction') { value -= 20; }
  return value.clamp(0, 100).toDouble();
}

String _description(Map<String, String> tags, String category) {
  final facts = <String>[categoryNames[category]!];
  for (final entry in const {
    'historic': 'Тип', 'artwork_type': 'Искусство', 'start_date': 'Дата',
    'artist_name': 'Автор', 'cuisine': 'Кухня', 'opening_hours': 'Часы работы',
  }.entries) {
    final value = tags[entry.key];
    if (value != null && value.trim().isNotEmpty) { facts.add('${entry.value}: $value'); }
  }
  if (tags['description']?.isNotEmpty ?? false) { facts.add(tags['description']!); }
  if (tags['fee'] == 'yes') { facts.add('В OSM указана плата за посещение'); }
  return facts.join('\n');
}

List<Place> parseOsmPlaces(dynamic payload, GeoPoint start, int radius) {
  if (payload is! Map<String, dynamic> || payload['elements'] is! List) {
    throw const FormatException('Сервис вернул неожиданный ответ');
  }
  if (payload['remark'] != null && payload['remark'].toString().trim().isNotEmpty) {
    throw const FormatException('Сервис не завершил запрос. Повторите поиск позже.');
  }
  final result = <Place>[];
  final seen = <String>{};
  for (final raw in payload['elements'] as List<dynamic>) {
    if (raw is! Map<String, dynamic>) { continue; }
    final type = raw['type'];
    final id = raw['id'];
    if (!['node', 'way', 'relation'].contains(type) || id is! int || id <= 0) { continue; }
    final key = '$type/$id';
    if (!seen.add(key)) { continue; }
    final tagsRaw = raw['tags'];
    if (tagsRaw is! Map) { continue; }
    final tags = <String, String>{};
    for (final entry in tagsRaw.entries) {
      if (entry.key is String && entry.value is String) {
        tags[entry.key as String] = entry.value as String;
      }
    }
    if (_restricted(tags)) { continue; }
    final category = _category(tags);
    if (category == null) { continue; }
    // Cafes with explicit brand tags are excluded; unknown ownership remains unknown.
    if (category == 'food' && ((tags['brand']?.isNotEmpty ?? false) ||
        tags.containsKey('brand:wikidata') || tags['disused'] == 'yes' ||
        tags['abandoned'] == 'yes' || tags.containsKey('disused:amenity') ||
        tags.containsKey('abandoned:amenity'))) { continue; }
    final center = raw['center'];
    final coords = type == 'node' ? raw : center;
    if (coords is! Map || coords['lat'] is! num || coords['lon'] is! num) { continue; }
    final point = GeoPoint((coords['lat'] as num).toDouble(), (coords['lon'] as num).toDouble());
    if (!point.valid) { continue; }
    final distance = distanceMeters(start, point);
    if (distance > radius) { continue; }
    final name = tags['name:ru'] ?? tags['name'] ?? tags['name:en'] ??
        '${categoryNames[category]} · OSM $id';
    final publicAccess = _publicAccess(tags);
    result.add(Place(
      id: key, name: name, category: category, lat: point.lat, lon: point.lon,
      description: _description(tags, category), score: _novelty(tags, category),
      legalAccess: publicAccess, tags: Map.unmodifiable(tags),
      osmUrl: Uri.https('www.openstreetmap.org', '/$key'), distance: distance,
      coordinateIsCenter: type != 'node',
      accessLabel: tags.containsKey('access:conditional') || tags.containsKey('foot:conditional')
          ? 'В OSM есть условия доступа — проверь источник'
          : publicAccess ? 'Доступ разрешён по тегам OSM'
          : 'Доступ в OSM не подтверждён',
      safetyNote: ['industrial', 'history'].contains(category) &&
          (tags['building'] != null || ['bunker', 'ruins'].contains(tags['historic']))
          ? 'Сначала проверь возможность осмотра снаружи; вход внутрь не проверен.' : null,
    ));
  }
  // Mapping can include both a node and a building for the same POI.
  result.sort((a, b) => a.coordinateIsCenter == b.coordinateIsCenter
      ? a.id.compareTo(b.id) : a.coordinateIsCenter ? 1 : -1);
  final deduped = <Place>[];
  for (final place in result) {
    if (deduped.any((p) => p.name.trim().toLowerCase() == place.name.trim().toLowerCase() &&
        p.category == place.category && distanceMeters(p.point, place.point) < 40)) { continue; }
    deduped.add(place);
  }
  return deduped;
}

List<Place> rankLivePlaces(List<Place> places, {
  required GeoPoint start, required int radius, required int minutes,
  required int wildness, required Set<String> interests,
  bool onlyPublicAccess = false,
}) {
  final pool = places.where((p) => interests.contains(p.category) &&
      (!onlyPublicAccess || p.legalAccess)).toList();
  final chosen = <Place>[];
  final counts = <String, int>{};
  final count = (minutes ~/ 30).clamp(3, 7).toInt();
  final weight = 0.35 + wildness.clamp(0, 100) / 100 * 0.5;
  double value(Place p) => p.score * weight +
      100 * (1 - p.distance / radius).clamp(0, 1) * (1 - weight) -
      (counts[p.category] ?? 0) * 12;
  while (pool.isNotEmpty && chosen.length < count) {
    pool.sort((a, b) {
      final score = value(b).compareTo(value(a));
      return score != 0 ? score : a.id.compareTo(b.id);
    });
    final next = pool.removeAt(0);
    chosen.add(next);
    counts.update(next.category, (n) => n + 1, ifAbsent: () => 1);
  }
  // Order cards by distance from start; this is explicitly not a routed itinerary.
  chosen.sort((a, b) => distanceMeters(start, a.point).compareTo(distanceMeters(start, b.point)));
  return chosen;
}
