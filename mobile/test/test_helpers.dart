import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// A ListView can build a control just outside the visible viewport. Wait for
// the layout after scrolling and tap the interactive parent, not its label.
Future<void> tapVisibleControl(WidgetTester tester, String label) async {
  final control = find.ancestor(
    of: find.text(label),
    matching: find.byWidgetPredicate((widget) =>
      widget is ButtonStyleButton || widget is SwitchListTile),
  ).first;
  await tester.scrollUntilVisible(control, 200);
  await tester.pumpAndSettle();
  expect(control.hitTestable(), findsOneWidget, reason: 'Control must be on screen: $label');
  await tester.tap(control);
  await tester.pumpAndSettle();
}
