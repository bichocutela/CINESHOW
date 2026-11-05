import 'package:flutter/material.dart';
import '../../core/models/media_item.dart';
import '../../core/services/catalog_notices.dart';

class NoticesPage extends StatefulWidget {
  const NoticesPage({super.key, required this.onOpen});
  final ValueChanged<MediaItem> onOpen;
  @override
  State<NoticesPage> createState() => _NoticesPageState();
}

class _NoticesPageState extends State<NoticesPage> {
  List<Map<String, dynamic>> items = [];
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await CatalogNotices.instance.events();
    await CatalogNotices.instance.markRead();
    if (mounted) setState(() => items = rows);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Novidades')),
      body: SafeArea(
          child: ListView(children: [
        const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
                'As novidades são verificadas ao atualizar o catálogo e enquanto o app estiver aberto. Ative o sino nos detalhes para acompanhar capítulos.')),
        if (items.isEmpty)
          const Padding(
              padding: EdgeInsets.all(24),
              child: Text('Nenhuma novidade desde a última sincronização.')),
        for (final item in items)
          ListTile(
              leading: const Icon(Icons.notifications_outlined),
              title: Text(item['title'] as String),
              subtitle: Text(item['body'] as String),
              onTap: () {
                Navigator.pop(context);
                widget.onOpen(MediaItem.fromJson(
                    Map<String, dynamic>.from(item['item'] as Map)));
              })
      ])));
}
