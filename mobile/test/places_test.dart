import 'package:antitourist/places.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> fixture({bool? access = true, double lat = 59.4}) => {
  'name': 'Example', 'category': 'history', 'lat': lat, 'lon': 24.7,
  'description': 'Test', 'anti_tourist_score': 80, 'legal_access': access,
};

void main() {
  test('API excludes denied and unspecified access', () {
    final result = parseApiPlaces({'places': [
      fixture(), fixture(access: false), fixture(access: null),
    ]});
    expect(result, hasLength(1));
  });
  test('Reject out-of-range coordinates', () {
    expect(() => Place.fromJson(fixture(lat: 100)), throwsFormatException);
  });
  test('Demo prioritizes selected interests', () {
    final history = Place.fromJson(fixture());
    final weird = Place.fromJson({...fixture(), 'category': 'weird'});
    final result = selectDemoPlaces([history, weird],
      minutes: 120, wildness: 70, interests: {'weird'});
    expect(result.first.category, 'weird');
  });
}
