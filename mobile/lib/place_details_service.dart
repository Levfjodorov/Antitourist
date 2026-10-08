import 'dart:convert';
import 'package:html/parser.dart' show parseFragment;
import 'package:http/http.dart' as http;
import 'places.dart';

const wikimediaUserAgent = 'AntiTourist/0.5.1 (https://github.com/Levfjodorov/Antitourist)';

class PlacePhoto {
  const PlacePhoto({required this.url, required this.source, required this.credit,
    required this.license, this.licenseUrl, this.caption, this.nearbyMeters});
  final Uri url, source;
  final String credit, license;
  final Uri? licenseUrl;
  final String? caption;
  final double? nearbyMeters;
}
class PlaceDetails {
  const PlaceDetails({this.description, this.article, this.photo, this.nearbyPhotos = const [], this.partial = false});
  final String? description;
  final Uri? article;
  final PlacePhoto? photo;
  final List<PlacePhoto> nearbyPhotos;
  final bool partial;
}

String metadataText(dynamic raw) => (parseFragment(raw is String ? raw : '').text ?? '').trim();
Uri? safeWebUrl(String? value) {
  final uri = value == null ? null : Uri.tryParse(value.trim());
  return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty && uri.userInfo.isEmpty ? uri : null;
}

PlacePhoto? parseCommonsPhoto(Map<String, dynamic> data) {
  final pages = data['query']?['pages'];
  if (pages is! List || pages.isEmpty) { return null; }
  final infos = pages.first['imageinfo'];
  if (infos is! List || infos.isEmpty) { return null; }
  final info = infos.first as Map;
  final metadata = info['extmetadata'];
  if (metadata is! Map) { return null; }
  String field(String key) => metadataText(metadata[key]?['value']);
  final url = safeWebUrl(info['thumburl'] as String?);
  final source = safeWebUrl(info['descriptionurl'] as String?);
  final attribution = field('Attribution');
  final credit = attribution.isNotEmpty ? attribution
    : [field('Artist'), field('Credit')].where((s) => s.isNotEmpty).join(' · ');
  final license = field('LicenseShortName');
  if (url == null || source == null || url.host != 'upload.wikimedia.org' || source.host != 'commons.wikimedia.org' ||
      !['image/jpeg', 'image/png', 'image/webp'].contains(info['thumbmime'] ?? info['mime']) ||
      (field('Artist').isEmpty && attribution.isEmpty) || credit.isEmpty || license.isEmpty) { return null; }
  return PlacePhoto(url: url, source: source, credit: credit, license: license,
    licenseUrl: safeWebUrl(field('LicenseUrl')), caption: field('ImageDescription'));
}

List<PlacePhoto> parseNearbyPhotos(Map<String, dynamic> data, GeoPoint origin) {
  final pages = data['query']?['pages'];
  if (pages is! List || !origin.valid) { return const []; }
  final result = <PlacePhoto>[];
  final seen = <String>{};
  for (final raw in pages) {
    try {
      if (raw is! Map || raw['ns'] != 6) { continue; }
      final coordinates = raw['coordinates'];
      if (coordinates is! List || coordinates.isEmpty) { continue; }
      final coordinate = coordinates.first;
      if (coordinate['globe'] != 'earth' || coordinate['lat'] is! num || coordinate['lon'] is! num) { continue; }
      final point = GeoPoint((coordinate['lat'] as num).toDouble(), (coordinate['lon'] as num).toDouble());
      if (!point.valid) { continue; }
      final distance = distanceMeters(origin, point);
      if (distance > 150) { continue; }
      final photo = parseCommonsPhoto({'query': {'pages': [raw]}});
      if (photo == null || !seen.add(photo.source.toString())) { continue; }
      result.add(PlacePhoto(url: photo.url, source: photo.source, credit: photo.credit,
        license: photo.license, licenseUrl: photo.licenseUrl, caption: photo.caption,
        nearbyMeters: distance));
    } catch (_) { /* One malformed file should not hide other valid photos. */ }
  }
  result.sort((a, b) => a.nearbyMeters!.compareTo(b.nearbyMeters!));
  return result.take(3).toList();
}

