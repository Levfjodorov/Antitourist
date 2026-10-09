import 'dart:async';
import 'package:antitourist/language_settings.dart';
import 'package:antitourist/place_details_screen.dart';
import 'package:antitourist/place_details_service.dart';
import 'package:antitourist/place_translation_service.dart';
import 'package:antitourist/places.dart';
import 'package:antitourist/strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'route_fixtures.dart';

class DeferredDetailsService extends PlaceDetailsService {
  final calls = <({String language, Completer<PlaceDetails> result})>[];
  @override
  Future<PlaceDetails> load(Place place, String language) {
    final result = Completer<PlaceDetails>();
    calls.add((language: language, result: result));
    return result.future;
  }
}

class DeferredTranslator implements PlaceTextTranslator {
  final calls = <({String target, bool mobile, Completer<TranslatedPlaceText> result})>[];
  @override
  Future<TranslatedPlaceText> translate(PlaceDetails original, String targetLanguage,
      {bool allowMobileData = false}) {
    final result = Completer<TranslatedPlaceText>();
    calls.add((target: targetLanguage, mobile: allowMobileData, result: result));
    return result.future;
  }
}

void main() {
  testWidgets('A discovered article shows the name-and-coordinate match and its distance', (tester) async {
    final service = DeferredDetailsService();
    await tester.pumpWidget(MaterialApp(home: PlaceDetailsScreen(
      place: routePlaces.first, demo: false, service: service)));
    service.calls.single.result.complete(const PlaceDetails(description: 'История аптеки.',
      textLanguage: 'ru', articleTitle: 'Ратушная аптека', articleDistanceMeters: 12,
      article: null));
    await tester.pumpAndSettle();
    final hint = find.text('Статья найдена по совпадению названия и координат: примерно 12 м от точки. Проверь источник, если сведения не соответствуют месту.');
    final scroll = find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(hint, 150, scrollable: scroll);
    expect(hint, findsOneWidget); expect(tester.takeException(), isNull);
  });
  const source = PlaceDetails(articleTitle: 'Monument', textLanguage: 'et',
    description: 'Avatud 1928. aastal.', sections: [PlaceArticleSection('Ajalugu', 'Taastatud 2009. aastal.')]);
  const translated = TranslatedPlaceText(title: 'Памятник', description: 'Открыт в 1928 году.',
    sections: [PlaceArticleSection('История памятника', 'Восстановлен в 2009 году.')]);
  testWidgets('Foreign article translates into the app language automatically and the original toggle needs no new request', (tester) async {
    final service = DeferredDetailsService();
    final translator = DeferredTranslator();
    await tester.pumpWidget(MaterialApp(home: PlaceDetailsScreen(
      place: routePlaces.first, demo: false, service: service, translator: translator)));
    service.calls.single.result.complete(source);
    await tester.pump();
    expect(translator.calls.single.target, 'ru'); expect(translator.calls.single.mobile, isFalse);
    expect(find.text('Avatud 1928. aastal.'), findsOneWidget);
    translator.calls.single.result.complete(translated);
    await tester.pumpAndSettle();
    final scroll = find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(find.text('Открыт в 1928 году.'), 150, scrollable: scroll);
    expect(find.text('История памятника'), findsOneWidget);
    final toggle = find.byKey(const ValueKey('toggle-original-text'));
    await Scrollable.ensureVisible(tester.element(toggle), alignment: 0.5);
    await tester.pumpAndSettle();
    expect(toggle.hitTestable(), findsOneWidget);
    await tester.tap(toggle); await tester.pumpAndSettle();
    expect(find.text('Avatud 1928. aastal.'), findsOneWidget);
    await Scrollable.ensureVisible(tester.element(toggle), alignment: 0.5);
    await tester.pumpAndSettle();
    expect(toggle.hitTestable(), findsOneWidget);
    await tester.tap(toggle); await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Открыт в 1928 году.'), 150, scrollable: scroll);
    expect(find.text('Открыт в 1928 году.'), findsOneWidget);
    expect(translator.calls.length, 1); expect(service.calls.length, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Cellular retry works, keeps its permission, and disables duplicate taps while loading', (tester) async {
    final service = DeferredDetailsService();
    final translator = DeferredTranslator();
    await tester.pumpWidget(MaterialApp(home: PlaceDetailsScreen(
      place: routePlaces.first, demo: false, service: service, translator: translator)));
    service.calls.single.result.complete(source); await tester.pump();
    translator.calls.first.result.completeError(const PlaceTranslationException(TranslationProblem.wifiRequired));
    await tester.pumpAndSettle();
    expect(find.text('Для загрузки языковых пакетов подключи Wi-Fi или разреши мобильный интернет кнопкой ниже.'), findsOneWidget);
    final mobile = find.byKey(const ValueKey('translation-mobile-data'));
    await Scrollable.ensureVisible(tester.element(mobile), alignment: 0.5);
    await tester.pumpAndSettle();
    expect(mobile.hitTestable(), findsOneWidget);
    await tester.tap(mobile); await tester.pump();
    expect(translator.calls.last.mobile, isTrue);
    expect(tester.widget<TextButton>(mobile).onPressed, isNull);
    await tester.tap(mobile); await tester.pump();
    expect(translator.calls.length, 2);
    translator.calls.last.result.completeError(StateError('Model unavailable'));
    await tester.pumpAndSettle();
    expect(find.text('Avatud 1928. aastal.'), findsOneWidget);
    expect(find.byKey(const ValueKey('retry-translation')), findsOneWidget);
    expect(find.byKey(const ValueKey('translation-diagnostic')), findsOneWidget);
    final retry = find.byKey(const ValueKey('retry-translation'));
    await Scrollable.ensureVisible(tester.element(retry), alignment: 0.5);
    await tester.pumpAndSettle();
    expect(retry.hitTestable(), findsOneWidget);
    await tester.tap(retry); await tester.pump();
    expect(translator.calls.last.mobile, isTrue);
    translator.calls.last.result.complete(translated); await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('retry-translation')), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Changing language or closing the card discards a pending translation', (tester) async {
    final settings = LanguageSettings(); addTearDown(settings.dispose);
    final service = DeferredDetailsService();
    final translator = DeferredTranslator();
    await tester.pumpWidget(LanguageScope(settings: settings, child: MaterialApp(home: PlaceDetailsScreen(
      place: routePlaces.first, demo: false, service: service, translator: translator))));
    service.calls.single.result.complete(source); await tester.pump();
    await settings.select(AppLanguage.et); await tester.pump();
    service.calls.last.result.complete(source); await tester.pumpAndSettle();
    translator.calls.single.result.complete(translated); await tester.pumpAndSettle();
    expect(find.text('Открыт в 1928 году.'), findsNothing);
    expect(find.text('Avatud 1928. aastal.'), findsOneWidget);
    await settings.select(AppLanguage.ru); await tester.pump();
    service.calls.last.result.complete(source); await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    translator.calls.last.result.complete(translated); await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets('Opening a place loads history automatically and ignores an older language response', (tester) async {
    final settings = LanguageSettings();
    addTearDown(settings.dispose);
    final service = DeferredDetailsService();
    await tester.pumpWidget(LanguageScope(settings: settings, child: MaterialApp(
      home: PlaceDetailsScreen(place: routePlaces.first, demo: false, service: service))));
    expect(service.calls.single.language, 'ru');
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await settings.select(AppLanguage.et);
    await tester.pump();
    expect(service.calls.last.language, 'et');
    service.calls.last.result.complete(const PlaceDetails(description: 'Koha kirjeldus.',
      sections: [PlaceArticleSection('Ajalugu', 'Ehitatud 1890. aastal.')]));
    await tester.pumpAndSettle();
    expect(find.text('Koha kirjeldus.'), findsOneWidget);
    expect(find.text('Ehitatud 1890. aastal.'), findsOneWidget);
    service.calls.first.result.complete(const PlaceDetails(description: 'Устаревший ответ.'));
    await tester.pumpAndSettle();
    expect(find.text('Устаревший ответ.'), findsNothing);
    expect(find.text('Koha kirjeldus.'), findsOneWidget);
    expect(service.calls.length, 2); expect(tester.takeException(), isNull);
  });
  testWidgets('Failed automatic loading offers retry and then shows an honest empty state', (tester) async {
    final service = DeferredDetailsService();
    await tester.pumpWidget(MaterialApp(home: PlaceDetailsScreen(
      place: routePlaces.first, demo: false, service: service)));
    service.calls.single.result.completeError(StateError('Offline'));
    await tester.pumpAndSettle();
    final retry = find.byKey(const ValueKey('retry-place-details'));
    expect(retry, findsOneWidget);
    await tester.ensureVisible(retry);
    await tester.tap(retry);
    await tester.pump();
    expect(service.calls.length, 2);
    service.calls.last.result.complete(const PlaceDetails());
    await tester.pumpAndSettle();
    expect(find.text('Не удалось найти статью об этом месте в Wikipedia или связанных источниках.'), findsOneWidget);
    expect(retry, findsNothing); expect(tester.takeException(), isNull);
  });
  testWidgets('A late network response after closing the card does not update a disposed screen', (tester) async {
    final service = DeferredDetailsService();
    await tester.pumpWidget(MaterialApp(home: PlaceDetailsScreen(
      place: routePlaces.first, demo: false, service: service)));
    await tester.pumpWidget(const SizedBox.shrink());
    service.calls.single.result.complete(const PlaceDetails(description: 'Late response'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets('Fictional demo places do not load real photos or history', (tester) async {
    final service = DeferredDetailsService();
    await tester.pumpWidget(MaterialApp(home: PlaceDetailsScreen(
      place: routePlaces.first, demo: true, service: service)));
    await tester.pumpAndSettle();
    expect(service.calls, isEmpty); expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
