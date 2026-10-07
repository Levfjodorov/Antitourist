import 'package:antitourist/places.dart';
import 'package:antitourist/walk_screen.dart';
import 'package:antitourist/walk_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'route_fixtures.dart';

void main() {
  testWidgets('Visit, skip, completion and undo work on a narrow phone screen', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 640);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final session = WalkSession(sampleRoute());
    await tester.pumpWidget(MaterialApp(home: WalkScreen(session: session, start: tallinnStart)));
    expect(find.text('Первое место'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Посетил · следующая точка'), 200);
    await tester.tap(find.text('Посетил · следующая точка'));
    await tester.pumpAndSettle();
    expect(session.currentIndex, 1);
    await tester.scrollUntilVisible(find.text('Пропустить точку'), 150);
    await tester.tap(find.text('Пропустить точку'));
    await tester.pumpAndSettle();
    expect(session.complete, isTrue);
    await tester.scrollUntilVisible(find.text('Отменить последнюю отметку'), 150);
    await tester.tap(find.text('Отменить последнюю отметку'));
    await tester.pumpAndSettle();
    expect(session.currentIndex, 1);
    expect(tester.takeException(), isNull);
  });
}
