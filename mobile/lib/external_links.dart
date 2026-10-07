import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'language_settings.dart';

Future<void> openExternal(BuildContext context, Uri uri) async {
  try {
    if (uri.scheme != 'https' || !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw Exception('No URL handler');
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'linkError'))));
    }
  }
}
