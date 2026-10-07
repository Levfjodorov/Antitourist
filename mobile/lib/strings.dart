import 'places.dart';
import 'translations.dart';

enum AppLanguage {
  ru('ru', 'Русский'), et('et', 'Eesti'), en('en', 'English');
  const AppLanguage(this.code, this.label);
  final String code, label;
  static AppLanguage? fromCode(String? code) {
    for (final language in values) {
      if (language.code == code) { return language; }
    }
    return null;
  }
}

class AppStrings {
  const AppStrings(this.language);
  final AppLanguage language;

  String t(String key, [Map<String, Object> parameters = const {}]) {
    final values = translations[key];
    if (values == null) { throw ArgumentError.value(key, 'key', 'Unknown translation'); }
    var text = values[language.index];
    for (final entry in parameters.entries) {
      text = text.replaceAll('{${entry.key}}', entry.value.toString());
    }
    return text;
  }

  String category(String key) => t('category_$key');
  String distance(double meters) => meters < 1000
      ? t('meters', {'value': meters.round()})
      : t('kilometers', {'value': (meters / 1000).toStringAsFixed(1)});
  String minutes(int value) => value < 60 ? t('minutes', {'value': value})
      : t('hoursMinutes', {'hours': value ~/ 60, 'minutes': value % 60});

  String error(String original) {
    if (original.startsWith('Сервис карт вернул HTTP ')) { return t('errMapService'); }
    if (original.startsWith('Сервис маршрутов вернул HTTP ')) { return t('errRouteService'); }
    return t(errorKeys[original] ?? 'errSearch');
  }

  String? _tag(Map<String, String> tags, String key) {
    for (final candidate in ['$key:${language.code}', key, '$key:en', '$key:et', '$key:ru']) {
      final value = tags[candidate];
      if (value != null && value.trim().isNotEmpty) { return value.trim(); }
    }
    return null;
  }

  String name(Place place) {
    if (place.osmUrl != null) {
      return _tag(place.tags, 'name') ?? '${category(place.category)} · OpenStreetMap';
    }
    return place.localizedNames[language.code] ?? place.name;
  }

  String description(Place place) {
    if (place.osmUrl == null) {
      return place.localizedDescriptions[language.code] ?? place.description;
    }
    final lines = <String>[category(place.category)];
    for (final key in ['historic', 'artwork_type', 'start_date', 'artist_name', 'cuisine', 'opening_hours']) {
      final value = _tag(place.tags, key);
      if (value == null) { continue; }
      final valueKey = 'value_$value';
      final readable = translations.containsKey(valueKey) ? t(valueKey) : value;
      lines.add('${t('fact_$key')}: $readable');
    }
    final sourceDescription = _tag(place.tags, 'description');
    if (sourceDescription != null) { lines.add(sourceDescription); }
    if (place.tags['fee'] == 'yes') { lines.add(t('fee')); }
    return lines.join('\n');
  }

  String access(Place place) {
    if (place.tags.containsKey('access:conditional') || place.tags.containsKey('foot:conditional')) {
      return t('accessConditional');
    }
    return t(place.legalAccess ? 'accessPublic' : 'accessUnknown');
  }

  String? safety(Place place) {
    if (place.safetyNote == null) { return null; }
    if (place.osmUrl != null) { return t('safetyOutside'); }
    return place.localizedSafetyNotes[language.code] ?? place.safetyNote;
  }
}
