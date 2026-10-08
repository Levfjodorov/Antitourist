import 'places.dart';

Uri googlePlaceSearch(Place place, String name) {
  if (!place.point.valid) { throw const FormatException('Invalid place coordinates'); }
  final address = [place.tags['addr:street'], place.tags['addr:housenumber'],
    place.tags['addr:city'], place.tags['addr:country']].whereType<String>()
    .where((s) => s.trim().isNotEmpty).join(', ');
  // A search is not a verified Google Place ID. The user checks the matching result.
  final hint = address.isNotEmpty ? String.fromCharCodes(address.runes.take(80))
    : '${place.lat.toStringAsFixed(6)},${place.lon.toStringAsFixed(6)}';
  final title = String.fromCharCodes(name.trim().runes.take(60));
  return Uri.https('www.google.com', '/maps/search/', {
    'api': '1', 'query': '${title.isEmpty ? '' : '$title, '}$hint',
  });
}
