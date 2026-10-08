bool isWebPage(Uri uri) =>
    uri.scheme == 'https' && uri.host.isNotEmpty && uri.userInfo.isEmpty;

bool isGoogleMapsPage(Uri uri) =>
    isWebPage(uri) &&
    ((const {'google.com', 'www.google.com'}).contains(uri.host) &&
        (uri.path == '/maps' || uri.path.startsWith('/maps/')) ||
        uri.host == 'maps.google.com');

Uri webPageUri(Uri uri) {
  if (!isGoogleMapsPage(uri)) return uri;
  final query = Map<String, List<String>>.from(uri.queryParametersAll)
    ..removeWhere((key, _) =>
        key == 'entry' || key == 'coh' || key.startsWith('utm_'));
  return uri.replace(queryParameters: query);
}

// Decode only the browser fallback, never execute the Android intent itself.
Uri? intentWebFallback(String url) {
  if (!url.startsWith('intent://') || !url.endsWith(';end;')) return null;
  final marker = url.indexOf('#Intent;');
  if (marker < 0) return null;
  final extras = url.substring(marker + '#Intent;'.length).split(';');
  final fallbacks = extras.where((part) => part.startsWith('S.browser_fallback_url='));
  if (fallbacks.length != 1) return null;
  try {
    final encoded = fallbacks.single.substring('S.browser_fallback_url='.length);
    final uri = Uri.tryParse(Uri.decodeComponent(encoded));
    return uri != null && isWebPage(uri) ? webPageUri(uri) : null;
  } on FormatException {
    return null;
  }
}

class IntentFallbacks {
  final _visited = <Uri>{};

  Uri? next(String intent) {
    final uri = intentWebFallback(intent);
    if (uri == null || _visited.length >= 8 || !_visited.add(uri)) return null;
    return uri;
  }

  void reset() => _visited.clear();
}

String desktopMapsUserAgent(String? original) {
  final agent = original ??
      'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';
  return agent
      .replaceFirst(RegExp(r'\([^)]*\)'), '(X11; Linux x86_64)')
      .replaceAll(RegExp(r'\sVersion/\S+'), '')
      .replaceAll(' Mobile', '');
}
