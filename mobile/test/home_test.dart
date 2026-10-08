import 'package:antitourist/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

void main() {
  testWidgets('Live mode is default and narrow screens can reach search', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 640);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(const AntiTouristApp());
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, appTitle), findsOneWidget);
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
    await tapVisibleControl(tester, 'Попробовать на примере');
    expect(tester.widget<SwitchListTile>(find.widgetWithText(
      SwitchListTile, 'Попробовать на примере')).value, isTrue);
    await tapVisibleControl(tester, 'Удиви меня');
    expect(find.text('Места для прогулки'), findsOneWidget);
    expect(find.text('Пример · Места вымышленные, идти к ним не нужно.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
