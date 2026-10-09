import 'dart:convert';
import 'package:antitourist/estonia_heritage.dart';
import 'package:antitourist/places.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final pharmacy = Place(id: 'node/1197', name: 'Raeapteek', category: 'history',
  lat: 59.43775259, lon: 24.74584422, description: '', score: 80, legalAccess: true,
  osmUrl: Uri.parse('https://www.openstreetmap.org/node/1197'), tags: const {'ref:kmr': '1197'});
Map<String, dynamic> monument({String number = '1197', String title = 'Tallinna Raeapteek, 14.-20. saj.',
  double lat = 59.43775259}) => {'type': 'Feature', 'geometry': {'type': 'Point', 'coordinates': [24.74584422, lat]},
    'properties': {'nimi': title, 'vk_registrinumber': number, 'tyyp': 'KPO_LIIK_EHITISMALESTIS',
      'register_url': '<script>untrusted remote HTML</script>'}};
void main() {
  test('Explicit heritage number finds the exact nearby monument and constructs a trusted source', () {
    final records = parseHeritageRecords({'features': [monument(number: '9999'), monument()]}, pharmacy);
    expect(records.single.number, '1197');
    expect(records.single.source.toString(), 'https://register.muinas.ee/public.php?menuID=monument&action=view&id=1197');
    expect(records.single.title, 'Tallinna Raeapteek, 14.-20. saj.');
  });
  test('Coordinate proximity alone cannot attach history to a different monument', () {
    final place = Place.fromJson({...pharmacy.toJson(), 'tags': <String, String>{}, 'name': 'Different place'});
    expect(parseHeritageRecords({'features': [monument()]}, place), isEmpty);
    expect(parseHeritageRecords({'features': [monument(lat: 59.50)]}, pharmacy), isEmpty);
  });
  test('Exact name matches are rejected when two heritage identities are ambiguous', () {
    final place = Place.fromJson({...pharmacy.toJson(), 'tags': <String, String>{}, 'name': 'Tallinna Raeapteek'});
    expect(parseHeritageRecords({'features': [monument(), monument(number: '555')]}, place), isEmpty);
    expect(parseHeritageRecords({'features': [monument()]}, place).single.number, '1197');
  });
  test('WFS uses official longitude/latitude coordinates, bounded features and safe numeric CQL', () async {
    var calls = 0;
    final service = EstoniaHeritageService(client: MockClient((request) async {
      calls++;
      expect(request.url.host, 'gsavalik.envir.ee');
      expect(request.url.queryParameters['version'], '1.0.0');
      expect(request.url.queryParameters['CQL_FILTER'], "vk_registrinumber='1197'");
      expect(request.url.queryParameters['maxFeatures'], '100');
      return http.Response(jsonEncode({'features': [monument()]}), 200);
    }));
    expect((await service.load(pharmacy)).single.number, '1197');
    expect((await service.load(pharmacy)).single.number, '1197'); expect(calls, 1);
    expect(isInEstonia(const GeoPoint(48.8, 2.3)), isFalse);
  });
}
