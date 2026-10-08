import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart';
import 'language_settings.dart';
import 'places.dart';

abstract interface class AddressLookup {
  Future<String?> lookup(GeoPoint point, String language);
}

String coordinateLabel(GeoPoint point) =>
  '${point.lat.toStringAsFixed(6)}, ${point.lon.toStringAsFixed(6)}';

String formatPlacemark(Placemark place) {
  String clean(String? value) => value?.trim() ?? '';
  final road = [clean(place.thoroughfare), clean(place.subThoroughfare)]
    .where((s) => s.isNotEmpty).join(' ');
  final street = road.isNotEmpty ? road : clean(place.street);
  final name = clean(place.name);
  final parts = <String>[
    if (name.isNotEmpty && !RegExp(r'^\d+[a-zA-Z]?$').hasMatch(name) &&
        name.toLowerCase() != street.toLowerCase() &&
        name.toLowerCase() != clean(place.thoroughfare).toLowerCase()) name,
    street,
    clean(place.subLocality),
    clean(place.locality).isNotEmpty ? clean(place.locality) : clean(place.administrativeArea),
    clean(place.country),
  ];
  final seen = <String>{};
  return parts.where((s) => s.isNotEmpty && seen.add(s.toLowerCase())).join(', ');
}

class DeviceAddressLookup implements AddressLookup {
  final _cache = <String, String>{};
  @override
  Future<String?> lookup(GeoPoint point, String language) async {
    if (!point.valid) { return null; }
    final key = '${coordinateLabel(point)}:$language';
    if (_cache.containsKey(key)) { return _cache[key]; }
    final geocoder = Geocoding(locale: Locale(language));
    if (!await geocoder.isPresent().timeout(const Duration(seconds: 8))) { return null; }
    final places = await geocoder.placemarkFromCoordinates(point.lat, point.lon)
      .timeout(const Duration(seconds: 8));
    if (places.isEmpty) { return null; }
    final address = formatPlacemark(places.first);
    if (address.isEmpty) { return null; }
    if (_cache.length >= 30) { _cache.remove(_cache.keys.first); }
    _cache[key] = address;
    return address;
  }
}

class LocationAddress extends StatefulWidget {
  const LocationAddress({super.key, required this.point, this.lookup});
  final GeoPoint point;
  final AddressLookup? lookup;
  @override
  State<LocationAddress> createState() => _LocationAddressState();
}
class _LocationAddressState extends State<LocationAddress> {
  late final AddressLookup _defaultLookup;
  String? _address, _language;
  bool _loading = false;
  int _request = 0;
  @override
  void initState() { super.initState(); _defaultLookup = DeviceAddressLookup(); }
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final language = context.strings.language.code;
    if (_language != language) { _language = language; _load(); }
  }
  @override
  void didUpdateWidget(LocationAddress oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.point.lat != widget.point.lat || oldWidget.point.lon != widget.point.lon ||
        oldWidget.lookup != widget.lookup) { _load(); }
  }
  Future<void> _load() async {
    final request = ++_request;
    final point = widget.point;
    final language = _language ?? 'ru';
    setState(() { _loading = true; _address = null; });
    String? address;
    try { address = await (widget.lookup ?? _defaultLookup).lookup(point, language); }
    catch (_) { /* Coordinates remain usable when the phone cannot resolve an address. */ }
    if (mounted && request == _request) {
      setState(() { _address = address; _loading = false; });
    }
  }
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const SizedBox(height: 8),
    Text(tr(context, _loading ? 'addressLoading' : _address == null ? 'addressUnavailable' : 'nearAddress',
      {'value': _address ?? ''})),
    if (_address != null) Text(tr(context, 'addressPrecisionHint')),
    SelectableText(tr(context, 'coordinates', {'value': coordinateLabel(widget.point)})),
    Wrap(spacing: 8, children: [
      TextButton.icon(onPressed: () async {
        await Clipboard.setData(ClipboardData(text: coordinateLabel(widget.point)));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(context, 'coordinatesCopied'))));
        }
      }, icon: const Icon(Icons.copy_outlined), label: Text(tr(context, 'copyCoordinates'))),
      if (!_loading && _address == null) TextButton(onPressed: _load, child: Text(tr(context, 'retryAddress'))),
    ]),
  ]);
}
