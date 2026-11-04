import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/services/iptv_catalog.dart';
import '../player/presentation/player_page.dart';

const categoryNames = {
  'animation': 'Animação',
  'auto': 'Automóveis',
  'business': 'Negócios',
  'classic': 'Clássicos',
  'comedy': 'Comédia',
  'cooking': 'Culinária',
  'culture': 'Cultura',
  'documentary': 'Documentários',
  'education': 'Educação',
  'entertainment': 'Entretenimento',
  'family': 'Família',
  'general': 'Geral',
  'interactive': 'Interativos',
  'kids': 'Infantil',
  'legislative': 'Legislativos',
  'lifestyle': 'Estilo de vida',
  'movies': 'Filmes',
  'music': 'Música',
  'news': 'Notícias',
  'outdoor': 'Ao ar livre',
  'public': 'Públicos',
  'relax': 'Relaxamento',
  'religious': 'Religiosos',
  'science': 'Ciência',
  'series': 'Séries',
  'shop': 'Compras',
  'sports': 'Esportes',
  'travel': 'Viagem',
  'weather': 'Clima',
};

class LivePage extends StatefulWidget {
  const LivePage({super.key});
  @override
  State<LivePage> createState() => _LivePageState();
}

class _LivePageState extends State<LivePage> {
  final catalog = IptvCatalog();
  List<TvChannel> channels = [];
  Set<String> favorites = {};
  bool loading = true, refreshing = false, onlyFavorites = false;
  String query = '', country = 'BR', category = '';
  String? error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = await catalog.cached();
    if (!mounted) return;
    setState(() {
      channels = saved;
      favorites = (prefs.getStringList('tv.favorites') ?? []).toSet();
      loading = saved.isEmpty;
    });
    await _refresh();
  }

  Future<void> _refresh() async {
    if (refreshing) return;
    setState(() {
      refreshing = true;
      error = null;
    });
    try {
      final fresh = await catalog.refresh();
      if (mounted) setState(() => channels = fresh);
    } catch (_) {
      if (mounted)
        setState(
          () => error = channels.isEmpty
              ? 'Não foi possível carregar os canais. Tente novamente.'
              : 'Não foi possível atualizar. Exibindo os canais salvos.',
        );
    } finally {
      if (mounted)
        setState(() {
          loading = false;
          refreshing = false;
        });
    }
  }

  Future<void> _favorite(TvChannel channel) async {
    setState(() {
      favorites.contains(channel.id)
          ? favorites.remove(channel.id)
          : favorites.add(channel.id);
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('tv.favorites', favorites.toList());
  }

  void _play(TvChannel channel, int index) => Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => PlayerPage(media: channel.media(index)),
        ),
      );
  @override
  void dispose() {
    catalog.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final countries = channels
        .map((c) => c.country)
        .where((v) => v.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    final categories = channels.expand((c) => c.categories).toSet().toList()
      ..sort();
    final visible = channels
        .where(
          (c) =>
              (country.isEmpty || c.country == country) &&
              (category.isEmpty || c.categories.contains(category)) &&
              (!onlyFavorites || favorites.contains(c.id)) &&
              c.name.toLowerCase().contains(query.toLowerCase().trim()),
        )
        .toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'AO VIVO',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                onPressed: refreshing ? null : _refresh,
                tooltip: 'Atualizar canais',
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            onChanged: (v) => setState(() => query = v),
            decoration: const InputDecoration(
              hintText: 'Buscar canal',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              DropdownButton<String>(
                value: country,
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text('Todos os países'),
                  ),
                  for (final c in {...countries, 'BR'}.toList()..sort())
                    DropdownMenuItem(
                      value: c,
                      child: Text(c == 'BR' ? 'Brasil' : c),
                    ),
                ],
                onChanged: (v) => setState(() => country = v ?? ''),
              ),
              DropdownButton<String>(
                value: category,
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text('Todas as categorias'),
                  ),
                  for (final c in {
                    ...categories,
                    if (category.isNotEmpty) category,
                  }.toList()
                    ..sort())
                    DropdownMenuItem(
                      value: c,
                      child: Text(categoryNames[c] ?? c),
                    ),
                ],
                onChanged: (v) => setState(() => category = v ?? ''),
              ),
              FilterChip(
                label: const Text('Favoritos'),
                selected: onlyFavorites,
                onSelected: (v) => setState(() => onlyFavorites = v),
              ),
            ],
          ),
        ),
        if (refreshing) const LinearProgressIndicator(),
        if (error != null)
          Padding(padding: const EdgeInsets.all(12), child: Text(error!)),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text('${visible.length} canais · Fonte: iptv-org'),
        ),
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : visible.isEmpty
                  ? const Center(child: Text('Nenhum canal com estes filtros.'))
                  : RefreshIndicator(
                      onRefresh: _refresh,
                      child: ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: visible.length,
                        itemBuilder: (context, index) {
                          final c = visible[index];
                          return ListTile(
                            leading: SizedBox(
                              width: 56,
                              height: 44,
                              child: c.logo == null
                                  ? const Icon(Icons.live_tv)
                                  : Image.network(
                                      c.logo!,
                                      fit: BoxFit.contain,
                                      cacheWidth: 160,
                                      errorBuilder: (_, e, s) =>
                                          const Icon(Icons.live_tv),
                                    ),
                            ),
                            title: Text(c.name),
                            subtitle: Text(
                              '${c.country} · ${c.categories.map((v) => categoryNames[v] ?? v).join(', ')}',
                            ),
                            onTap: () => _play(c, 0),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Favoritar canal',
                                  onPressed: () => _favorite(c),
                                  icon: Icon(
                                    favorites.contains(c.id)
                                        ? Icons.star
                                        : Icons.star_border,
                                  ),
                                ),
                                PopupMenuButton<int>(
                                  tooltip: 'Fontes de transmissão',
                                  onSelected: (i) => _play(c, i),
                                  itemBuilder: (_) => [
                                    for (var i = 0; i < c.streams.length; i++)
                                      PopupMenuItem(
                                        value: i,
                                        child: Text(
                                          'Fonte ${i + 1} · ${c.streams[i]['quality'] ?? ''} ${((c.streams[i]['labels'] as List?) ?? []).join(', ')}',
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
        ),
      ],
    );
  }
}
