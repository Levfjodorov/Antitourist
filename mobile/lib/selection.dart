import 'dart:math';
import 'places.dart';

List<Place> alternatives(List<Place> pool, List<Place> selected, {Place? replacing}) {
  final used = selected.map((p) => p.key).toSet();
  final result = pool.where((p) => !used.contains(p.key)).toList();
  result.sort((a, b) {
    if (replacing != null) {
      final category = (b.category == replacing.category ? 1 : 0) -
        (a.category == replacing.category ? 1 : 0);
      if (category != 0) { return category; }
    }
    return a.distance.compareTo(b.distance);
  });
  return result;
}

// Change membership, not just the display order. Retain the original pool filters.
List<Place>? anotherSelection(List<Place> pool, List<Place> selected, {Random? random}) {
  final extra = alternatives(pool, selected)..shuffle(random ?? Random());
  if (extra.isEmpty) { return null; }
  final retained = List<Place>.of(selected)..shuffle(random ?? Random());
  return [...extra, ...retained].take(selected.length).toList();
}
