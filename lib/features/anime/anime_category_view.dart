import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/models/media_item.dart';
import '../../core/services/anime_catalog.dart';
import '../../core/services/poster_sources.dart';

class AnimeCategoryView extends StatefulWidget {
  const AnimeCategoryView(
      {super.key, required this.onOpen, this.active = true, this.serviceFactory});
  final AnimeCatalogService Function(String provider)? serviceFactory;
  final Future<void> Function(MediaItem item, String? episode) onOpen;
  final bool active;
  @override
  State<AnimeCategoryView> createState() => _AnimeCategoryViewState();
}

class _AnimeCategoryViewState extends State<AnimeCategoryView>
    with WidgetsBindingObserver {
  String provider = 'animesonlinecc';
  AnimeCatalogService get service => widget.serviceFactory?.call(provider) ?? AnimeCatalogService(provider: provider);
  final searchController = TextEditingController();
  List<MediaItem> recent = [], episodes = [], items = [];
  List<Map<String, dynamic>> notices = [];
  String mode = 'Recentes', query = '';
  String? letter, error;
  int page = 0, generation = 0;
  bool loading = false, more = true, opening = false;
  Timer? timer, debounce;
  bool foreground = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initial();
    timer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (foreground && widget.active && mode == 'Recentes') _refresh();
    });
  }

  Future<void> _initial() async {
    final request = ++generation;
    final selectedService = service;
    final cache = await selectedService.cached();
    if (!mounted || request != generation) return;
    setState(() {
      recent = cache['titles']!;
      episodes = cache['episodes']!;
    });
    await _refresh();
  }

  Future<void> _refresh() async {
    if (loading || !mounted) return;
    final request = ++generation;
    final selectedService = service;
    setState(() { loading = true; error = null; });
    try {
      final data = await selectedService.refresh();
      final rows = await selectedService.notices();
      if (mounted && request == generation) {
        setState(() { recent = data['titles']!; episodes = data['episodes']!; notices = rows; });
      }
    } catch (_) {
      if (mounted && request == generation) setState(() => error = 'A fonte não respondeu. Exibindo os dados salvos.');
    } finally {
      if (mounted && request == generation) setState(() => loading = false);
    }
  }

  Future<void> _mode(String value) async {
    debounce?.cancel();
    final request = ++generation;
    setState(() { mode = value; loading = false; });
    if (value == 'A–Z') { await _list(reset: true); }
    else if (value == 'Recentes') { await _refresh(); }
    else if (value == 'Novidades') {
      try {
        final rows = await service.notices(markRead: true);
        if (mounted && request == generation) setState(() => notices = rows);
      } catch (_) {
        if (mounted && request == generation) setState(() => error = 'Não foi possível carregar as novidades agora.');
      }
    }
  }

  void _letter(String? value) {
    debounce?.cancel();
    searchController.clear();
    letter = value;
    query = '';
    _list(reset: true);
  }

  Future<void> _list({bool reset = false}) async {
    if (!mounted) return;
    final request = ++generation;
    final next = reset ? 1 : page + 1;
    setState(() {
      mode = 'A–Z';
      loading = true;
      error = null;
      if (reset) {
        items = [];
        page = 0;
        more = true;
      }
    });
    try {
      final result =
          await service.list(letter: letter, query: query, page: next);
      if (!mounted || request != generation) return;
      final joined = {
        for (final i in [...items, ...result.items]) i.sources.first.pageUrl: i
      };
      final sorted = joined.values.toList()
        ..sort(
            (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      setState(() {
        items = sorted;
        more = result.more;
        page = next;
        loading = false;
      });
    } catch (_) {
      if (mounted && request == generation) {
        setState(() {
          loading = false;
          error = 'Não foi possível carregar esta página. Tente novamente.';
        });
      }
    }
  }

  void _query(String value) {
    debounce?.cancel();
    query = value.trim();
    setState(() => loading = false);
    generation++;
    debounce =
        Timer(const Duration(milliseconds: 400), () => _list(reset: true));
  }

  Future<void> _open(MediaItem item) async {
    if (opening) return;
    setState(() => opening = true);
    try {
      final result = await service.contextFor(item);
      if (mounted) await widget.onOpen(result.item, result.episode);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Não foi possível abrir este anime.')));
      }
    } finally {
      if (mounted) setState(() => opening = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (foreground && widget.active && mode == 'Recentes') _refresh();
  }

  @override
  void dispose() {
    generation++;
    timer?.cancel();
    debounce?.cancel();
    searchController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Widget _rail(String title, List<MediaItem> data) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(title,
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold))),
        SizedBox(
            height: 245,
            child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: data.length,
                separatorBuilder: (_, i) => const SizedBox(width: 12),
                itemBuilder: (_, i) => SizedBox(
                    width: 135,
                    child:
                        AnimeTile(item: data[i], onTap: () => _open(data[i])))))
      ]);
  @override
  Widget build(BuildContext context) => SafeArea(
      top: false,
      child: Column(children: [
        Wrap(spacing: 8, children: [
          for (final entry in const {
            'animesonlinecc': 'Animes Online',
            'superflix': 'SuperFlix'
          }.entries)
            ChoiceChip(
                label: Text(entry.value),
                selected: provider == entry.key,
                onSelected: loading
                    ? null
                    : (_) {
                        debounce?.cancel();
                        generation++;
                        setState(() {
                          searchController.clear();
                          provider = entry.key;
                          mode = 'Recentes';
                          query = '';
                          letter = null;
                          page = 0;
                          items = [];
                          recent = [];
                          episodes = [];
                          more = true;
                        });
                        _initial();
                      })
        ]),
        Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
                controller: searchController,
                onChanged: _query,
                decoration: const InputDecoration(
                    hintText: 'Buscar anime',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder()))),
        SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              for (final value in ['Recentes', 'A–Z', 'Novidades'])
                Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                        label: Text(value == 'Novidades'
                            ? 'Novidades (${notices.where((n) => n['read'] != true).length})'
                            : value),
                        selected: mode == value,
                        onSelected: (_) => _mode(value))),
              IconButton(
                  tooltip: 'Atualizar animes',
                  onPressed: loading ? null : () => mode == 'A–Z' ? _list(reset: true) : _refresh(),
                  icon: const Icon(Icons.refresh))
            ])),
        if (mode == 'A–Z')
          SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(children: [
                ChoiceChip(
                    label: const Text('Todas'),
                    selected: letter == null,
                    onSelected: (_) => _letter(null)),
                for (var code = 65; code <= 90; code++)
                  Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: ChoiceChip(
                          label: Text(String.fromCharCode(code)),
                          selected: letter == String.fromCharCode(code),
                          onSelected: (_) => _letter(String.fromCharCode(code))))
              ])),
        if (loading || opening) const LinearProgressIndicator(),
        if (error != null)
          Padding(padding: const EdgeInsets.all(12), child: Text(error!)),
        Expanded(
            child: mode == 'Recentes'
                ? RefreshIndicator(
                    onRefresh: _refresh,
                    child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        children: [
                          _rail('Animes adicionados recentemente', recent),
                          _rail('Episódios recentes na fonte', episodes)
                        ]))
                : mode == 'Novidades'
                    ? ListView(padding: const EdgeInsets.all(16), children: [
                        const Text(
                            'Novidades de anime ficam nesta categoria. Atualização ao abrir e enquanto o app estiver em uso.'),
                        if (notices.isEmpty)
                          const Padding(
                              padding: EdgeInsets.all(24),
                              child: Text(
                                  'Nenhuma novidade desde a primeira sincronização.')),
                        for (final row in notices)
                          ListTile(
                              title: Text(row['title'] as String),
                              subtitle: Text(row['body'] as String),
                              leading: const Icon(Icons.notifications_outlined),
                              onTap: () => _open(MediaItem.fromJson(
                                  Map<String, dynamic>.from(
                                      row['item'] as Map))))
                      ])
                    : CustomScrollView(slivers: [
                        SliverPadding(
                            padding: const EdgeInsets.all(16),
                            sliver: SliverGrid(
                                delegate: SliverChildBuilderDelegate(
                                    (_, i) => AnimeTile(
                                        item: items[i],
                                        onTap: () => _open(items[i])),
                                    childCount: items.length),
                                gridDelegate:
                                    const SliverGridDelegateWithMaxCrossAxisExtent(
                                        maxCrossAxisExtent: 180,
                                        childAspectRatio: .58,
                                        crossAxisSpacing: 12,
                                        mainAxisSpacing: 16))),
                        SliverToBoxAdapter(
                            child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: OutlinedButton(
                                    onPressed:
                                        loading || !more ? null : () => _list(),
                                    child: Text(more
                                        ? 'Carregar mais animes'
                                        : 'Fim desta lista'))))
                      ]))
      ]));
}

class AnimeTile extends StatelessWidget {
  const AnimeTile({super.key, required this.item, required this.onTap});
  final MediaItem item;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final images = posterSources(item);
    return InkWell(
        onTap: onTap,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
              child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                      width: double.infinity,
                      child: images.isEmpty
                          ? const ColoredBox(
                              color: Color(0xFF25232F),
                              child: Icon(Icons.movie_outlined))
                          : Image.network(images.first,
                              fit: BoxFit.cover,
                              cacheWidth: 360,
                              errorBuilder: (_, error, stack) =>
                                  const ColoredBox(
                                      color: Color(0xFF25232F),
                                      child: Icon(Icons.movie_outlined)))))),
          const SizedBox(height: 8),
          Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis),
          if (item.audio.isNotEmpty)
            Text(item.audio,
                style: const TextStyle(color: Colors.white60, fontSize: 12))
        ]));
  }
}
