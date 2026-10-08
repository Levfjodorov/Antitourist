import 'dart:async';
import 'package:antitourist/language_settings.dart';
import 'package:antitourist/location_address.dart';
import 'package:antitourist/places.dart';
import 'package:antitourist/strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geocoding/geocoding.dart';

class FakeAddressLookup implements AddressLookup {
  final requests = <({GeoPoint point, String language, Completer<String?> response})>[];
  @override
  Future<String?> lookup(GeoPoint point, String language) {
    final response = Completer<String?>();
    requests.add((point: point, language: language, response: response));
    return response.future;
  }
}
void main() {
  test('An address keeps the street and town without duplicate labels or a lone house number', () {
    expect(formatPlacemark(const Placemark(name: '5', thoroughfare: 'Narva mnt',
      subThoroughfare: '5', subLocality: 'Kesklinn', locality: 'Tallinn', country: 'Eesti')),
      'Narva mnt 5, Kesklinn, Tallinn, Eesti');
    expect(formatPlacemark(const Placemark(name: 'Tallinn', locality: 'Tallinn', country: 'Eesti')),
      'Tallinn, Eesti');
    expect(formatPlacemark(const Placemark()), '');
    expect(coordinateLabel(tallinnStart), '59.437000, 24.753600');
  });
  testWidgets('A late lookup cannot replace the address of a newly selected point', (tester) async {
    final lookup = FakeAddressLookup();
    Widget screen(GeoPoint point) => MaterialApp(home: Scaffold(body: LocationAddress(point: point, lookup: lookup)));
    await tester.pumpWidget(screen(tallinnStart));
    expect(lookup.requests.length, 1);
    const next = GeoPoint(59.44, 24.76);
    await tester.pumpWidget(screen(next));
    expect(lookup.requests.length, 2);
    lookup.requests.last.response.complete('New address'); await tester.pumpAndSettle();
    lookup.requests.first.response.complete('Old address'); await tester.pumpAndSettle();
    expect(find.text('Адрес рядом: New address'), findsOneWidget);
    expect(find.text('Адрес рядом: Old address'), findsNothing);
    expect(find.text('Координаты: 59.440000, 24.760000'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('An address failure retains coordinates and permits retry in the chosen language', (tester) async {
    final lookup = FakeAddressLookup();
    final settings = LanguageSettings(); addTearDown(settings.dispose);
    await tester.pumpWidget(LanguageScope(settings: settings, child: MaterialApp(
      home: Scaffold(body: LocationAddress(point: tallinnStart, lookup: lookup)))));
    lookup.requests.first.response.completeError(StateError('offline')); await tester.pumpAndSettle();
    expect(find.text('Не удалось определить адрес. Координаты доступны ниже.'), findsOneWidget);
    expect(find.text('Координаты: 59.437000, 24.753600'), findsOneWidget);
    await tester.tap(find.text('Повторить поиск адреса')); await tester.pump();
    lookup.requests.last.response.complete('Tallinn'); await tester.pumpAndSettle();
    await settings.select(AppLanguage.et); await tester.pump();
    expect(lookup.requests.last.language, 'et');
    lookup.requests.last.response.complete('Tallinn, Eesti'); await tester.pumpAndSettle();
    expect(find.text('Lähim aadress: Tallinn, Eesti'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
