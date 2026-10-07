import 'dart:convert';
import 'package:antitourist/places.dart';
import 'package:antitourist/results_screen.dart';
import 'package:antitourist/routing_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'route_fixtures.dart';
import 'test_helpers.dart';

void main() {
  testWidgets('A routing failure keeps the original places visible and permits retry', (tester) async {
    var calls = 0;
    final service = RoutingService(client: MockClient((_) async {
      calls++; return http.Response('offline', 503);
    }));
    await tester.pumpWidget(MaterialApp(home: ResultsScreen(places: routePlaces, demo: false,
      start: tallinnStart, candidateCount: 2, requestedMinutes: 60, routingService: service)));
    await tester.tap(find.text('Построить пеший маршрут'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.text('Сервис маршрутов временно недоступен. Попробуй позже.'), findsOneWidget);
    expect(find.text('Построить пеший маршрут'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('1. Первое место'), 150);
    expect(find.text('1. Первое место'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('A valid route opens the walking session without loading map tiles', (tester) async {
    var now = DateTime.utc(2026, 10, 7);
    final service = RoutingService(now: () => now, delay: (d) async { now = now.add(d); },
      client: MockClient((request) async {
        final payload = request.url.path.contains('/table/')
          ? {'code': 'Ok', 'durations': [[0, 1, 10], [1, 0, 1], [1, 1, 0]]}
          : routePayload(routePlaces);
        return http.Response(jsonEncode(payload), 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
      }));
    await tester.pumpWidget(MaterialApp(home: ResultsScreen(places: routePlaces, demo: false,
      start: tallinnStart, candidateCount: 2, requestedMinutes: 60, routingService: service)));
    await tester.tap(find.text('Построить пеший маршрут'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Начать прогулку'), 150);
    await tester.tap(find.text('Начать прогулку'));
    await tester.pumpAndSettle();
    expect(find.text('Твоя прогулка'), findsOneWidget);
    expect(find.text('Первое место'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Removing a place reroutes and a failed edit keeps the previous plan', (tester) async {
    var now = DateTime.utc(2026, 10, 7);
    var unavailable = false;
    final service = RoutingService(now: () => now, delay: (d) async { now = now.add(d); },
      client: MockClient((request) async {
        if (unavailable) { return http.Response('offline', 503); }
        final count = request.url.path.split('/').last.split(';').length - 1;
        final places = count == 1 ? [routePlaces.last] : routePlaces;
        final payload = request.url.path.contains('/table/')
          ? {'code': 'Ok', 'durations': count == 1 ? [[0, 1], [1, 0]]
              : [[0, 1, 10], [1, 0, 1], [1, 1, 0]]}
          : routePayload(places);
        return http.Response(jsonEncode(payload), 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
      }));
    await tester.pumpWidget(MaterialApp(home: ResultsScreen(places: routePlaces, demo: false,
      start: tallinnStart, candidateCount: 2, requestedMinutes: 60, routingService: service)));
    await tapVisibleControl(tester, 'Построить пеший маршрут');
    unavailable = true;
    final remove = find.byKey(const ValueKey('remove-node/1'));
    await tester.scrollUntilVisible(remove, 200); await tester.pumpAndSettle();
    await tester.tap(remove); await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Мест в подборке: 2'), -200);
    expect(find.text('Мест в подборке: 2'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Изменение не применено: прежние места и маршрут сохранены. Попробуй ещё раз.'), 200);
    expect(find.text('Изменение не применено: прежние места и маршрут сохранены. Попробуй ещё раз.'), findsOneWidget);
    unavailable = false;
    await tester.scrollUntilVisible(remove, 200); await tester.pumpAndSettle();
    await tester.tap(remove); await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Мест в подборке: 1'), -200);
    expect(find.text('Мест в подборке: 1'), findsOneWidget);
    expect(find.text('Мест в подборке: 2'), findsNothing);
    expect(tester.takeException(), isNull);
  });

}
