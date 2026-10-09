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
  int request = 0;
  @override
  void initState() { super.initState(); service = widget.service ?? PlaceDetailsService.shared; }
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!widget.demo && loadedLanguage != context.strings.language.code) { _load(); }
  }
  @override
  void dispose() {
    request++;
    if (widget.service != null) { service.close(); }
    super.dispose();
  }
  Future<void> _load() async {
    final language = context.strings.language.code;
    final currentRequest = ++request;
    setState(() { loading = true; failed = false; details = null; loadedLanguage = language; });
    try {
      final result = await service.load(widget.place, language);
      if (mounted && currentRequest == request) { setState(() { details = result; failed = result.partial; }); }
    } catch (_) {
      if (mounted && currentRequest == request) { setState(() => failed = true); }
    } finally {
      if (mounted && currentRequest == request) { setState(() => loading = false); }
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
  List<Widget> _information(PlaceDetails? info, PlacePhoto? photo, List<PlacePhoto> photos) => [
    const SizedBox(height: 16),
    Text(tr(context, 'moreInfoTitle'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
    if (loading) SizedBox(height: 180, child: Center(child: Column(
      mainAxisSize: MainAxisSize.min, children: [
        const CircularProgressIndicator(), const SizedBox(height: 12),
        Text(tr(context, 'detailsLoading')),
      ]))),
    if (info != null) ...[
      if (photo != null) _photo(photo, context.strings.name(widget.place), photos)
      else if (!info.partial) Padding(padding: const EdgeInsets.only(top: 12),
        child: Text(tr(context, 'noPhoto'))),
      if (info.description != null) ...[
        const SizedBox(height: 16), SelectableText(info.description!),
      ],
      for (final section in info.sections) ...[
        const SizedBox(height: 16),
        Text(section.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8), SelectableText(section.text),
      ],
      if (info.description == null && info.sections.isEmpty && !info.partial)
        Padding(padding: const EdgeInsets.only(top: 12), child: Text(tr(context, 'noExtraInfo'))),
      if (info.textTruncated) Text(tr(context, 'articleTruncated')),
      if (info.description != null || info.sections.isNotEmpty) ...[
        const SizedBox(height: 12),
        if (info.article?.host.endsWith('.wikipedia.org') == true)
          Text(tr(context, 'wikipediaAttribution', {
            'title': info.articleTitle ?? context.strings.name(widget.place),
            'language': info.textLanguage ?? '—',
          }), style: Theme.of(context).textTheme.bodySmall)
        else Text(tr(context, 'sourceLanguageHint')),
      ],
      if (info.article != null) Wrap(spacing: 8, children: [
        TextButton.icon(onPressed: () => openInApp(context, info.article!),
          icon: const Icon(Icons.source_outlined), label: Text(tr(context, 'articleSource'))),
        if (info.article?.host.endsWith('.wikipedia.org') == true)
          TextButton(onPressed: () => openInApp(context,
            Uri.parse('https://creativecommons.org/licenses/by-sa/4.0/')),
            child: Text(tr(context, 'wikipediaLicense'))),
      ]),
      if (info.nearbyPhotos.isNotEmpty) ...[
        const SizedBox(height: 16),
        Text(tr(context, 'nearbyPhotosTitle'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        Text(tr(context, 'nearbyPhotosHint')),
        for (final nearby in info.nearbyPhotos) ...[
          Text(tr(context, 'nearbyPhotoDistance', {'distance': nearby.nearbyMeters!.round()})),
          _photo(nearby, tr(context, 'nearbyPhotosTitle'), photos),
        ],
      ],
    ],
    if (failed) ...[
      const SizedBox(height: 12), Text(tr(context, 'detailsError')),
      OutlinedButton.icon(key: const ValueKey('retry-place-details'), onPressed: loading ? null : _load,
        icon: const Icon(Icons.refresh), label: Text(tr(context, 'retryDetails'))),
    ],
    const SizedBox(height: 12),
    Text(tr(context, 'photoPrivacy'), style: Theme.of(context).textTheme.bodySmall),
    const Divider(height: 32),
  ];
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
        if (!widget.demo) ..._information(info, photo, photos),
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
