import 'dart:math' as math;

const categoryNames = <String, String>{
  'history': 'История', 'weird': 'Странности', 'views': 'Виды',
  'food': 'Кофе и еда', 'industrial': 'Индустриальное',
};

class GeoPoint {
  const GeoPoint(this.lat, this.lon);
  final double lat, lon;
  bool get valid => lat.isFinite && lon.isFinite &&
      lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180;
}

const tallinnStart = GeoPoint(59.437, 24.7536);

double distanceMeters(GeoPoint a, GeoPoint b) {
  const radians = math.pi / 180;
  final dLat = (b.lat - a.lat) * radians;
  final dLon = (b.lon - a.lon) * radians;
  final h = math.pow(math.sin(dLat / 2), 2) +
      math.cos(a.lat * radians) * math.cos(b.lat * radians) *
      math.pow(math.sin(dLon / 2), 2);
  return 6371000 * 2 * math.asin(math.sqrt(h.clamp(0, 1)));
}

String formatDistance(double meters) => meters < 1000
    ? '${meters.round()} м' : '${(meters / 1000).toStringAsFixed(1)} км';

class Place {
  const Place({required this.name, required this.category, required this.lat,
    required this.lon, required this.description, required this.score,
    required this.legalAccess, this.safetyNote, this.id = '', this.osmUrl,
    this.distance = 0, this.coordinateIsCenter = false,
    this.accessLabel = 'Доступ не указан', this.tags = const {},
    this.localizedNames = const {}, this.localizedDescriptions = const {},
    this.localizedSafetyNotes = const {}});
  final String name, category, description, id, accessLabel;
  final double lat, lon, score, distance;
  // For live data this means an explicit public/permissive OSM tag, not a legal verification.
  final bool legalAccess, coordinateIsCenter;
  final String? safetyNote;
  final Uri? osmUrl;
  final Map<String, String> tags;
  final Map<String, String> localizedNames, localizedDescriptions, localizedSafetyNotes;
  GeoPoint get point => GeoPoint(lat, lon);

  factory Place.fromJson(Map<String, dynamic> json) {
    final lat = (json['lat'] as num).toDouble();
    final lon = (json['lon'] as num).toDouble();
    final score = (json['anti_tourist_score'] as num).toDouble();
    if (!GeoPoint(lat, lon).valid || !score.isFinite || score < 0 || score > 100) {
      throw const FormatException('Некорректные координаты или рейтинг');
    }
    return Place(name: json['name'] as String,
      category: json['category'] as String, lat: lat, lon: lon,
      description: json['description'] as String, score: score,
      legalAccess: json['legal_access'] == true,
      id: json['id'] as String? ?? '', safetyNote: json['safety_note'] as String?,
      localizedNames: Map<String, String>.from(json['names'] as Map? ?? const {}),
      localizedDescriptions: Map<String, String>.from(json['descriptions'] as Map? ?? const {}),
      localizedSafetyNotes: Map<String, String>.from(json['safety_notes'] as Map? ?? const {}));
  }
}

List<Place> parseApiPlaces(dynamic payload) {
  final items = (payload as Map<String, dynamic>)['places'] as List<dynamic>;
  return items.map((item) => Place.fromJson(item as Map<String, dynamic>))
      .where((place) => place.legalAccess).toList();
}

List<Place> selectDemoPlaces(List<Place> places, {
  required int minutes, required int wildness, required Set<String> interests,
}) {
  final selected = places.where((p) => p.score >= 45 + wildness * 0.25).toList();
  if (selected.length < 3) { selected.clear(); selected.addAll(places); }
  selected.sort((a, b) {
    final order = (interests.contains(b.category) ? 1 : 0) -
        (interests.contains(a.category) ? 1 : 0);
    return order != 0 ? order : b.score.compareTo(a.score);
  });
  return selected.take((minutes ~/ 30).clamp(3, 7).toInt()).toList();
}
