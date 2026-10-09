class PlaceFact {
  const PlaceFact({required this.key, required this.value, required this.source});
  final String key, value;
  final Uri source;
}
class LocalPlaceRecord {
  const LocalPlaceRecord({required this.title, required this.type, required this.number,
    required this.source, required this.distance});
  final String title, type, number;
  final Uri source;
  final double distance;
}
