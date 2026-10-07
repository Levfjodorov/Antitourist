import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
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
  final apiController = TextEditingController();
  final interests = <String>{'history', 'weird', 'views'};
  double hours = 2, wildness = 70;
  String mode = 'walking';
  bool demo = true, loading = false;
  String? error;

  @override
  void dispose() { apiController.dispose(); super.dispose(); }

  Future<void> generate() async {
    setState(() { loading = true; error = null; });
    final requestedDemo = demo;
    try {
      final List<Place> selected;
      if (requestedDemo) {
        final raw = jsonDecode(await rootBundle.loadString('assets/demo_places.json')) as List<dynamic>;
        selected = selectDemoPlaces(
          raw.map((item) => Place.fromJson(item as Map<String, dynamic>)).toList(),
          minutes: (hours * 60).round(), wildness: wildness.round(), interests: interests);
      } else {
        final uri = Uri.tryParse(apiController.text.trim());
        if (uri == null || uri.scheme != 'https' || uri.host.isEmpty ||
            uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) {
          throw const FormatException('Введите адрес HTTPS-сервера, например https://api.example.com');
        }
        final basePath = uri.path.replaceFirst(RegExp(r'/+$'), '');
        final response = await http.post(
          uri.replace(path: '$basePath/api/v1/routes/surprise'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'lat': 59.437, 'lon': 24.7536,
            'duration_minutes': (hours * 60).round(), 'mode': mode,
            'wildness': wildness.round(), 'interests': interests.toList()}),
        ).timeout(const Duration(seconds: 20));
        if (response.statusCode != 200) { throw Exception('HTTP ${response.statusCode}'); }
        selected = parseApiPlaces(jsonDecode(utf8.decode(response.bodyBytes)));
        if (selected.isEmpty) { throw Exception('Сервер не вернул доступных точек.'); }
      }
      if (!mounted) return;
      await Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => ResultsScreen(places: selected, demo: requestedDemo)));
    } catch (e) {
      if (mounted) { setState(() => error = 'Не удалось получить подборку. $e'); }
    } finally {
      if (mounted) { setState(() => loading = false); }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('AntiTourist · Таллинн')),
    body: ListView(padding: const EdgeInsets.all(24), children: [
      const Text('Город за пределами\nпутеводителей.',
        style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800)),
      const SizedBox(height: 12),
      const Text('История, странные детали, неожиданные места.'),
      const SizedBox(height: 20),
      SwitchListTile(contentPadding: EdgeInsets.zero,
        title: const Text('Демонстрационный режим'),
        subtitle: const Text('Вымышленные точки. Подборка работает без сервера.'),
        value: demo, onChanged: loading ? null : (v) => setState(() => demo = v)),
      if (!demo) ...[
        TextField(controller: apiController, enabled: !loading,
          keyboardType: TextInputType.url, autocorrect: false,
          decoration: const InputDecoration(labelText: 'Адрес вашего API',
            hintText: 'https://api.example.com', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        const Text('Нужен запущенный сервер. Backend 0.1 также возвращает тестовые точки.'),
      ],
      const SizedBox(height: 20),
      const Text('Старт: центр Таллинна. GPS в прототипе пока не используется.'),
      const SizedBox(height: 20),
      Text('Время: ${hours.round()} ч'),
      Slider(value: hours, min: 1, max: 5, divisions: 4,
        onChanged: loading ? null : (v) => setState(() => hours = v)),
      DropdownMenu<String>(initialSelection: mode, enabled: !loading,
        label: const Text('Как передвигаемся'), dropdownMenuEntries: const [
          DropdownMenuEntry(value: 'walking', label: 'Пешком'),
          DropdownMenuEntry(value: 'cycling', label: 'Велосипед'),
          DropdownMenuEntry(value: 'driving', label: 'Машина'),
        ], onSelected: (v) => setState(() => mode = v ?? 'walking')),
      const SizedBox(height: 24),
      Text('Необычность: ${wildness.round()}%'),
      Slider(value: wildness, min: 0, max: 100, divisions: 10,
        onChanged: loading ? null : (v) => setState(() => wildness = v)),
      const Text('Что интересно?'),
      const SizedBox(height: 8),
      Wrap(spacing: 8, children: categoryNames.entries.map((entry) => FilterChip(
        label: Text(entry.value), selected: interests.contains(entry.key),
        onSelected: loading ? null : (v) => setState(() {
          if (v) { interests.add(entry.key); } else { interests.remove(entry.key); }
        }))).toList()),
      const SizedBox(height: 24),
      if (error != null) ...[
        Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        const SizedBox(height: 12),
      ],
      FilledButton.icon(onPressed: loading ? null : generate,
        icon: loading ? const SizedBox(width: 18, height: 18,
          child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.casino_outlined),
        label: Padding(padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text(loading ? 'Ищем…' : 'УДИВИ МЕНЯ'))),
      const SizedBox(height: 12),
      const Text('Прототип 0.1.1. Время и транспорт — параметры подбора; дороги и время пути пока не рассчитываются.'),
    ]));
}

class ResultsScreen extends StatelessWidget {
  const ResultsScreen({super.key, required this.places, required this.demo});
  final List<Place> places;
  final bool demo;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Твоя подборка')),
    body: ListView(padding: const EdgeInsets.all(20), children: [
      Text('${places.length} необычных точек',
        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
      const SizedBox(height: 12),
      Text(demo ? 'ДЕМО · Все точки вымышленные. По этой подборке нельзя ориентироваться в городе.'
        : 'Данные вашего API. Backend 0.1 использует вымышленные точки. Проверяйте источник перед прогулкой.'),
      const SizedBox(height: 16),
      OutlinedButton.icon(icon: const Icon(Icons.map_outlined),
        label: const Text('Точки на карте · нужен интернет'),
        onPressed: () => Navigator.of(context).push<void>(MaterialPageRoute(
          builder: (_) => RouteMap(places: places, demo: demo)))),
      const SizedBox(height: 12),
      for (var i = 0; i < places.length; i++) Card(child: Padding(
        padding: const EdgeInsets.all(18), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${i + 1}. ${places[i].name}',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('${categoryNames[places[i].category] ?? places[i].category} · Score ${places[i].score.round()}/100'),
            const SizedBox(height: 8), Text(places[i].description),
            if (places[i].safetyNote != null) ...[
              const SizedBox(height: 10), Text(places[i].safetyNote!),
            ],
          ]))),
    ]));
}
