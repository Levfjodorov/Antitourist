import 'package:antitourist/web_navigation.dart';
import 'package:flutter_test/flutter_test.dart';

const kukkurIntent = 'intent://www.google.com/maps/search/?api=1&query=Kukkur%2C+59.405555%2C24.705426&entry=ml&utm_campaign=ml-ardl-wv&coh=230964'
    '#Intent;scheme=https;package=com.google.android.apps.maps;'
    'S.browser_fallback_url=https%3A%2F%2Fwww.google.com%2Fmaps%2Fsearch%2F%3Fapi%3D1%26query%3DKukkur%252C%2B59.405555%252C24.705426%26entry%3Dml%26utm_campaign%3Dml-ardl-wv%26coh%3D230964;end;';

void main() {
  test('The reported Kukkur intent preserves the place and coordinates', () {
    final page = intentWebFallback(kukkurIntent)!;
    expect(page.scheme, 'https');
    expect(page.host, 'www.google.com');
    expect(page.queryParameters, {
      'api': '1', 'query': 'Kukkur, 59.405555,24.705426',
    });
  });

  test('Missing, malformed and unsafe browser fallbacks are rejected', () {
    for (final target in ['http://example.com', 'javascript:alert(1)',
      'file:///etc/passwd', 'https://user:password@example.com',
      'intent://maps', '//example.com', 'https:']) {
      final link = 'intent://maps/#Intent;S.browser_fallback_url=${Uri.encodeComponent(target)};end;';
      expect(intentWebFallback(link), isNull, reason: target);
    }
    for (final link in ['intent://maps/#Intent;end;',
      'intent://maps/#Intent;S.browser_fallback_url=%ZZ;end;',
      kukkurIntent.replaceFirst(';end;', ''),
      kukkurIntent.replaceFirst('intent://', 'https://'),
      kukkurIntent.replaceFirst(';end;', ';S.browser_fallback_url=https%3A%2F%2Fexample.com;end;')]) {
      expect(intentWebFallback(link), isNull);
    }
  });

  test('Repeated fallback URLs stop even when tracking parameters differ', () {
    final fallbacks = IntentFallbacks();
    expect(fallbacks.next(kukkurIntent), isNotNull);
    expect(fallbacks.next(kukkurIntent.replaceAll('230964', '999999')), isNull);
    fallbacks.reset();
    expect(fallbacks.next(kukkurIntent), isNotNull);
  });

  test('Only Google Maps uses a desktop agent with the actual browser version', () {
    const agent = 'Mozilla/5.0 (Linux; Android 15; Phone; wv) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Version/4.0 Chrome/154.0.1.2 Mobile Safari/537.36';
    final desktop = desktopMapsUserAgent(agent);
    expect(desktop, contains('Chrome/154.0.1.2'));
    expect(desktop, isNot(contains('Android')));
    expect(desktop, isNot(contains('Mobile')));
    expect(desktop, isNot(contains('Version/4.0')));
    expect(isGoogleMapsPage(Uri.parse('https://www.google.com/maps/search/?api=1')), isTrue);
    expect(isGoogleMapsPage(Uri.parse('https://www.google.com.evil.com/maps/search/')), isFalse);
    expect(isGoogleMapsPage(Uri.parse('https://www.google.com/search?q=test')), isFalse);
    expect(isGoogleMapsPage(Uri.parse('https://ru.wikipedia.org/wiki/Tallinn')), isFalse);
  });
}
