import 'dart:convert';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'place_details_service.dart';

class TranslatedPlaceText {
  const TranslatedPlaceText({this.title, this.description, required this.sections});
  final String? title, description;
  final List<PlaceArticleSection> sections;
}

abstract interface class PlaceTextTranslator {
  Future<TranslatedPlaceText> translate(PlaceDetails original, String targetLanguage,
    {bool allowMobileData = false});
}

class PlaceTranslationService implements PlaceTextTranslator {
  static final shared = PlaceTranslationService();
  final _cache = <String, TranslatedPlaceText>{};

  @override
  Future<TranslatedPlaceText> translate(PlaceDetails original, String targetLanguage,
      {bool allowMobileData = false}) async {
    final source = BCP47Code.fromRawValue(original.textLanguage ?? '');
    final target = BCP47Code.fromRawValue(targetLanguage);
    if (source == null || target == null) { throw UnsupportedError('Translation language'); }
    if (source == target) {
      return TranslatedPlaceText(title: original.articleTitle, description: original.description,
        sections: original.sections);
    }
    final texts = <String>[
      original.articleTitle ?? '', original.description ?? '',
      for (final section in original.sections) ...[section.title, section.text],
    ];
    final key = jsonEncode([source.bcpCode, target.bcpCode, texts]);
    if (_cache[key] case final cached?) { return cached; }

    // English is the pivot; other languages need their own downloaded model.
    // No article text is sent to a translation server.
    final models = OnDeviceTranslatorModelManager();
    for (final language in {source, target}.where((value) => value != TranslateLanguage.english)) {
      if (!await models.isModelDownloaded(language.bcpCode)) {
        final downloaded = await models.downloadModel(language.bcpCode,
          isWifiRequired: !allowMobileData).timeout(const Duration(seconds: 60));
        if (!downloaded) { throw StateError('Translation model unavailable'); }
      }
    }
    final translator = OnDeviceTranslator(sourceLanguage: source, targetLanguage: target);
    try {
      final translated = <String>[];
      for (final text in texts) {
        translated.add(await _translateText(translator, text));
      }
      final result = TranslatedPlaceText(
        title: translated[0].isEmpty ? null : translated[0],
        description: translated[1].isEmpty ? null : translated[1],
        sections: List.unmodifiable([for (var index = 2; index < translated.length; index += 2)
          PlaceArticleSection(translated[index], translated[index + 1])]),
      );
      if (_cache.length >= 30) { _cache.remove(_cache.keys.first); }
      _cache[key] = result;
      return result;
    } finally {
      await translator.close();
    }
  }

  Future<String> _translateText(OnDeviceTranslator translator, String text) async {
    if (text.trim().isEmpty) { return ''; }
    final paragraphs = <String>[];
    for (final paragraph in text.split('\n')) {
      final runes = paragraph.runes.toList();
      final pieces = <String>[];
      for (var start = 0; start < runes.length;) {
        final limit = start + 1800;
        var end = limit < runes.length ? limit : runes.length;
        if (end < runes.length) {
          for (var candidate = end; candidate > start + 900; candidate--) {
            if (runes[candidate - 1] == 32) { end = candidate; break; }
          }
        }
        final input = String.fromCharCodes(runes.sublist(start, end)).trim();
        if (input.isNotEmpty) {
          final output = await translator.translateText(input).timeout(const Duration(seconds: 20));
          if (output.trim().isEmpty || output == 'null') { throw StateError('Empty translation'); }
          pieces.add(output.trim());
        }
        start = end;
      }
      paragraphs.add(pieces.join(' '));
    }
    return paragraphs.join('\n');
  }
}
