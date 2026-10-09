import 'dart:async';
import 'package:antitourist/language_settings.dart';
import 'package:antitourist/place_details_screen.dart';
import 'package:antitourist/place_details_service.dart';
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

void main() {
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
    expect(find.text('История этого места пока отсутствует в связанных источниках.'), findsOneWidget);
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
