import 'package:flutter/material.dart';
import 'external_links.dart';
import 'google_place_links.dart';
import 'language_settings.dart';
import 'place_card.dart';
import 'place_details_service.dart';
import 'place_photo_image.dart';
import 'place_photo_screen.dart';
import 'places.dart';

class PlaceDetailsScreen extends StatefulWidget {
  const PlaceDetailsScreen({super.key, required this.place, required this.demo, this.service});
  final Place place;
  final bool demo;
  final PlaceDetailsService? service;
  @override
  State<PlaceDetailsScreen> createState() => _PlaceDetailsScreenState();
}
class _PlaceDetailsScreenState extends State<PlaceDetailsScreen> {
  late final PlaceDetailsService service;
  PlaceDetails? details;
  bool loading = false, failed = false;
  String? loadedLanguage;
  @override
  void initState() { super.initState(); service = widget.service ?? PlaceDetailsService(); }
  @override
  void dispose() { service.close(); super.dispose(); }
  Future<void> _load() async {
    final language = context.strings.language.code;
    setState(() { loading = true; failed = false; details = null; loadedLanguage = language; });
    try {
      final result = await service.load(widget.place, language);
      if (mounted) { setState(() { details = result; failed = result.partial; }); }
    } catch (_) {
      if (mounted) { setState(() => failed = true); }
    } finally {
      if (mounted) { setState(() => loading = false); }
    }
  }
  void _openPhoto(PlacePhoto photo, List<PlacePhoto> photos) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PlacePhotoScreen(
      photos: List.unmodifiable(photos), initialIndex: photos.indexOf(photo),
      placeName: context.strings.name(widget.place))));
  }
  Widget _photo(PlacePhoto photo, String label, List<PlacePhoto> photos) => Column(
    crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 12),
      Semantics(button: true, label: tr(context, 'openPhoto'), child: InkWell(
        onTap: () => _openPhoto(photo, photos),
        child: ClipRRect(borderRadius: BorderRadius.circular(12),
          child: PlacePhotoImage(photo: photo, label: label, height: 240, fit: BoxFit.cover)))),
      const SizedBox(height: 8),
      if (photo.caption != null && photo.caption!.isNotEmpty) Text(photo.caption!),
      Text(photo.credit),
      Wrap(spacing: 8, children: [
        TextButton.icon(key: ValueKey('open-photo:${photo.source}'),
          onPressed: () => _openPhoto(photo, photos),
          icon: const Icon(Icons.fullscreen), label: Text(tr(context, 'openPhoto'))),
        TextButton(onPressed: () => openInApp(context, photo.source), child: Text(tr(context, 'photoSource'))),
        if (photo.licenseUrl != null) TextButton(onPressed: () => openInApp(context, photo.licenseUrl!), child: Text(photo.license))
        else Text(photo.license),
      ]),
    ]);
  @override
  Widget build(BuildContext context) {
    final place = widget.place;
    final info = loadedLanguage == context.strings.language.code ? details : null;
    final photo = info?.photo;
    final photos = <PlacePhoto>[?photo, ...?info?.nearbyPhotos];
    final tags = place.tags;
    final address = [tags['addr:street'], tags['addr:housenumber'], tags['addr:city']]
      .whereType<String>().join(' ');
    final rawWebsite = tags['website'] ?? tags['contact:website'];
    final website = safeWebUrl(rawWebsite);
    final websiteLabel = rawWebsite == null || rawWebsite.trim().isEmpty ? null : rawWebsite;
    final phone = tags['phone'] ?? tags['contact:phone'];
    return Scaffold(appBar: AppBar(title: Text(tr(context, 'placeDetails')), actions: const [LanguageMenu()]),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text(context.strings.name(place), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold))),
          FavoriteButton(place: place),
        ]),
        Text(context.strings.category(place.category)),
        const SizedBox(height: 12),
        Text(tr(context, 'reason_${place.category}')),
        const SizedBox(height: 12),
        Text(context.strings.description(place)),
        if (widget.demo) Text(tr(context, 'demoBanner')) else ...[
          const SizedBox(height: 12),
          Text(context.strings.access(place)),
          if (context.strings.safety(place) case final safety?) Text(safety),
          if (address.isNotEmpty) ListTile(contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.location_on_outlined), title: Text(tr(context, 'address')),
            subtitle: SelectableText(address)),
          if (tags['opening_hours'] case final hours?) ...[
            Text(tr(context, 'hoursRaw', {'value': context.strings.openingHours(hours)})),
            Text(tr(context, 'hoursUnverified')),
          ],
          if (phone != null) ListTile(contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.phone_outlined), title: Text(tr(context, 'phone')),
            subtitle: SelectableText(phone)),
          if (tags['fee'] case final fee?) Text(tr(context, 'feeRaw', {'value':
            fee == 'yes' ? tr(context, 'yes') : fee == 'no' ? tr(context, 'no') : fee})),
          if (tags['wheelchair'] case final wheelchair?) Text(tr(context, 'wheelchairRaw', {'value':
            wheelchair == 'yes' ? tr(context, 'yes') : wheelchair == 'no' ? tr(context, 'no')
              : wheelchair == 'limited' ? tr(context, 'limited') : wheelchair})),
          if (website != null) TextButton.icon(onPressed: () => openInApp(context, website),
            icon: const Icon(Icons.language), label: Text(tr(context, 'website'))),
          if (website == null && websiteLabel != null) SelectableText(tr(context, 'websiteRaw', {'value': websiteLabel})),
          if (place.osmUrl != null) TextButton.icon(onPressed: () => openInApp(context, place.osmUrl!),
            icon: const Icon(Icons.open_in_new), label: Text(tr(context, 'source'))),
          const Divider(height: 32),
          Text(tr(context, 'moreInfoTitle'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          Text(tr(context, 'photoPrivacy')),
          const SizedBox(height: 12),
          OutlinedButton.icon(onPressed: loading ? null : _load,
            icon: loading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.photo_outlined),
            label: Text(tr(context, loading ? 'detailsLoading' : 'loadDetails'))),
          if (failed) Text(tr(context, 'detailsError')),
          if (info != null) ...[
            if (photo != null) _photo(photo, context.strings.name(place), photos)
            else if (!info.partial) Text(tr(context, 'noPhoto')),
            if (info.nearbyPhotos.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(tr(context, 'nearbyPhotosTitle'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              Text(tr(context, 'nearbyPhotosHint')),
              for (final nearby in info.nearbyPhotos) ...[
                Text(tr(context, 'nearbyPhotoDistance', {'distance': nearby.nearbyMeters!.round()})),
                _photo(nearby, tr(context, 'nearbyPhotosTitle'), photos),
              ],
            ],
            if (info.description != null) ...[
              const SizedBox(height: 12), SelectableText(info.description!),
              Text(tr(context, 'sourceLanguageHint')),
            ] else if (!info.partial) Text(tr(context, 'noExtraInfo')),
            if (info.article != null) TextButton.icon(onPressed: () => openInApp(context, info.article!),
              icon: const Icon(Icons.open_in_new), label: Text(tr(context, 'articleSource'))),
            if (info.description != null && info.article?.host.endsWith('.wikipedia.org') == true)
              TextButton(onPressed: () => openInApp(context, Uri.parse('https://en.wikipedia.org/wiki/Wikipedia:Copyrights')),
                child: Text(tr(context, 'wikipediaLicense'))),
          ],
          const Divider(height: 32),
          Text(tr(context, 'googlePhotosTitle'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          Text(tr(context, 'googlePhotosHint')),
          OutlinedButton.icon(onPressed: () => openInApp(context,
            googlePlaceSearch(place, context.strings.name(place))), icon: const Icon(Icons.open_in_new),
            label: Text(tr(context, 'googlePlaceSearch'))),
          const SizedBox(height: 12), Text(tr(context, 'placeDataHint')),
        ],
      ]));
  }
}
