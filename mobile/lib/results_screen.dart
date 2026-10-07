import 'package:flutter/material.dart';
import 'external_links.dart';
import 'places.dart';
import 'route_map.dart';
import 'routing_service.dart';
import 'walk_screen.dart';
import 'walk_session.dart';
import 'walking_route.dart';

class ResultsScreen extends StatefulWidget {
  const ResultsScreen({super.key, required this.places, required this.demo,
    required this.start, required this.candidateCount, required this.requestedMinutes,
    this.routingService});
  final List<Place> places;
  final bool demo;
  final GeoPoint start;
  final int candidateCount, requestedMinutes;
  final RoutingService? routingService;
  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  late final RoutingService _service;
  WalkingRoute? _route;
  WalkSession? _session;
  bool _building = false;
  String? _error;
  @override
  void initState() { super.initState(); _service = widget.routingService ?? RoutingService(); }
  @override
  void dispose() { _service.close(); super.dispose(); }

  Future<void> _buildRoute() async {
    setState(() { _building = true; _error = null; });
    try {
      final result = await _service.build(widget.start, widget.places);
      if (!mounted) { return; }
      setState(() { _route = result; _session = WalkSession(result); });
    } on RouteFailure catch (e) {
      if (mounted) { setState(() => _error = e.message); }
    } catch (_) {
      if (mounted) { setState(() => _error = 'Не удалось рассчитать маршрут. Повтори позже.'); }
    } finally {
      if (mounted) { setState(() => _building = false); }
    }
  }

  Future<void> _openWalk() async {
    await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) =>
      WalkScreen(session: _session!, start: widget.start)));
    if (mounted) { setState(() {}); }
  }

  @override
  Widget build(BuildContext context) {
    final route = _route;
    final places = route?.places ?? widget.places;
    return Scaffold(
      appBar: AppBar(title: const Text('Твоя подборка')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Text('${places.length} необычных точек',
          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Text(widget.demo ? 'ДЕМО · Все точки вымышленные.'
          : 'Отобрано из ${widget.candidateCount} объектов OSM.'),
        if (!widget.demo) ...[
          const Padding(padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('Рейтинг основан на типе объекта. Популярность и количество туристов пока неизвестны.')),
          if (route == null) ...[
            const Text('Построй пеший маршрут: упорядочим места по времени переходов и покажем путь по улицам.'),
            const Text('Старт и точки отправятся сервису FOSSGIS/OSRM для расчёта.'),
            const SizedBox(height: 12),
            FilledButton.icon(onPressed: _building ? null : _buildRoute,
              icon: _building ? const SizedBox(width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.route_outlined),
              label: Text(_building ? 'Рассчитываем путь…' : 'Построить пеший маршрут')),
            if (_building) const Text('Расчёт обычно занимает несколько секунд; при медленном ответе — до минуты.'),
            if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ] else ...[
            Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Пешком ${formatDistance(route.meters)} · ≈ ${formatMinutes(route.walkMinutes)}',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                Text('С остановками: ≈ ${formatMinutes(route.totalMinutes)}'),
                Text('Заложено по 10 мин на место: всего ${route.visitMinutes} мин.'),
                Text('Финиш: ${places.last.name}'),
                if (route.snapDistances.any((distance) => distance > 5))
                  const Text('Линия проходит по ближайшим пешеходным участкам в пределах 75 м от маркеров. Подходы к входам проверь на месте.'),
                if (route.totalMinutes > widget.requestedMinutes)
                  Text('Подборка длиннее выбранных ${formatMinutes(widget.requestedMinutes)}. Выбери меньший радиус или другую подборку.'),
              ]))),
            FilledButton.icon(onPressed: _openWalk, icon: const Icon(Icons.directions_walk),
              label: Text(_session!.complete ? 'Посмотреть итог прогулки'
                : _session!.processed > 0 ? 'Продолжить прогулку' : 'Начать прогулку')),
            const Text('Путь рассчитан по пешеходным данным OSM. Время приблизительное; входы и ограничения проверь на месте.'),
          ],
        ],
        const SizedBox(height: 12),
        OutlinedButton.icon(icon: const Icon(Icons.map_outlined),
          label: Text(route == null ? 'Показать на карте' : 'Показать маршрут на карте'),
          onPressed: () => Navigator.of(context).push<void>(MaterialPageRoute(
            builder: (_) => RouteMap(places: places, demo: widget.demo, start: widget.start, route: route)))),
        const SizedBox(height: 12),
        for (var i = 0; i < places.length; i++) Card(child: Padding(
          padding: const EdgeInsets.all(18), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${i + 1}. ${places[i].name}',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('${categoryNames[places[i].category]} · Необычность ${places[i].score.round()}/100'),
              if (!widget.demo) Text('${formatDistance(places[i].distance)} от старта по прямой'),
              if (route != null) Text('Переход: ${formatDistance(route.legs[i].meters)} · ≈ '
                '${formatMinutes((route.legs[i].seconds / 60).ceil())} ${i == 0 ? 'от старта' : 'от предыдущей точки'}'),
              const SizedBox(height: 10), Text(places[i].description),
              if (!widget.demo) ...[
                const SizedBox(height: 10), Text(places[i].accessLabel),
                if (places[i].coordinateIsCenter)
                  const Text('Маркер — центр объекта, а не подтверждённый вход.'),
                if (route != null && route.snapDistances[i + 1] > 5)
                  Text('Путь подходит на ${route.snapDistances[i + 1].round()} м к маркеру объекта.'),
              ],
              if (places[i].safetyNote != null) ...[
                const SizedBox(height: 10), Text(places[i].safetyNote!),
              ],
              if (route != null) TextButton.icon(onPressed: () => openExternal(context,
                walkingNavigationUri(route.snappedPoints[i + 1])), icon: const Icon(Icons.navigation_outlined),
                label: const Text('Навигация Google Maps')),
              if (places[i].osmUrl != null) TextButton.icon(
                onPressed: () => openExternal(context, places[i].osmUrl!),
                icon: const Icon(Icons.open_in_new), label: const Text('Источник OSM')),
            ]))),
        if (!widget.demo) ...[
          const Text('Данные © OpenStreetMap contributors. Маршруты: OSRM / FOSSGIS.'),
          TextButton(onPressed: () => openExternal(context, Uri.parse('https://routing.openstreetmap.de/about.html')),
            child: const Text('О сервисе маршрутов')),
          TextButton(onPressed: () => openExternal(context, Uri.parse('https://www.openstreetmap.org/fixthemap')),
            child: const Text('Сообщить об ошибке карты OSM')),
        ],
      ]),
    );
  }
}
