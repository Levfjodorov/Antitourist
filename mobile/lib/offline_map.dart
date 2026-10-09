import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'places.dart';
import 'walking_route.dart';

class OfflineStreet {
  const OfflineStreet(this.kind, this.points);
  final String kind;
  final List<GeoPoint> points;
  Map<String, dynamic> toJson() => {'kind': kind, 'points': [for (final p in points) [p.lat, p.lon]]};
  factory OfflineStreet.fromJson(Map<String, dynamic> data) {
    final raw = data['points'] as List;
    if (raw.length < 2 || raw.length > 5000 || !['road', 'water', 'park'].contains(data['kind'])) {
      throw const FormatException('Invalid offline street');
    }
    final points = raw.map((p) => GeoPoint((p[0] as num).toDouble(), (p[1] as num).toDouble())).toList();
    if (points.any((p) => !p.valid)) { throw const FormatException('Invalid map coordinate'); }
    return OfflineStreet(data['kind'] as String, points);
  }
}

List<OfflineStreet> parseOfflineStreets(Map<String, dynamic> data) {
  final elements = data['elements'];
  if (elements is! List || elements.length > 12000 || data.containsKey('remark')) {
    throw const FormatException('Incomplete offline map');
  }
  final streets = <OfflineStreet>[];
  for (final element in elements) {
    try {
      if (element['type'] != 'way') { continue; }
      final geometry = element['geometry'];
      final tags = element['tags'];
      if (geometry is! List || geometry.length < 2 || geometry.length > 5000 || tags is! Map) { continue; }
      final kind = tags.containsKey('highway') ? 'road' : tags['natural'] == 'water' ? 'water' : 'park';
      streets.add(OfflineStreet.fromJson({'kind': kind,
        'points': [for (final p in geometry) [p['lat'], p['lon']]]}));
    } catch (_) { /* Reject an invalid way without damaging valid ones. */ }
  }
  if (streets.isEmpty) { throw const FormatException('No streets downloaded'); }
  return streets;
}

class OfflineMapService {
  OfflineMapService({http.Client? client}) : client = client ?? http.Client();
  final http.Client client;
  Future<List<OfflineStreet>> load(WalkingRoute route) async {
    if (route.geometry.length < 2 || route.geometry.any((p) => !p.valid)) {
      throw const FormatException('Invalid route');
    }
    final south = route.geometry.map((p) => p.lat).reduce(math.min) - 0.002;
    final north = route.geometry.map((p) => p.lat).reduce(math.max) + 0.002;
    final padding = 220 / (111320 * math.cos(route.geometry.first.lat * math.pi / 180).abs().clamp(0.1, 1));
    final west = route.geometry.map((p) => p.lon).reduce(math.min) - padding;
    final east = route.geometry.map((p) => p.lon).reduce(math.max) + padding;
    if (distanceMeters(GeoPoint(south, west), GeoPoint(north, east)) > 20000) {
      throw const FormatException('Offline map area too large');
    }
    final bbox = '$south,$west,$north,$east';
    final query = '[out:json][timeout:25][maxsize:16777216];('
      'way["highway"]["highway"!~"motorway|motorway_link|construction|proposed|raceway"]($bbox);'
      'way["natural"="water"]($bbox);way["leisure"~"^(park|garden)\$"]($bbox);'
      ');out tags geom;';
    final response = await client.post(Uri.parse('https://overpass-api.de/api/interpreter'),
      headers: {'User-Agent': 'AntiTourist/0.6.0 (https://github.com/Levfjodorov/Antitourist)'},
      body: {'data': query}).timeout(const Duration(seconds: 40));
    if (response.statusCode != 200 || response.bodyBytes.length > 16 * 1024 * 1024) {
      throw const FormatException('Offline map unavailable');
    }
    return parseOfflineStreets(jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>);
  }
}
