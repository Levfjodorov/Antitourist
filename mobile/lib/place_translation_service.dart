import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
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

enum TranslationProblem { wifiRequired, offline, downloadTimeout, unavailable, failed }

class PlaceTranslationException implements Exception {
  const PlaceTranslationException(this.problem, {this.diagnostic = ''});
  final TranslationProblem problem;
  final String diagnostic;
  @override
  String toString() => 'Translation ${problem.name}: $diagnostic';
}

class PlaceTranslationService implements PlaceTextTranslator {
  PlaceTranslationService({this.modelTimeout = const Duration(minutes: 5),
    Future<Map<String, dynamic>?> Function()? networkStatus})
    : _networkStatus = networkStatus ?? _readNetworkStatus;
  static final shared = PlaceTranslationService();
  static const _network = MethodChannel('antitourist/translation_network');
  final Duration modelTimeout;
  final Future<Map<String, dynamic>?> Function() _networkStatus;
  static Future<Map<String, dynamic>?> _readNetworkStatus() =>
    _network.invokeMapMethod<String, dynamic>('status');
  final _cache = <String, TranslatedPlaceText>{};
  final _pending = <String, Future<TranslatedPlaceText>>{};

  @override
  Future<TranslatedPlaceText> translate(PlaceDetails original, String targetLanguage,
      {bool allowMobileData = false}) {
    final key = jsonEncode([original.textLanguage, targetLanguage, original.articleTitle,
      original.description, for (final section in original.sections) [section.title, section.text], allowMobileData]);
    return _pending.putIfAbsent(key, () => _translate(original, targetLanguage,
      allowMobileData: allowMobileData).whenComplete(() { _pending.remove(key); }));
  }

  Future<TranslatedPlaceText> _translate(PlaceDetails original, String targetLanguage,
      {required bool allowMobileData}) async {
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
    String? stage;
    try {
      for (final language in {source, target}.where((value) => value != TranslateLanguage.english)) {
        stage = 'model ${language.bcpCode}';
        if (!await models.isModelDownloaded(language.bcpCode).timeout(const Duration(seconds: 15))) {
          final status = await _networkStatus().timeout(const Duration(seconds: 15));
          if (status?['connected'] != true) {
            throw const PlaceTranslationException(TranslationProblem.offline);
          }
          // Do not enqueue a Wi-Fi-only download on cellular. ML Kit reuses that
          // pending native task on retry, even when the new call allows mobile data.
          if (!allowMobileData && status?['wifi'] != true) {
            throw const PlaceTranslationException(TranslationProblem.wifiRequired);
          }
          final downloaded = await models.downloadModel(language.bcpCode,
            isWifiRequired: !allowMobileData).timeout(modelTimeout);
          if (!downloaded) { throw StateError('Translation model unavailable'); }
        }
      }
      stage = 'text ${source.bcpCode} → ${target.bcpCode}';
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
    } on PlaceTranslationException { rethrow; }
    on TimeoutException catch (error) {
      throw PlaceTranslationException(stage?.startsWith('model ') == true ?
        TranslationProblem.downloadTimeout : TranslationProblem.failed,
        diagnostic: '$stage: $error');
    } on MissingPluginException catch (error) {
      throw PlaceTranslationException(TranslationProblem.unavailable, diagnostic: error.toString());
    } on PlatformException catch (error) {
      throw PlaceTranslationException(TranslationProblem.failed,
        diagnostic: '$stage: ${error.code}: ${error.message ?? ""}');
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
