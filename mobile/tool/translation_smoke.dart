// Separate release entry point used only by the Android translation smoke job.
import 'dart:convert';
import 'package:antitourist/place_details_service.dart';
import 'package:antitourist/place_translation_service.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home: Scaffold(body: Center(child: Text('Translation smoke test')))));
  try {
    const original = PlaceDetails(articleTitle: 'Tondipoiste monument', textLanguage: 'et',
      description: 'Mälestusmärk avati 1928. aastal.',
      sections: [PlaceArticleSection('Ajalugu', 'Mälestusmärk taastati 2009. aastal.')]);
    final result = await PlaceTranslationService().translate(original, 'ru', allowMobileData: true);
    if (result.description == original.description || result.sections.single.text == original.sections.single.text ||
        !RegExp('[А-Яа-я]').hasMatch(result.description ?? '')) {
      throw StateError('Native translation did not produce Russian text');
    }
    debugPrint('ANTITOURIST_TRANSLATION_RESULT=${jsonEncode({
      'ok': true, 'description': result.description, 'section': result.sections.single.text,
    })}');
  } catch (error, stack) {
    debugPrintStack(stackTrace: stack);
    debugPrint('ANTITOURIST_TRANSLATION_RESULT=${jsonEncode({'ok': false, 'error': error.toString()})}');
  }
}
