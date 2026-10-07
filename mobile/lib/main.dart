import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:geolocator/geolocator.dart';
import 'external_links.dart';
import 'language_settings.dart';
import 'osm.dart';
import 'overpass.dart';
import 'places.dart';
import 'results_screen.dart';
import 'route_map.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await LanguageSettings.load();
  runApp(AntiTouristApp(settings: settings));
}

class AntiTouristApp extends StatefulWidget {
  const AntiTouristApp({super.key, this.settings});
  final LanguageSettings? settings;
  @override
  State<AntiTouristApp> createState() => _AntiTouristAppState();
}

class _AntiTouristAppState extends State<AntiTouristApp> {
  late final LanguageSettings settings;
  @override
  void initState() { super.initState(); settings = widget.settings ?? LanguageSettings(); }
  @override
  void dispose() { if (widget.settings == null) { settings.dispose(); } super.dispose(); }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: settings,
    builder: (_, child) => LanguageScope(settings: settings, child: MaterialApp(
      debugShowCheckedModeBanner: false, title: 'AntiTourist',
      locale: Locale(settings.language.code),
      supportedLocales: const [Locale('ru'), Locale('et'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(useMaterial3: true, brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xffb5f36a),
        scaffoldBackgroundColor: const Color(0xff111711)),
      home: const HomeScreen())));
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
  String startLabel = 'startTallinn';
  int? accuracyMeters;
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
        startLabel = 'startGps'; accuracyMeters = position.accuracy.round();
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
      start = point; startLabel = 'startMap'; error = null; locationSettings = null;
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
        places: selected, demo: requestedDemo, start: origin, candidateCount: candidateCount, requestedMinutes: (hours * 60).round())));
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
    appBar: AppBar(actions: const [LanguageMenu()], title: const Text('AntiTourist · 0.4.0')),
    body: ListView(padding: const EdgeInsets.all(24), children: [
      Align(alignment: Alignment.centerLeft, child: Image.asset(
        'assets/branding/logo_foreground.png', width: 112, height: 112,
        semanticLabel: tr(context, 'logo'))),
      const SizedBox(height: 12),
      Text(tr(context, 'headline'),
        style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800)),
      const SizedBox(height: 12),
      Text(tr(context, 'intro')),
      const SizedBox(height: 20),
      Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr(context, startLabel, {'distance': accuracyMeters ?? 0}), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            OutlinedButton.icon(onPressed: loading ? null : locate,
              icon: const Icon(Icons.my_location), label: Text(tr(context, 'myLocation'))),
            TextButton(onPressed: loading ? null : pickStart, child: Text(tr(context, 'chooseMap'))),
            TextButton(onPressed: loading ? null : () => setState(() {
              start = tallinnStart; startLabel = 'startTallinn'; error = null; locationSettings = null;
            }), child: Text(tr(context, 'tallinn'))),
          ]),
        ]))),
      const SizedBox(height: 12),
      Text(tr(context, 'radius', {'value': radiusKm.round()})),
      Slider(value: radiusKm, min: 1, max: 5, divisions: 4,
        onChanged: loading || demo ? null : (v) => setState(() => radiusKm = v)),
      Text(tr(context, 'hours', {'value': hours.round()})),
      Slider(value: hours, min: 1, max: 5, divisions: 4,
        onChanged: loading ? null : (v) => setState(() => hours = v)),
      Text(tr(context, 'timeHint')),
      const SizedBox(height: 20),
      Text(tr(context, 'novelty', {'value': wildness.round()})),
      Slider(value: wildness, min: 0, max: 100, divisions: 10,
        onChanged: loading ? null : (v) => setState(() => wildness = v)),
      Text(tr(context, 'noveltyHint')),
      const SizedBox(height: 12),
      Text(tr(context, 'interests')),
      const SizedBox(height: 8),
      Wrap(spacing: 8, children: categoryNames.entries.map((entry) => FilterChip(
        label: Text(context.strings.category(entry.key)), selected: interests.contains(entry.key),
        onSelected: loading ? null : (v) => setState(() {
          if (v) { interests.add(entry.key); } else { interests.remove(entry.key); }
        }))).toList()),
      if (!demo) SwitchListTile(contentPadding: EdgeInsets.zero,
        title: Text(tr(context, 'publicOnly')),
        subtitle: Text(tr(context, 'publicHint')),
        value: onlyPublic, onChanged: loading ? null : (v) => setState(() => onlyPublic = v)),
      SwitchListTile(contentPadding: EdgeInsets.zero,
        title: Text(tr(context, 'demoMode')),
        subtitle: Text(tr(context, 'demoHint')),
        value: demo, onChanged: loading ? null : (v) => setState(() => demo = v)),
      if (error != null) ...[
        Text(context.strings.error(error!), style: TextStyle(color: Theme.of(context).colorScheme.error)),
        if (locationSettings != null) TextButton(onPressed: () async {
          if (locationSettings == 'app') { await Geolocator.openAppSettings(); }
          else { await Geolocator.openLocationSettings(); }
        }, child: Text(tr(context, 'settings'))),
        const SizedBox(height: 12),
      ],
      FilledButton.icon(onPressed: loading ? null : generate,
        icon: loading ? const SizedBox(width: 18, height: 18,
          child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.casino_outlined),
        label: Padding(padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text(loading ? tr(context, 'wait') : tr(context, 'surprise')))),
      const SizedBox(height: 14),
      Text(tr(context, 'privacy')),
      TextButton(onPressed: () => openExternal(context, Uri.parse('https://www.openstreetmap.org/copyright')),
        child: Text(tr(context, 'attribution'))),
    ]));
}
