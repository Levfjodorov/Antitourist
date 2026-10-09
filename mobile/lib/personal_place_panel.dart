import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'app_store.dart';
import 'language_settings.dart';
import 'personal_photos.dart';
import 'places.dart';

class PersonalPlacePanel extends StatefulWidget {
  const PersonalPlacePanel({super.key, required this.place});
  final Place place;
  @override
  State<PersonalPlacePanel> createState() => _PersonalPlacePanelState();
}
class _PersonalPlacePanelState extends State<PersonalPlacePanel> {
  final note = TextEditingController();
  bool initialized = false, busy = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!initialized) { note.text = AppStoreScope.of(context)?.memory(widget.place)?.note ?? ''; initialized = true; }
  }
  @override
  void dispose() { note.dispose(); super.dispose(); }
  Future<void> _run(Future<bool?> Function() operation, {bool photo = false}) async {
    setState(() => busy = true);
    bool? success = false;
    try { success = await operation(); } catch (_) { /* Show a localized recoverable failure. */ }
    if (!mounted) { return; }
    setState(() => busy = false);
    if (success == null) { return; }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(context,
      success ? 'personalSaved' : photo ? 'personalPhotoError' : 'dataSaveError'))));
  }
  void _openPhoto(PersonalPhotos photos, String name) {
    final file = photos.file(name);
    if (file == null) { return; }
    Navigator.of(context).push<void>(MaterialPageRoute(builder: (context) => Scaffold(
      appBar: AppBar(title: Text(tr(context, 'myPhotos'))),
      body: Center(child: InteractiveViewer(minScale: 1, maxScale: 5,
        child: Image.file(file, errorBuilder: (_, error, stack) => Text(tr(context, 'personalPhotoMissing'))))))));
  }
  @override
  Widget build(BuildContext context) {
    final store = AppStoreScope.of(context);
    if (store == null) { return const SizedBox.shrink(); }
    final memory = store.memory(widget.place);
    final photos = PersonalPhotosScope.of(context);
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr(context, 'myPlaceTitle'), style: Theme.of(context).textTheme.titleLarge),
        if (store.isVisited(widget.place)) Text(tr(context, 'visitedPlace')),
        if (memory?.walkVisits.isNotEmpty == true) Text(tr(context, 'visitedInWalk')),
        if (memory?.manualVisit != null || memory?.walkVisits.isNotEmpty != true)
          SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(tr(context, 'markVisited')),
            value: memory?.manualVisit != null,
            onChanged: busy ? null : (value) => _run(() => store.setVisited(widget.place, value))),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(tr(context, 'excludePlace')),
          subtitle: Text(tr(context, 'excludePlaceHint')), value: memory?.excluded ?? false,
          onChanged: busy ? null : (value) => _run(() => store.setExcluded(widget.place, value))),
        const SizedBox(height: 12),
        TextField(key: const ValueKey('personal-note'), enabled: !busy, controller: note, minLines: 3, maxLines: 8,
          maxLength: 6000, decoration: InputDecoration(labelText: tr(context, 'myNote'),
            hintText: tr(context, 'myNoteHint'), border: const OutlineInputBorder())),
        FilledButton.icon(key: const ValueKey('save-personal-note'),
          onPressed: busy ? null : () => _run(() => store.saveNote(widget.place, note.text)),
          icon: const Icon(Icons.save_outlined), label: Text(tr(context, 'saveNote'))),
        const SizedBox(height: 12), Text(tr(context, 'myPhotos')),
        if (photos != null && photos.directory != null && memory != null) Wrap(spacing: 8, runSpacing: 8, children: [
          for (final name in memory.photos) SizedBox(width: 144, child: Column(children: [
            GestureDetector(onTap: () => _openPhoto(photos, name),
              child: Image.file(photos.file(name)!, height: 110, width: 144, fit: BoxFit.cover,
                errorBuilder: (_, error, stack) => SizedBox(height: 110,
                  child: Center(child: Text(tr(context, 'personalPhotoMissing')))))),
            TextButton.icon(onPressed: busy ? null : () => _run(() async {
              final success = await store.removePhoto(widget.place, name);
              if (success) { await photos.delete(name); } return success;
            }), icon: const Icon(Icons.delete_outline), label: Text(tr(context, 'delete'))),
          ])),
        ]),
        if (photos?.directory == null && memory?.photos.isNotEmpty == true) Text(tr(context, 'personalPhotoMissing')),
        if (photos != null && photos.directory != null && (memory?.photos.length ?? 0) < 20)
          Wrap(spacing: 8, children: [
            OutlinedButton.icon(onPressed: busy ? null : () => _run(
              () => photos.pick(store, widget.place, ImageSource.gallery), photo: true),
              icon: const Icon(Icons.photo_library_outlined), label: Text(tr(context, 'addMyPhoto'))),
            TextButton.icon(onPressed: busy ? null : () => _run(
              () => photos.pick(store, widget.place, ImageSource.camera), photo: true),
              icon: const Icon(Icons.camera_alt_outlined), label: Text(tr(context, 'takeMyPhoto'))),
          ]),
        if (busy) const LinearProgressIndicator(),
        const StorageNotice(),
      ])));
  }
}
