import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:antitourist/language_settings.dart';
import 'package:antitourist/place_details_screen.dart';
import 'package:antitourist/place_details_service.dart';
import 'package:antitourist/place_photo_screen.dart';
import 'package:antitourist/places.dart';
import 'package:antitourist/strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'route_fixtures.dart';
import 'test_helpers.dart';

final tinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=');

class ImageHttpClient implements HttpClient {
  int requests = 0;
  bool fail = false;
  @override
  set autoUncompress(bool value) {}
  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    requests++;
    return ImageRequest(fail);
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class ImageRequest implements HttpClientRequest {
  ImageRequest(this.fail);
  final bool fail;
  @override
  HttpHeaders get headers => ImageHeaders();
  @override
  Future<HttpClientResponse> close() async => ImageResponse(fail);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class ImageHeaders implements HttpHeaders {
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class ImageResponse extends Stream<List<int>> implements HttpClientResponse {
  ImageResponse(this.fail);
  final bool fail;
  @override
  int get statusCode => fail ? 503 : 200;
  @override
  int get contentLength => tinyPng.length;
  @override
  HttpClientResponseCompressionState get compressionState => HttpClientResponseCompressionState.notCompressed;
  @override
  StreamSubscription<List<int>> listen(void Function(List<int>)? onData,
      {Function? onError, void Function()? onDone, bool? cancelOnError}) =>
    Stream<List<int>>.value(tinyPng).listen(onData, onError: onError,
      onDone: onDone, cancelOnError: cancelOnError);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final gallery = [for (var index = 0; index < 3; index++) PlacePhoto(
  url: Uri.parse('https://upload.wikimedia.org/photo-$index.png'),
  source: Uri.parse('https://commons.wikimedia.org/wiki/File:Photo-$index.png'),
  credit: 'Author $index', license: 'CC BY-SA 4.0', caption: 'Caption $index',
  nearbyMeters: index * 20.0)];

class GalleryDetailsService extends PlaceDetailsService {
  @override
  Future<PlaceDetails> load(Place place, String language) async => PlaceDetails(
    description: 'The place description.', nearbyPhotos: gallery);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ImageHttpClient client;
  setUp(() {
    client = ImageHttpClient();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });
  tearDown(() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  void photoTest(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      final previous = debugNetworkImageHttpClientProvider;
      debugNetworkImageHttpClientProvider = () => client;
      try {
        await body(tester);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        debugNetworkImageHttpClientProvider = previous;
      }
    });
  }

  photoTest('Gallery starts at the selected photo, pages and resets zoom', (tester) async {
    await tester.pumpWidget(MaterialApp(home: PlacePhotoScreen(
      photos: gallery, placeName: 'Test place', initialIndex: 1)));
    await tester.pumpAndSettle();
    expect(find.text('Фото 2 из 3'), findsOneWidget);
    expect(find.text('Author 1'), findsOneWidget);
    final viewer = tester.widget<InteractiveViewer>(find.byType(InteractiveViewer).hitTestable().first);
    viewer.transformationController!.value = Matrix4.diagonal3Values(2, 2, 1);
    await tester.pump();
    await tester.tap(find.byTooltip('Сбросить масштаб'));
    await tester.pump();
    expect(viewer.transformationController!.value.getMaxScaleOnAxis(), 1);
    await tester.tap(find.byTooltip('Следующее фото'));
    await tester.pumpAndSettle();
    expect(find.text('Фото 3 из 3'), findsOneWidget);
    expect(find.text('Author 2'), findsOneWidget);
    final next = find.byWidgetPredicate((widget) =>
      widget is IconButton && widget.tooltip == 'Следующее фото');
    expect(tester.widget<IconButton>(next).onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  photoTest('An image can be retried after the network recovers', (tester) async {
    client.fail = true;
    await tester.pumpWidget(MaterialApp(home: PlacePhotoScreen(
      photos: [gallery.first], placeName: 'Test place')));
    await tester.pumpAndSettle();
    expect(find.text('Загрузить фото ещё раз'), findsOneWidget);
    final before = client.requests;
    client.fail = false;
    await tester.tap(find.text('Загрузить фото ещё раз'));
    await tester.pumpAndSettle();
    expect(client.requests, greaterThan(before));
    expect(find.text('Загрузить фото ещё раз'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  photoTest('Photos remain usable in landscape with large text and language changes', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(640, 360);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final settings = LanguageSettings();
    addTearDown(settings.dispose);
    await tester.pumpWidget(LanguageScope(settings: settings, child: MaterialApp(
      builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(
        textScaler: const TextScaler.linear(2)), child: child!),
      home: PlacePhotoScreen(photos: gallery, placeName: 'A long place name'))));
    await tester.pumpAndSettle();
    await settings.select(AppLanguage.et);
    await tester.pumpAndSettle();
    expect(find.text('Foto 1/3'), findsOneWidget);
    await settings.select(AppLanguage.en);
    await tester.pumpAndSettle();
    expect(find.text('Photo 1 of 3'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  photoTest('Place details open the selected nearby photo and return to the same place', (tester) async {
    final service = GalleryDetailsService();
    await tester.pumpWidget(MaterialApp(home: PlaceDetailsScreen(
      place: routePlaces.first, demo: false, service: service)));
    await tapVisibleControl(tester, 'Загрузить сведения и фото');
    final button = find.byKey(ValueKey('open-photo:${gallery[1].source}'));
    await tester.scrollUntilVisible(button, 200);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.byType(PlacePhotoScreen), findsOneWidget);
    expect(find.text('Фото 2 из 3'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(PlaceDetailsScreen), findsOneWidget);
    expect(find.byType(PlacePhotoScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
