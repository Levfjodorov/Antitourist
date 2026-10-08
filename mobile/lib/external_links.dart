import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'language_settings.dart';

Future<void> openExternal(BuildContext context, Uri uri) =>
    _open(context, uri, LaunchMode.externalApplication);

Future<void> openInApp(BuildContext context, Uri uri) =>
    _open(context, uri, LaunchMode.inAppWebView);

Future<void> _open(BuildContext context, Uri uri, LaunchMode mode) async {
  try {
    if (uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
      throw const FormatException('Expected a public HTTPS URL');
    }
    // Do not let an unsupported embedded view silently open another app.
    if (mode == LaunchMode.inAppWebView && !await supportsLaunchMode(mode)) {
      throw StateError('Embedded browsing is unavailable');
    }
    if (!await launchUrl(uri, mode: mode,
        webViewConfiguration: const WebViewConfiguration(
          enableJavaScript: true, enableDomStorage: true))) {
      throw Exception('No URL handler');
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context,
          mode == LaunchMode.inAppWebView ? 'inAppLinkError' : 'linkError'))));
    }
  }
}
