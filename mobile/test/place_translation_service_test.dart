import 'package:antitourist/place_details_service.dart';
import 'package:antitourist/place_translation_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('google_mlkit_on_device_translator');
  late List<MethodCall> calls;
  late Set<String> downloaded;
  var fail = false;
  const original = PlaceDetails(articleTitle: 'Monument', description: 'Avatud 1928. aastal.',
    textLanguage: 'et', sections: [PlaceArticleSection('Ajalugu', 'Taastatud 2009. aastal.')]);
  setUp(() {
    calls = []; downloaded = {}; fail = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      final args = call.arguments as Map;
      if (call.method == 'nlp#manageLanguageModelModels') {
        switch (args['task']) {
          case 'check': return downloaded.contains(args['model']);
          case 'download': downloaded.add(args['model'] as String); return 'success';
        }
      }
      if (call.method == 'nlp#startLanguageTranslator') {
        if (fail) { throw PlatformException(code: 'translation-failed'); }
        return '[${args['target']}] ${args['text']}';
      }
      return null;
    });
  });
  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));

  test('Downloads models over Wi-Fi, translates all article fields, caches and closes the native translator', () async {
    final service = PlaceTranslationService();
    final result = await service.translate(original, 'ru');
    expect(result.title, '[ru] Monument'); expect(result.description, '[ru] Avatud 1928. aastal.');
    expect(result.sections.single.title, '[ru] Ajalugu');
    expect(result.sections.single.text, '[ru] Taastatud 2009. aastal.');
    final downloads = calls.where((c) => (c.arguments as Map)['task'] == 'download');
    expect(downloads.map((c) => (c.arguments as Map)['model']), ['et', 'ru']);
    expect(downloads.every((c) => (c.arguments as Map)['wifi'] == true), isTrue);
    expect(calls.last.method, 'nlp#closeLanguageTranslator');
    final count = calls.length;
    expect(await service.translate(original, 'ru'), same(result)); expect(calls.length, count);
    expect(original.description, 'Avatud 1928. aastal.');
  });
  test('Mobile data is enabled only by an explicit request; native target text uses no models', () async {
    final service = PlaceTranslationService();
    await service.translate(original, 'ru', allowMobileData: true);
    expect(calls.where((c) => (c.arguments as Map)['task'] == 'download')
      .every((c) => (c.arguments as Map)['wifi'] == false), isTrue);
    calls.clear();
    expect((await service.translate(original, 'et')).description, original.description);
    expect(calls, isEmpty);
  });
  test('Large Unicode paragraphs are translated in bounded pieces and keep paragraph breaks', () async {
    final text = '${List.filled(4000, '😀').join()}\n\nAvatud 1928. aastal.';
    final result = await PlaceTranslationService().translate(
      PlaceDetails(description: text, textLanguage: 'et'), 'ru');
    final inputs = calls.where((c) => c.method == 'nlp#startLanguageTranslator')
      .map((c) => (c.arguments as Map)['text'] as String).toList();
    expect(inputs.length, greaterThan(2));
    expect(inputs.every((text) => text.runes.length <= 1800), isTrue);
    expect(inputs.any((text) => text.contains('\uFFFD')), isFalse);
    expect(result.description, contains('\n\n[ru] Avatud 1928. aastal.'));
  });
  test('A failed translation closes its resources and can be retried without caching failure', () async {
    final service = PlaceTranslationService();
    fail = true;
    await expectLater(service.translate(original, 'ru'), throwsA(isA<PlatformException>()));
    expect(calls.last.method, 'nlp#closeLanguageTranslator');
    fail = false;
    final result = await service.translate(original, 'ru');
    expect(result.description, '[ru] Avatud 1928. aastal.');
    expect(calls.where((c) => c.method == 'nlp#closeLanguageTranslator').length, 2);
  });
}
