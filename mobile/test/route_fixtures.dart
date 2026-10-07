import 'package:antitourist/places.dart';
import 'package:antitourist/walking_route.dart';

const routePlaces = [
  Place(id: 'node/1', name: 'Первое место', category: 'history', lat: 59.4371,
    lon: 24.7536, description: 'История', score: 70, legalAccess: true),
  Place(id: 'node/2', name: 'Второе место', category: 'weird', lat: 59.4372,
    lon: 24.7536, description: 'Искусство', score: 80, legalAccess: true),
];

Map<String, dynamic> routePayload(List<Place> places) => {
  'code': 'Ok',
  'waypoints': [
    {'location': [tallinnStart.lon, tallinnStart.lat], 'distance': 0},
    for (final p in places) {'location': [p.lon, p.lat], 'distance': 0},
  ],
  'routes': [{
    'distance': places.length * 100, 'duration': places.length * 80,
    'geometry': {'type': 'LineString', 'coordinates': [
      [tallinnStart.lon, tallinnStart.lat], for (final p in places) [p.lon, p.lat],
    ]},
    'legs': [for (final _ in places) {'distance': 100, 'duration': 80}],
  }],
};

WalkingRoute sampleRoute() => parseWalkingRoute(routePayload(routePlaces), tallinnStart, routePlaces);
