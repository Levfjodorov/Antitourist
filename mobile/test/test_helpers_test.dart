import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'test_helpers.dart';

void main() {
  testWidgets('Scrolling can find and tap a control that has not been built yet', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 640);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    var taps = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ListView.builder(
      itemCount: 20, itemExtent: 100,
      itemBuilder: (_, index) => index == 19
        ? TextButton(onPressed: () { taps++; }, child: const Text('Last button'))
        : Text('Row $index')))));
    expect(find.text('Last button'), findsNothing);
    await tapVisibleControl(tester, 'Last button');
    expect(taps, 1);
    expect(tester.takeException(), isNull);
  });
}
