import 'package:antitourist/places.dart';
import 'package:antitourist/walking_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'route_fixtures.dart';

void main() {
  test('Foot endpoints preserve longitude/latitude order and tight snap radius', () {
    final uri = footRequestUri('route', [tallinnStart, routePlaces.first.point]);
    expect(uri.scheme, 'https');
    expect(uri.host, 'routing.openstreetmap.de');
    expect(uri.path, startsWith('/routed-foot/route/v1/foot/24.753600,59.437000;'));
    expect(uri.queryParameters['radiuses'], '75;75');
    expect(uri.queryParameters['geometries'], 'geojson');
    expect(uri.queryParameters['overview'], 'full');
    expect(uri.queryParameters.containsKey('fallback_speed'), isFalse);
    expect(() => footRequestUri('car', [tallinnStart, tallinnStart]), throwsFormatException);
    expect(() => footRequestUri('route', [const GeoPoint(double.nan, 0), tallinnStart]), throwsFormatException);
  });

  test('Directed order beats nearest-first greed and ends freely without a return leg', () {
    // From the start B is closer, but going A then B is substantially faster.
    final order = optimalVisitOrder([
      [0, 4, 1], [10, 0, 1], [10, 100, 0],
    ]);
    expect(order, [1, 2]);
    expect(order, hasLength(2));
    expect(order, isNot(contains(0)));
  });

  test('Null edges are not replaced by straight-line walking estimates', () {
    expect(optimalVisitOrder([[0, 1, null], [null, 0, 2], [null, null, 0]]), [1, 2]);
    expect(() => optimalVisitOrder([[0, 1, null], [1, 0, null], [null, null, 0]]),
      throwsA(isA<RouteFailure>()));
    expect(() => parseFootMatrix({'code': 'Ok', 'durations': [[0, -1], [1, 0]]}, 2),
      throwsFormatException);
    expect(() => parseFootMatrix({'code': 'Ok', 'durations': [[0], [1]]}, 2),
      throwsFormatException);
  });

  test('Seven-stop optimization matches an independent brute-force oracle', () {
    final matrix = List.generate(8, (i) => List<double?>.generate(8,
      (j) => i == j ? 0 : ((i * 17 + j * 31 + i * j * 7) % 99 + 1).toDouble()));
    double best = double.infinity;
    void visit(List<int> remaining, int previous, double cost) {
      if (remaining.isEmpty) { if (cost < best) { best = cost; } return; }
      for (final next in remaining) {
        visit(remaining.where((i) => i != next).toList(), next, cost + matrix[previous][next]!);
      }
    }
    visit([1, 2, 3, 4, 5, 6, 7], 0, 0);
    final order = optimalVisitOrder(matrix);
    var actual = 0.0;
    var previous = 0;
    for (final next in order) { actual += matrix[previous][next]!; previous = next; }
    expect(order.toSet(), {1, 2, 3, 4, 5, 6, 7});
    expect(actual, best);
  });

  test('Route parsing converts GeoJSON and preserves leg and visit estimates', () {
    final route = sampleRoute();
    expect(route.geometry.last.lat, routePlaces.last.lat);
    expect(route.geometry.last.lon, routePlaces.last.lon);
    expect(route.meters, 200);
    expect(route.seconds, 160);
    expect(route.walkMinutes, 3);
    expect(route.visitMinutes, 20);
    expect(route.totalMinutes, 23);
    expect(route.legs, hasLength(2));
    expect(formatMinutes(90), '1 ч 30 мин');
  });

  test('Reject incomplete geometry, incorrect totals and excessive snaps', () {
    final missing = routePayload(routePlaces);
    (missing['routes'] as List).first['geometry']['coordinates'] = [];
    expect(() => parseWalkingRoute(missing, tallinnStart, routePlaces), throwsFormatException);
    final wrongTotal = routePayload(routePlaces);
    (wrongTotal['routes'] as List).first['distance'] = 10000;
    expect(() => parseWalkingRoute(wrongTotal, tallinnStart, routePlaces), throwsFormatException);
    final farSnap = routePayload(routePlaces);
    (farSnap['waypoints'] as List)[1]['location'] = [24.7536, 59.45];
    expect(() => parseWalkingRoute(farSnap, tallinnStart, routePlaces), throwsA(isA<RouteFailure>()));
    expect(() => parseWalkingRoute({'code': 'NoSegment'}, tallinnStart, routePlaces),
      throwsA(isA<RouteFailure>()));
  });

  test('External navigation is HTTPS, pedestrian and uses destination latitude first', () {
    final uri = walkingNavigationUri(routePlaces.first.point);
    expect(uri.scheme, 'https');
    expect(uri.queryParameters['destination'], '59.4371,24.7536');
    expect(uri.queryParameters['travelmode'], 'walking');
    expect(uri.queryParameters['dir_action'], 'navigate');
    expect(uri.queryParameters.containsKey('origin'), isFalse);
  });
}
