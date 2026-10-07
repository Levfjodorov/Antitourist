import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'places.dart';
import 'walking_route.dart';

class RoutingService {
  RoutingService({http.Client? client, DateTime Function()? now,
      Future<void> Function(Duration)? delay})
    : _client = client ?? http.Client(), _now = now ?? DateTime.now,
      _delay = delay ?? ((duration) => Future<void>.delayed(duration));
  final http.Client _client;
  final DateTime Function() _now;
  final Future<void> Function(Duration) _delay;
  final _cache = <String, ({DateTime fetched, dynamic payload})>{};
  DateTime? _lastSent, _retryAfter;
  bool _busy = false, _closed = false;

  void close() { _closed = true; _client.close(); }

  Future<dynamic> _getJson(Uri uri) async {
    final cached = _cache[uri.toString()];
    if (cached != null && _now().difference(cached.fetched) < const Duration(minutes: 10)) {
      return cached.payload;
    }
    if (_closed) { throw const RouteFailure('Расчёт отменён.'); }
    if (_retryAfter != null && _now().isBefore(_retryAfter!)) {
      throw const RouteFailure('Сервис маршрутов перегружен. Подожди минуту и повтори.');
    }
    // FOSSGIS allows at most one request per second. Space all network requests,
    // including the table followed by route, retries and changed queries.
    if (_lastSent != null) {
      final remaining = const Duration(milliseconds: 1100) - _now().difference(_lastSent!);
      if (remaining > Duration.zero) { await _delay(remaining); }
    }
    if (_closed) { throw const RouteFailure('Расчёт отменён.'); }
    _lastSent = _now();
    final response = await _client.get(uri, headers: {
      'User-Agent': 'AntiTourist/0.3 Android test (https://github.com/Levfjodorov/Antitourist)',
      'Accept': 'application/json',
    }).timeout(const Duration(seconds: 25));
    if (response.statusCode == 429) {
      _retryAfter = _now().add(const Duration(minutes: 1));
      throw const RouteFailure('Сервис маршрутов перегружен. Подожди минуту и повтори.');
    }
    if (response.statusCode != 200 && response.statusCode != 400) {
      throw RouteFailure('Сервис маршрутов вернул HTTP ${response.statusCode}. Повтори позже.');
    }
    if (response.bodyBytes.length > 8 * 1024 * 1024) {
      throw const RouteFailure('Ответ маршрутизатора слишком большой. Выбери меньше мест.');
    }
    final payload = jsonDecode(utf8.decode(response.bodyBytes));
    checkOsrmStatus(payload);
    // Parsing of each response is checked before it can become a cached result.
    return payload;
  }

  void _remember(String key, dynamic payload) {
    if (_cache.length >= 8 && !_cache.containsKey(key)) { _cache.remove(_cache.keys.first); }
    _cache[key] = (fetched: _now(), payload: payload);
  }

  Future<WalkingRoute> build(GeoPoint start, List<Place> places) async {
    if (_closed) { throw const RouteFailure('Расчёт отменён.'); }
    if (_busy) { throw const RouteFailure('Маршрут уже рассчитывается.'); }
    if (!start.valid || places.isEmpty || places.length > 7 || places.any((p) => !p.point.valid)) {
      throw const RouteFailure('Для маршрута нужны старт и от 1 до 7 мест.');
    }
    _busy = true;
    try {
      final input = [start, for (final p in places) p.point];
      final tableUri = footRequestUri('table', input);
      final tablePayload = await _getJson(tableUri);
      final matrix = parseFootMatrix(tablePayload, input.length);
      _remember(tableUri.toString(), tablePayload);
      final order = optimalVisitOrder(matrix);
      final ordered = [for (final i in order) places[i - 1]];
      final routeUri = footRequestUri('route', [start, for (final p in ordered) p.point]);
      final routePayload = await _getJson(routeUri);
      final route = parseWalkingRoute(routePayload, start, ordered);
      _remember(routeUri.toString(), routePayload);
      return route;
    } on TimeoutException {
      throw const RouteFailure('Сервис маршрутов не ответил вовремя. Повтори позже.');
    } on http.ClientException {
      throw const RouteFailure('Не удалось связаться с сервисом маршрутов. Проверь интернет.');
    } on FormatException {
      throw const RouteFailure('Сервис вернул неполный или некорректный маршрут. Повтори позже.');
    } finally {
      _busy = false;
    }
  }
}
