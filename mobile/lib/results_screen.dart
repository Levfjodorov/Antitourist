import 'package:flutter/material.dart';
import 'external_links.dart';
import 'language_settings.dart';
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
      appBar: AppBar(actions: const [LanguageMenu()], title: Text(tr(context, 'results'))),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Text(tr(context, 'placeCount', {'count': places.length}),
          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Text(widget.demo ? tr(context, 'demoBanner')
          : tr(context, 'selectedFrom', {'count': widget.candidateCount})),
        if (!widget.demo) ...[
          Padding(padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(tr(context, 'ratingHint'))),
          if (route == null) ...[
            Text(tr(context, 'routeIntro')),
            Text(tr(context, 'routePrivacy')),
            const SizedBox(height: 12),
            FilledButton.icon(onPressed: _building ? null : _buildRoute,
              icon: _building ? const SizedBox(width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.route_outlined),
              label: Text(_building ? tr(context, 'building') : tr(context, 'buildRoute'))),
            if (_building) Text(tr(context, 'buildingHint')),
            if (_error != null) Text(context.strings.error(_error!), style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ] else ...[
            Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr(context, 'walkSummary', {'distance': context.strings.distance(route.meters), 'time': context.strings.minutes(route.walkMinutes)}),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                Text(tr(context, 'withStops', {'time': context.strings.minutes(route.totalMinutes)})),
                Text(tr(context, 'stopEstimate', {'time': context.strings.minutes(route.visitMinutes)})),
                Text(tr(context, 'finish', {'name': context.strings.name(places.last)})),
                if (route.snapDistances.any((distance) => distance > 5))
                  Text(tr(context, 'entranceHint')),
                if (route.totalMinutes > widget.requestedMinutes)
                  Text(tr(context, 'tooLong', {'time': context.strings.minutes(widget.requestedMinutes)})),
              ]))),
            FilledButton.icon(onPressed: _openWalk, icon: const Icon(Icons.directions_walk),
              label: Text(_session!.complete ? tr(context, 'walkResult')
                : _session!.processed > 0 ? tr(context, 'continueWalk') : tr(context, 'startWalk'))),
            Text(tr(context, 'routeCaution')),
          ],
        ],
        const SizedBox(height: 12),
        OutlinedButton.icon(icon: const Icon(Icons.map_outlined),
          label: Text(route == null ? tr(context, 'showMap') : tr(context, 'showRoute')),
          onPressed: () => Navigator.of(context).push<void>(MaterialPageRoute(
            builder: (_) => RouteMap(places: places, demo: widget.demo, start: widget.start, route: route)))),
        const SizedBox(height: 12),
        for (var i = 0; i < places.length; i++) Card(child: Padding(
          padding: const EdgeInsets.all(18), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${i + 1}. ${context.strings.name(places[i])}',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(tr(context, 'placeCategory', {'category': context.strings.category(places[i].category), 'score': places[i].score.round()})),
              if (!widget.demo) Text(tr(context, 'fromStart', {'distance': context.strings.distance(places[i].distance)})),
              if (route != null) Text(tr(context, 'leg', {'distance': context.strings.distance(route.legs[i].meters),
                'time': context.strings.minutes((route.legs[i].seconds / 60).ceil()),
                'origin': tr(context, i == 0 ? 'originStart' : 'originPrevious')})),
              const SizedBox(height: 10), Text(context.strings.description(places[i])),
              if (!widget.demo) ...[
                const SizedBox(height: 10), Text(context.strings.access(places[i])),
                if (places[i].coordinateIsCenter)
                  Text(tr(context, 'markerCenter')),
                if (route != null && route.snapDistances[i + 1] > 5)
                  Text(tr(context, 'snap', {'distance': route.snapDistances[i + 1].round()})),
              ],
              if (places[i].safetyNote != null) ...[
                const SizedBox(height: 10), Text(context.strings.safety(places[i])!),
              ],
              if (route != null) TextButton.icon(onPressed: () => openExternal(context,
                walkingNavigationUri(route.snappedPoints[i + 1])), icon: const Icon(Icons.navigation_outlined),
                label: Text(tr(context, 'navigation'))),
              if (places[i].osmUrl != null) TextButton.icon(
                onPressed: () => openExternal(context, places[i].osmUrl!),
                icon: const Icon(Icons.open_in_new), label: Text(tr(context, 'source'))),
            ]))),
        if (!widget.demo) ...[
          Text(tr(context, 'routingAttribution')),
          TextButton(onPressed: () => openExternal(context, Uri.parse('https://routing.openstreetmap.de/about.html')),
            child: Text(tr(context, 'aboutRouting'))),
          TextButton(onPressed: () => openExternal(context, Uri.parse('https://www.openstreetmap.org/fixthemap')),
            child: Text(tr(context, 'fixMap'))),
        ],
      ]),
    );
  }
}
