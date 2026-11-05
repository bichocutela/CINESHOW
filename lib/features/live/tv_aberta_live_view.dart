import 'package:flutter/material.dart';
import '../../core/services/tv_aberta.dart';
import '../../core/services/iptv_catalog.dart';
import '../player/presentation/source_page.dart';
import 'live_player_page.dart';

class TvAbertaLiveView extends StatefulWidget {
  const TvAbertaLiveView({super.key});
  @override
  State<TvAbertaLiveView> createState() => _TvAbertaLiveViewState();
}
class _TvAbertaLiveViewState extends State<TvAbertaLiveView> {
  final service = TvAbertaService();
  List<Map<String, dynamic>> channels = [];
  String query = '', category = '';
  String? error, opening;
  bool loading = true;
  @override
  void initState() { super.initState(); _initial(); }
  Future<void> _initial() async {
    try {
      final cached = await service.channels(cached: true);
      if (mounted) setState(() => channels = cached);
    } catch (_) { /* A corrupt cache does not stop refresh. */ }
    if (mounted) await _refresh();
  }
  Future<void> _refresh() async {
    setState(() { loading = true; error = null; });
    try {
      final rows = await service.channels();
      rows.sort((a, b) => '${a['name']}'.toLowerCase().compareTo('${b['name']}'.toLowerCase()));
      if (mounted) setState(() => channels = rows);
    } catch (_) {
      if (mounted) setState(() => error = channels.isEmpty ? 'A fonte não respondeu. Tente novamente.' : 'Exibindo a última lista salva.');
    } finally { if (mounted) setState(() => loading = false); }
  }
  Future<void> _open(Map<String, dynamic> row) async {
    if (opening != null) return;
    setState(() => opening = '${row['slug']}');
    try {
      final options = await service.streams(row);
      if (!mounted) return;
      final native = options.where((v) => v['native'] == true).toList();
      if (native.isNotEmpty) {
        final channel = TvChannel('tvaberta:${row['slug']}', '${row['name']}', 'BR',
            ['${row['category'] ?? ''}'], row['logo'] as String?, native);
        await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => LivePlayerPage(channel: channel)));
      } else if (options.isNotEmpty) {
        await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => SourcePage(title: '${row['name']}',
          url: options.first['url'] as String, headers: {'Referer': options.first['referrer'] as String}, embedded: true)));
      } else { throw StateError('Sem servidor disponível'); }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Este canal não entregou uma transmissão disponível. Tente outro canal ou atualize a lista.')));
    } finally { if (mounted) setState(() => opening = null); }
  }
  @override
  Widget build(BuildContext context) {
    final categories = channels.map((v) => '${v['category'] ?? ''}').where((v) => v.isNotEmpty).toSet().toList()..sort();
    final rows = channels.where((v) => (category.isEmpty || v['category'] == category) && '${v['name']}'.toLowerCase().contains(query.toLowerCase())).toList();
    return RefreshIndicator(onRefresh: _refresh, child: ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), physics: const AlwaysScrollableScrollPhysics(),
      itemCount: rows.length + 1, itemBuilder: (context, index) {
        if (index == 0) return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Canais · TV Aberta Online', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          TextField(onChanged: (v) => setState(() => query = v), decoration: const InputDecoration(
            border: OutlineInputBorder(), prefixIcon: Icon(Icons.search), hintText: 'Buscar canal')),
          DropdownButton<String>(isExpanded: true, value: category, items: [
            const DropdownMenuItem(value: '', child: Text('Todas as categorias')),
            for (final c in {...categories, if (category.isNotEmpty) category}) DropdownMenuItem(value: c, child: Text(c))
          ], onChanged: (v) => setState(() => category = v ?? '')),
          if (loading) const LinearProgressIndicator(),
          if (error != null) Text(error!),
          OutlinedButton.icon(onPressed: loading ? null : _refresh, icon: const Icon(Icons.refresh), label: const Text('Atualizar lista')),
          Text('${rows.length} canais'),
          if (!loading && rows.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('Nenhum canal com estes filtros.'))
        ]);
        final row = rows[index - 1];
        return Card(child: ListTile(title: Text('${row['name']}'), subtitle: Text('${row['category'] ?? ''}'),
          leading: SizedBox(width: 48, height: 48, child: Image.network('${row['logo'] ?? ''}', fit: BoxFit.contain,
            errorBuilder: (_, e, stack) => const Icon(Icons.live_tv))),
          trailing: opening == '${row['slug']}' ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator()) : const Icon(Icons.play_circle_outline),
          onTap: opening == null ? () => _open(row) : null));
      }));
  }
}
