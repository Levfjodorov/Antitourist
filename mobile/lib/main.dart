import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'external_links.dart';
import 'osm.dart';
import 'overpass.dart';
import 'places.dart';
import 'route_map.dart';

void main() => runApp(const AntiTouristApp());

class AntiTouristApp extends StatelessWidget {
  const AntiTouristApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false, title: 'AntiTourist',
    theme: ThemeData(useMaterial3: true, brightness: Brightness.dark,
      colorSchemeSeed: const Color(0xffb5f36a),
      scaffoldBackgroundColor: const Color(0xff111711)),
    home: const HomeScreen());
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final service = OverpassService();
  final interests = <String>{'history', 'weird', 'views'};
  GeoPoint start = tallinnStart;
  String startLabel = 'Центр Таллинна';
  double hours = 2, wildness = 70, radiusKm = 2;
  bool demo = false, onlyPublic = false, loading = false;
  String? error;
  String? locationSettings;

  @override
  void dispose() { service.close(); super.dispose(); }

  Future<void> locate() async {
    setState(() { loading = true; error = null; locationSettings = null; });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        locationSettings = 'device';
        throw const SearchFailure('Включи геолокацию на телефоне или выбери старт на карте.');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        locationSettings = 'app';
        throw const SearchFailure('Разреши геолокацию в настройках AntiTourist или выбери старт на карте.');
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.unableToDetermine) {
        throw const SearchFailure('Геолокация не разрешена. Можно выбрать старт на карте.');
      }
      final position = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 20)));
      final point = GeoPoint(position.latitude, position.longitude);
      if (!point.valid) { throw const SearchFailure('Телефон вернул некорректные координаты.'); }
      if (mounted) { setState(() {
        start = point;
        startLabel = 'Моя геопозиция · точность ≈ ${position.accuracy.round()} м';
      }); }
    } on TimeoutException {
      if (mounted) { setState(() => error = 'Не удалось определить позицию за 20 секунд. Повтори снаружи или выбери точку на карте.'); }
    } on SearchFailure catch (e) {
      if (mounted) { setState(() => error = e.message); }
    } catch (_) {
      if (mounted) { setState(() => error = 'Не удалось получить геопозицию. Выбери старт на карте.'); }
    } finally {
      if (mounted) { setState(() => loading = false); }
    }
  }

  Future<void> pickStart() async {
    final point = await Navigator.of(context).push<GeoPoint>(MaterialPageRoute(
      builder: (_) => StartPicker(initial: start)));
    if (point != null && mounted) { setState(() {
      start = point; startLabel = 'Старт выбран на карте'; error = null; locationSettings = null;
    }); }
  }

  Future<void> generate() async {
    if (interests.isEmpty) {
      setState(() => error = 'Выбери хотя бы один интерес.');
      return;
    }
    setState(() { loading = true; error = null; locationSettings = null; });
    final requestedDemo = demo;
    final origin = requestedDemo ? tallinnStart : start;
    try {
      final List<Place> selected;
      var candidateCount = 0;
      if (requestedDemo) {
        final raw = jsonDecode(await rootBundle.loadString('assets/demo_places.json')) as List<dynamic>;
        selected = selectDemoPlaces(
          raw.map((item) => Place.fromJson(item as Map<String, dynamic>)).toList(),
          minutes: (hours * 60).round(), wildness: wildness.round(), interests: interests);
      } else {
        final radius = (radiusKm * 1000).round();
        final candidates = await service.search(origin, radius, Set.of(interests));
        candidateCount = candidates.length;
        selected = rankLivePlaces(candidates, start: origin, radius: radius,
          minutes: (hours * 60).round(), wildness: wildness.round(),
          interests: interests, onlyPublicAccess: onlyPublic);
        if (selected.isEmpty) {
          throw SearchFailure(onlyPublic
            ? 'Нет мест с явно указанным разрешённым доступом. Измени фильтр или радиус.'
            : 'Подходящих мест не найдено. Увеличь радиус или выбери другие интересы.');
        }
      }
      if (!mounted) { return; }
      await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => ResultsScreen(
        places: selected, demo: requestedDemo, start: origin, candidateCount: candidateCount)));
    } on SearchFailure catch (e) {
      if (mounted) { setState(() => error = e.message); }
    } catch (_) {
      if (mounted) { setState(() => error = 'Поиск не завершился. Проверь интернет и повтори позже.'); }
    } finally {
      if (mounted) { setState(() => loading = false); }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('AntiTourist · 0.2')),
    body: ListView(padding: const EdgeInsets.all(24), children: [
      const Text('Город за пределами\nпутеводителей.',
        style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800)),
      const SizedBox(height: 12),
      const Text('Найди интересные детали рядом: искусство, историю, виды и кофе.'),
      const SizedBox(height: 20),
      Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(startLabel, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          Text('${start.lat.toStringAsFixed(5)}, ${start.lon.toStringAsFixed(5)}'),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            OutlinedButton.icon(onPressed: loading ? null : locate,
              icon: const Icon(Icons.my_location), label: const Text('Моя геопозиция')),
            TextButton(onPressed: loading ? null : pickStart, child: const Text('Выбрать на карте')),
            TextButton(onPressed: loading ? null : () => setState(() {
              start = tallinnStart; startLabel = 'Центр Таллинна'; error = null; locationSettings = null;
            }), child: const Text('Таллинн')),
          ]),
        ]))),
      const SizedBox(height: 12),
      Text('Радиус поиска: ${radiusKm.round()} км'),
      Slider(value: radiusKm, min: 1, max: 5, divisions: 4,
        onChanged: loading || demo ? null : (v) => setState(() => radiusKm = v)),
      Text('Время на прогулку: ${hours.round()} ч'),
      Slider(value: hours, min: 1, max: 5, divisions: 4,
        onChanged: loading ? null : (v) => setState(() => hours = v)),
      const Text('Время пока определяет размер подборки, а не длительность пути.'),
      const SizedBox(height: 20),
      Text('Необычность: ${wildness.round()}%'),
      Slider(value: wildness, min: 0, max: 100, divisions: 10,
        onChanged: loading ? null : (v) => setState(() => wildness = v)),
      const Text('Больше необычности — выше вес типов объектов; меньше — выше вес близости.'),
      const SizedBox(height: 12),
      Wrap(spacing: 8, children: categoryNames.entries.map((entry) => FilterChip(
        label: Text(entry.value), selected: interests.contains(entry.key),
        onSelected: loading ? null : (v) => setState(() {
          if (v) { interests.add(entry.key); } else { interests.remove(entry.key); }
        }))).toList()),
      if (!demo) SwitchListTile(contentPadding: EdgeInsets.zero,
        title: const Text('Только с разрешённым доступом в OSM'),
        subtitle: const Text('У многих мест доступ не указан, поэтому этот фильтр сокращает подборку.'),
        value: onlyPublic, onChanged: loading ? null : (v) => setState(() => onlyPublic = v)),
      SwitchListTile(contentPadding: EdgeInsets.zero,
        title: const Text('Демонстрационный режим'),
        subtitle: const Text('Вымышленные точки из версии 0.1'),
        value: demo, onChanged: loading ? null : (v) => setState(() => demo = v)),
      if (error != null) ...[
        Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        if (locationSettings != null) TextButton(onPressed: () async {
          if (locationSettings == 'app') { await Geolocator.openAppSettings(); }
          else { await Geolocator.openLocationSettings(); }
        }, child: const Text('Открыть настройки')),
        const SizedBox(height: 12),
      ],
      FilledButton.icon(onPressed: loading ? null : generate,
        icon: loading ? const SizedBox(width: 18, height: 18,
          child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.casino_outlined),
        label: Padding(padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text(loading ? 'Подожди…' : 'УДИВИ МЕНЯ'))),
      const SizedBox(height: 14),
      const Text('Для поиска координаты старта отправляются сервису Overpass. Карта загружается из OpenStreetMap. GPS запрашивается по кнопке.'),
      TextButton(onPressed: () => openExternal(context, Uri.parse('https://www.openstreetmap.org/copyright')),
        child: const Text('Данные © OpenStreetMap contributors')),
    ]));
}

