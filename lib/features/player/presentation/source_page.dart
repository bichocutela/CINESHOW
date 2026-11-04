import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Keeps the provider's original page and player inside the app.
class SourcePage extends StatefulWidget {
  const SourcePage({super.key, required this.title, required this.url});
  final String title, url;
  @override
  State<SourcePage> createState() => _SourcePageState();
}

class _SourcePageState extends State<SourcePage> {
  late final WebViewController controller;
  int progress = 0;
  bool failed = false;
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
          onPageStarted: (_) {
            if (mounted) setState(() => failed = false);
          },
          onWebResourceError: (e) {
            if (mounted && e.isForMainFrame == true) {
              setState(() => failed = true);
            }
          },
          onNavigationRequest: (r) {
            final uri = Uri.tryParse(r.url);
            return uri != null && ['http', 'https'].contains(uri.scheme)
                ? NavigationDecision.navigate
                : NavigationDecision.prevent;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  Future<void> _back() async {
    if (await controller.canGoBack()) {
      await controller.goBack();
    } else if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Voltar',
            onPressed: _back,
            icon: const Icon(Icons.arrow_back),
          ),
          title: Text(widget.title),
          actions: [
            IconButton(
              tooltip: 'Recarregar',
              onPressed: () => controller.reload(),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: Column(
          children: [
            if (progress < 100 && !failed)
              LinearProgressIndicator(value: progress / 100),
            if (failed)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    const Text(
                      'A fonte não carregou. Tente novamente ou abra na fonte pela tela de detalhes.',
                    ),
                    TextButton(
                      onPressed: () => controller.reload(),
                      child: const Text('Tentar novamente'),
                    ),
                  ],
                ),
              ),
            Expanded(child: WebViewWidget(controller: controller)),
          ],
        ),
      );
}
