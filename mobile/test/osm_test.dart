import 'package:antitourist/osm.dart';
import 'package:antitourist/places.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> node(int id, Map<String, String> tags,
    {double lat = 59.437, double lon = 24.7536}) => {
  'type': 'node', 'id': id, 'lat': lat, 'lon': lon, 'tags': tags,
};

List<Place> parse(List<Map<String, dynamic>> items) =>
    parseOsmPlaces({'elements': items}, tallinnStart, 2000);

void main() {
  test('Queries are deterministic, bounded and include node coordinates', () {
    final query = buildOverpassQuery(tallinnStart, 2000, {'weird', 'history'});
    expect(query, buildOverpassQuery(tallinnStart, 2000, {'history', 'weird'}));
    expect(query, contains('(around:2000,59.437000,24.753600)'));
    expect(query, endsWith('out body center;'));
    expect(query, isNot(contains('amenity')));
    expect(query, contains(r'[historic~"^(memorial|monument|ruins|archaeological_site|boundary_stone)$"]'));
    final otherQuery = buildOverpassQuery(tallinnStart, 2000, {'food', 'industrial'});
    expect(otherQuery, contains(r'[amenity~"^(cafe|restaurant)$"]'));
    expect(otherQuery, contains(r'[historic~"^(bunker|industrial)$"]'));
    expect(otherQuery, contains(r'[man_made~"^(crane|water_tower)$"]'));
    expect(() => buildOverpassQuery(tallinnStart, 5001, {'history'}), throwsFormatException);
    expect(() => buildOverpassQuery(tallinnStart, 2000, {'injected;'}), throwsFormatException);
    expect(() => buildOverpassQuery(const GeoPoint(91, 0), 2000, {'history'}), throwsFormatException);
  });

  test('Known private, closed, military and construction objects are excluded', () {
    final result = parse([
      for (final restriction in ['no', 'private', 'customers', 'permit', 'military'])
        node(restriction.hashCode.abs() + 1,
          {'tourism': 'artwork', 'access': restriction, 'foot': 'yes'}),
      node(1, {'tourism': 'artwork', 'foot': 'no'}),
      node(2, {'historic': 'bunker', 'military': 'bunker'}),
      node(3, {'tourism': 'viewpoint', 'construction': 'yes'}),
      node(4, {'tourism': 'artwork', 'name': 'Open mural', 'access': 'yes'}),
    ]);
    expect(result.map((p) => p.name), ['Open mural']);
  });

  test('Unknown and conditional access is never declared confirmed', () {
    final result = parse([
      node(1, {'tourism': 'artwork', 'name': 'Unknown'}),
      node(2, {'tourism': 'viewpoint', 'name': 'Conditional',
        'access': 'yes', 'access:conditional': 'no @ (sunset-sunrise)'}),
      node(3, {'historic': 'monument', 'name': 'Public', 'foot': 'designated'}),
    ]);
    expect(result.where((p) => p.legalAccess).map((p) => p.name), ['Public']);
    expect(result.firstWhere((p) => p.name == 'Unknown').accessLabel, contains('не подтверждён'));
    final ranked = rankLivePlaces(result, start: tallinnStart, radius: 2000,
      minutes: 120, wildness: 70, interests: {'history', 'weird', 'views'},
      onlyPublicAccess: true);
    expect(ranked.map((p) => p.name), ['Public']);
  });

  test('Ways use labelled centers and duplicates prefer precise nodes', () {
    final result = parse([
      {'type': 'way', 'id': 10, 'center': {'lat': 59.43701, 'lon': 24.7536},
        'tags': {'name': 'Mural', 'tourism': 'artwork'}},
      node(20, {'name': 'Mural', 'tourism': 'artwork'}),
      {'type': 'relation', 'id': 30, 'center': {'lat': 59.438, 'lon': 24.754},
        'tags': {'name': 'Memorial', 'historic': 'memorial'}},
    ]);
    expect(result, hasLength(2));
    final mural = result.firstWhere((p) => p.name == 'Mural');
    expect(mural.id, 'node/20');
    expect(mural.coordinateIsCenter, isFalse);
    expect(mural.osmUrl.toString(), 'https://www.openstreetmap.org/node/20');
    expect(result.firstWhere((p) => p.name == 'Memorial').coordinateIsCenter, isTrue);
  });

  test('Invalid coordinates, unknown types and distant centers are skipped', () {
    expect(parse([
      node(1, {'tourism': 'viewpoint'}, lat: 91),
      node(2, {'tourism': 'viewpoint'}, lat: double.nan),
      node(3, {'tourism': 'viewpoint'}, lat: 60),
      {'type': 'way', 'id': 4, 'tags': {'tourism': 'viewpoint'}},
      {...node(5, {'tourism': 'viewpoint'}), 'type': 'bad'},
      node(6, {'tourism': 'hotel'}),
    ]), isEmpty);
  });

  test('Food excludes explicit chains and disused venues', () {
    final result = parse([
      node(1, {'amenity': 'cafe', 'brand': 'Chain'}),
      node(2, {'amenity': 'cafe', 'brand:wikidata': 'Q1'}),
      node(3, {'amenity': 'cafe', 'disused': 'yes'}),
      node(4, {'amenity': 'cafe', 'name': 'Cafe without brand tag'}),
    ]);
    expect(result.map((p) => p.name), ['Cafe without brand tag']);
  });

  test('Partial responses are errors, rather than incomplete recommendations', () {
    expect(() => parseOsmPlaces({'remark': 'runtime error: timed out',
      'elements': [node(1, {'tourism': 'viewpoint'})]}, tallinnStart, 2000),
      throwsFormatException);
    expect(() => parseOsmPlaces({'error': 'no elements'}, tallinnStart, 2000),
      throwsFormatException);
  });

  test('Live selection respects interests, adds diversity and limits stops', () {
    final places = [
      for (var i = 0; i < 4; i++) Place(id: 'node/$i', name: '$i',
        category: 'history', lat: 59.437, lon: 24.7536,
        description: '', score: 90, legalAccess: true),
      const Place(id: 'node/9', name: 'Art', category: 'weird',
        lat: 59.437, lon: 24.7536, description: '', score: 80, legalAccess: true),
      const Place(id: 'node/10', name: 'Food', category: 'food',
        lat: 59.437, lon: 24.7536, description: '', score: 100, legalAccess: true),
    ];
    final result = rankLivePlaces(places, start: tallinnStart, radius: 2000,
      minutes: 60, wildness: 100, interests: {'history', 'weird'});
    expect(result, hasLength(3));
    expect(result.any((p) => p.name == 'Art'), isTrue);
    expect(result.any((p) => p.category == 'food'), isFalse);
  });

  test('Distances are geodesic, including across the date line', () {
    expect(distanceMeters(tallinnStart, tallinnStart), 0);
    expect(distanceMeters(const GeoPoint(0, 179.9), const GeoPoint(0, -179.9)),
      closeTo(22239, 10));
    expect(formatDistance(1250), '1.3 км');
  });
}
