import 'dart:async';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'language_settings.dart';
import 'web_navigation.dart';

class PlaceWebScreen extends StatefulWidget {
  const PlaceWebScreen({super.key, required this.uri});
  final Uri uri;

  @override
  State<PlaceWebScreen> createState() => _PlaceWebScreenState();
}

class _PlaceWebScreenState extends State<PlaceWebScreen> {
  WebViewController? _controller;
  final _fallbacks = IntentFallbacks();
  late Uri _lastPage;
  String? _defaultAgent;
  bool _ready = false, _error = false, _canGoBack = false;
  int _progress = 0;

  @override
  void initState() {
    super.initState();
    _lastPage = webPageUri(widget.uri);
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      final controller = WebViewController();
      _controller = controller;
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      _defaultAgent = await controller.getUserAgent();
      await controller.setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: _navigate,
        onProgress: (value) {
          if (mounted) setState(() => _progress = value);
        },
        onPageStarted: (url) {
          final uri = Uri.tryParse(url);
          if (mounted) {
            setState(() {
              _error = false;
              _progress = 0;
              if (uri != null && isWebPage(uri)) _lastPage = uri;
            });
          }
        },
        onPageFinished: (_) {
          if (mounted) setState(() => _progress = 100);
          unawaited(_refreshHistory());
        },
        onWebResourceError: (error) {
          if (error.isForMainFrame == true) _showError();
        },
      ));
      if (!mounted) return;
      setState(() => _ready = true);
      await _load(_lastPage);
    } catch (_) {
      _showError();
    }
  }

  NavigationDecision _navigate(NavigationRequest request) {
    final uri = Uri.tryParse(request.url);
    if (uri != null && isWebPage(uri)) return NavigationDecision.navigate;
    if (!request.isMainFrame) {
      return request.url == 'about:blank'
          ? NavigationDecision.navigate : NavigationDecision.prevent;
    }
    final fallback = _fallbacks.next(request.url);
    if (fallback != null) {
      // Cancel the intent first, then load the web page outside the callback.
      unawaited(Future<void>(() async {
        if (mounted) await _load(fallback);
      }));
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'webLinkUnavailable'))));
    }
    return NavigationDecision.prevent;
  }

  Future<void> _load(Uri uri) async {
    if (!mounted || !isWebPage(uri)) return;
    try {
      final controller = _controller!;
      final page = webPageUri(uri);
      await controller.setUserAgent(
        isGoogleMapsPage(page) ? desktopMapsUserAgent(_defaultAgent) : _defaultAgent);
      if (!mounted) return;
      setState(() {
        _lastPage = page;
        _error = false;
        _progress = 0;
      });
      await controller.loadRequest(page);
    } catch (_) {
      _showError();
    }
  }

  void _showError() {
    if (mounted) setState(() { _error = true; _progress = 100; });
  }

  Future<void> _refreshHistory() async {
    try {
      final canGoBack = await _controller?.canGoBack() ?? false;
      if (mounted) setState(() => _canGoBack = canGoBack);
    } catch (_) {
      if (mounted) setState(() => _canGoBack = false);
    }
  }

  Future<void> _back() async {
    try {
      if (await _controller?.canGoBack() ?? false) {
        await _controller!.goBack();
        await _refreshHistory();
        return;
      }
    } catch (_) {
      // A broken WebView must still let the user return to the place card.
    }
    if (mounted) Navigator.of(context).pop();
  }

  void _retry() {
    _fallbacks.reset();
    unawaited(_ready ? _load(_lastPage) : _initialize());
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_canGoBack,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) unawaited(_back());
    },
    child: Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: _back),
        title: Text(_lastPage.host),
        actions: [
          IconButton(onPressed: _retry, tooltip: tr(context, 'retryPage'),
            icon: const Icon(Icons.refresh)),
          IconButton(onPressed: () => Navigator.of(context).pop(),
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            icon: const Icon(Icons.close)),
        ]),
      body: Column(children: [
        if (_progress < 100 && !_error)
          LinearProgressIndicator(value: _progress / 100),
        Expanded(child: _error
          ? Center(child: Padding(padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(tr(context, 'inAppLinkError'), textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(onPressed: _retry, child: Text(tr(context, 'retryPage'))),
              ])))
          : _ready
            ? WebViewWidget(controller: _controller!)
            : const SizedBox.shrink()),
      ]),
    ),
  );
}
