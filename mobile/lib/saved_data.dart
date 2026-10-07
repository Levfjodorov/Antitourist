import 'places.dart';
import 'walk_session.dart';
import 'walking_route.dart';

GeoPoint readPoint(dynamic value) {
  if (value is! List || value.length != 2 || value.any((v) => v is! num)) {
    throw const FormatException('Invalid point');
  }
  final point = GeoPoint((value[0] as num).toDouble(), (value[1] as num).toDouble());
  if (!point.valid) { throw const FormatException('Invalid coordinates'); }
  return point;
}

List<double> writePoint(GeoPoint p) => [p.lat, p.lon];

double readNumber(dynamic value) {
  if (value is! num || !value.isFinite || value < 0) {
    throw const FormatException('Invalid distance or duration');
  }
  return value.toDouble();
}

Map<String, dynamic> encodeSession(WalkSession session) {
  final route = session.route;
  return {
    'places': route.places.map((p) => p.toJson()).toList(),
    'geometry': route.geometry.map(writePoint).toList(),
    'snapped': route.snappedPoints.map(writePoint).toList(),
    'snap_distances': route.snapDistances,
    'legs': route.legs.map((l) => [l.meters, l.seconds]).toList(),
    'meters': route.meters, 'seconds': route.seconds,
    'statuses': session.statuses.map((s) => s.name).toList(), 'history': session.history,
  };
}

WalkSession decodeSession(Map<String, dynamic> data) {
  final places = readPlaces(data['places'], max: 7);
  final geometry = (data['geometry'] as List).map(readPoint).toList();
  final snapped = (data['snapped'] as List).map(readPoint).toList();
  final distances = (data['snap_distances'] as List).map(readNumber).toList();
  final legs = (data['legs'] as List).map((raw) {
    final values = raw as List;
    if (values.length != 2) { throw const FormatException('Invalid leg'); }
    return WalkingLeg(meters: readNumber(values[0]), seconds: readNumber(values[1]));
  }).toList();
  final meters = readNumber(data['meters']);
  final seconds = readNumber(data['seconds']);
  if (places.isEmpty || geometry.length < 2 || geometry.length > 100000 ||
      snapped.length != places.length + 1 || distances.length != snapped.length ||
      legs.length != places.length || distances.any((d) => d > 75.5) ||
      (legs.fold<double>(0, (s, l) => s + l.meters) - meters).abs() > 5 ||
      (legs.fold<double>(0, (s, l) => s + l.seconds) - seconds).abs() > 5) {
    throw const FormatException('Invalid saved route');
  }
  for (var i = 0; i < places.length; i++) {
    if (distanceMeters(places[i].point, snapped[i + 1]) > 76) {
      throw const FormatException('Invalid saved waypoint');
    }
  }
  return WalkSession.restore(WalkingRoute(places: places, geometry: geometry,
    snappedPoints: snapped, snapDistances: distances, legs: legs,
    meters: meters, seconds: seconds),
    List<String>.from(data['statuses'] as List), List<int>.from(data['history'] as List));
}

List<Place> readPlaces(dynamic raw, {int max = 500}) {
  if (raw is! List || raw.length > max) { throw const FormatException('Invalid place list'); }
  final places = raw.map((p) => Place.fromJson(Map<String, dynamic>.from(p as Map))).toList();
  if (places.map((p) => p.key).toSet().length != places.length ||
      places.any((p) => !p.distance.isFinite || p.distance < 0 || !categoryNames.containsKey(p.category))) {
    throw const FormatException('Invalid saved places');
  }
  return places;
}

class SavedWalk {
  SavedWalk({required this.id, required this.start, required this.places,
    required this.candidates, required this.demo, required this.requestedMinutes,
    required this.created, required this.updated, this.session});
  final String id;
  final GeoPoint start;
  final List<Place> places, candidates;
  final bool demo;
  final int requestedMinutes;
  final DateTime created, updated;
  final WalkSession? session;
  bool get complete => session?.complete ?? false;
  Map<String, dynamic> toJson() => {
    'id': id, 'start': writePoint(start), 'places': places.map((p) => p.toJson()).toList(),
    'candidates': candidates.map((p) => p.toJson()).toList(), 'demo': demo,
    'minutes': requestedMinutes, 'created': created.toIso8601String(),
    'updated': updated.toIso8601String(),
    if (session != null) 'session': encodeSession(session!),
  };
  factory SavedWalk.fromJson(Map<String, dynamic> data) {
    final places = readPlaces(data['places'], max: 7);
    final id = data['id'] as String;
    final minutes = data['minutes'] as int;
    final session = data['session'] == null ? null
      : decodeSession(Map<String, dynamic>.from(data['session'] as Map));
    final start = readPoint(data['start']);
    if (id.isEmpty || places.isEmpty || minutes < 1 || minutes > 1440 ||
        (data['demo'] == true && session != null) ||
        (session != null && (distanceMeters(start, session.route.snappedPoints.first) > 76 ||
          places.map((p) => p.key).join('|') != session.route.places.map((p) => p.key).join('|')))) {
      throw const FormatException('Invalid saved walk');
    }
    return SavedWalk(id: id, start: start, places: places,
      candidates: readPlaces(data['candidates']), demo: data['demo'] == true,
      requestedMinutes: minutes, created: DateTime.parse(data['created'] as String),
      updated: DateTime.parse(data['updated'] as String), session: session);
  }
}
