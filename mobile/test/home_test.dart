import 'package:antitourist/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Live mode is default and narrow screens can reach search', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 640);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(const AntiTouristApp());
    await tester.pumpAndSettle();
    expect(find.text('Центр Таллинна'), findsOneWidget);
    expect(find.text('Где я сейчас'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Попробовать на примере'), 250);
    final switches = tester.widgetList<SwitchListTile>(find.byType(SwitchListTile));
    expect(switches.every((s) => !s.value), isTrue);
    await tester.scrollUntilVisible(find.text('Удиви меня'), 250);
    expect(find.text('Удиви меня'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Demo opens fictional results without using live search', (tester) async {
    await tester.pumpWidget(const AntiTouristApp());
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Попробовать на примере'), 250);
    await tester.tap(find.text('Попробовать на примере'));
    await tester.pump();
    await tester.scrollUntilVisible(find.text('Удиви меня'), 250);
    await tester.tap(find.text('Удиви меня'));
    await tester.pumpAndSettle();
    expect(find.text('Места для прогулки'), findsOneWidget);
    expect(find.text('Пример · Места вымышленные, идти к ним не нужно.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