class ResultsScreen extends StatelessWidget {
  const ResultsScreen({super.key, required this.places, required this.demo,
    required this.start, required this.candidateCount});
  final List<Place> places;
  final bool demo;
  final GeoPoint start;
  final int candidateCount;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Твоя подборка')),
    body: ListView(padding: const EdgeInsets.all(20), children: [
      Text('${places.length} необычных точек',
        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
      const SizedBox(height: 12),
      Text(demo ? 'ДЕМО · Все точки вымышленные.'
        : 'Отобрано из $candidateCount объектов OSM. Расстояния по прямой; путь по улицам ещё не рассчитан.'),
      if (!demo) const Padding(padding: EdgeInsets.symmetric(vertical: 12),
        child: Text('Рейтинг основан на типе объекта. Популярность и количество туристов пока неизвестны.')),
      OutlinedButton.icon(icon: const Icon(Icons.map_outlined),
        label: const Text('Показать на карте'),
        onPressed: () => Navigator.of(context).push<void>(MaterialPageRoute(
          builder: (_) => RouteMap(places: places, demo: demo, start: start)))),
      const SizedBox(height: 12),
      for (var i = 0; i < places.length; i++) Card(child: Padding(
        padding: const EdgeInsets.all(18), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${i + 1}. ${places[i].name}',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('${categoryNames[places[i].category]} · Необычность ${places[i].score.round()}/100'),
            if (!demo) Text('${formatDistance(places[i].distance)} от старта по прямой'),
            const SizedBox(height: 10), Text(places[i].description),
            if (!demo) ...[
              const SizedBox(height: 10), Text(places[i].accessLabel),
              if (places[i].coordinateIsCenter)
                const Text('Маркер — центр объекта, а не подтверждённый вход.'),
            ],
            if (places[i].safetyNote != null) ...[
              const SizedBox(height: 10), Text(places[i].safetyNote!),
            ],
            if (places[i].osmUrl != null) TextButton.icon(
              onPressed: () => openExternal(context, places[i].osmUrl!),
              icon: const Icon(Icons.open_in_new), label: const Text('Источник OSM')),
          ]))),
      if (!demo) const Text('Данные © OpenStreetMap contributors. Доступность и часы работы могут меняться.'),
    ]));
}
