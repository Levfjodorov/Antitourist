import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'place_information.dart';
import 'places.dart';

bool isInEstonia(GeoPoint point) => point.valid && point.lat >= 57.4 && point.lat <= 59.9 &&
  point.lon >= 21.6 && point.lon <= 28.3;
String? heritageNumber(Place place) {
  for (final key in ['ref:kmr', 'ref:EE:muinas', 'heritage:ref']) {
    final value = place.tags[key]?.trim();
    if (value != null && RegExp(r'^[1-9][0-9]{0,7}$').hasMatch(value)) { return value; }
  }
  return null;
}
String _name(String value) => value.toLowerCase().split(',').first
  .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ').trim();

List<LocalPlaceRecord> parseHeritageRecords(Map<String, dynamic> data, Place place) {
  final features = data['features'];
  if (features is! List) { throw const FormatException('Invalid heritage response'); }
  final number = heritageNumber(place);
  final names = {place.name, ...place.localizedNames.values,
    ...place.tags.entries.where((e) => ['name', 'alt_name', 'official_name', 'old_name'].contains(e.key.split(':').first))
      .expand((e) => e.value.split(';'))}.map(_name).where((n) => n.length >= 4).toSet();
  final matches = <String, LocalPlaceRecord>{};
  for (final raw in features) {
    try {
      if (raw is! Map || raw['geometry']?['type'] != 'Point') { continue; }
      final coordinates = raw['geometry']['coordinates'];
      if (coordinates is! List || coordinates.length != 2 || coordinates.any((v) => v is! num)) { continue; }
      final point = GeoPoint((coordinates[1] as num).toDouble(), (coordinates[0] as num).toDouble());
      if (!point.valid) { continue; }
      final distance = distanceMeters(place.point, point);
      if (distance > 200) { continue; }
      final properties = raw['properties'];
      final ref = properties?['vk_registrinumber'];
      final title = properties?['nimi'];
      final type = properties?['tyyp'];
      if (ref is! String || !RegExp(r'^[1-9][0-9]{0,7}$').hasMatch(ref) ||
          title is! String || title.isEmpty || title.length > 1000) { continue; }
      if (number != null ? ref != number : !names.contains(_name(title))) { continue; }
      matches[ref] = LocalPlaceRecord(title: title, type: type is String ? type : '', number: ref,
        source: Uri.https('register.muinas.ee', '/public.php', {'menuID': 'monument', 'action': 'view', 'id': ref}),
        distance: distance);
    } catch (_) { /* Keep other valid records. */ }
  }
  // A name with two register IDs is ambiguous; never choose just the nearest.
  return matches.length == 1 ? matches.values.toList() : const [];
}

class EstoniaHeritageService {
  EstoniaHeritageService({http.Client? client}) : client = client ?? http.Client();
  final http.Client client;
  final _cache = <String, List<LocalPlaceRecord>>{};
  static final shared = EstoniaHeritageService();
  Future<List<LocalPlaceRecord>> load(Place place) async {
    if (place.osmUrl == null || !isInEstonia(place.point)) { return const []; }
    if (_cache[place.key] case final cached?) { return cached; }
    final ref = heritageNumber(place);
    final latDelta = 200 / 111320;
    final lonDelta = latDelta / math.cos(place.lat * math.pi / 180).abs().clamp(0.1, 1);
    final params = {'service': 'WFS', 'version': '1.0.0', 'request': 'GetFeature',
      'typeName': 'muinsuskaitse:kpo_malestised_241', 'srsName': 'EPSG:4326',
      'outputFormat': 'application/json', 'maxFeatures': '100',
      // WFS 1.0 EPSG:4326 uses longitude,latitude for the bounding box.
      if (ref != null) 'CQL_FILTER': "vk_registrinumber='$ref'"
      else 'bbox': '${place.lon - lonDelta},${place.lat - latDelta},${place.lon + lonDelta},${place.lat + latDelta},EPSG:4326',
    };
    final response = await client.get(Uri.https('gsavalik.envir.ee', '/geoserver/muinsuskaitse/wfs', params),
      headers: {'User-Agent': 'AntiTourist/0.6.0 (https://github.com/Levfjodorov/Antitourist)',
        'Accept': 'application/json'}).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200 || response.bodyBytes.length > 2000000) {
      throw const FormatException('Heritage service unavailable');
    }
    final records = parseHeritageRecords(jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>, place);
    if (_cache.length >= 40) { _cache.remove(_cache.keys.first); }
    _cache[place.key] = records;
    return records;
  }
}
