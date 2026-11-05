import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/models/media_item.dart';
import '../../core/services/media_downloads.dart';

Future<void> downloadMedia(BuildContext context, MediaItem item) async {
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(const SnackBar(content: Text('Verificando o arquivo para download...')));
  try {
    await MediaDownloads.instance.start(item);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(const SnackBar(
        content: Text('Download enviado ao Android. Acompanhe em Sobre → Meus downloads.')));
  } catch (error) {
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(error is StateError
        ? error.message.toString() : 'Não foi possível iniciar o download.')));
  }
}

class DownloadsPage extends StatefulWidget {
  const DownloadsPage({super.key});
  @override
  State<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends State<DownloadsPage>
    with WidgetsBindingObserver {
  List<Map<String, dynamic>> items = [];
  Timer? timer;
  bool polling = false, foreground = true;
  String? error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    timer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (foreground) _load();
    });
  }

  Future<void> _load() async {
    if (polling) return;
    polling = true;
    try {
      final next = await MediaDownloads.instance.list();
      if (mounted) setState(() { items = next; error = null; });
    } catch (_) {
      if (mounted) setState(() => error = 'Não foi possível consultar os downloads.');
    } finally {
      polling = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (foreground) _load();
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _remove(int id) async {
    final confirmed = await showDialog<bool>(context: context, builder: (context) =>
      AlertDialog(title: const Text('Excluir download?'),
        content: const Text('O arquivo será removido deste aparelho.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Voltar')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Excluir'))
        ]));
    if (confirmed != true) return;
    await MediaDownloads.instance.remove(id);
    await _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Meus downloads')),
      body: SafeArea(child: RefreshIndicator(onRefresh: _load,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          const Text('Os downloads continuam pelo Android após sair desta tela. Links temporários podem expirar antes da conclusão.'),
          if (error != null) Text(error!),
          if (items.isEmpty) const Padding(padding: EdgeInsets.all(24),
              child: Text('Nenhum download por aqui. Use Baixar no filme ou capítulo.')),
          for (final item in items) ListTile(
            title: Text(item['title'] as String),
            subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(switch (item['state']) {
                'ready' => 'Concluído · disponível offline',
                'failed' => 'Falhou · tente iniciar novamente na fonte',
                'paused' => 'Aguardando conexão ou espaço',
                _ => 'Baixando...'
              }),
              if (item['state'] == 'downloading' || item['state'] == 'paused')
                LinearProgressIndicator(value: (item['total'] as num) > 0
                    ? ((item['bytes'] as num) / (item['total'] as num)).clamp(0.0, 1.0).toDouble()
                    : null)
            ]),
            onTap: item['state'] == 'ready' ? () async {
              try { await MediaDownloads.instance.open((item['id'] as num).toInt()); }
              catch (_) { if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Não foi possível abrir o arquivo.')));
              }}
            } : null,
            trailing: IconButton(tooltip: 'Excluir download', icon: const Icon(Icons.delete_outline),
                onPressed: () => _remove((item['id'] as num).toInt())))
        ]))));
}
