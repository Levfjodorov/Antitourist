import 'dart:math';
import 'package:antitourist/places.dart';
import 'package:antitourist/selection.dart';
import 'package:antitourist/walk_session.dart';
import 'package:antitourist/walking_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'route_fixtures.dart';

const extra = Place(id: 'node/3', name: 'Alternative', category: 'history', lat: 59.4373,
  lon: 24.7536, description: 'Other', score: 60, legalAccess: true);
void main() {
  test('Another selection actually changes membership and stays within the filtered pool', () {
    final replacement = anotherSelection([...routePlaces, extra], routePlaces, random: Random(1))!;
    expect(replacement.length, 2);
    expect(replacement.map((p) => p.key).toSet().length, 2);
    expect(replacement.any((p) => p.key == extra.key), isTrue);
    expect(anotherSelection(routePlaces, routePlaces), isNull);
  });
  test('Replacement options do not duplicate currently selected places', () {
    expect(alternatives([...routePlaces, extra], routePlaces, replacing: routePlaces.first), [extra]);
  });
  test('Rerouting preserves surviving marks and their original undo order', () {
    final session = WalkSession(sampleRoute())..advance(StopStatus.visited)..advance(StopStatus.skipped);
    final reversed = routePlaces.reversed.toList();
    final route = parseWalkingRoute(routePayload(reversed), tallinnStart, reversed);
    final rebased = session.rebased(route);
    expect(rebased.statuses, [StopStatus.skipped, StopStatus.visited]);
    rebased.undo();
    expect(rebased.statuses, [StopStatus.pending, StopStatus.visited]);
    final reducedPlaces = [routePlaces.first, extra];
    final reduced = session.rebased(parseWalkingRoute(routePayload(reducedPlaces), tallinnStart, reducedPlaces));
    expect(reduced.statuses, [StopStatus.visited, StopStatus.pending]);
    expect(reduced.history, [0]);
  });
}
