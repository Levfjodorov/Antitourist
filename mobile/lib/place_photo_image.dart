import 'dart:io';
import 'package:flutter/material.dart';
import 'language_settings.dart';
import 'place_details_service.dart';

class PlacePhotoImage extends StatefulWidget {
  const PlacePhotoImage({super.key, required this.photo, required this.label,
    this.height, this.fit = BoxFit.contain});

  final PlacePhoto photo;
  final String label;
  final double? height;
  final BoxFit fit;

  @override
  State<PlacePhotoImage> createState() => _PlacePhotoImageState();
}

class _PlacePhotoImageState extends State<PlacePhotoImage> {
  int attempt = 0;

  ImageProvider get provider => widget.photo.localPath == null
    ? NetworkImage(widget.photo.url.toString(), headers: const {'User-Agent': wikimediaUserAgent})
    : FileImage(File(widget.photo.localPath!));

  Future<void> _retry() async {
    await provider.evict();
    if (mounted) { setState(() => attempt++); }
  }

  @override
  Widget build(BuildContext context) => Image(
    key: ValueKey('${widget.photo.url}:$attempt'),
    image: provider, height: widget.height, width: double.infinity,
    fit: widget.fit, semanticLabel: widget.label,
    loadingBuilder: (context, child, progress) => progress == null ? child
      : SizedBox(height: widget.height, child: Center(child: Semantics(
          label: tr(context, 'photoLoading'),
          child: CircularProgressIndicator(value: progress.expectedTotalBytes == null
            ? null : progress.cumulativeBytesLoaded / progress.expectedTotalBytes!)))),
    errorBuilder: (context, error, stack) => SizedBox(height: widget.height,
      child: Center(child: SingleChildScrollView(child: Padding(
        padding: const EdgeInsets.all(16), child: Column(mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.broken_image_outlined),
            const SizedBox(height: 8),
            Text(tr(context, 'photoError'), textAlign: TextAlign.center),
            TextButton.icon(onPressed: _retry, icon: const Icon(Icons.refresh),
              label: Text(tr(context, 'retryPhoto'))),
          ]))))),
  );
}
