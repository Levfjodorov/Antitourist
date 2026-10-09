import 'places.dart';

bool validPhotoName(String name) => RegExp(r'^[a-f0-9]{32}\.(jpg|png|webp)$').hasMatch(name);

class PlaceMemory {
  PlaceMemory({required this.place, this.note = '', this.manualVisit, this.excluded = false,
    List<String>? photos, Map<String, DateTime>? walkVisits})
    : photos = photos ?? [], walkVisits = walkVisits ?? {};
  final Place place;
  String note;
  DateTime? manualVisit;
  bool excluded;
  final List<String> photos;
  final Map<String, DateTime> walkVisits;
  bool get visited => manualVisit != null || walkVisits.isNotEmpty;
  DateTime? get lastVisit {
    final dates = [if (manualVisit != null) manualVisit!, ...walkVisits.values]..sort();
    return dates.isEmpty ? null : dates.last;
  }
  bool get hasContent => note.isNotEmpty || photos.isNotEmpty;
  Map<String, dynamic> toJson() => {'place': place.toJson(), 'note': note,
    'manualVisit': manualVisit?.toUtc().toIso8601String(), 'excluded': excluded,
    'photos': photos, 'walkVisits': walkVisits.map((key, value) => MapEntry(key, value.toUtc().toIso8601String()))};
  factory PlaceMemory.fromJson(Map<String, dynamic> data) {
    final note = data['note'] as String? ?? '';
    final photos = List<String>.from(data['photos'] as List? ?? []);
    final visits = Map<String, dynamic>.from(data['walkVisits'] as Map? ?? {});
    if (note.runes.length > 6000 || photos.length > 20 || photos.toSet().length != photos.length ||
        photos.any((name) => !validPhotoName(name)) || visits.length > 10000) {
      throw const FormatException('Invalid personal place data');
    }
    return PlaceMemory(place: Place.fromJson(Map<String, dynamic>.from(data['place'] as Map)),
      note: note, photos: photos, excluded: data['excluded'] == true,
      manualVisit: data['manualVisit'] == null ? null : DateTime.parse(data['manualVisit'] as String),
      walkVisits: visits.map((key, value) => MapEntry(key, DateTime.parse(value as String))));
  }
}
