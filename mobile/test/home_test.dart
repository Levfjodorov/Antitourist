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
    expect(find.text('Центр Таллинна'), findsOneWidget);
    expect(find.text('Моя геопозиция'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Демонстрационный режим'), 250);
    final switches = tester.widgetList<SwitchListTile>(find.byType(SwitchListTile));
    expect(switches.every((s) => !s.value), isTrue);
    await tester.scrollUntilVisible(find.text('УДИВИ МЕНЯ'), 250);
    expect(find.text('УДИВИ МЕНЯ'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Demo opens fictional results without using live search', (tester) async {
    await tester.pumpWidget(const AntiTouristApp());
    await tester.scrollUntilVisible(find.text('Демонстрационный режим'), 250);
    await tester.tap(find.text('Демонстрационный режим'));
    await tester.pump();
    await tester.scrollUntilVisible(find.text('УДИВИ МЕНЯ'), 250);
    await tester.tap(find.text('УДИВИ МЕНЯ'));
    await tester.pumpAndSettle();
    expect(find.text('Твоя подборка'), findsOneWidget);
    expect(find.text('ДЕМО · Все точки вымышленные.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
