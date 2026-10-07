import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'places.dart';

class RouteMap extends StatelessWidget {
  const RouteMap({super.key, required this.places, required this.demo});
  final List<Place> places;
  final bool demo;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Точки на карте')),
    body: Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Text(demo
        ? 'ДЕМО · Вымышленные точки. Это не маршрут для прогулки.'
        : 'Координаты вашего API. Путь не рассчитан. Backend 0.1 возвращает тестовые точки.')),
      Expanded(child: FlutterMap(
        options: const MapOptions(initialCenter: LatLng(59.440, 24.750), initialZoom: 12),
        children: [
          TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.antitourist.antitourist'),
          MarkerLayer(markers: [
            for (var i = 0; i < places.length; i++) Marker(
              point: LatLng(places[i].lat, places[i].lon), width: 42, height: 42,
              child: GestureDetector(
                onTap: () => showModalBottomSheet<void>(context: context,
                  builder: (_) => Padding(padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(places[i].name, style: const TextStyle(fontSize: 22)),
                      const SizedBox(height: 12), Text(places[i].description),
                    ]))),
                child: CircleAvatar(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  child: Text('${i + 1}')))),
          ]),
          const SimpleAttributionWidget(source: Text('OpenStreetMap contributors')),
        ])),
    ]));
}
