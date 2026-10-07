import 'package:antitourist/app_store.dart';
import 'package:antitourist/main.dart';
import 'package:antitourist/places.dart';
import 'package:antitourist/walk_screen.dart';
import 'package:antitourist/walk_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'app_store_test.dart' show MemoryAppStorage, savedFixture;
import 'route_fixtures.dart';
import 'test_helpers.dart';

void main() {
  testWidgets('The home screen resumes saved progress after a cold start', (tester) async {
    final disk = MemoryAppStorage();
    final original = await AppStore.load(storage: disk);
    final session = WalkSession(sampleRoute())..advance(StopStatus.visited);
    await original.put(savedFixture(session));
    final restored = await AppStore.load(storage: disk);
    addTearDown(original.dispose); addTearDown(restored.dispose);
    await tester.pumpWidget(AntiTouristApp(store: restored));
    await tester.pumpAndSettle();
    await tapVisibleControl(tester, 'Продолжить прогулку');
    await tapVisibleControl(tester, 'Продолжить прогулку');
    expect(find.text('Второе место'), findsOneWidget);
    expect(restored.active!.session!.canUndo, isTrue);
    await tapVisibleControl(tester, 'Отменить последнюю отметку');
    expect((await AppStore.load(storage: disk)).active!.session!.processed, 0);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Walk buttons persist completion into history', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 640);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final disk = MemoryAppStorage();
    final store = await AppStore.load(storage: disk); addTearDown(store.dispose);
    final session = WalkSession(sampleRoute());
    await store.put(savedFixture(session));
    await tester.pumpWidget(AppStoreScope(store: store, child: MaterialApp(
      home: WalkScreen(session: session, start: tallinnStart,
        onChanged: () => store.put(savedFixture(session))))));
    await tapVisibleControl(tester, 'Я здесь побывал — дальше');
    await tapVisibleControl(tester, 'Пропустить место');
    expect((await AppStore.load(storage: disk)).history.single.session!.skipped, 1);
    expect(tester.takeException(), isNull);
  });
}
