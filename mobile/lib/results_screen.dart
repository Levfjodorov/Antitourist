import 'package:flutter/material.dart';
import 'external_links.dart';
import 'app_store.dart';
import 'saved_data.dart';
import 'selection.dart';
import 'place_card.dart';
import 'language_settings.dart';
import 'places.dart';
import 'route_map.dart';
import 'routing_service.dart';
import 'walk_screen.dart';
import 'walk_session.dart';
import 'walking_route.dart';
import 'offline_store.dart';

class ResultsScreen extends StatefulWidget {
  const ResultsScreen({super.key, required this.places, required this.demo,
    required this.start, required this.candidateCount, required this.requestedMinutes,
    this.routingService, this.candidates = const [], this.savedWalk});
  final List<Place> places, candidates;
  final SavedWalk? savedWalk;
  final bool demo;
  final GeoPoint start;
  final int candidateCount, requestedMinutes;
  final RoutingService? routingService;
  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  late final RoutingService _service;
  late List<Place> _selected;
  late List<Place> _pool;
  String? _savedId;
  DateTime? _created;
  bool _saving = false;
  WalkingRoute? _route;
  WalkSession? _session;
  bool _building = false;
  String? _error;
  @override
  void initState() { super.initState(); _service = widget.routingService ?? RoutingService();
    _selected = List.of(widget.places);
    final unique = <String, Place>{for (final p in widget.places) p.key: p,
      for (final p in widget.candidates) p.key: p};
    _pool = unique.values.take(500).toList();
    _session = widget.savedWalk?.session;
    _route = _session?.route;
    _savedId = widget.savedWalk?.id;
    _created = widget.savedWalk?.created; }
  @override
  void dispose() { _service.close(); super.dispose(); }

