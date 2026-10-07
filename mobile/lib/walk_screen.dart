import 'package:flutter/material.dart';
import 'external_links.dart';
import 'places.dart';
import 'route_map.dart';
import 'walk_session.dart';
import 'walking_route.dart';

class WalkScreen extends StatefulWidget {
  const WalkScreen({super.key, required this.session, required this.start});
  final WalkSession session;
  final GeoPoint start;
  @override
  State<WalkScreen> createState() => _WalkScreenState();
}

class _WalkScreenState extends State<WalkScreen> {
  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final route = session.route;
    final index = session.currentIndex;
    return Scaffold(
      appBar: AppBar(title: const Text('Твоя прогулка')),
      body: ListView(padding: const EdgeInsets.all(24), children: [
        LinearProgressIndicator(value: session.processed / route.places.length),
        const SizedBox(height: 12),
        Text('Завершено ${session.processed} из ${route.places.length}'),
        const SizedBox(height: 20),
        if (index == null) ...[
          const Icon(Icons.flag_outlined, size: 64),
          const Text('Прогулка завершена', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
          Text('Посещено: ${session.visited} · Пропущено: ${session.skipped}'),
          const SizedBox(height: 16),
          Text('Запланировано: ${formatDistance(route.meters)} · ходьба ${formatMinutes(route.walkMinutes)}'),
          const Text('Это параметры рассчитанного пути, а не измеренный пройденный трек.'),
          TextButton(onPressed: () => setState(session.restart), child: const Text('Начать заново')),
        ] else ...[
          Text('Точка ${index + 1} из ${route.places.length}',
            style: const TextStyle(fontSize: 18)),
          Text(route.places[index].name,
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Text('${formatDistance(route.legs[index].meters)} · ≈ ${formatMinutes((route.legs[index].seconds / 60).ceil())} '
            '${index == 0 ? 'от старта' : 'от предыдущей точки'}'),
          const SizedBox(height: 16),
          Text(route.places[index].description),
          const SizedBox(height: 12),
          Text(route.places[index].accessLabel),
          if (route.places[index].safetyNote != null) Text(route.places[index].safetyNote!),
          if (route.snapDistances[index + 1] > 5)
            Text('Пешеходный путь проходит в ${route.snapDistances[index + 1].round()} м от маркера объекта. Вход проверь на месте.'),
          const SizedBox(height: 20),
          OutlinedButton.icon(onPressed: () => openExternal(context,
            walkingNavigationUri(route.snappedPoints[index + 1])),
            icon: const Icon(Icons.navigation_outlined), label: const Text('Навигация Google Maps')),
          const Text('Google Maps построит свой пеший путь от текущего местоположения; он может отличаться от линии здесь.'),
          const SizedBox(height: 16),
          FilledButton.icon(onPressed: () => setState(() => session.advance(StopStatus.visited)),
            icon: const Icon(Icons.check), label: const Text('Посетил · следующая точка')),
          TextButton(onPressed: () => setState(() => session.advance(StopStatus.skipped)),
            child: const Text('Пропустить точку')),
          const Text('После пропуска общий путь не пересчитывается. Навигация ведёт к следующей точке от твоей позиции.'),
        ],
        const SizedBox(height: 12),
        if (session.canUndo) TextButton(onPressed: () => setState(session.undo),
          child: const Text('Отменить последнюю отметку')),
        OutlinedButton.icon(icon: const Icon(Icons.map_outlined), label: const Text('Карта всей прогулки'),
          onPressed: () => Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => RouteMap(
            places: route.places, demo: false, start: widget.start, route: route)))),
        const SizedBox(height: 16),
        const Text('Прогресс хранится до закрытия приложения. Отмечай посещение вручную; фонового слежения нет.'),
      ]),
    );
  }
}
