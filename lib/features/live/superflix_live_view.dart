import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/services/superflix_catalog.dart';
import '../player/presentation/source_page.dart';

class SuperflixLiveView extends StatefulWidget {
  const SuperflixLiveView({super.key, this.events = false, this.service});
  final SuperflixService? service;
  final bool events;
  @override
  State<SuperflixLiveView> createState() => _SuperflixLiveViewState();
}

class _SuperflixLiveViewState extends State<SuperflixLiveView> {
  late final service = widget.service ?? SuperflixService();
  List<Map<String, dynamic>> items = [];
  String? updated;
  String query = '', category = '';
  String? error;
  bool loading = true, refreshing = false;
  String get key => 'cineshow.superflix.live.${widget.events}';
  @override
  void initState() {
    super.initState();
    _initial();
  }

  Future<void> _initial() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      var cached = ((jsonDecode(prefs.getString(key) ?? '[]')) as List)
          .map((v) => Map<String, dynamic>.from(v as Map))
          .toList();
      if (cached.isEmpty) cached = await service.cachedLive(events: widget.events);
      if (mounted) {
        setState(() {
          items = cached;
          loading = cached.isEmpty;
        });
      }
    } catch (_) {}
    if (mounted) await _refresh();
  }

  Future<void> _refresh() async {
    if (refreshing || !mounted) return;
    setState(() {
      refreshing = true;
      error = null;
    });
    try {
      final rows = await service.live(events: widget.events);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, jsonEncode(rows));
      if (mounted) setState(() {
        items = rows;
        updated = service.lastUpdatedAt?.toLocal().toString().split('.').first;
        error = service.usingSnapshot ? '${service.lastError ?? 'Consulta direta indisponível.'} Exibindo a lista de reserva verificada.' : null;
      });
    } catch (_) {
      if (mounted) {
        setState(() => error =
            items.isEmpty ? 'Não foi possível carregar a fonte. Tente novamente.' : 'Não foi possível atualizar. Exibindo a última lista salva.');
      }
    } finally {
      if (mounted) {
        setState(() {
          loading = false;
          refreshing = false;
        });
      }
    }
  }

  void _open(Map<String, dynamic> item) {
    final uri =
        Uri.tryParse('${item[widget.events ? 'play_event_url' : 'embed_url']}');
    if (uri == null ||
        uri.origin != superflixOrigin ||
        !RegExp(r'^/(?:canal|eventos)/').hasMatch(uri.path)) {
      return;
    }
    Navigator.push(
        context,
        MaterialPageRoute<void>(
            builder: (_) => SourcePage(
                title: '${item[widget.events ? 'title' : 'name']}',
                url: uri.toString(),
                headers: const {'Referer': '$superflixOrigin/'},
                embedded: true)));
  }

  String _time(String value) {
    final time = DateTime.tryParse(value);
    if (time == null) return value;
    String two(int n) => '$n'.padLeft(2, '0');
    return '${two(time.day)}/${two(time.month)}/${time.year} ${two(time.hour)}:${two(time.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final categories = items
        .map((v) => '${v['category'] ?? ''}')
        .where((v) => v.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    final rows = items
        .where((v) =>
            (category.isEmpty || v['category'] == category) &&
            '${v[widget.events ? 'title' : 'name']}'
                .toLowerCase()
                .contains(query.toLowerCase()))
        .toList();
    return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              Text(
                  widget.events
                      ? 'Agenda esportiva · SuperFlix'
                      : 'Canais · SuperFlix',
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              TextField(
                  onChanged: (v) => setState(() => query = v),
                  decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.search),
                      hintText:
                          widget.events ? 'Buscar evento' : 'Buscar canal')),
              DropdownButton<String>(
                  isExpanded: true,
                  value: category,
                  items: [
                    const DropdownMenuItem(
                        value: '', child: Text('Todas as categorias')),
                    for (final c in {
                      ...categories,
                      if (category.isNotEmpty) category
                    })
                      DropdownMenuItem(value: c, child: Text(c))
                  ],
                  onChanged: (v) => setState(() => category = v ?? '')),
              if (refreshing) const LinearProgressIndicator(),
              if (updated != null) Text('Lista verificada em: $updated', style: const TextStyle(fontSize: 12, color: Colors.white60)),
              if (error != null) Text(error!),
              OutlinedButton.icon(onPressed: refreshing ? null : _refresh,
                icon: const Icon(Icons.refresh), label: const Text('Atualizar lista')),
              if (loading)
                const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator())),
              if (!loading && error == null && rows.isEmpty)
                const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Nenhum resultado com estes filtros.')),
              for (final row in rows)
                Card(
                    child: ListTile(
                        leading: SizedBox(
                            width: 52,
                            height: 52,
                            child: Image.network(
                                '${row[widget.events ? 'poster' : 'logo_url'] ?? ''}',
                                fit: BoxFit.contain,
                                errorBuilder: (_, e, stack) => Icon(
                                    widget.events
                                        ? Icons.sports
                                        : Icons.live_tv))),
                        title: Text('${row[widget.events ? 'title' : 'name']}'),
                        subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${row['category'] ?? ''}'),
                              if (widget.events) ...[
                                Text('${row['competition'] ?? ''}'),
                                if ('${row['start_time'] ?? ''}'.isNotEmpty)
                                  Text(
                                      'Horário informado: ${_time('${row['start_time']}')}'),
                                Text(row['status'] == 'live'
                                    ? '● AO VIVO'
                                    : row['status'] == 'upcoming'
                                        ? 'Agendado'
                                        : '${row['status'] ?? ''}')
                              ]
                            ]),
                        trailing: const Icon(Icons.play_circle_outline),
                        onTap: () => _open(row))),
              const SizedBox(height: 12),
              const Text(
                  'As opções desta fonte usam o player incorporado. A disponibilidade depende de cada transmissão.',
                  style: TextStyle(color: Colors.white60, fontSize: 12))
            ]));
  }
}
