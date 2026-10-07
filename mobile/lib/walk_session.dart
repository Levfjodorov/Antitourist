import 'walking_route.dart';

enum StopStatus { pending, visited, skipped }

class WalkSession {
  WalkSession(this.route) : statuses = List.filled(route.places.length, StopStatus.pending);
  factory WalkSession.restore(WalkingRoute route, List<String> states, List<int> history) {
    if (states.length != route.places.length ||
        states.any((s) => !StopStatus.values.any((v) => v.name == s)) ||
        history.toSet().length != history.length ||
        history.any((i) => i < 0 || i >= states.length || states[i] == 'pending') ||
        states.where((s) => s != 'pending').length != history.length) {
      throw const FormatException('Invalid saved progress');
    }
    final session = WalkSession(route);
    for (var i = 0; i < states.length; i++) {
      session.statuses[i] = StopStatus.values.firstWhere((s) => s.name == states[i]);
    }
    session._history.addAll(history);
    return session;
  }

  List<int> get history => List.unmodifiable(_history);

  // Keep marks and undo order for places that survive an edit, even when reordered.
  WalkSession rebased(WalkingRoute replacement) {
    final keys = replacement.places.map((p) => p.key).toList();
    final states = List.filled(keys.length, StopStatus.pending.name);
    final history = <int>[];
    for (final previous in _history) {
      final next = keys.indexOf(route.places[previous].key);
      if (next >= 0) { states[next] = statuses[previous].name; history.add(next); }
    }
    return WalkSession.restore(replacement, states, history);
  }

  final WalkingRoute route;
  final List<StopStatus> statuses;
  final _history = <int>[];
  int? get currentIndex {
    final index = statuses.indexOf(StopStatus.pending);
    return index < 0 ? null : index;
  }
  bool get complete => currentIndex == null;
  bool get canUndo => _history.isNotEmpty;
  int get visited => statuses.where((s) => s == StopStatus.visited).length;
  int get skipped => statuses.where((s) => s == StopStatus.skipped).length;
  int get processed => visited + skipped;

  void advance(StopStatus status) {
    if (status == StopStatus.pending) { throw ArgumentError('Нужно выбрать посещение или пропуск'); }
    final index = currentIndex;
    if (index == null) { return; }
    statuses[index] = status;
    _history.add(index);
  }

  void undo() {
    if (_history.isNotEmpty) { statuses[_history.removeLast()] = StopStatus.pending; }
  }

  void restart() {
    for (var i = 0; i < statuses.length; i++) { statuses[i] = StopStatus.pending; }
    _history.clear();
  }
}
