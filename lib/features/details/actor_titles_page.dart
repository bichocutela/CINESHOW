import 'package:flutter/material.dart';
import '../../core/models/media_item.dart';
import '../../core/services/actor_catalog.dart';
import '../../core/services/poster_sources.dart';

class ActorTitlesPage extends StatefulWidget {
  const ActorTitlesPage(
      {super.key,
      required this.name,
      required this.onOpen,
      this.archiveUrls = const [],
      this.catalog});
  final String name;
  final ValueChanged<MediaItem> onOpen;
  final List<String> archiveUrls;
  final ActorCatalog? catalog;
  @override
  State<ActorTitlesPage> createState() => _ActorTitlesState();
}

class _ActorTitlesState extends State<ActorTitlesPage> {
  late final catalog = widget.catalog ?? ActorCatalog();
  List<MediaItem> items = [];
  bool loading = true, more = true;
  String? error;
  @override
  void initState() {
    super.initState();
    _initial();
  }

  Future<void> _initial() async {
    final cached = await catalog.titles(widget.name);
    if (!mounted) return;
    setState(() => items = cached);
    await _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final found = await catalog.search(widget.name,
          reset: reset, archiveUrls: widget.archiveUrls);
      if (!mounted) return;
      setState(() {
        items = found.items;
        more = found.hasMore;
        error = found.errors.isEmpty
            ? null
            : 'Algumas fontes não responderam. Tente novamente para completar os resultados.';
      });
    } catch (_) {
      if (mounted)
        {
setState(() => error =
            'Não foi possível consultar as fontes agora. Tente novamente.');
}
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: Text(widget.name), actions: [
        IconButton(
            tooltip: 'Atualizar filmes do ator',
            onPressed: loading ? null : () => _load(reset: true),
            icon: const Icon(Icons.refresh))
      ]),
      body: SafeArea(
          top: false,
          child: RefreshIndicator(
              onRefresh: () => _load(reset: true),
              child: ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  itemCount: items.length + 2,
                  itemBuilder: (context, index) {
                    if (index == 0)
                      {
return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                                'Filmes e séries disponíveis nas fontes do CINESHOW, pesquisados pelo elenco.'),
                            const SizedBox(height: 8),
                            if (loading) const LinearProgressIndicator(),
                            if (error != null) Text(error!),
                            if (!loading && items.isEmpty && error == null)
                              const Padding(
                                  padding: EdgeInsets.all(24),
                                  child: Text(
                                      'Nenhum título foi encontrado nas fontes consultadas.')),
                          ]);
}
                    if (index == items.length + 1)
                      {
return more || error != null
                          ? OutlinedButton.icon(
                              onPressed: loading ? null : () => _load(),
                              icon: const Icon(Icons.expand_more),
                              label: Text(error == null
                                  ? 'Carregar mais títulos'
                                  : 'Tentar fontes pendentes'))
                          : const SizedBox.shrink();
}
                    final item = items[index - 1];
                    return ListTile(
                        leading: posterSources(item).isEmpty
                            ? const Icon(Icons.movie_outlined)
                            : Image.network(posterSources(item).first,
                                width: 40,
                                height: 60,
                                fit: BoxFit.cover,
                                errorBuilder: (_, e, stack) =>
                                    const Icon(Icons.movie_outlined)),
                        title: Text(item.title),
                        subtitle: Text(
                            '${item.typeLabel}${item.year > 0 ? ' · ${item.year}' : ''}'),
                        onTap: () => widget.onOpen(item));
                  }))));
}
