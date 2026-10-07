import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> openExternal(BuildContext context, Uri uri) async {
  try {
    if (uri.scheme != 'https' || !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw Exception('No URL handler');
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось открыть ссылку. Проверь браузер на телефоне.')));
    }
  }
}
