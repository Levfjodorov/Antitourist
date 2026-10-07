import 'dart:async';
import 'dart:convert';
import 'package:antitourist/places.dart';
import 'package:antitourist/routing_service.dart';
import 'package:antitourist/walking_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'route_fixtures.dart';

http.Response reply(Object data, {int status = 200}) => http.Response(jsonEncode(data), status,
  headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  test('Build makes only two pedestrian requests, spaces them and caches parsed results', () async {
    var now = DateTime.utc(2026, 10, 7);
    final sent = <DateTime>[];
    final paths = <String>[];
    final service = RoutingService(now: () => now,
      delay: (duration) async { now = now.add(duration); },
      client: MockClient((request) async {
        sent.add(now); paths.add(request.url.path);
        expect(request.headers['user-agent'], contains('AntiTourist/0.3'));
        expect(request.url.path, startsWith('/routed-foot/'));
        if (request.url.path.contains('/table/')) {
          return reply({'code': 'Ok', 'durations': [[0, 100, 1], [1, 0, 100], [1, 1, 0]]});
        }
        return reply(routePayload(routePlaces.reversed.toList()));
      }));
    addTearDown(service.close);
    final route = await service.build(tallinnStart, routePlaces);
    expect(route.places.first.name, 'Второе место');
    expect(paths, hasLength(2));
    expect(sent.last.difference(sent.first), greaterThanOrEqualTo(const Duration(milliseconds: 1100)));
    await service.build(tallinnStart, routePlaces);
    expect(sent, hasLength(2));
    now = now.add(const Duration(minutes: 11));
    await service.build(tallinnStart, routePlaces);
    expect(sent, hasLength(4));
  });

  test('Unreachable places stop before the route request', () async {
    var calls = 0;
    final service = RoutingService(client: MockClient((_) async {
      calls++; return reply({'code': 'Ok', 'durations': [[0, null, null], [null, 0, null], [null, null, 0]]});
    }));
    addTearDown(service.close);
    await expectLater(service.build(tallinnStart, routePlaces), throwsA(isA<RouteFailure>()));
    expect(calls, 1);
  });

  test('429 enforces a minute cooldown and performs no automatic retry', () async {
    var now = DateTime.utc(2026, 10, 7);
    var calls = 0;
    final service = RoutingService(now: () => now,
      delay: (d) async { now = now.add(d); }, client: MockClient((_) async {
        calls++; return reply({}, status: 429);
      }));
    addTearDown(service.close);
    await expectLater(service.build(tallinnStart, routePlaces), throwsA(isA<RouteFailure>()));
    now = now.add(const Duration(seconds: 30));
    await expectLater(service.build(tallinnStart, routePlaces), throwsA(isA<RouteFailure>()));
    expect(calls, 1);
    now = now.add(const Duration(seconds: 31));
    await expectLater(service.build(tallinnStart, routePlaces), throwsA(isA<RouteFailure>()));
    expect(calls, 2);
  });

  test('Incomplete route is not cached and can be retried', () async {
    var now = DateTime.utc(2026, 10, 7);
    var routes = 0;
    final service = RoutingService(now: () => now,
      delay: (d) async { now = now.add(d); }, client: MockClient((request) async {
        if (request.url.path.contains('/table/')) {
          return reply({'code': 'Ok', 'durations': [[0, 1, 10], [1, 0, 1], [1, 1, 0]]});
        }
        routes++;
        return routes == 1 ? reply({'code': 'Ok', 'routes': []}) : reply(routePayload(routePlaces));
      }));
    addTearDown(service.close);
    await expectLater(service.build(tallinnStart, routePlaces), throwsA(isA<RouteFailure>()));
    expect((await service.build(tallinnStart, routePlaces)).places, hasLength(2));
    expect(routes, 2);
  });

  test('Parallel calculations are rejected and transport failures are readable', () async {
    final pending = Completer<http.Response>();
    final service = RoutingService(client: MockClient((_) => pending.future));
    addTearDown(service.close);
    final first = service.build(tallinnStart, routePlaces);
    await expectLater(service.build(tallinnStart, routePlaces), throwsA(isA<RouteFailure>()));
    pending.complete(reply({'code': 'NoTable'}, status: 400));
    await expectLater(first, throwsA(isA<RouteFailure>()));
    final offline = RoutingService(client: MockClient((_) async { throw http.ClientException('offline'); }));
    addTearDown(offline.close);
    await expectLater(offline.build(tallinnStart, routePlaces), throwsA(isA<RouteFailure>()));
  });
}
