import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'osm.dart';
import 'places.dart';

class SearchFailure implements Exception {
  const SearchFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

class OverpassService {
  OverpassService({http.Client? client, DateTime Function()? now})
      : _client = client ?? http.Client(), _now = now ?? DateTime.now;
  final http.Client _client;
  final DateTime Function() _now;
  final _cache = <String, ({DateTime fetched, dynamic payload})>{};
  DateTime? _lastRequest;
  DateTime? _retryAfter;
  bool _busy = false;

  void close() => _client.close();

  Future<List<Place>> search(GeoPoint start, int radius, Set<String> interests) async {
    final query = buildOverpassQuery(start, radius, interests);
    final cached = _cache[query];
    if (cached != null && _now().difference(cached.fetched) < const Duration(minutes: 5)) {
      return parseOsmPlaces(cached.payload, start, radius);
    }
    if (_busy) { throw const SearchFailure('Поиск уже выполняется.'); }
    if (_retryAfter != null && _now().isBefore(_retryAfter!)) {
      throw const SearchFailure('Сервис карт перегружен. Подожди минуту и повтори поиск.');
    }
    if (_lastRequest != null && _now().difference(_lastRequest!) < const Duration(seconds: 20)) {
      throw const SearchFailure('Подожди 20 секунд перед новым запросом к сервису карт.');
    }
    _busy = true;
    _lastRequest = _now();
    try {
      final response = await _client.post(
        Uri.https('overpass-api.de', '/api/interpreter'),
        headers: {'User-Agent': 'AntiTourist/0.2 (Android prototype)', 'Accept': 'application/json'},
        body: {'data': query},
      ).timeout(const Duration(seconds: 35));
      if (response.statusCode == 429) {
        _retryAfter = _now().add(const Duration(minutes: 1));
        throw const SearchFailure('Сервис карт перегружен. Подожди минуту и повтори поиск.');
      }
      if (response.statusCode != 200) {
        throw SearchFailure('Сервис карт вернул HTTP ${response.statusCode}. Повтори позже.');
      }
      if (response.bodyBytes.length > 16 * 1024 * 1024) {
        throw const SearchFailure('Слишком большой ответ. Уменьши радиус поиска.');
      }
      final payload = jsonDecode(utf8.decode(response.bodyBytes));
      final places = parseOsmPlaces(payload, start, radius);
      if (_cache.length >= 6) { _cache.remove(_cache.keys.first); }
      _cache[query] = (fetched: _now(), payload: payload);
      return places;
    } on TimeoutException {
      throw const SearchFailure('Сервис карт не ответил вовремя. Повтори позже или уменьши радиус.');
    } on http.ClientException {
      throw const SearchFailure('Не удалось связаться с сервисом карт. Проверь интернет.');
    } on FormatException {
      throw const SearchFailure('Сервис вернул неполные или некорректные данные. Повтори позже.');
    } finally {
      _busy = false;
    }
  }
}
