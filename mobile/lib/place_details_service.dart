import 'dart:convert';
import 'package:html/parser.dart' show parseFragment;
import 'package:http/http.dart' as http;
import 'places.dart';

const wikimediaUserAgent = 'AntiTourist/0.5.8 (https://github.com/Levfjodorov/Antitourist)';

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
  const PlaceDetails({this.description, this.article, this.photo, this.nearbyPhotos = const [],
    this.sections = const [], this.textLanguage, this.articleTitle, this.textTruncated = false,
    this.partial = false, this.articleDistanceMeters});
  final String? description;
  final Uri? article;
  final PlacePhoto? photo;
  final List<PlacePhoto> nearbyPhotos;
  final List<PlaceArticleSection> sections;
  final String? textLanguage, articleTitle;
  // Set only for an article discovered by matching a name and coordinates.
  final double? articleDistanceMeters;
  final bool partial, textTruncated;
}

class PlaceArticleSection {
  const PlaceArticleSection(this.title, this.text);
  final String title, text;
}

class NearbyArticle {
  const NearbyArticle({required this.title, required this.language,
    required this.pageId, required this.distance, this.wikidata});
  final String title, language;
  final int pageId;
  final double distance;
  final String? wikidata;
}

String _normalizedName(String value) => value.toLowerCase()
  .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ').trim();

Set<String> _placeNames(Place place) {
  const generic = {'place', 'unknown', 'unnamed', 'monument', 'memorial', 'church',
    'museum', 'park', 'viewpoint', 'cafe', 'café', 'restaurant', 'ruins',
    'место', 'без названия', 'памятник', 'мемориал', 'церковь', 'музей', 'парк',
    'смотровая площадка', 'кафе', 'ресторан', 'руины', 'koht', 'nimetu',
    'mälestusmärk', 'kirik', 'muuseum', 'vaateplatvorm', 'kohvik', 'varemed'};
  const nameTags = {'name', 'alt_name', 'official_name', 'short_name', 'old_name'};
  final names = <String>{place.name, ...place.localizedNames.values};
  for (final entry in place.tags.entries) {
    if (nameTags.contains(entry.key.split(':').first)) {
      names.addAll(entry.value.split(';'));
    }
  }
  return names.map(_normalizedName)
    .where((name) => name.length >= 4 && name.length < 500 && !generic.contains(name)).toSet();
}

// A nearby article alone is not an identity match. Require an exact normalized
// title or redirect match, an Earth coordinate within 250 m, and a real article.
List<NearbyArticle> matchingNearbyArticles(Map<String, dynamic> data, Place place, String language) {
  final pages = data['query']?['pages'];
  final names = _placeNames(place);
  if (pages is! List || !place.point.valid || names.isEmpty) { return const []; }
  final result = <NearbyArticle>[];
  final seen = <int>{};
  for (final raw in pages) {
    try {
      if (raw is! Map || raw['ns'] != 0 || raw.containsKey('missing') ||
          raw['pageprops'] is Map && (raw['pageprops'] as Map).containsKey('disambiguation')) { continue; }
      final id = raw['pageid'];
      final title = raw['title'];
      if (id is! int || id <= 0 || title is! String || title.isEmpty ||
          title.length >= 500 || title.contains('|')) { continue; }
      final aliases = <String>[title];
      if (raw['redirects'] case final List redirects) {
        for (final redirect in redirects) {
          if (redirect is Map && redirect['title'] is String) { aliases.add(redirect['title'] as String); }
        }
      }
      if (!aliases.map(_normalizedName).any(names.contains)) { continue; }
      final coordinates = raw['coordinates'];
      if (coordinates is! List || coordinates.isEmpty) { continue; }
      final coordinate = coordinates.first;
      if (coordinate is! Map || coordinate['globe'] != 'earth' ||
          coordinate['lat'] is! num || coordinate['lon'] is! num) { continue; }
      final point = GeoPoint((coordinate['lat'] as num).toDouble(), (coordinate['lon'] as num).toDouble());
      if (!point.valid) { continue; }
      final distance = distanceMeters(place.point, point);
      if (distance > 250 || !seen.add(id)) { continue; }
      final entity = raw['pageprops']?['wikibase_item'];
      result.add(NearbyArticle(title: title, language: language, pageId: id, distance: distance,
        wikidata: entity is String && RegExp(r'^Q[1-9][0-9]*$').hasMatch(entity) ? entity : null));
    } catch (_) { /* Ignore one malformed candidate, rather than other articles. */ }
  }
  return result;
}

