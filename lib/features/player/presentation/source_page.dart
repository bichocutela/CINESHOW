import 'dart:async';
import '../../../core/services/source_navigation.dart';
import '../../../core/services/player_migrations.dart';
import '../../../core/services/provider_embed.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Keeps the provider's original page and player inside the app.
class SourcePage extends StatefulWidget {
  const SourcePage(
      {super.key,
      required this.title,
      required this.url,
      this.headers = const {},
      this.embedded = false,
      this.onNext});
  final String title, url;
  final Map<String, String> headers;
  final bool embedded;
  final Future<void> Function()? onNext;
  @override
  State<SourcePage> createState() => _SourcePageState();
}

class _SourcePageState extends State<SourcePage> {
  String get playerUrl => canonicalPlayerUrl(widget.url);
  late final WebViewController controller;
  late final navigation = SourceNavigationPolicy(widget.embedded
      ? providerEmbedBase(playerUrl, widget.headers)
      : playerUrl);
  int progress = 0;
  bool failed = false;
  bool advancing = false;
  Widget? fullscreenView;
  VoidCallback? hideFullscreen;
  @override
  void initState() {
    super.initState();
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (v) {
            if (mounted) setState(() => progress = v);
          },
          onPageStarted: (url) {
            if (widget.embedded && url == 'about:blank') return;
            if (!navigation.allows(url, isMainFrame: true)) {
              unawaited(controller
                  .runJavaScript('window.stop();')
                  .catchError((Object _) {}));
              if (mounted) setState(() => failed = true);
              return;
            }
            if (mounted) setState(() => failed = false);
          },
          onWebResourceError: (e) {
            if (mounted && e.isForMainFrame == true) {
              setState(() => failed = true);
            }
          },
          onNavigationRequest: (r) {
            return navigation.allows(r.url, isMainFrame: r.isMainFrame)
                ? NavigationDecision.navigate
                : NavigationDecision.prevent;
          },
        ),
      );
    unawaited(_configure());
  }

  Future<void> _configure() async {
    try {
      final android = controller.platform;
      if (android is AndroidWebViewController) {
        final cookies = WebViewCookieManager().platform;
        if (cookies is AndroidWebViewCookieManager) {
          await cookies.setAcceptThirdPartyCookies(android, true);
        }
        await android.setCustomWidgetCallbacks(
            onShowCustomWidget: (view, onHidden) {
          if (!mounted) {
            onHidden();
            return;
          }
          setState(() {
            fullscreenView = view;
            hideFullscreen = onHidden;
          });
          unawaited(SystemChrome.setEnabledSystemUIMode(
              SystemUiMode.immersiveSticky));
        }, onHideCustomWidget: () {
          if (mounted) {
            setState(() {
              fullscreenView = null;
              hideFullscreen = null;
            });
          }
          unawaited(
              SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
        });
      }
      if (mounted) await _retry();
    } catch (_) {
      if (mounted) setState(() => failed = true);
    }
  }

  Future<void> _retry() async {
    if (!mounted) return;
    setState(() {
      failed = false;
      progress = 0;
    });
    if (widget.embedded) {
      await controller.loadHtmlString(providerEmbedHtml(playerUrl),
          baseUrl: providerEmbedBase(playerUrl, widget.headers));
    } else {
      await controller.loadRequest(Uri.parse(navigation.retryUrl),
          headers: widget.headers);
    }
  }

  Future<void> _next() async {
    if (advancing || widget.onNext == null) return;
    setState(() => advancing = true);
    try {
      await widget.onNext!();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Não foi possível abrir o próximo capítulo.')));
      }
    } finally {
      if (mounted) setState(() => advancing = false);
    }
  }

  Future<void> _external() async {
    try {
      await launchUrl(Uri.parse(playerUrl),
          mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Não foi possível abrir a fonte.')));
      }
    }
  }

  @override
  void dispose() {
    hideFullscreen?.call();
    if (fullscreenView != null) {
      unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    }
    super.dispose();
  }

  Future<void> _back() async {
    if (await controller.canGoBack()) {
      await controller.goBack();
    } else if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: fullscreenView == null,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) hideFullscreen?.call();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: fullscreenView != null
            ? null
            : AppBar(
                leading: IconButton(
                  tooltip: 'Voltar',
                  onPressed: _back,
                  icon: const Icon(Icons.arrow_back),
                ),
                title: Text(widget.title),
                actions: [
                  if (widget.onNext != null)
                    IconButton(
                        tooltip: 'Próximo capítulo',
                        onPressed: advancing ? null : _next,
                        icon: const Icon(Icons.skip_next)),
                  IconButton(
                      tooltip: 'Abrir na fonte',
                      onPressed: _external,
                      icon: const Icon(Icons.open_in_new)),
                  IconButton(
                    tooltip: 'Recarregar',
                    onPressed: _retry,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
        body: SafeArea(
          top: fullscreenView != null,
          maintainBottomViewPadding: true,
          child: fullscreenView ??
              Column(
                children: [
                  if (progress < 100 && !failed)
                    LinearProgressIndicator(value: progress / 100),
                  if (failed)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          const Text(
                            'Não foi possível carregar a página do filme. Tente novamente ou escolha outra fonte nos detalhes.',
                          ),
                          TextButton(
                            onPressed: _retry,
                            child: const Text('Tentar novamente'),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                      child: failed
                          ? const SizedBox.shrink()
                          : WebViewWidget(controller: controller)),
                ],
              ),
        ),
      ));
}
