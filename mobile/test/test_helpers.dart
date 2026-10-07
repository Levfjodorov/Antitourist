import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// A ListView can build a control just outside the visible viewport. Wait for
// the layout after scrolling and tap the interactive parent, not its label.
// Keep the finder empty while lazy list children have not been built yet;
// .first would throw before scrollUntilVisible can perform the first scroll.
Future<void> tapVisibleControl(WidgetTester tester, String label) async {
  final control = find.ancestor(
    of: find.text(label),
    matching: find.byWidgetPredicate((widget) =>
      widget is ButtonStyleButton || widget is SwitchListTile),
  );
  await tester.scrollUntilVisible(control, 200);
  await tester.pumpAndSettle();
  expect(control.hitTestable(), findsOneWidget, reason: 'Control must be on screen: $label');
  await tester.tap(control);
  await tester.pumpAndSettle();
}
