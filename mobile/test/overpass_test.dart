import 'dart:async';
import 'dart:convert';
import 'package:antitourist/overpass.dart';
import 'package:antitourist/places.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response reply(Object payload, {int status = 200}) => http.Response(
  jsonEncode(payload), status,
  headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  test('Posts bounded query via HTTPS and caches valid results for five minutes', () async {
    var calls = 0;
    var now = DateTime.utc(2026, 10, 7);
    final service = OverpassService(now: () => now, client: MockClient((request) async {
      calls++;
      expect(request.method, 'POST');
      expect(request.url.toString(), 'https://overpass-api.de/api/interpreter');
      final form = Uri.splitQueryString(request.body);
      expect(form['data'], contains('out body center;'));
      return reply({'elements': [{'type': 'node', 'id': 1, 'lat': 59.437,
        'lon': 24.7536, 'tags': {'tourism': 'artwork', 'name': 'Рисунок'}}]});
    }));
    addTearDown(service.close);
    expect((await service.search(tallinnStart, 2000, {'weird'})).single.name, 'Рисунок');
    await service.search(tallinnStart, 2000, {'weird'});
    expect(calls, 1);
    now = now.add(const Duration(minutes: 6));
    await service.search(tallinnStart, 2000, {'weird'});
    expect(calls, 2);
  });

  test('Changed queries are throttled, without an automatic second request', () async {
    var calls = 0;
    var now = DateTime.utc(2026, 10, 7);
    final service = OverpassService(now: () => now, client: MockClient((_) async {
      calls++; return reply({'elements': []});
    }));
    addTearDown(service.close);
    await service.search(tallinnStart, 2000, {'weird'});
    await expectLater(service.search(tallinnStart, 3000, {'weird'}),
      throwsA(isA<SearchFailure>()));
    expect(calls, 1);
    now = now.add(const Duration(seconds: 21));
    await service.search(tallinnStart, 3000, {'weird'});
    expect(calls, 2);
  });

  test('429 prevents additional requests for a minute', () async {
    var calls = 0;
    var now = DateTime.utc(2026, 10, 7);
    final service = OverpassService(now: () => now, client: MockClient((_) async {
      calls++; return reply({}, status: 429);
    }));
    addTearDown(service.close);
    await expectLater(service.search(tallinnStart, 2000, {'views'}),
      throwsA(isA<SearchFailure>()));
    now = now.add(const Duration(seconds: 30));
    await expectLater(service.search(tallinnStart, 2000, {'views'}),
      throwsA(isA<SearchFailure>()));
    expect(calls, 1);
    now = now.add(const Duration(seconds: 31));
    await expectLater(service.search(tallinnStart, 2000, {'views'}),
      throwsA(isA<SearchFailure>()));
    expect(calls, 2);
  });

  test('Parallel queries are rejected', () async {
    final pending = Completer<http.Response>();
    final service = OverpassService(client: MockClient((_) => pending.future));
    addTearDown(service.close);
    final first = service.search(tallinnStart, 2000, {'views'});
    await expectLater(service.search(tallinnStart, 3000, {'views'}),
      throwsA(isA<SearchFailure>()));
    pending.complete(reply({'elements': []}));
    expect(await first, isEmpty);
  });

  test('A partial response is not cached and has no fictional fallback', () async {
    var calls = 0;
    var now = DateTime.utc(2026, 10, 7);
    final service = OverpassService(now: () => now, client: MockClient((_) async {
      calls++; return reply({'remark': 'runtime error', 'elements': []});
    }));
    addTearDown(service.close);
    await expectLater(service.search(tallinnStart, 2000, {'views'}),
      throwsA(isA<SearchFailure>()));
    now = now.add(const Duration(seconds: 21));
    await expectLater(service.search(tallinnStart, 2000, {'views'}),
      throwsA(isA<SearchFailure>()));
    expect(calls, 2);
  });

  test('HTTP errors, invalid JSON and network errors become readable failures', () async {
    for (final response in [reply({}, status: 503), http.Response('<html>', 200)]) {
      final service = OverpassService(client: MockClient((_) async => response));
      await expectLater(service.search(tallinnStart, 2000, {'views'}),
        throwsA(isA<SearchFailure>()));
      service.close();
    }
    final service = OverpassService(client: MockClient((_) async {
      throw http.ClientException('offline');
    }));
    addTearDown(service.close);
    await expectLater(service.search(tallinnStart, 2000, {'views'}),
      throwsA(isA<SearchFailure>()));
  });
}
