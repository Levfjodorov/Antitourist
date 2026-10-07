const categoryNames = <String, String>{
  'history': 'История', 'weird': 'Странности', 'views': 'Виды',
  'food': 'Кофе и еда', 'industrial': 'Индустриальное',
};

class Place {
  const Place({required this.name, required this.category, required this.lat,
    required this.lon, required this.description, required this.score,
    required this.legalAccess, this.safetyNote});
  final String name, category, description;
  final double lat, lon, score;
  final bool legalAccess;
  final String? safetyNote;

  factory Place.fromJson(Map<String, dynamic> json) {
    final lat = (json['lat'] as num).toDouble();
    final lon = (json['lon'] as num).toDouble();
    final score = (json['anti_tourist_score'] as num).toDouble();
    if (!lat.isFinite || lat < -90 || lat > 90 ||
        !lon.isFinite || lon < -180 || lon > 180 ||
        !score.isFinite || score < 0 || score > 100) {
      throw const FormatException('Некорректные координаты или рейтинг');
    }
    return Place(name: json['name'] as String,
      category: json['category'] as String, lat: lat, lon: lon,
      description: json['description'] as String, score: score,
      legalAccess: json['legal_access'] == true,
      safetyNote: json['safety_note'] as String?);
  }
}

List<Place> parseApiPlaces(dynamic payload) {
  final items = (payload as Map<String, dynamic>)['places'] as List<dynamic>;
  return items.map((item) => Place.fromJson(item as Map<String, dynamic>))
      .where((place) => place.legalAccess).toList();
}

// Fictional UI examples, never verified navigation destinations.
List<Place> selectDemoPlaces(List<Place> places, {
  required int minutes, required int wildness, required Set<String> interests,
}) {
  final selected = places.where((p) => p.score >= 45 + wildness * 0.25).toList();
  if (selected.length < 3) {
    selected.clear();
    selected.addAll(places);
  }
  selected.sort((a, b) {
    final order = (interests.contains(b.category) ? 1 : 0) -
        (interests.contains(a.category) ? 1 : 0);
    return order != 0 ? order : b.score.compareTo(a.score);
  });
  return selected.take((minutes ~/ 30).clamp(3, 7).toInt()).toList();
}
