import 'package:antitourist/app_store.dart';
import 'package:antitourist/language_settings.dart';
import 'package:antitourist/main.dart';
import 'package:antitourist/strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'app_store_test.dart' show MemoryAppStorage;
import 'route_fixtures.dart';
import 'test_helpers.dart';

void main() {
  testWidgets('Favorites screen changes language and removes a favorite persistently', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 640);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final disk = MemoryAppStorage();
    final store = await AppStore.load(storage: disk);
    final settings = LanguageSettings();
    addTearDown(store.dispose); addTearDown(settings.dispose);
    await store.toggleFavorite(routePlaces.first);
    await tester.pumpWidget(AntiTouristApp(store: store, settings: settings));
    await tester.pumpAndSettle();
    await tapVisibleControl(tester, 'Мои прогулки');
    await tester.tap(find.widgetWithText(Tab, 'Избранное'));
    await tester.pumpAndSettle();
    expect(find.text('Первое место'), findsOneWidget);
    await settings.select(AppLanguage.en); await tester.pumpAndSettle();
    expect(find.widgetWithText(Tab, 'Favorites'), findsOneWidget);
    expect(find.text('Details and photo'), findsOneWidget);
    await tester.tap(find.byTooltip('Remove from favorites')); await tester.pumpAndSettle();
    expect((await AppStore.load(storage: disk)).favorites, isEmpty);
    expect(find.text('Tap the heart on a place to save it here.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