class PlaceDetailsService {
  PlaceDetailsService({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;
  final _cache = <String, PlaceDetails>{};
  void close() => _client.close();
  Future<Map<String, dynamic>> _get(Uri uri) async {
    final response = await _client.get(uri, headers: {
      'User-Agent': wikimediaUserAgent,
      'Accept': 'application/json',
    }).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200 || response.bodyBytes.length > 2000000) {
      throw const FormatException('Wikimedia unavailable');
    }
    final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    if (data.containsKey('error')) { throw const FormatException('Wikimedia API error'); }
    return data;
  }
  Future<PlaceDetails> load(Place place, String language) async {
    final key = '${place.key}:$language';
    if (_cache.containsKey(key)) { return _cache[key]!; }
    if (place.osmUrl == null) { return const PlaceDetails(); }
    var failed = false;
    String? filename, summary, title, articleLanguage;
    Uri? article;
    final commons = place.tags['wikimedia_commons'];
    if (commons != null && commons.startsWith('File:')) { filename = commons.substring(5); }
    final image = place.tags['image'];
    if (filename == null && image != null) {
      final uri = safeWebUrl(image);
      if (uri != null && uri.host == 'commons.wikimedia.org' && uri.path.startsWith('/wiki/File:')) {
        filename = Uri.decodeComponent(uri.path.substring('/wiki/File:'.length));
      } else if (uri != null && uri.host == 'upload.wikimedia.org' &&
          uri.path.startsWith('/wikipedia/commons/')) {
        final pieces = uri.pathSegments;
        if (pieces.length >= 5) { filename = pieces[2] == 'thumb' ? pieces[pieces.length - 2] : pieces.last; }
      }
    }
    final wikipedia = place.tags['wikipedia:$language'] ?? place.tags['wikipedia'];
    final match = wikipedia == null ? null : RegExp(r'^([a-z]{2,12}(?:-[a-z]+)?):(.+)$').firstMatch(wikipedia);
    if (match != null) { articleLanguage = match[1]; title = match[2]; }
    final wikidata = place.tags['wikidata'];
    if (wikidata != null && RegExp(r'^Q[1-9][0-9]*$').hasMatch(wikidata)) {
      try {
        final entityData = await _get(Uri.https('www.wikidata.org', '/wiki/Special:EntityData/$wikidata.json'));
        final entity = entityData['entities']?[wikidata] as Map?;
        final claims = entity?['claims']?['P18'];
        if (filename == null && claims is List) {
          for (final claim in claims) {
            if (claim['rank'] == 'deprecated') { continue; }
            final value = claim['mainsnak']?['datavalue']?['value'];
            if (value is String && value.isNotEmpty) { filename = value; break; }
          }
        }
        final preferred = entity?['sitelinks']?['${language}wiki']?['title'];
        if (preferred is String) { title = preferred; articleLanguage = language; }
        if (title == null) {
          final description = entity?['descriptions']?[language]?['value'];
          if (description is String) {
            summary = description;
            article = Uri.https('www.wikidata.org', '/wiki/$wikidata');
          }
        }
      } catch (_) { failed = true; }
    }
    if (title != null && articleLanguage != null) {
      article = Uri.https('$articleLanguage.wikipedia.org', '/wiki/${title.replaceAll(' ', '_')}');
      try {
        final data = await _get(Uri.https('$articleLanguage.wikipedia.org', '/w/api.php', {
          'action': 'query', 'format': 'json', 'formatversion': '2', 'prop': 'extracts|pageimages', 'piprop': 'name', 'pilicense': 'free',
          'exintro': '1', 'explaintext': '1', 'exchars': '1000', 'redirects': '1', 'titles': title,
        }));
        final pages = data['query']?['pages'];
        final extract = pages is List && pages.isNotEmpty ? pages.first['extract'] : null;
        if (extract is String && extract.trim().isNotEmpty) { summary = extract.trim(); }
        final pageImage = pages is List && pages.isNotEmpty ? pages.first['pageimage'] : null;
        if (filename == null && pageImage is String && pageImage.isNotEmpty) { filename = pageImage; }
      } catch (_) { failed = true; }
    }
    PlacePhoto? photo;
    if (filename != null && filename.isNotEmpty && filename.length < 300 && !filename.contains('|')) {
      try {
        final data = await _get(Uri.https('commons.wikimedia.org', '/w/api.php', {
          'action': 'query', 'format': 'json', 'formatversion': '2', 'prop': 'imageinfo',
          'iiprop': 'url|mime|extmetadata', 'iiurlwidth': '640', 'titles': 'File:$filename',
        }));
        photo = parseCommonsPhoto(data);
      } catch (_) { failed = true; }
    }
    var nearby = <PlacePhoto>[];
    if (photo == null && place.point.valid) {
      try {
        final data = await _get(Uri.https('commons.wikimedia.org', '/w/api.php', {
          'action': 'query', 'format': 'json', 'formatversion': '2',
          'generator': 'geosearch', 'ggsnamespace': '6',
          'ggscoord': '${place.lat}|${place.lon}', 'ggsradius': '150', 'ggslimit': '8',
          'prop': 'imageinfo|coordinates', 'coprimary': 'primary',
          'iiprop': 'url|mime|extmetadata', 'iiurlwidth': '640',
        }));
        nearby = parseNearbyPhotos(data, place.point);
      } catch (_) { failed = true; }
    }
    final result = PlaceDetails(description: summary, article: article, photo: photo,
      nearbyPhotos: nearby, partial: failed);
    if (!failed) {
      if (_cache.length >= 30) { _cache.remove(_cache.keys.first); }
      _cache[key] = result;
    }
    return result;
  }
}
