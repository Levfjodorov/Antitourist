import 'package:flutter/material.dart';
import 'external_links.dart';
import 'language_settings.dart';
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
      appBar: AppBar(actions: const [LanguageMenu()], title: Text(tr(context, 'walkTitle'))),
      body: ListView(padding: const EdgeInsets.all(24), children: [
        LinearProgressIndicator(value: session.processed / route.places.length),
        const SizedBox(height: 12),
        Text(tr(context, 'progress', {'done': session.processed, 'total': route.places.length})),
        const SizedBox(height: 20),
        if (index == null) ...[
          const Icon(Icons.flag_outlined, size: 64),
          Text(tr(context, 'complete'), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
          Text(tr(context, 'visitedSkipped', {'visited': session.visited, 'skipped': session.skipped})),
          const SizedBox(height: 16),
          Text(tr(context, 'planned', {'distance': context.strings.distance(route.meters), 'time': context.strings.minutes(route.walkMinutes)})),
          Text(tr(context, 'plannedHint')),
          TextButton(onPressed: () => setState(session.restart), child: Text(tr(context, 'restart'))),
        ] else ...[
          Text(tr(context, 'nextStop', {'index': index + 1, 'total': route.places.length}),
            style: const TextStyle(fontSize: 18)),
          Text(context.strings.name(route.places[index]),
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Text(tr(context, 'leg', {'distance': context.strings.distance(route.legs[index].meters),
            'time': context.strings.minutes((route.legs[index].seconds / 60).ceil()),
            'origin': tr(context, index == 0 ? 'originStart' : 'originPrevious')})),
          const SizedBox(height: 16),
          Text(context.strings.description(route.places[index])),
          const SizedBox(height: 12),
          Text(context.strings.access(route.places[index])),
          if (route.places[index].safetyNote != null) Text(context.strings.safety(route.places[index])!),
          if (route.snapDistances[index + 1] > 5)
            Text(tr(context, 'snap', {'distance': route.snapDistances[index + 1].round()})),
          const SizedBox(height: 20),
          OutlinedButton.icon(onPressed: () => openExternal(context,
            walkingNavigationUri(route.snappedPoints[index + 1])),
            icon: const Icon(Icons.navigation_outlined), label: Text(tr(context, 'navigation'))),
          Text(tr(context, 'googleHint')),
          const SizedBox(height: 16),
          FilledButton.icon(onPressed: () => setState(() => session.advance(StopStatus.visited)),
            icon: const Icon(Icons.check), label: Text(tr(context, 'visited'))),
          TextButton(onPressed: () => setState(() => session.advance(StopStatus.skipped)),
            child: Text(tr(context, 'skip'))),
          Text(tr(context, 'skipHint')),
        ],
        const SizedBox(height: 12),
        if (session.canUndo) TextButton(onPressed: () => setState(session.undo),
          child: Text(tr(context, 'undo'))),
        OutlinedButton.icon(icon: const Icon(Icons.map_outlined), label: Text(tr(context, 'wholeWalk')),
          onPressed: () => Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => RouteMap(
            places: route.places, demo: false, start: widget.start, route: route)))),
        const SizedBox(height: 16),
        Text(tr(context, 'progressHint')),
      ]),
    );
  }
}
