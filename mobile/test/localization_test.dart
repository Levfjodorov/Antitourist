import 'dart:convert';
import 'package:antitourist/language_settings.dart';
import 'package:antitourist/main.dart';
import 'package:antitourist/osm.dart';
import 'package:antitourist/places.dart';
import 'package:antitourist/strings.dart';
import 'package:antitourist/translations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class MemoryLanguageStore implements LanguageStore {
  String? value;
  bool failWrites = false;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String code) async {
    if (failWrites) { throw StateError('Storage unavailable'); }
    value = code;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('All languages cover every message with matching placeholders', () {
    final placeholders = RegExp(r'\{([a-zA-Z]+)\}');
    for (final entry in translations.entries) {
      expect(entry.value.length, AppLanguage.values.length, reason: entry.key);
      final expected = placeholders.allMatches(entry.value.first).map((m) => m[1]).toSet();
      for (final value in entry.value) {
        expect(value.trim(), isNotEmpty, reason: entry.key);
        expect(placeholders.allMatches(value).map((m) => m[1]).toSet(), expected, reason: entry.key);
      }
    }
    expect(const AppStrings(AppLanguage.et).distance(1250), '1.3 km');
    expect(const AppStrings(AppLanguage.en).minutes(90), '1 h 30 min');
    expect(const AppStrings(AppLanguage.ru).minutes(90), '1 ч 30 мин');
  });

  test('A saved language overrides the default after restarting', () async {
    final store = MemoryLanguageStore();
    final settings = await LanguageSettings.load(store: store);
    expect(settings.language, AppLanguage.ru);
    expect(await settings.select(AppLanguage.et), isTrue);
    final restarted = await LanguageSettings.load(store: store);
    expect(restarted.language, AppLanguage.et);
    store.value = 'unsupported';
    final invalid = await LanguageSettings.load(store: store);
    expect(invalid.language, AppLanguage.ru);
    store.failWrites = true;
    expect(await invalid.select(AppLanguage.en), isFalse);
    expect(invalid.language, AppLanguage.en);
    settings.dispose(); restarted.dispose(); invalid.dispose();
  });

  test('Map names and details prefer the selected language without mixing UI labels', () {
    final places = parseOsmPlaces({'elements': [{
      'type': 'node', 'id': 1, 'lat': 59.437, 'lon': 24.7536,
      'tags': {'name': 'Kohalik nimi', 'name:ru': 'Русское название', 'name:en': 'English name',
        'historic': 'memorial', 'access': 'yes',
        'description': 'Eestikeelne kirjeldus', 'description:en': 'English description'},
    }]}, tallinnStart, 1000);
    final place = places.single;
    const et = AppStrings(AppLanguage.et), en = AppStrings(AppLanguage.en), ru = AppStrings(AppLanguage.ru);
    expect(ru.name(place), 'Русское название');
    expect(et.name(place), 'Kohalik nimi');
    expect(en.name(place), 'English name');
    expect(en.description(place), contains('Place type: Memorial'));
    expect(en.description(place), contains('English description'));
    expect(et.description(place), contains('Mälestusmärk'));
    expect(en.access(place), startsWith('The map lists public access.'));
    expect(en.error('Сервис маршрутов вернул HTTP 503. Повтори позже.'),
      'The routing service is temporarily unavailable. Try again later.');
  });

  testWidgets('Switching languages preserves settings and translates an open results screen', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 640);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final store = MemoryLanguageStore();
    final settings = LanguageSettings(store: store);
    addTearDown(settings.dispose);
    await tester.pumpWidget(AntiTouristApp(settings: settings));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Попробовать на примере'), 200);
    await tester.tap(find.text('Попробовать на примере'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('language-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eesti'));
    await tester.pumpAndSettle();
    expect(store.value, 'et');
    final demoSwitch = tester.widgetList<SwitchListTile>(find.byType(SwitchListTile))
      .singleWhere((s) => (s.title as Text).data == 'Proovi näidisandmetega');
    expect(demoSwitch.value, isTrue);
    await tester.scrollUntilVisible(find.text('Üllata mind'), 200);
    await tester.tap(find.text('Üllata mind'));
    await tester.pumpAndSettle();
    expect(find.text('Kohad jalutuskäiguks'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('language-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(find.text('Places for your walk'), findsOneWidget);
    expect(find.text('Example · These places are fictional. Do not use them for a real walk.'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('1. Unusual sculpture'), 200);
    expect(find.text('1. Unusual sculpture'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('Example places have translated content in all supported languages', () async {
    final raw = jsonDecode(await rootBundle.loadString('assets/demo_places.json')) as List<dynamic>;
    for (final entry in raw) {
      final place = Place.fromJson(entry as Map<String, dynamic>);
      for (final language in AppLanguage.values) {
        expect(place.localizedNames[language.code], isNotEmpty);
        expect(place.localizedDescriptions[language.code], isNotEmpty);
        expect(place.localizedSafetyNotes[language.code], isNotEmpty);
      }
    }
  });
}
