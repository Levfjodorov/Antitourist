import 'places.dart';

class RouteFailure implements Exception {
  const RouteFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

class WalkingLeg {
  const WalkingLeg({required this.meters, required this.seconds});
  final double meters, seconds;
}

class WalkingRoute {
  const WalkingRoute({required this.places, required this.geometry,
    required this.snappedPoints, required this.snapDistances,
    required this.legs, required this.meters, required this.seconds});
  final List<Place> places;
  final List<GeoPoint> geometry, snappedPoints;
  final List<double> snapDistances;
  final List<WalkingLeg> legs;
  final double meters, seconds;
  // An explicit estimate for visiting each place, not a provider prediction.
  int get visitMinutes => places.length * 10;
  int get walkMinutes => (seconds / 60).ceil();
  int get totalMinutes => walkMinutes + visitMinutes;
}

String formatMinutes(int minutes) => minutes < 60 ? '$minutes мин'
    : '${minutes ~/ 60} ч ${minutes % 60} мин';

Uri walkingNavigationUri(GeoPoint point) {
  if (!point.valid) { throw const FormatException('Некорректная точка навигации'); }
  return Uri.https('www.google.com', '/maps/dir/', {
    'api': '1', 'destination': '${point.lat},${point.lon}',
    'travelmode': 'walking', 'dir_action': 'navigate',
  });
}

Uri footRequestUri(String service, List<GeoPoint> points) {
  if (!['table', 'route'].contains(service) || points.length < 2 ||
      points.length > 8 || points.any((p) => !p.valid)) {
    throw const FormatException('Некорректные параметры маршрута');
  }
  final coordinates = points.map((p) =>
    '${p.lon.toStringAsFixed(6)},${p.lat.toStringAsFixed(6)}').join(';');
  // The routed-foot instance selects the pedestrian graph, independently
  // of OSRM's profile name in the URL. Never use the general car demo endpoint.
  return Uri.https('routing.openstreetmap.de', '/routed-foot/$service/v1/foot/$coordinates', {
    'radiuses': List.filled(points.length, '75').join(';'),
    'generate_hints': 'false',
    if (service == 'table') 'annotations': 'duration',
    if (service == 'route') ...{
      'geometries': 'geojson', 'overview': 'full',
      'steps': 'false', 'alternatives': 'false', 'continue_straight': 'false',
    },
  });
}

double _nonnegative(dynamic value) {
  if (value is! num || !value.isFinite || value < 0) {
    throw const FormatException('Некорректное расстояние или время');
  }
  return value.toDouble();
}

GeoPoint _coordinate(dynamic raw) {
  if (raw is! List || raw.length < 2 || raw[0] is! num || raw[1] is! num) {
    throw const FormatException('Некорректные координаты пути');
  }
  final point = GeoPoint((raw[1] as num).toDouble(), (raw[0] as num).toDouble());
  if (!point.valid) { throw const FormatException('Координаты вне диапазона'); }
  return point;
}

void checkOsrmStatus(dynamic payload) {
  if (payload is! Map<String, dynamic>) { throw const FormatException('Некорректный ответ маршрутизатора'); }
  switch (payload['code']) {
    case 'Ok': return;
    case 'NoSegment':
      throw const RouteFailure('Рядом с одной из точек нет пешеходного пути в пределах 75 м. Попробуй другую подборку или старт.');
    case 'NoRoute':
    case 'NoTable':
      throw const RouteFailure('Не удалось соединить все места пешеходными путями. Попробуй другую подборку.');
    default:
      throw const RouteFailure('Сервис не смог рассчитать пеший маршрут. Повтори позже.');
  }
}

List<List<double?>> parseFootMatrix(dynamic payload, int size) {
  checkOsrmStatus(payload);
  final rows = (payload as Map<String, dynamic>)['durations'];
  if (rows is! List || rows.length != size) { throw const FormatException('Неполная матрица переходов'); }
  return rows.map<List<double?>>((row) {
    if (row is! List || row.length != size) { throw const FormatException('Неполная строка матрицы'); }
    return row.map<double?>((value) => value == null ? null : _nonnegative(value)).toList();
  }).toList();
}

// Held–Karp: exact shortest open visit order in the supplied directed duration
// matrix, fixed start at index 0, free final stop, at most seven POIs.
List<int> optimalVisitOrder(List<List<double?>> matrix) {
  final size = matrix.length;
  if (size < 2 || size > 8 || matrix.any((row) => row.length != size) ||
      matrix.expand((row) => row).any((v) => v != null && (!v.isFinite || v < 0))) {
    throw const FormatException('Некорректная матрица');
  }
  final n = size - 1;
  final full = (1 << n) - 1;
  final cost = List.generate(full + 1, (_) => List.filled(n, double.infinity));
  final parent = List.generate(full + 1, (_) => List.filled(n, -1));
  for (var j = 0; j < n; j++) {
    final value = matrix[0][j + 1];
    if (value != null) { cost[1 << j][j] = value; }
  }
  for (var mask = 1; mask <= full; mask++) {
    for (var last = 0; last < n; last++) {
      if ((mask & (1 << last)) == 0 || !cost[mask][last].isFinite) { continue; }
      for (var next = 0; next < n; next++) {
        if ((mask & (1 << next)) != 0) { continue; }
        final edge = matrix[last + 1][next + 1];
        if (edge == null) { continue; }
        final nextMask = mask | (1 << next);
        final candidate = cost[mask][last] + edge;
        if (candidate < cost[nextMask][next]) {
          cost[nextMask][next] = candidate;
          parent[nextMask][next] = last;
        }
      }
    }
  }
  var last = 0;
  for (var j = 1; j < n; j++) {
    if (cost[full][j] < cost[full][last]) { last = j; }
  }
  if (!cost[full][last].isFinite) {
    throw const RouteFailure('Не удалось соединить все места пешком. Попробуй другую подборку.');
  }
  var mask = full;
  final reversed = <int>[];
  while (last >= 0) {
    reversed.add(last + 1);
    final previous = parent[mask][last];
    mask ^= 1 << last;
    last = previous;
  }
  return reversed.reversed.toList();
}

WalkingRoute parseWalkingRoute(dynamic payload, GeoPoint start, List<Place> ordered) {
  checkOsrmStatus(payload);
  final data = payload as Map<String, dynamic>;
  final routes = data['routes'];
  final waypoints = data['waypoints'];
  if (ordered.isEmpty || routes is! List || routes.isEmpty || routes.first is! Map ||
      waypoints is! List || waypoints.length != ordered.length + 1) {
    throw const FormatException('Неполный маршрут');
  }
  final route = routes.first as Map;
  final rawGeometry = route['geometry'];
  final rawLegs = route['legs'];
  if (rawGeometry is! Map || rawGeometry['type'] != 'LineString' ||
      rawGeometry['coordinates'] is! List || rawLegs is! List || rawLegs.length != ordered.length) {
    throw const FormatException('Неполная геометрия или этапы');
  }
  final geometry = (rawGeometry['coordinates'] as List).map(_coordinate).toList();
  if (geometry.length < 2 || geometry.length > 100000) {
    throw const FormatException('Некорректная длина геометрии');
  }
  final inputs = [start, for (final place in ordered) place.point];
  final snapped = <GeoPoint>[];
  final distances = <double>[];
  for (var i = 0; i < waypoints.length; i++) {
    final raw = waypoints[i];
    if (raw is! Map) { throw const FormatException('Некорректная точка привязки'); }
    final point = _coordinate(raw['location']);
    final shift = _nonnegative(raw['distance']);
    if (shift > 75.5 || distanceMeters(inputs[i], point) > 76) {
      throw const RouteFailure('Сервис привязал точку слишком далеко от места. Попробуй другую подборку.');
    }
    snapped.add(point); distances.add(shift);
  }
  if (distanceMeters(geometry.first, snapped.first) > 30 ||
      distanceMeters(geometry.last, snapped.last) > 30) {
    throw const FormatException('Геометрия не соответствует началу и финишу');
  }
  final legs = rawLegs.map<WalkingLeg>((raw) {
    if (raw is! Map) { throw const FormatException('Некорректный этап'); }
    return WalkingLeg(meters: _nonnegative(raw['distance']), seconds: _nonnegative(raw['duration']));
  }).toList();
  final meters = _nonnegative(route['distance']);
  final seconds = _nonnegative(route['duration']);
  final legMeters = legs.fold<double>(0, (sum, leg) => sum + leg.meters);
  final legSeconds = legs.fold<double>(0, (sum, leg) => sum + leg.seconds);
  if ((meters - legMeters).abs() > 5 || (seconds - legSeconds).abs() > 5) {
    throw const FormatException('Итог маршрута не соответствует этапам');
  }
  return WalkingRoute(places: List.unmodifiable(ordered), geometry: List.unmodifiable(geometry),
    snappedPoints: List.unmodifiable(snapped), snapDistances: List.unmodifiable(distances),
    legs: List.unmodifiable(legs), meters: meters, seconds: seconds);
}
