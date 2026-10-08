import 'package:flutter/material.dart';
import 'external_links.dart';
import 'language_settings.dart';
import 'place_details_service.dart';
import 'place_photo_image.dart';

class PlacePhotoScreen extends StatefulWidget {
  const PlacePhotoScreen({super.key, required this.photos,
    required this.placeName, this.initialIndex = 0})
      : assert(initialIndex >= 0);

  final List<PlacePhoto> photos;
  final String placeName;
  final int initialIndex;

  @override
  State<PlacePhotoScreen> createState() => _PlacePhotoScreenState();
}

class _PlacePhotoScreenState extends State<PlacePhotoScreen> {
  late final PageController pages;
  late final List<TransformationController> zooms;
  late int index;
  bool zoomed = false;

  @override
  void initState() {
    super.initState();
    assert(widget.photos.isNotEmpty);
    assert(widget.initialIndex < widget.photos.length);
    index = widget.initialIndex;
    pages = PageController(initialPage: index);
    zooms = List.generate(widget.photos.length, (_) => TransformationController()
      ..addListener(_zoomChanged));
  }

  void _zoomChanged() {
    final value = zooms[index].value.getMaxScaleOnAxis() > 1.01;
    if (mounted && zoomed != value) { setState(() => zoomed = value); }
  }

  void _resetZoom() => zooms[index].value = Matrix4.identity();

  void _goTo(int target) {
    _resetZoom();
    pages.animateToPage(target, duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut);
  }

  @override
  void dispose() {
    pages.dispose();
    for (final zoom in zooms) {
      zoom.removeListener(_zoomChanged);
      zoom.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final photo = widget.photos[index];
    return Scaffold(
      appBar: AppBar(title: Text(widget.placeName, maxLines: 1,
        overflow: TextOverflow.ellipsis), actions: [
          IconButton(onPressed: zoomed ? _resetZoom : null,
            tooltip: tr(context, 'resetPhotoZoom'), icon: const Icon(Icons.zoom_out_map)),
        ]),
      body: SafeArea(child: Column(children: [
        Expanded(child: PageView.builder(
          controller: pages,
          physics: zoomed ? const NeverScrollableScrollPhysics() : null,
          itemCount: widget.photos.length,
          onPageChanged: (value) {
            setState(() { index = value; zoomed = false; });
            _resetZoom();
          },
          itemBuilder: (context, page) => InteractiveViewer(
            transformationController: zooms[page], minScale: 1, maxScale: 5,
            child: Center(child: PlacePhotoImage(photo: widget.photos[page],
              label: widget.photos[page].caption?.trim().isNotEmpty == true
                ? widget.photos[page].caption! : widget.placeName)),
          ),
        )),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton(onPressed: index > 0 ? () => _goTo(index - 1) : null,
            tooltip: tr(context, 'previousPhoto'), icon: const Icon(Icons.chevron_left)),
          Flexible(child: Text(tr(context, 'galleryCounter',
            {'current': index + 1, 'total': widget.photos.length}))),
          IconButton(onPressed: index + 1 < widget.photos.length ? () => _goTo(index + 1) : null,
            tooltip: tr(context, 'nextPhoto'), icon: const Icon(Icons.chevron_right)),
        ]),
        ConstrainedBox(constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .3),
          child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr(context, 'photoZoomHint')),
              if (photo.nearbyMeters case final distance?)
                Text(tr(context, 'nearbyPhotoDistance', {'distance': distance.round()})),
              if (photo.caption case final caption?) Text(caption),
              SelectableText(photo.credit),
              Wrap(spacing: 8, children: [
                TextButton(onPressed: () => openInApp(context, photo.source),
                  child: Text(tr(context, 'photoSource'))),
                if (photo.licenseUrl case final licenseUrl?)
                  TextButton(onPressed: () => openInApp(context, licenseUrl),
                    child: Text(photo.license))
                else Text(photo.license),
              ]),
            ]))),
      ])),
    );
  }
}
