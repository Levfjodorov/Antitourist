import 'package:antitourist/external_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

class RecordingUrlLauncher extends UrlLauncherPlatform {
  bool supported = true;
  bool succeeds = true;
  final launches = <({String url, LaunchOptions options})>[];

  @override
  Future<bool> supportsMode(PreferredLaunchMode mode) async => supported;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launches.add((url: url, options: options));
    return succeeds;
  }
}

void main() {
  late UrlLauncherPlatform previous;
  late RecordingUrlLauncher launcher;
  setUp(() {
    previous = UrlLauncherPlatform.instance;
    launcher = RecordingUrlLauncher();
    UrlLauncherPlatform.instance = launcher;
  });
  tearDown(() => UrlLauncherPlatform.instance = previous);

  Future<BuildContext> page(WidgetTester tester) async {
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (value) {
      context = value;
      return const SizedBox();
    }))));
    return context;
  }

  testWidgets('Place pages use the embedded view with JavaScript and storage', (tester) async {
    final context = await page(tester);
    for (final url in ['https://www.google.com/maps/search/?api=1&query=Tallinn',
      'https://ru.wikipedia.org/wiki/Tallinn', 'https://commons.wikimedia.org/wiki/File:Place.jpg']) {
      await openInApp(context, Uri.parse(url));
    }
    expect(launcher.launches.length, 3);
    for (final call in launcher.launches) {
      expect(call.options.mode, PreferredLaunchMode.inAppWebView);
      expect(call.options.webViewConfiguration.enableJavaScript, isTrue);
      expect(call.options.webViewConfiguration.enableDomStorage, isTrue);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('Unsupported embedded views and unsafe links never open another app', (tester) async {
    final context = await page(tester);
    for (final url in ['http://example.com', 'https://name:secret@example.com',
      'intent://maps', 'https:']) {
      await openInApp(context, Uri.parse(url));
    }
    launcher.supported = false;
    await openInApp(context, Uri.parse('https://example.com'));
    await tester.pump();
    expect(launcher.launches, isEmpty);
    expect(find.text('Не удалось открыть страницу внутри приложения. Попробуй ещё раз.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('A failed page launch shows an error without external fallback', (tester) async {
    final context = await page(tester);
    launcher.succeeds = false;
    await openInApp(context, Uri.parse('https://example.com'));
    await tester.pump();
    expect(launcher.launches.single.options.mode, PreferredLaunchMode.inAppWebView);
    expect(find.text('Не удалось открыть страницу внутри приложения. Попробуй ещё раз.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
