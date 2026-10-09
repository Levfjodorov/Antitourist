import 'package:flutter/material.dart';
import 'app_store.dart';
import 'language_settings.dart';
import 'place_card.dart';
import 'results_screen.dart';
import 'saved_data.dart';
import 'offline_store.dart';
import 'places.dart';

Future<void> openSavedWalk(BuildContext context, SavedWalk walk) =>
  Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => ResultsScreen(
    places: walk.places, candidates: walk.candidates, demo: walk.demo,
    start: walk.start, candidateCount: walk.candidates.length,
    requestedMinutes: walk.requestedMinutes, savedWalk: walk)));

class MyPlacesScreen extends StatelessWidget {
  const MyPlacesScreen({super.key});
  Future<void> _delete(BuildContext context, SavedWalk walk) async {
    final accepted = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: Text(tr(context, 'deleteWalk')),
      content: Text(tr(context, 'deleteWalkHint')),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr(context, 'cancel'))),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr(context, 'delete')))]));
    if (accepted == true && context.mounted) { await AppStoreScope.of(context)!.remove(walk.id); }
  }
  Widget _walks(BuildContext context, List<SavedWalk> walks, String empty) => ListView(
    padding: const EdgeInsets.all(20), children: [
      const StorageNotice(),
      if (walks.isEmpty) Text(tr(context, empty)),
      for (final walk in walks) Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(context.strings.name(walk.places.first), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          Text(tr(context, 'savedWalkCount', {'count': walk.places.length})),
          Text(MaterialLocalizations.of(context).formatMediumDate(walk.updated.toLocal())),
          if (walk.demo) Text(tr(context, 'demoBanner')),
          if (walk.complete) Text(tr(context, 'visitedSkipped', {'visited': walk.session!.visited, 'skipped': walk.session!.skipped})),
          if (walk.session != null) ...[
            Text(tr(context, 'progress', {'done': walk.session!.processed, 'total': walk.places.length})),
            Text(tr(context, 'walkSummary', {'distance': context.strings.distance(walk.session!.route.meters),
              'time': context.strings.minutes(walk.session!.route.walkMinutes)})),
          ],
          Wrap(spacing: 8, children: [
            FilledButton(onPressed: () => openSavedWalk(context, walk),
              child: Text(tr(context, walk.complete ? 'walkResult' : 'openSavedWalk'))),
            TextButton(onPressed: () => _delete(context, walk), child: Text(tr(context, 'delete'))),
            if (walk.session != null && OfflineScope.of(context)?.streets(walk.session!.route) != null)
              TextButton(onPressed: () async {
                final ok = await OfflineScope.of(context)!.remove(walk.id);
                if (context.mounted) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(context, ok ? 'offlineRemoved' : 'dataSaveError')))); }
              }, child: Text(tr(context, 'removeOffline'))),
          ]),
        ]))),
    ]);
  Widget _places(BuildContext context, List<Place> places, String empty) => ListView(
    padding: const EdgeInsets.all(20), children: [const StorageNotice(),
      if (places.isEmpty) Text(tr(context, empty)),
      for (final place in places) PlaceCard(place: place, demo: place.osmUrl == null, showDistance: false),
    ]);
  @override
  Widget build(BuildContext context) {
    final store = AppStoreScope.of(context)!;
    return DefaultTabController(length: 6, child: Scaffold(
      appBar: AppBar(title: Text(tr(context, 'myPlaces')), actions: const [LanguageMenu()],
        bottom: TabBar(isScrollable: true, tabs: [Tab(text: tr(context, 'savedTab')), Tab(text: tr(context, 'favoritesTab')),
          Tab(text: tr(context, 'historyTab')), Tab(text: tr(context, 'visitedTab')),
          Tab(text: tr(context, 'notesTab')), Tab(text: tr(context, 'excludedTab'))])),
      body: TabBarView(children: [
        _walks(context, store.saved, 'emptySaved'),
        ListView(padding: const EdgeInsets.all(20), children: [
          const StorageNotice(),
          if (store.favorites.isEmpty) Text(tr(context, 'emptyFavorites')),
          for (final place in store.favorites) PlaceCard(place: place, demo: place.osmUrl == null, showDistance: false),
        ]),
        _walks(context, store.history, 'emptyHistory'),
        _places(context, store.visitedPlaces, 'emptyVisited'),
        _places(context, store.memories.where((m) => m.hasContent).map((m) => m.place).toList(), 'emptyNotes'),
        _places(context, store.memories.where((m) => m.excluded).map((m) => m.place).toList(), 'emptyExcluded'),
      ])));
  }
}
