import 'package:antitourist/walk_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'route_fixtures.dart';

void main() {
  test('Visit and skip advance individually and remain reversible after completion', () {
    final session = WalkSession(sampleRoute());
    expect(session.currentIndex, 0);
    session.advance(StopStatus.visited);
    expect(session.currentIndex, 1);
    session.advance(StopStatus.skipped);
    expect(session.complete, isTrue);
    expect(session.visited, 1);
    expect(session.skipped, 1);
    session.undo();
    expect(session.currentIndex, 1);
    expect(session.skipped, 0);
    session.undo();
    expect(session.currentIndex, 0);
    expect(session.processed, 0);
    session.undo();
    expect(session.processed, 0);
  });
  test('Restart resets progress and pending cannot be used to advance', () {
    final session = WalkSession(sampleRoute());
    expect(() => session.advance(StopStatus.pending), throwsArgumentError);
    session.advance(StopStatus.visited);
    session.restart();
    expect(session.currentIndex, 0);
    expect(session.canUndo, isFalse);
  });
}
