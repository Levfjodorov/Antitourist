import 'walking_route.dart';

enum StopStatus { pending, visited, skipped }

class WalkSession {
  WalkSession(this.route) : statuses = List.filled(route.places.length, StopStatus.pending);
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
