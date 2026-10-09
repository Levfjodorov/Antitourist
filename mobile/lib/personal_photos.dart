import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'app_store.dart';
import 'place_memory.dart';
import 'places.dart';

class PersonalPhotos {
  PersonalPhotos({this.directory, ImagePicker? picker}) : picker = picker ?? ImagePicker();
  final Directory? directory;
  final ImagePicker picker;
  static Future<PersonalPhotos> load() async {
    try {
      final directory = Directory('${(await getApplicationSupportDirectory()).path}/personal-photos');
      await directory.create(recursive: true);
      return PersonalPhotos(directory: directory);
    } catch (_) { return PersonalPhotos(); }
  }
  File? file(String name) => directory != null && validPhotoName(name)
    ? File('${directory!.path}/$name') : null;
  Future<String> importPhoto(XFile picked) async {
    if (directory == null) { throw const FileSystemException('Photo directory unavailable'); }
    final size = await picked.length();
    if (size <= 0 || size > 12 * 1024 * 1024) { throw const FormatException('Photo too large'); }
    final bytes = await picked.readAsBytes();
    if (bytes.length != size) { throw const FormatException('Incomplete photo'); }
    final String extension;
    if (bytes.length > 3 && bytes[0] == 0xff && bytes[1] == 0xd8 && bytes[2] == 0xff) { extension = 'jpg'; }
    else if (bytes.length > 8 && bytes.take(8).join(',') == '137,80,78,71,13,10,26,10') { extension = 'png'; }
    else if (bytes.length > 12 && String.fromCharCodes(bytes.take(4)) == 'RIFF' &&
        String.fromCharCodes(bytes.skip(8).take(4)) == 'WEBP') { extension = 'webp'; }
    else { throw const FormatException('Unsupported photo format'); }
    final random = Random.secure();
    final id = List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    final name = '$id.$extension';
    final target = file(name)!;
    final temporary = File('${target.path}.tmp');
    await temporary.writeAsBytes(bytes, flush: true);
    await temporary.rename(target.path);
    return name;
  }
  Future<bool> pick(AppStore store, Place place, ImageSource source) async {
    if ((store.memory(place)?.photos.length ?? 0) >= 20 || directory == null) {
      throw const FileSystemException('Cannot add another photo');
    }
    if (!await store.beginPhoto(place)) { return false; }
    try {
      final picked = await picker.pickImage(source: source, maxWidth: 2048,
        maxHeight: 2048, imageQuality: 85, requestFullMetadata: false);
      if (picked == null) { return await store.cancelPhoto(); }
      final name = await importPhoto(picked);
      return await store.finishPhoto(name);
    } catch (_) { await store.cancelPhoto(); rethrow; }
  }
  Future<void> recover(AppStore store) async {
    if (directory == null) { return; }
    try {
      final lost = await picker.retrieveLostData();
      if (lost.isEmpty) {
        if (store.pendingPhotoPlace != null) { await store.cancelPhoto(); }
        return;
      }
      if (store.pendingPhotoPlace == null || lost.exception != null) {
        if (store.pendingPhotoPlace != null) { await store.cancelPhoto(); }
        return;
      }
      final picked = lost.files?.firstOrNull;
      if (picked != null) { await store.finishPhoto(await importPhoto(picked)); }
      else { await store.cancelPhoto(); }
    } catch (_) { store.saveFailed = true; }
  }
  Future<void> delete(String name) async {
    final target = file(name);
    if (target != null && await target.exists()) { await target.delete(); }
  }
}

class PersonalPhotosScope extends InheritedWidget {
  const PersonalPhotosScope({super.key, required this.photos, required super.child});
  final PersonalPhotos photos;
  static PersonalPhotos? of(BuildContext context) =>
    context.dependOnInheritedWidgetOfExactType<PersonalPhotosScope>()?.photos;
  @override
  bool updateShouldNotify(PersonalPhotosScope oldWidget) => oldWidget.photos != photos;
}
