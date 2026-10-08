import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'language_settings.dart';
import 'place_web_screen.dart';
import 'web_navigation.dart';

Future<void> openExternal(BuildContext context, Uri uri) async {
  try {
    if (!isWebPage(uri)) throw const FormatException('Expected an HTTPS URL');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw Exception('No URL handler');
    }
  } catch (_) {
    _showLinkError(context, 'linkError');
  }
}

Future<void> openInApp(BuildContext context, Uri uri) async {
  try {
    if (!isWebPage(uri)) throw const FormatException('Expected an HTTPS URL');
    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => PlaceWebScreen(uri: uri)));
  } catch (_) {
    _showLinkError(context, 'inAppLinkError');
  }
}

void _showLinkError(BuildContext context, String key) {
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(tr(context, key))));
  }
}
