import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'external_links.dart';
import 'places.dart';
import 'walking_route.dart';

Widget osmAttribution(BuildContext context) => SimpleAttributionWidget(
  source: const Text('OpenStreetMap contributors'),
  onTap: () => openExternal(context, Uri.parse('https://www.openstreetmap.org/copyright')));

class RouteMap extends StatelessWidget {
  const RouteMap({super.key, required this.places, required this.demo, required this.start, this.route});
  final List<Place> places;
  final bool demo;
  final GeoPoint start;
  final WalkingRoute? route;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(route == null ? 'Точки на карте' : 'Пеший маршрут')),
    body: Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Text(demo
        ? 'ДЕМО · Вымышленные точки.'
        : route == null ? 'Места из OSM. Расстояния по прямой; пешеходный путь ещё не рассчитан.'
        : 'Пешком ${formatDistance(route!.meters)} · ≈ ${formatMinutes(route!.walkMinutes)}. Линия — путь по данным OSM.')),
      if (route != null && route!.snapDistances.any((distance) => distance > 5))
        const Padding(padding: EdgeInsets.symmetric(horizontal: 12),
          child: Text('Путь подходит к ближайшим пешеходным участкам рядом с маркерами; входы проверь на месте.')),
      Expanded(child: FlutterMap(
        options: MapOptions(initialCenter: LatLng(start.lat, start.lon), initialZoom: 13,
          initialCameraFit: CameraFit.bounds(
            bounds: LatLngBounds.fromPoints([
              LatLng(start.lat, start.lon),
              for (final place in places) LatLng(place.lat, place.lon),
              if (route != null) for (final point in route!.geometry) LatLng(point.lat, point.lon),
            ], drawInSingleWorld: true),
            padding: const EdgeInsets.all(44), maxZoom: 16)),
        children: [
          TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.antitourist.antitourist', maxNativeZoom: 19),
          if (route != null) PolylineLayer(polylines: [Polyline(
            points: [for (final point in route!.geometry) LatLng(point.lat, point.lon)],
            strokeWidth: 5, color: const Color(0xff246bfd))]),
          MarkerLayer(markers: [
            Marker(point: LatLng(start.lat, start.lon), width: 42, height: 42,
              child: const Tooltip(message: 'Старт поиска',
                child: Icon(Icons.my_location, size: 34, color: Colors.blue))),
            for (var i = 0; i < places.length; i++) Marker(
              point: LatLng(places[i].lat, places[i].lon), width: 42, height: 42,
              child: GestureDetector(
                onTap: () => showModalBottomSheet<void>(context: context,
                  isScrollControlled: true,
                  builder: (sheetContext) => SafeArea(child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(places[i].name, style: const TextStyle(fontSize: 22)),
                        const SizedBox(height: 12), Text(places[i].description),
                        const SizedBox(height: 12),
                        Text(demo ? 'Тестовые данные' : places[i].accessLabel),
                        if (places[i].coordinateIsCenter)
                          const Text('Маркер — центр объекта; точное место входа не задано.'),
                        if (places[i].safetyNote != null) Text(places[i].safetyNote!),
                        if (places[i].osmUrl != null)
                          TextButton(onPressed: () => openExternal(sheetContext, places[i].osmUrl!),
                            child: const Text('Открыть источник OSM')),
                      ])))),
                child: CircleAvatar(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  child: Text('${i + 1}')))),
          ]),
          osmAttribution(context),
        ])),
      if (route != null) SafeArea(top: false, child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8), child: Wrap(
          alignment: WrapAlignment.center, spacing: 8, children: [
            TextButton(onPressed: () => openExternal(context, Uri.parse('https://routing.openstreetmap.de/about.html')),
              child: const Text('Маршруты: OSRM / FOSSGIS')),
            TextButton(onPressed: () => openExternal(context, Uri.parse('https://www.openstreetmap.org/fixthemap')),
              child: const Text('Исправить карту OSM')),
          ]))),
    ]));
}

class StartPicker extends StatefulWidget {
  const StartPicker({super.key, required this.initial});
  final GeoPoint initial;
  @override
  State<StartPicker> createState() => _StartPickerState();
}

class _StartPickerState extends State<StartPicker> {
  late GeoPoint selected;
  @override
  void initState() { super.initState(); selected = widget.initial; }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Выбрать старт')),
    body: Column(children: [
      const Padding(padding: EdgeInsets.all(12), child: Text('Нажми на карту, чтобы выбрать точку поиска.')),
      Expanded(child: FlutterMap(
        options: MapOptions(initialCenter: LatLng(selected.lat, selected.lon), initialZoom: 13,
          onTap: (_, point) => setState(() => selected = GeoPoint(point.latitude, point.longitude))),
        children: [
          TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.antitourist.antitourist', maxNativeZoom: 19),
          MarkerLayer(markers: [Marker(point: LatLng(selected.lat, selected.lon),
            width: 42, height: 42, child: const Icon(Icons.location_on, size: 40, color: Colors.blue))]),
          osmAttribution(context),
        ])),
      SafeArea(top: false, child: Padding(padding: const EdgeInsets.all(16),
        child: FilledButton(onPressed: () => Navigator.of(context).pop(selected),
          child: const Text('Искать отсюда')))),
    ]));
}