// TextExtracts supplies plain text and wiki-style headings, never executable HTML.
// Keep the historical sections, rather than requesting only the introduction.
({String? lead, List<PlaceArticleSection> sections, bool truncated}) parseArticleText(String raw) {
  final original = raw.trim();
  final text = String.fromCharCodes(original.runes.take(24000));
  final headings = RegExp(r'^(={2,6})[ \t]*(.+?)[ \t]*\1[ \t]*$', multiLine: true)
    .allMatches(text).toList();
  final lead = text.substring(0, headings.isEmpty ? text.length : headings.first.start).trim();
  final sections = <PlaceArticleSection>[];
  for (var index = 0; index < headings.length; index++) {
    final heading = headings[index];
    final body = text.substring(heading.end,
      index + 1 < headings.length ? headings[index + 1].start : text.length).trim();
    if (body.isNotEmpty) { sections.add(PlaceArticleSection(heading[2]!.trim(), body)); }
  }
  return (lead: lead.isEmpty ? null : lead, sections: List.unmodifiable(sections),
    truncated: text.length < original.length);
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
  // Reuse successful downloads when a card is reopened during this app session.
  static final shared = PlaceDetailsService();
  final http.Client _client;
  final _cache = <String, PlaceDetails>{};
  final _pending = <String, Future<PlaceDetails>>{};
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
  Future<({NearbyArticle? article, bool partial})> _discoverArticle(Place place, String language) async {
    if (!place.point.valid || _placeNames(place).isEmpty) { return (article: null, partial: false); }
    // Search the selected language, a local name's language and English. Estonia
    // gets Estonian before other name languages; the total stays bounded at 3.
    final languages = <String>{language,
      if (place.lat >= 57.4 && place.lat <= 59.9 && place.lon >= 21.6 && place.lon <= 28.3) 'et',
      ...place.localizedNames.keys,
      ...place.tags.keys.where((key) => key.startsWith('name:')).map((key) => key.substring(5)),
      'en',
    }.where((code) => RegExp(r'^[a-z]{2,12}(?:-[a-z]+)?$').hasMatch(code)).take(3);
    final results = await Future.wait(languages.map((code) async {
      try {
        final data = await _get(Uri.https('$code.wikipedia.org', '/w/api.php', {
          'action': 'query', 'format': 'json', 'formatversion': '2',
          'generator': 'geosearch', 'ggsnamespace': '0',
          'ggscoord': '${place.lat}|${place.lon}', 'ggsradius': '250', 'ggslimit': '20',
          'prop': 'coordinates|redirects|pageprops', 'coprimary': 'primary', 'colimit': '50',
          'rdnamespace': '0', 'rdlimit': '20', 'ppprop': 'disambiguation|wikibase_item',
        }));
        return (matches: matchingNearbyArticles(data, place, code), partial: false);
      } catch (_) { return (matches: <NearbyArticle>[], partial: true); }
    }));
    final matches = results.expand((result) => result.matches).toList();
    final identities = matches.map((match) => match.wikidata ?? '${match.language}:${match.pageId}').toSet();
    // Versions of the same Wikidata entity are safe to prefer by language.
    // Two distinct matching objects are ambiguous even if one is closer.
    return (article: identities.length == 1 ? matches.first : null,
      partial: results.any((result) => result.partial));
  }
  Future<Map<String, dynamic>?> _wikipediaPage(String title, String language, String preferredLanguage) async {
    final data = await _get(Uri.https('$language.wikipedia.org', '/w/api.php', {
      'action': 'query', 'format': 'json', 'formatversion': '2',
      'prop': 'extracts|pageimages|info|langlinks|pageprops', 'ppprop': 'disambiguation',
      'piprop': 'name', 'pilicense': 'free', 'inprop': 'url',
      'explaintext': '1', 'exsectionformat': 'wiki', 'redirects': '1', 'titles': title,
      'lllang': preferredLanguage, 'lllimit': '1',
    }));
    final pages = data['query']?['pages'];
    if (pages is! List || pages.isEmpty || pages.first is! Map ||
        (pages.first as Map).containsKey('missing')) { return null; }
    final page = Map<String, dynamic>.from(pages.first as Map);
    if (page['pageprops'] is Map && (page['pageprops'] as Map).containsKey('disambiguation')) { return null; }
    return page;
  }
  Future<PlaceDetails> load(Place place, String language) {
    final key = '${place.key}:$language';
    if (_cache.containsKey(key)) { return Future.value(_cache[key]!); }
    return _pending.putIfAbsent(key, () => _load(place, language, key)
      .whenComplete(() { _pending.remove(key); }));
  }
  Future<PlaceDetails> _load(Place place, String language, String key) async {
    if (place.osmUrl == null) { return const PlaceDetails(); }
    var failed = false;
    String? filename, summary, title, articleLanguage;
    var sections = <PlaceArticleSection>[];
    var textTruncated = false;
    double? articleDistance;
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
    final localizedWikipedia = place.tags['wikipedia:$language'];
    final wikipedia = localizedWikipedia == null ? place.tags['wikipedia']
      : localizedWikipedia.contains(':') ? localizedWikipedia : '$language:$localizedWikipedia';
    final match = wikipedia == null ? null : RegExp(r'^([a-z]{2,12}(?:-[a-z]+)?):(.+)$').firstMatch(wikipedia);
    if (match != null) { articleLanguage = match[1]; title = match[2]; }
    var wikidata = place.tags['wikidata'];
    if (title == null && (wikidata == null || !RegExp(r'^Q[1-9][0-9]*$').hasMatch(wikidata))) {
      final discovery = await _discoverArticle(place, language);
      failed = failed || discovery.partial;
      if (discovery.article case final NearbyArticle found) {
        title = found.title; articleLanguage = found.language; articleDistance = found.distance;
        wikidata = found.wikidata;
      }
    }
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
        // An exact entity may have its history only in another supported language.
        if (title == null) {
          for (final fallback in ['en', 'et', 'ru']) {
            final candidate = entity?['sitelinks']?['${fallback}wiki']?['title'];
            if (candidate is String && candidate.isNotEmpty) {
              title = candidate; articleLanguage = fallback; break;
            }
          }
        }
        if (title == null) {
          final description = entity?['descriptions']?[language]?['value'];
          if (description is String) {
            summary = description;
            article = Uri.https('www.wikidata.org', '/wiki/$wikidata');
          }
        }
      } catch (_) { failed = true; }
    }
    if (title != null && title.length < 500 && !title.contains('|') && articleLanguage != null) {
      article = Uri.https('$articleLanguage.wikipedia.org', '/wiki/${title.replaceAll(' ', '_')}');
      try {
        var page = await _wikipediaPage(title, articleLanguage, language);
        final originalPageImage = page?['pageimage'];
        if (articleLanguage != language) {
          final links = page?['langlinks'];
          if (links is List) {
            for (final link in links) {
              if (link is! Map || link['lang'] != language) { continue; }
              final localizedTitle = link['title'] ?? link['*'];
              if (localizedTitle is! String || localizedTitle.isEmpty ||
                  localizedTitle.length >= 500 || localizedTitle.contains('|')) { continue; }
              try {
                final localized = await _wikipediaPage(localizedTitle, language, language);
                if (localized?['extract'] case final String text when text.trim().isNotEmpty) {
                  page = localized; title = localizedTitle; articleLanguage = language;
                  article = Uri.https('$language.wikipedia.org', '/wiki/${title.replaceAll(' ', '_')}');
                }
              } catch (_) { failed = true; /* Keep the original article for translation. */ }
              break;
            }
          }
        }
        final extract = page?['extract'];
        if (extract is String && extract.trim().isNotEmpty) {
          final text = parseArticleText(extract);
          summary = text.lead; sections = text.sections; textTruncated = text.truncated;
          final resolvedTitle = page?['title'];
          if (resolvedTitle is String && resolvedTitle.isNotEmpty) { title = resolvedTitle; }
          final resolvedUrl = safeWebUrl(page?['fullurl'] as String?);
          if (resolvedUrl?.host == '$articleLanguage.wikipedia.org') { article = resolvedUrl; }
        }
        final pageImage = page?['pageimage'] ?? originalPageImage;
        if (filename == null && pageImage is String && pageImage.isNotEmpty) { filename = pageImage; }
      } catch (_) { failed = true; }
    }
    PlacePhoto? photo;
    if (filename != null && filename.isNotEmpty && filename.length < 300 && !filename.contains('|')) {
      try {
        final data = await _get(Uri.https('commons.wikimedia.org', '/w/api.php', {
          'action': 'query', 'format': 'json', 'formatversion': '2', 'prop': 'imageinfo',
          'iiprop': 'url|mime|extmetadata', 'iiurlwidth': '1280', 'titles': 'File:$filename',
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
          'iiprop': 'url|mime|extmetadata', 'iiurlwidth': '1280',
        }));
        nearby = parseNearbyPhotos(data, place.point);
      } catch (_) { failed = true; }
    }
    final result = PlaceDetails(description: summary, article: article, photo: photo,
      nearbyPhotos: nearby, sections: sections, textLanguage: articleLanguage,
      articleTitle: title, textTruncated: textTruncated, partial: failed,
      articleDistanceMeters: articleDistance);
    if (!failed) {
      if (_cache.length >= 30) { _cache.remove(_cache.keys.first); }
      _cache[key] = result;
    }
    return result;
  }
}
