import 'dart:convert';
import 'package:antitourist/places.dart';
import 'package:antitourist/results_screen.dart';
import 'package:antitourist/routing_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'route_fixtures.dart';

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
}