  Future<bool> _save({bool showMessage = false}) async {
    final store = AppStoreScope.of(context);
    if (store == null) { return true; }
    final now = DateTime.now();
    _savedId ??= now.microsecondsSinceEpoch.toString();
    _created ??= now;
    setState(() => _saving = true);
    final success = await store.put(SavedWalk(id: _savedId!, start: widget.start,
      places: List.of(_route?.places ?? _selected), candidates: _pool, demo: widget.demo,
      requestedMinutes: widget.requestedMinutes, created: _created!, updated: now, session: _session));
    if (mounted) {
      setState(() => _saving = false);
      if (showMessage) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(context,
          success ? 'walkSaved' : 'dataSaveError'))));
      }
    }
    return success;
  }

  Future<void> _buildRoute([List<Place>? replacement]) async {
    setState(() { _building = true; _error = null; });
    try {
      final result = await _service.build(widget.start, replacement ?? _selected);
      if (!mounted) { return; }
      setState(() {
        _session = _session?.rebased(result) ?? WalkSession(result);
        _route = result; _selected = List.of(result.places);
      });
      await _save();
    } on RouteFailure catch (e) {
      if (mounted) { setState(() => _error = e.message); }
    } catch (_) {
      if (mounted) { setState(() => _error = 'Не удалось рассчитать маршрут. Повтори позже.'); }
    } finally {
      if (mounted) { setState(() => _building = false); }
    }
  }

  Future<void> _apply(List<Place> replacement) async {
    if (_route != null) { await _buildRoute(replacement); }
    else {
      setState(() { _selected = replacement; _error = null; });
      if (_savedId != null) { await _save(); }
    }
  }

  Future<void> _another() async {
    final store = AppStoreScope.of(context);
    final pool = _pool.where((p) => store?.canSuggest(p) ?? true).toList();
    final replacement = anotherSelection(pool, _selected);
    if (replacement == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(context, 'noAlternatives'))));
      return;
    }
    await _apply(replacement);
  }

  Future<void> _replace(Place place) async {
    final store = AppStoreScope.of(context);
    final options = alternatives(_pool.where((p) => store?.canSuggest(p) ?? true).toList(), _selected, replacing: place);
    if (options.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(context, 'noAlternatives'))));
      return;
    }
    final chosen = await showModalBottomSheet<Place>(context: context, isScrollControlled: true,
      builder: (context) => SafeArea(child: SizedBox(height: MediaQuery.sizeOf(context).height * 0.65,
        child: Column(children: [
          Padding(padding: const EdgeInsets.all(16), child: Text(tr(context, 'chooseReplacement'),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
          Expanded(child: ListView.builder(itemCount: options.length, itemBuilder: (context, i) => ListTile(
            title: Text(context.strings.name(options[i])),
            subtitle: Text('${context.strings.category(options[i].category)} · ${context.strings.distance(options[i].distance)}'),
            onTap: () => Navigator.pop(context, options[i])))),
        ]))));
    if (chosen != null && mounted) {
      await _apply([for (final p in _selected) p.key == place.key ? chosen : p]);
    }
  }

  Future<void> _prepareOffline({bool allowMobileData = false}) async {
    final offline = OfflineScope.of(context);
    if (offline == null || _route == null || !await _save() || !mounted) { return; }
    final store = AppStoreScope.of(context)!;
    final walk = store.walks.firstWhere((w) => w.id == _savedId);
    final language = context.strings.language.code;
    final success = await offline.prepare(walk, language, allowMobileData: allowMobileData);
    if (mounted) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(context,
      success ? 'offlineReady' : 'offlinePartial')))); }
  }

  Future<void> _openWalk() async {
    await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) =>
      WalkScreen(session: _session!, start: widget.start, onChanged: () => _save())));
    if (mounted) { setState(() {}); }
  }

  @override
  Widget build(BuildContext context) {
    final route = _route;
    final places = route?.places ?? _selected;
    final offline = OfflineScope.of(context);
    final busy = _building || _saving || (offline?.busy ?? false);
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
            FilledButton.icon(onPressed: busy ? null : () => _buildRoute(),
              icon: _building ? const SizedBox(width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.route_outlined),
              label: Text(_building ? tr(context, 'building') : tr(context, 'buildRoute'))),
            if (_building) Text(tr(context, 'buildingHint')),
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
            FilledButton.icon(onPressed: busy ? null : _openWalk, icon: const Icon(Icons.directions_walk),
              label: Text(_session!.complete ? tr(context, 'walkResult')
                : _session!.processed > 0 ? tr(context, 'continueWalk') : tr(context, 'startWalk'))),
            Text(tr(context, 'routeCaution')),
            if (offline?.available == true) ...[
              Text(tr(context, 'offlineHint')),
              if (offline!.ready(_savedId, route, context.strings.language.code)) Text(tr(context, 'offlineReady')),
              OutlinedButton.icon(key: const ValueKey('prepare-offline'),
                onPressed: busy ? null : () => _prepareOffline(), icon: const Icon(Icons.download_for_offline_outlined),
                label: Text(tr(context, 'prepareOffline'))),
              if (!offline.ready(_savedId, route, context.strings.language.code)) TextButton(
                onPressed: busy ? null : () => _prepareOffline(allowMobileData: true),
                child: Text(tr(context, 'prepareOfflineMobile'))),
              if (offline.busy) ...[LinearProgressIndicator(value: offline.total == 0 ? null : offline.done / offline.total),
                Text(tr(context, 'offlineProgress', {'done': offline.done, 'total': offline.total}))],
              if (offline.saveFailed || offline.loadFailed) Text(tr(context, 'offlineStorageError')),
            ],
          ],
        ],
        const SizedBox(height: 12),
        OutlinedButton.icon(icon: const Icon(Icons.map_outlined),
          label: Text(route == null ? tr(context, 'showMap') : tr(context, 'showRoute')),
          onPressed: () => Navigator.of(context).push<void>(MaterialPageRoute(
            builder: (_) => RouteMap(places: places, demo: widget.demo, start: widget.start, route: route)))),
        const SizedBox(height: 12),
        const StorageNotice(),
        if (_error != null) ...[
          Text(context.strings.error(_error!), style: TextStyle(color: Theme.of(context).colorScheme.error)),
          if (route != null) Text(tr(context, 'editFailedKept')),
        ],
        if (AppStoreScope.of(context) != null) OutlinedButton.icon(
          onPressed: busy ? null : () => _save(showMessage: true), icon: const Icon(Icons.bookmark_outline),
          label: Text(tr(context, _saving ? 'saving' : 'saveWalk'))),
        if (!widget.demo) Text(tr(context, 'autoSaveHint')),
        OutlinedButton.icon(onPressed: busy ? null : _another, icon: const Icon(Icons.casino_outlined),
          label: Text(tr(context, 'anotherSelection'))),
        Text(tr(context, 'editSelectionHint')),
        if (_building && route != null) Text(tr(context, 'recalculating')),
        const SizedBox(height: 12),
        for (var i = 0; i < places.length; i++) PlaceCard(place: places[i], demo: widget.demo, number: i + 1,
          enabled: !busy, navigationPoint: route?.snappedPoints[i + 1],
          routeInfo: route == null ? null : tr(context, 'leg', {
            'distance': context.strings.distance(route.legs[i].meters),
            'time': context.strings.minutes((route.legs[i].seconds / 60).ceil()),
            'origin': tr(context, i == 0 ? 'originStart' : 'originPrevious')}) +
            (route.snapDistances[i + 1] > 5 ? '\n${tr(context, 'snap', {'distance': route.snapDistances[i + 1].round()})}' : ''),
          onReplace: () => _replace(places[i]),
          onRemove: places.length > 1 ? () => _apply(places.where((p) => p.key != places[i].key).toList()) : null),
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
