import 'package:antitourist/language_settings.dart';
import 'package:antitourist/places.dart';
import 'package:antitourist/strings.dart';
import 'package:antitourist/walk_screen.dart';
import 'package:antitourist/walk_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'route_fixtures.dart';

void main() {
  testWidgets('Changing language keeps visited stops and undo history', (tester) async {
    final settings = LanguageSettings();
    addTearDown(settings.dispose);
    final session = WalkSession(sampleRoute());
    session.advance(StopStatus.visited);
    await tester.pumpWidget(LanguageScope(settings: settings, child: MaterialApp(
      home: WalkScreen(session: session, start: tallinnStart))));
    await settings.select(AppLanguage.et);
    await tester.pumpAndSettle();
    expect(find.text('Sinu jalutuskäik'), findsOneWidget);
    expect(session.currentIndex, 1);
    expect(session.visited, 1);
    expect(session.canUndo, isTrue);
    await tester.scrollUntilVisible(find.text('Võta viimane märge tagasi'), 200);
    await tester.tap(find.text('Võta viimane märge tagasi'));
    await tester.pumpAndSettle();
    expect(session.currentIndex, 0);
    expect(session.visited, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Visit, skip, completion and undo work on a narrow phone screen', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 640);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final session = WalkSession(sampleRoute());
    await tester.pumpWidget(MaterialApp(home: WalkScreen(session: session, start: tallinnStart)));
    expect(find.text('Первое место'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Я здесь побывал — дальше'), 200);
    await tester.tap(find.text('Я здесь побывал — дальше'));
    await tester.pumpAndSettle();
    expect(session.currentIndex, 1);
    await tester.scrollUntilVisible(find.text('Пропустить место'), 150);
    await tester.tap(find.text('Пропустить место'));
    await tester.pumpAndSettle();
    expect(session.complete, isTrue);
    await tester.scrollUntilVisible(find.text('Отменить последнюю отметку'), 150);
    await tester.tap(find.text('Отменить последнюю отметку'));
    await tester.pumpAndSettle();
    expect(session.currentIndex, 1);
    expect(tester.takeException(), isNull);
  });
}
