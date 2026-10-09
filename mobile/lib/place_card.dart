import 'package:flutter/material.dart';
import 'app_store.dart';
import 'external_links.dart';
import 'walking_route.dart';
import 'language_settings.dart';
import 'places.dart';
import 'place_details_screen.dart';

class FavoriteButton extends StatelessWidget {
  const FavoriteButton({super.key, required this.place});
  final Place place;
  @override
  Widget build(BuildContext context) {
    final store = AppStoreScope.of(context);
    if (store == null) { return const SizedBox.shrink(); }
    final favorite = store.isFavorite(place);
    return IconButton(tooltip: tr(context, favorite ? 'removeFavorite' : 'addFavorite'),
      icon: Icon(favorite ? Icons.favorite : Icons.favorite_border),
      onPressed: () async {
        final success = await store.toggleFavorite(place);
        if (!success && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(context, 'dataSaveError'))));
        }
      });
  }
}

class PlaceCard extends StatelessWidget {
  const PlaceCard({super.key, required this.place, required this.demo, this.number,
    this.routeInfo, this.onReplace, this.onRemove, this.enabled = true, this.navigationPoint, this.showDistance = true});
  final Place place;
  final bool demo, enabled, showDistance;
  final GeoPoint? navigationPoint;
  final int? number;
  final String? routeInfo;
  final VoidCallback? onReplace, onRemove;
  @override
  Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.all(16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: Text('${number == null ? '' : '$number. '}${context.strings.name(place)}',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
        FavoriteButton(place: place),
      ]),
      Text(context.strings.category(place.category), style: TextStyle(color: Theme.of(context).colorScheme.primary)),
      if (AppStoreScope.of(context)?.isVisited(place) == true) Text(tr(context, 'visitedPlace')),
      if (AppStoreScope.of(context)?.isExcluded(place) == true) Text(tr(context, 'excludedTab')),
      const SizedBox(height: 8),
      Text(tr(context, 'reason_${place.category}')),
      if (demo) Text(tr(context, 'fictionalPlace'))
      else ...[
        if (showDistance) Text(tr(context, 'fromStart', {'distance': context.strings.distance(place.distance)})),
        if (routeInfo != null) Text(routeInfo!),
        const SizedBox(height: 8),
        Text(context.strings.access(place)),
        if (place.tags['opening_hours'] case final hours?)
          Text(tr(context, 'hoursRaw', {'value': context.strings.openingHours(hours)})),
        if (place.coordinateIsCenter) Text(tr(context, 'markerCenter')),
      ],
      const SizedBox(height: 8),
      Text(context.strings.description(place), maxLines: 4, overflow: TextOverflow.ellipsis),
      Wrap(spacing: 4, children: [
        TextButton.icon(onPressed: () => Navigator.of(context).push<void>(MaterialPageRoute(
          builder: (_) => PlaceDetailsScreen(place: place, demo: demo))),
          icon: const Icon(Icons.info_outline), label: Text(tr(context, 'placeDetails'))),
        if (navigationPoint != null) TextButton.icon(onPressed: () => openExternal(context,
          walkingNavigationUri(navigationPoint!)), icon: const Icon(Icons.navigation_outlined),
          label: Text(tr(context, 'navigation'))),
        if (onReplace != null) TextButton.icon(key: ValueKey('replace-${place.key}'), onPressed: enabled ? onReplace : null,
          icon: const Icon(Icons.swap_horiz), label: Text(tr(context, 'replacePlace'))),
        if (onRemove != null) TextButton.icon(key: ValueKey('remove-${place.key}'), onPressed: enabled ? onRemove : null,
          icon: const Icon(Icons.remove_circle_outline), label: Text(tr(context, 'removePlace'))),
      ]),
    ])));
}
