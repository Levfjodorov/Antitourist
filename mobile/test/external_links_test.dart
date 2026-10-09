import 'dart:async';
import 'package:antitourist/external_links.dart';
import 'package:antitourist/place_web_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart' as platform;
import 'web_navigation_test.dart' show kukkurIntent;

class RecordingUrlLauncher extends UrlLauncherPlatform {
  @override
  Null get linkDelegate => null;
  final launches = <({String url, LaunchOptions options})>[];
  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launches.add((url: url, options: options));
    return true;
  }
}

class RecordingWebView extends platform.WebViewPlatform {
  RecordingController? controller;
  bool unavailable = false;
  @override
  platform.PlatformWebViewController createPlatformWebViewController(
      platform.PlatformWebViewControllerCreationParams params) {
    if (unavailable) throw StateError('WebView is unavailable');
    return controller = RecordingController(params);
  }
  @override
  platform.PlatformNavigationDelegate createPlatformNavigationDelegate(
      platform.PlatformNavigationDelegateCreationParams params) => RecordingDelegate(params);
  @override
  platform.PlatformWebViewWidget createPlatformWebViewWidget(
      platform.PlatformWebViewWidgetCreationParams params) => RecordingWidget(params);
}

class RecordingWidget extends platform.PlatformWebViewWidget {
  RecordingWidget(super.params) : super.implementation();
  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

class RecordingController extends platform.PlatformWebViewController {
  RecordingController(super.params) : super.implementation();
  final loads = <Uri>[];
  RecordingDelegate? delegate;
  JavaScriptMode? javascript;
  String? agent;
  bool history = false;
  int backCount = 0;
  @override
  Future<void> setJavaScriptMode(JavaScriptMode value) async { javascript = value; }
  @override
  Future<String?> getUserAgent() async => 'Mozilla/5.0 (Linux; Android 15; wv) '
      'AppleWebKit/537.36 Version/4.0 Chrome/154.0.0.0 Mobile Safari/537.36';
  @override
  Future<void> setUserAgent(String? value) async { agent = value; }
  @override
  Future<void> setPlatformNavigationDelegate(platform.PlatformNavigationDelegate value) async {
    delegate = value as RecordingDelegate;
  }
  @override
  Future<void> loadRequest(platform.LoadRequestParams params) async {
    loads.add(params.uri);
    delegate?.started?.call(params.uri.toString());
    delegate?.finished?.call(params.uri.toString());
  }
  @override
  Future<bool> canGoBack() async => history;
  @override
  Future<void> goBack() async { backCount++; history = false; }
}

class RecordingDelegate extends platform.PlatformNavigationDelegate {
  RecordingDelegate(super.params) : super.implementation();
  platform.NavigationRequestCallback? navigate;
  platform.PageEventCallback? started, finished;
  platform.WebResourceErrorCallback? error;
  @override
  Future<void> setOnNavigationRequest(platform.NavigationRequestCallback value) async {
    navigate = value;
  }
  @override
  Future<void> setOnPageStarted(platform.PageEventCallback value) async { started = value; }
  @override
  Future<void> setOnPageFinished(platform.PageEventCallback value) async { finished = value; }
  @override
  Future<void> setOnProgress(platform.ProgressCallback value) async {}
  @override
  Future<void> setOnWebResourceError(platform.WebResourceErrorCallback value) async { error = value; }
}

void main() {
  late UrlLauncherPlatform previousLauncher;
  platform.WebViewPlatform? previousWebView;
  late RecordingUrlLauncher launcher;
  late RecordingWebView web;
  setUp(() {
    previousLauncher = UrlLauncherPlatform.instance;
    previousWebView = platform.WebViewPlatform.instance;
    launcher = RecordingUrlLauncher();
    web = RecordingWebView();
    UrlLauncherPlatform.instance = launcher;
    platform.WebViewPlatform.instance = web;
  });
  tearDown(() {
    UrlLauncherPlatform.instance = previousLauncher;
    platform.WebViewPlatform.instance = previousWebView ?? (RecordingWebView()..unavailable = true);
  });

  Future<BuildContext> page(WidgetTester tester) async {
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (value) {
      context = value;
      return const SizedBox();
    }))));
    return context;
  }

  Future<RecordingController> openPage(WidgetTester tester, String url) async {
    final context = await page(tester);
    unawaited(openInApp(context, Uri.parse(url)));
    await tester.pumpAndSettle();
    return web.controller!;
  }

  testWidgets('Place pages use the owned WebView without an external launch', (tester) async {
    final context = await page(tester);
    for (final url in ['https://www.google.com/maps/search/?api=1&query=Tallinn',
      'https://ru.wikipedia.org/wiki/Tallinn', 'https://commons.wikimedia.org/wiki/File:Place.jpg']) {
      unawaited(openInApp(context, Uri.parse(url)));
      await tester.pumpAndSettle();
      expect(find.byType(PlaceWebScreen), findsOneWidget);
      expect(web.controller!.javascript, JavaScriptMode.unrestricted);
      expect(web.controller!.loads.single, Uri.parse(url));
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
    }
    expect(launcher.launches, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Unsafe initial URLs never create a view or open another app', (tester) async {
    final context = await page(tester);
    for (final url in ['http://example.com', 'https://name:secret@example.com',
      'intent://maps', 'https:']) {
      await openInApp(context, Uri.parse(url));
    }
    await tester.pump();
    expect(find.byType(PlaceWebScreen), findsNothing);
    expect(web.controller, isNull);
    expect(launcher.launches, isEmpty);
    expect(find.text('Не удалось открыть страницу внутри приложения. Попробуй ещё раз.'), findsOneWidget);
  });

  testWidgets('Unavailable WebViews show an error and can return to the app', (tester) async {
    web.unavailable = true;
    final context = await page(tester);
    unawaited(openInApp(context, Uri.parse('https://example.com')));
    await tester.pumpAndSettle();
    expect(find.text('Не удалось открыть страницу внутри приложения. Попробуй ещё раз.'), findsOneWidget);
    expect(launcher.launches, isEmpty);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.byType(PlaceWebScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('The reported Maps intent loads its HTTPS fallback inside the app', (tester) async {
    final controller = await openPage(tester,
        'https://www.google.com/maps/search/?api=1&query=Kukkur%2C+59.405555%2C24.705426');
    final decision = await controller.delegate!.navigate!(
      const NavigationRequest(url: kukkurIntent, isMainFrame: true));
    expect(decision, NavigationDecision.prevent);
    await tester.pumpAndSettle();
    expect(controller.loads.length, 2);
    expect(controller.loads.last.queryParameters['query'], 'Kukkur, 59.405555,24.705426');
    expect(controller.loads.every((uri) => uri.scheme == 'https'), isTrue);
    expect(controller.agent, isNot(contains('Android')));
    expect(launcher.launches, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Repeated intents, unsafe redirects and subframes never loop or launch apps', (tester) async {
    final controller = await openPage(tester, 'https://www.google.com/maps/search/?api=1&query=Kukkur');
    final navigate = controller.delegate!.navigate!;
    await navigate(const NavigationRequest(url: kukkurIntent, isMainFrame: true));
    await tester.pumpAndSettle();
    final count = controller.loads.length;
    for (final request in [
      const NavigationRequest(url: kukkurIntent, isMainFrame: true),
      const NavigationRequest(url: kukkurIntent, isMainFrame: false),
      const NavigationRequest(url: 'javascript:alert(1)', isMainFrame: true),
      const NavigationRequest(url: 'intent://maps/#Intent;S.browser_fallback_url=file%3A%2F%2F%2Fetc%2Fpasswd;end;', isMainFrame: true),
    ]) {
      expect(await navigate(request), NavigationDecision.prevent);
    }
    await tester.pumpAndSettle();
    expect(controller.loads.length, count);
    expect(launcher.launches, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Only main-page failures show retry; back restores the place card', (tester) async {
    final controller = await openPage(tester, 'https://ru.wikipedia.org/wiki/Tallinn');
    controller.delegate!.error!(const WebResourceError(errorCode: -2,
      description: 'Image failed', isForMainFrame: false));
    await tester.pump();
    expect(find.text('Не удалось открыть страницу внутри приложения. Попробуй ещё раз.'), findsNothing);
    controller.delegate!.error!(const WebResourceError(errorCode: -2,
      description: 'Page failed', isForMainFrame: true));
    await tester.pump();
    expect(find.text('Не удалось открыть страницу внутри приложения. Попробуй ещё раз.'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Повторить загрузку'));
    await tester.pumpAndSettle();
    expect(controller.loads.length, 2);
    controller.history = true;
    controller.delegate!.finished!('https://ru.wikipedia.org/wiki/Tallinn');
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(controller.backCount, 1);
    expect(find.byType(PlaceWebScreen), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(PlaceWebScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Explicit external navigation still uses the external application mode', (tester) async {
    final context = await page(tester);
    await openExternal(context, Uri.parse('https://www.google.com/maps/dir/?api=1&destination=Tallinn'));
    expect(launcher.launches.single.options.mode, PreferredLaunchMode.externalApplication);
    expect(find.byType(PlaceWebScreen), findsNothing);
  });
}
