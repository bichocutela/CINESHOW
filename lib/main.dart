import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'core/models/media_item.dart';
import 'core/services/poster_sources.dart';
import 'core/services/provider_playback.dart';
import 'core/services/catalog_categories.dart';
import 'features/catalog/category_bar.dart';
import 'features/downloads/downloads_page.dart';
import 'core/services/catalog_notices.dart';
import 'core/services/chapter_queue.dart';
import 'core/services/continue_watching.dart';
import 'features/notices/notices_page.dart';
import 'features/live/live_page.dart';
import 'features/player/presentation/player_page.dart';
import 'features/player/presentation/source_page.dart';
import 'core/services/live_catalog.dart';
import 'core/services/app_updates.dart';

void main() => runApp(const CineShowApp());

class CineShowApp extends StatelessWidget {
  const CineShowApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
      title: 'CINESHOW',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: const Color(0xFF0B0B10),
          colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFFE50914), brightness: Brightness.dark),
          useMaterial3: true),
      home: const ShellPage());
}

class ShellPage extends StatefulWidget {
  const ShellPage({super.key});
  @override
  State<ShellPage> createState() => _ShellState();
}

class _ShellState extends State<ShellPage> with WidgetsBindingObserver {
  final catalog = LiveCatalog();
  List<ContinueEntry> recent = [];
  List<MediaItem> items = [];
  Set<String> favorites = {};
  List<String> errors = [];
  bool loading = true;
  int tab = 0;
  bool liveOpened = false;
  String filter = 'Todos';
  CatalogCategory? category;
  List<MediaItem>? categoryItems;
  bool categoryLoading = false;
  int categoryRequest = 0;
  bool loadingMore = false, hasMore = true;
  Timer? syncTimer;
  bool foreground = true, syncing = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    CatalogNotices.instance.refreshBadge();
    syncTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (foreground && !syncing) _sync();
    });
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final cached = await catalog.cached();
    if (!mounted) return;
    setState(() {
      favorites = (p.getStringList('favorites') ?? []).toSet();
      items = cached;
      loading = cached.isEmpty;
    });
    await _recent();
    await _sync();
  }

  Future<void> _refresh() async {
    try {
      final r = await catalog.refresh();
      if (!mounted) return;
      setState(() {
        if (r.items.isNotEmpty)
          items = catalog.mergeItems([...items, ...r.items]);
        errors = r.errors;
        loading = false;
      });
      await CatalogNotices.instance.syncCatalog(r.items);
      if (category != null) await _selectCategory(category, force: true);
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
          errors = ['Conexão'];
        });
      }
    }
  }

  Future<void> _selectCategory(CatalogCategory? next,
      {bool force = false}) async {
    final generation = ++categoryRequest;
    final section = filter;
    setState(() {
      category = next;
      categoryItems = null;
      categoryLoading = next != null;
      loadingMore = false;
      hasMore = true;
    });
    if (next == null) return;
    try {
      final result = await catalog.category(next,
          kind: categoryKind(section), force: force);
      if (!mounted || generation != categoryRequest) return;
      setState(() {
        categoryItems = result.items;
        categoryLoading = false;
      });
      if (result.errors.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Algumas fontes desta categoria não responderam.')));
      }
    } catch (_) {
      if (!mounted || generation != categoryRequest) return;
      setState(() {
        categoryItems = [];
        categoryLoading = false;
      });
    }
  }

  Future<void> _more() async {
    if (loadingMore || categoryLoading) return;
    final generation = categoryRequest;
    setState(() => loadingMore = true);
    try {
      final page =
          await catalog.more(kind: categoryKind(filter), category: category);
      if (!mounted || generation != categoryRequest) return;
      setState(() {
        if (category == null) {
          items = catalog.mergeItems([...items, ...page.items]);
        } else {
          categoryItems = page.items;
        }
        hasMore = page.hasMore;
        loadingMore = false;
      });
      if (page.errors.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Algumas fontes falharam. Toque novamente para tentar as páginas pendentes.')));
      }
    } catch (_) {
      if (mounted && generation == categoryRequest)
        setState(() => loadingMore = false);
    }
  }

  Future<void> _sync() async {
    if (syncing) return;
    syncing = true;
    try {
      await _refresh();
      for (final watched in await CatalogNotices.instance.watched()) {
        if (!mounted || !foreground) break;
        final item = MediaItem.fromJson(
            Map<String, dynamic>.from(watched['item'] as Map));
        final source = MediaSource.fromJson(
            Map<String, dynamic>.from(watched['source'] as Map));
        try {
          final chapters = await catalog.episodes(source);
          await CatalogNotices.instance.syncChapters(item, source, chapters);
        } catch (_) {
          // One unavailable source must not stop other followed titles.
        }
      }
    } finally {
      syncing = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (foreground) _sync();
  }

  @override
  void dispose() {
    syncTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _favorite(MediaItem item) async {
    setState(() {
      favorites.contains(item.id)
          ? favorites.remove(item.id)
          : favorites.add(item.id);
    });
    final p = await SharedPreferences.getInstance();
    await p.setStringList('favorites', favorites.toList());
  }

  Future<void> _recent() async {
    final rows = await ContinueWatching().list();
    if (mounted) setState(() => recent = rows);
  }

  Future<void> _details(MediaItem item, {ContinueEntry? resume}) async {
    await Navigator.push(context, MaterialPageRoute<void>(
        builder: (_) => DetailsPage(item: item, catalog: catalog,
            isFavorite: favorites.contains(item.id),
            onFavorite: () => _favorite(item),
            resumeSource: resume?.source, resumePage: resume?.pageUrl)));
    await _recent();
  }
  @override
  Widget build(BuildContext context) {
    final visible = (category == null ? items : categoryItems ?? <MediaItem>[])
        .where((i) => filter == 'Todos' || i.typeLabel == filter)
        .toList();
    return Scaffold(
        appBar: AppBar(
            toolbarHeight: 88,
            title: Image.asset('assets/logo_header.png',
                height: 72, fit: BoxFit.contain, semanticLabel: 'Cine Show'),
            actions: [
              ValueListenableBuilder<int>(
                  valueListenable: CatalogNotices.instance.unread,
                  builder: (context, count, _) => IconButton(
                      tooltip: 'Novidades',
                      icon: Badge(
                          isLabelVisible: count > 0,
                          label: Text('$count'),
                          child: const Icon(Icons.notifications_outlined)),
                      onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                              builder: (_) => NoticesPage(onOpen: _details))))),
              IconButton(
                  onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                          builder: (_) =>
                              SearchPage(catalog: catalog, onOpen: _details))),
                  icon: const Icon(Icons.search),
                  tooltip: 'Buscar')
            ]),
        body: IndexedStack(index: tab, children: [
          RefreshIndicator(
              onRefresh: _sync,
              child: CustomScrollView(slivers: [
                SliverToBoxAdapter(
                    child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(children: [
                              for (final type in [
                                'Todos',
                                'Filme',
                                'Série',
                                'Novela',
                                'Reality'
                              ])
                                Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: ChoiceChip(
                                        label: Text(type),
                                        selected: filter == type,
                                        onSelected: (_) => setState(() {
                                              filter = type;
                                              category = null;
                                              categoryItems = null;
                                              categoryLoading = false;
                                              categoryRequest++;
                                              loadingMore = false;
                                              hasMore = true;
                                            })))
                            ])))),
                if (errors.isNotEmpty)
                  SliverToBoxAdapter(
                      child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                              'Algumas fontes não responderam. Exibindo o catálogo salvo.',
                              style: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant)))),
                if (recent.isNotEmpty)
                  SliverToBoxAdapter(child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Continuar assistindo',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                        for (final entry in recent.take(5)) ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.play_circle_outline),
                            title: Text(entry.item.title),
                            subtitle: Text('${entry.position.position.inMinutes} min de ${entry.position.duration.inMinutes} min'),
                            onTap: () => _details(entry.item, resume: entry))
                      ]))),
                if (loading)
                  const SliverFillRemaining(
                      child: Center(child: CircularProgressIndicator()))
                else ...[
                  if (visible.isNotEmpty)
                    SliverToBoxAdapter(
                        child: HeroCard(
                            item: visible.first,
                            onOpen: () => _details(visible.first))),
                  SliverToBoxAdapter(
                      child: CategoryBar(
                          section: filter,
                          selected: category,
                          onSelected: _selectCategory)),
                  if (categoryLoading)
                    const SliverToBoxAdapter(child: LinearProgressIndicator()),
                  if (!categoryLoading && visible.isEmpty)
                    const SliverToBoxAdapter(
                        child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                                'Nenhum título retornado nesta categoria.'))),
                  const SliverToBoxAdapter(
                      child: Padding(
                          padding: EdgeInsets.fromLTRB(16, 20, 16, 12),
                          child: Text('Explore o catálogo',
                              style: TextStyle(
                                  fontSize: 22, fontWeight: FontWeight.bold)))),
                  SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      sliver: SliverGrid(
                          delegate: SliverChildBuilderDelegate(
                              (context, index) => PosterCard(
                                  item: visible[index],
                                  onOpen: () => _details(visible[index])),
                              childCount: visible.length),
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: 180,
                                  childAspectRatio: .58,
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 16))),
                  if (filter != 'Novela' && filter != 'Reality')
                    SliverToBoxAdapter(
                        child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: OutlinedButton.icon(
                                onPressed:
                                    loadingMore || categoryLoading || !hasMore
                                        ? null
                                        : _more,
                                icon: const Icon(Icons.expand_more),
                                label: Text(loadingMore
                                    ? 'Carregando...'
                                    : hasMore
                                        ? 'Carregar mais títulos'
                                        : 'Fim do catálogo disponível'))))
                ]
              ])),
          ListView(padding: const EdgeInsets.all(16), children: [
            const Text('Minha lista',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            if (!items.any((i) => favorites.contains(i.id)))
              const Padding(
                  padding: EdgeInsets.only(top: 24),
                  child: Text(
                      'Adicione títulos à sua lista na tela de detalhes.')),
            for (final i in items.where((i) => favorites.contains(i.id)))
              ListTile(
                  title: Text(i.title),
                  subtitle: Text(i.typeLabel),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _details(i))
          ]),
          if (liveOpened) const LivePage() else const SizedBox.shrink(),
          const SettingsPage()
        ]),
        bottomNavigationBar: NavigationBar(
            selectedIndex: tab,
            onDestinationSelected: (v) => setState(() {
                  tab = v;
                  if (v == 2) liveOpened = true;
                }),
            destinations: const [
              NavigationDestination(
                  icon: Icon(Icons.home_outlined), label: 'Início'),
              NavigationDestination(
                  icon: Icon(Icons.bookmark_border), label: 'Minha lista'),
              NavigationDestination(
                  icon: Icon(Icons.live_tv), label: 'Ao Vivo'),
              NavigationDestination(
                  icon: Icon(Icons.settings_outlined), label: 'Sobre')
            ]));
  }
}

class Cover extends StatelessWidget {
  const Cover({super.key, required this.item});
  final MediaItem item;
  @override
  Widget build(BuildContext context) {
    final placeholder = ColoredBox(
        color: const Color(0xFF25232F),
        child: Center(
            child: Icon(
                item.kind == 'novela' ? Icons.live_tv : Icons.movie_outlined,
                size: 48,
                color: Colors.white38)));
    final candidates = posterSources(item);
    Widget imageAt(int index) {
      if (index >= candidates.length) return placeholder;
      return Image.network(candidates[index],
          fit: BoxFit.cover,
          cacheWidth: 360,
          errorBuilder: (_, error, stack) => imageAt(index + 1),
          loadingBuilder: (_, child, progress) =>
              progress == null ? child : placeholder);
    }

    return ClipRRect(
        borderRadius: BorderRadius.circular(12), child: Stack(
          fit: StackFit.expand, children: [
            imageAt(0),
            if (item.tags.isNotEmpty) Positioned(
                left: 6, top: 6,
                child: DecoratedBox(decoration: BoxDecoration(color: Color(0xFF682D75), borderRadius: BorderRadius.circular(6)),
                  child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      child: Text(item.tags.first, style: const TextStyle(color: Colors.white, fontSize: 11))))),
            if (item.audio.isNotEmpty) Positioned(
                left: 6, right: 6, bottom: 6,
                child: DecoratedBox(
                    decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(6)),
                    child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      child: Text(item.audio, maxLines: 2,
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)))))
          ]));
  }
}

class PosterCard extends StatelessWidget {
  const PosterCard({super.key, required this.item, required this.onOpen});
  final MediaItem item;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) => InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
            child: SizedBox(width: double.infinity, child: Cover(item: item))),
        const SizedBox(height: 8),
        Text(item.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        Text('${item.typeLabel}${item.year > 0 ? ' · ${item.year}' : ''}',
            style: const TextStyle(color: Colors.white54, fontSize: 12))
      ]));
}

class HeroCard extends StatelessWidget {
  const HeroCard({super.key, required this.item, required this.onOpen});
  final MediaItem item;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) => Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(
              colors: [Color(0xFF3A1420), Color(0xFF171722)])),
      child: Row(children: [
        SizedBox(width: 100, height: 150, child: Cover(item: item)),
        const SizedBox(width: 20),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('EM DESTAQUE',
              style: TextStyle(
                  fontSize: 11, color: Colors.white54, letterSpacing: 2)),
          const SizedBox(height: 10),
          Text(item.title,
              style:
                  const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          FilledButton.icon(
              onPressed: onOpen,
              icon: const Icon(Icons.info_outline),
              label: const Text('Ver detalhes'))
        ]))
      ]));
}

class DetailsPage extends StatefulWidget {
  const DetailsPage(
      {super.key,
      required this.item,
      required this.catalog,
      required this.isFavorite,
      required this.onFavorite,
      this.resumeSource, this.resumePage});
  final MediaItem item;
  final LiveCatalog catalog;
  final bool isFavorite;
  final VoidCallback onFavorite;
  final MediaSource? resumeSource;
  final String? resumePage;
  @override
  State<DetailsPage> createState() => _DetailsState();
}

class _DetailsState extends State<DetailsPage> {
  late bool favorite = widget.isFavorite;
  late MediaSource? selected = widget.resumeSource ?? widget.item.sources.firstOrNull;
  List<Map<String, dynamic>> episodes = [];
  bool loading = false;
  bool resolving = false;
  String? playbackError;
  ProviderPlaybackResolver? activeResolver;
  String? error;
  bool following = false;
  Future<void>? episodeRequest;
  @override
  void initState() {
    super.initState();
    CatalogNotices.instance.isFollowing(widget.item.id).then((value) {
      if (mounted) setState(() => following = value);
    });
    if (widget.item.kind != 'movie' && selected != null) _episodes();
    if (widget.resumePage != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _watchSource(widget.resumePage!);
      });
    }
  }

  Future<void> _episodes() => episodeRequest ??= _loadEpisodes().whenComplete(() => episodeRequest = null);

  Future<void> _loadEpisodes() async {
    setState(() {
      loading = true;
      error = null;
      episodes = [];
    });
    try {
      final source = selected!;
      final e = await widget.catalog.episodes(source);
      await CatalogNotices.instance.syncChapters(widget.item, source, e);
      if (mounted) setState(() => episodes = e);
    } catch (_) {
      if (mounted) {
        setState(() => error =
            'Não foi possível carregar os capítulos. Você pode abrir a fonte original.');
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https') return;
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
          mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Não foi possível abrir este endereço.')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Não foi possível abrir este endereço.')));
      }
    }
  }

  Future<void> _watchSource(String url, {bool download = false,
      bool auto = false, bool replaceCurrent = false, bool startFullscreen = false}) async {
    final source = selected;
    if (resolving || source == null) return;
    if (widget.item.kind != 'movie' && episodes.isEmpty) await _episodes();
    if (!mounted) return;
    if (widget.item.kind != 'movie' && url == source.pageUrl) {
      final ordered = orderedChapters(episodes);
      if (ordered.isNotEmpty) url = chapterUrl(ordered.last);
    }
    final resolver = ProviderPlaybackResolver();
    activeResolver = resolver;
    setState(() {
      resolving = true;
      playbackError = null;
    });
    try {
      final options = await resolver
          .resolve(widget.item, source, pageUrl: url)
          .timeout(const Duration(seconds: 90));
      if (!mounted) return;
      ProviderPlaybackOption? choice;
      if (options.length == 1 || auto) {
        choice = options.where((v) => v.direct).firstOrNull ?? options.first;
      } else {
        choice = await showModalBottomSheet<ProviderPlaybackOption>(
            context: context,
            builder: (context) => SafeArea(
                    child: ListView(shrinkWrap: true, children: [
                  const ListTile(title: Text('Escolher player disponível')),
                  for (final option in options)
                    ListTile(
                        title: Text(option.label),
                        subtitle: Text(option.direct
                            ? 'Vídeo direto no CINESHOW'
                            : 'Player externo · pode exigir anúncios ou verificação'),
                        trailing: const Icon(Icons.play_circle_outline),
                        onTap: () => Navigator.pop(context, option)),
                ])));
      }
      if (choice == null || !mounted) return;
      final expanded =
          await resolver.expand(choice).timeout(const Duration(seconds: 45));
      if (!mounted) return;
      final playable = expanded.first;
      if (download) {
        if (!playable.direct) {
          throw StateError(
              'Esta fonte fornece apenas um player externo e não disponibiliza arquivo para download.');
        }
        await downloadMedia(context, playable.media(widget.item));
        return;
      }
      final next = nextChapter(episodes, url);
      Future<void> advance(bool fullscreen) => _watchSource(chapterUrl(next!),
          auto: true, replaceCurrent: true, startFullscreen: fullscreen);
      final media = playable.media(widget.item);
      if (playable.direct) {
        try {
          await ContinueWatching().save(widget.item, source, url, media.id);
        } catch (_) {
          // A history storage failure must not stop playback.
        }
      }
      if (!playable.direct && startFullscreen) {
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        await SystemChrome.setPreferredOrientations([]);
      }
      if (!mounted) return;
      final route = MaterialPageRoute<void>(
          builder: (_) => playable.direct
              ? PlayerPage(media: media, initialFullscreen: startFullscreen,
                  onNext: next == null ? null : advance)
              : SourcePage(title: widget.item.title, url: playable.url,
                  headers: playable.headers, embedded: true,
                  onNext: next == null ? null : () => advance(false)));
      if (replaceCurrent) {
        Navigator.of(context).pushReplacement(route);
      } else {
        Navigator.push(context, route);
      }
    } catch (exception) {
      if (mounted) {
        setState(() => playbackError =
            'Não foi possível localizar a reprodução nesta fonte. ${exception is StateError ? exception.message : exception is TimeoutException ? 'A fonte demorou a responder.' : 'A fonte retornou uma resposta incompatível.'}');
      }
      if (replaceCurrent) rethrow;
    } finally {
      resolver.close();
      if (identical(activeResolver, resolver)) activeResolver = null;
      if (mounted) setState(() => resolving = false);
    }
  }

  @override
  void dispose() {
    activeResolver?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: Text(widget.item.title), actions: [
        if (widget.item.kind != 'movie' && selected != null)
          IconButton(
              tooltip: following
                  ? 'Parar de acompanhar capítulos'
                  : 'Acompanhar capítulos',
              icon: Icon(following
                  ? Icons.notifications_active
                  : Icons.notifications_outlined),
              onPressed: () async {
                try {
                  final value = await CatalogNotices.instance
                      .toggle(widget.item, selected!, episodes);
                  if (mounted) setState(() => following = value);
                } catch (_) {
                  if (context.mounted)
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text(
                            'Não foi possível acompanhar este título. Limite de 10 títulos.')));
                }
              })
      ]),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        SizedBox(
            height: 260,
            child: Center(
                child: SizedBox(width: 180, child: Cover(item: widget.item)))),
        const SizedBox(height: 20),
        Text(widget.item.title,
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
        Text(
            '${widget.item.typeLabel}${widget.item.year > 0 ? ' · ${widget.item.year}' : ''}',
            style: const TextStyle(color: Colors.white60)),
        const SizedBox(height: 16),
        Wrap(spacing: 8, children: [
          for (final s in widget.item.sources)
            ChoiceChip(
                label: Text(s.label),
                selected: s == selected,
                onSelected: loading || resolving
                    ? null
                    : (_) {
                        setState(() => selected = s);
                        if (widget.item.kind != 'movie' && selected != null) {
                          _episodes();
                        }
                      })
        ]),
        const SizedBox(height: 12),
        if (widget.item.streamUrl?.isNotEmpty == true)
          FilledButton.icon(
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                      builder: (_) => PlayerPage(media: widget.item))),
              icon: const Icon(Icons.play_arrow),
              label: const Text('Assistir no CINESHOW')),
        if (widget.item.streamUrl?.isNotEmpty != true && selected != null)
          FilledButton.icon(
              onPressed:
                  resolving ? null : () => _watchSource(selected!.pageUrl),
              icon: const Icon(Icons.play_arrow),
              label:
                  Text(resolving ? 'Localizando vídeo...' : 'Assistir no app')),
        if (selected != null && widget.item.streamUrl?.isNotEmpty != true)
          OutlinedButton.icon(
              onPressed: resolving
                  ? null
                  : () => _watchSource(selected!.pageUrl, download: true),
              icon: const Icon(Icons.download_outlined),
              label: Text(widget.item.kind == 'movie'
                  ? 'Baixar filme'
                  : 'Baixar capítulo')),
        if (widget.item.streamUrl?.isNotEmpty == true)
          OutlinedButton.icon(
              onPressed: () => downloadMedia(context, widget.item),
              icon: const Icon(Icons.download_outlined),
              label: const Text('Baixar vídeo')),
        if (resolving) const LinearProgressIndicator(),
        if (playbackError != null)
          Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(playbackError!)),
        if (selected != null)
          OutlinedButton.icon(
              onPressed: () => _open(selected!.pageUrl),
              icon: const Icon(Icons.open_in_new),
              label: const Text('Abrir na fonte')),
        OutlinedButton.icon(
            onPressed: () {
              widget.onFavorite();
              setState(() => favorite = !favorite);
            },
            icon: Icon(favorite ? Icons.bookmark : Icons.bookmark_border),
            label:
                Text(favorite ? 'Na minha lista' : 'Adicionar à minha lista')),
        if (widget.item.description.isNotEmpty) Text(widget.item.description),
        if (widget.item.kind != 'movie' && selected != null) ...[
          const SizedBox(height: 20),
          Row(children: [
            const Expanded(
                child: Text('Capítulos e episódios',
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
            IconButton(
                onPressed: loading ? null : _episodes,
                icon: const Icon(Icons.refresh))
          ]),
          if (loading)
            const Center(
                child: Padding(
                    padding: EdgeInsets.all(20),
                    child: CircularProgressIndicator())),
          if (error != null)
            Text(error!, style: const TextStyle(color: Colors.white60)),
          if (!loading && error == null && episodes.isEmpty)
            const Text('Consulte a lista completa na fonte original.'),
          for (final e in episodes)
            ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(e['title'] as String),
                trailing: PopupMenuButton<String>(
                    tooltip: 'Opções do capítulo',
                    onSelected: (action) => _watchSource(
                        (e['page_url'] as String?) ??
                            (e['player_path'] as String?) ??
                            selected!.pageUrl,
                        download: action == 'download'),
                    itemBuilder: (_) => const [
                          PopupMenuItem(value: 'play', child: Text('Assistir')),
                          PopupMenuItem(
                              value: 'download', child: Text('Baixar capítulo'))
                        ]),
                onTap: () => _watchSource((e['page_url'] as String?) ??
                    (e['player_path'] as String?) ??
                    selected!.pageUrl))
        ]
      ]));
}

class SearchPage extends StatefulWidget {
  const SearchPage({super.key, required this.catalog, required this.onOpen});
  final LiveCatalog catalog;
  final void Function(MediaItem) onOpen;
  @override
  State<SearchPage> createState() => _SearchState();
}

class _SearchState extends State<SearchPage> {
  Timer? timer;
  int request = 0;
  List<MediaItem> items = [];
  bool loading = false;
  String? error;
  void _query(String q) {
    timer?.cancel();
    final generation = ++request;
    if (q.trim().length < 2) {
      setState(() {
        items = [];
        loading = false;
        error = null;
      });
      return;
    }
    timer = Timer(const Duration(milliseconds: 400), () async {
      if (!mounted) return;
      setState(() {
        loading = true;
        error = null;
      });
      try {
        final r = await widget.catalog.refresh(query: q.trim());
        if (mounted && generation == request) {
          setState(() {
            items = r.items;
            loading = false;
            if (r.errors.isNotEmpty) error = 'Algumas fontes não responderam.';
          });
        }
      } catch (_) {
        if (mounted && generation == request) {
          setState(() {
            loading = false;
            error = 'Não foi possível buscar agora.';
          });
        }
      }
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Buscar')),
      body: Column(children: [
        Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
                autofocus: true,
                onChanged: _query,
                decoration: const InputDecoration(
                    hintText: 'Filmes, séries e novelas',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder()))),
        if (loading) const LinearProgressIndicator(),
        if (error != null)
          Padding(padding: const EdgeInsets.all(12), child: Text(error!)),
        Expanded(
            child: ListView.builder(
                itemCount: items.length,
                itemBuilder: (_, i) => ListTile(
                    title: Text(items[i].title),
                    subtitle: Text(
                        '${items[i].typeLabel} · ${items[i].sources.length} fonte(s)'),
                    onTap: () => widget.onOpen(items[i]))))
      ]));
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsState();
}

class _SettingsState extends State<SettingsPage> with WidgetsBindingObserver {
  final updater = AppUpdates();
  String version = '';
  String message = '';
  String updateState = 'idle';
  bool checking = false;
  bool installing = false;
  bool foreground = true;
  bool polling = false;
  bool autoInstall = true;
  int downloaded = 0;
  int total = 0;
  UpdateRelease? available;
  Timer? progressTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    PackageInfo.fromPlatform().then((p) {
      if (mounted) setState(() => version = '${p.version} (${p.buildNumber})');
    }).catchError((Object _) {});
    _poll();
    progressTimer = Timer.periodic(const Duration(seconds: 1), (_) => _poll());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    progressTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (foreground) _poll();
  }

  Future<void> _poll() async {
    if (polling || !foreground) return;
    polling = true;
    try {
      final status = await updater.status();
      if (!mounted) return;
      final next = status['state'] as String? ?? 'idle';
      if (next != updateState || next == 'downloading' || next == 'paused') {
        setState(() {
          updateState = next;
          downloaded = (status['bytes'] as num? ?? 0).toInt();
          total = (status['total'] as num? ?? 0).toInt();
          if (next == 'failed') {
            message = 'Download interrompido. Tente novamente.';
          }
          if (next == 'ready') {
            message = 'Download concluído. Pronto para instalar.';
          }
        });
      }
      if (next == 'ready' && autoInstall && !installing && foreground) {
        autoInstall = false;
        await _install();
      }
    } catch (_) {
      // The native updater is only available in the Android build.
    } finally {
      polling = false;
    }
  }

  Future<void> _updates() async {
    setState(() {
      checking = true;
      message = '';
    });
    final client = http.Client();
    try {
      final response = await client.get(
          Uri.parse(
              'https://api.github.com/repos/bichocutela/CINESHOW/releases/latest'),
          headers: {
            'Accept': 'application/vnd.github+json'
          }).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) throw StateError('Sem release');
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final current = await PackageInfo.fromPlatform();
      final tag = json['tag_name'] as String;
      final newer = UpdateRelease.isNewer(tag, current.version);
      final release = UpdateRelease.fromGitHub(json);
      if (!mounted) return;
      setState(() {
        available = newer ? release : null;
        message = !newer
            ? 'Você está na versão mais recente publicada.'
            : release == null
                ? 'A nova versão está sendo preparada. Tente novamente em alguns minutos.'
                : 'Nova versão disponível: ${release.version}';
      });
    } catch (_) {
      if (mounted) {
        setState(() =>
            message = 'Não foi possível consultar as atualizações agora.');
      }
    } finally {
      client.close();
      if (mounted) setState(() => checking = false);
    }
  }

  Future<void> _download() async {
    final release = available;
    if (release == null) return;
    setState(() {
      checking = true;
      message = 'Iniciando download...';
    });
    try {
      await updater.start(release);
      autoInstall = true;
      if (mounted) {
        setState(() {
          updateState = 'downloading';
          downloaded = 0;
          total = 0;
        });
      }
      await _poll();
    } catch (_) {
      if (mounted) {
        setState(() =>
            message = 'Não foi possível iniciar o download. Tente novamente.');
      }
    } finally {
      if (mounted) setState(() => checking = false);
    }
  }

  Future<void> _cancel() async {
    autoInstall = false;
    try {
      await updater.cancel();
      if (mounted) {
        setState(() {
          updateState = 'idle';
          message = 'Download cancelado e arquivo removido.';
        });
      }
    } catch (_) {
      if (mounted) setState(() => message = 'Não foi possível cancelar agora.');
    }
  }

  Future<void> _install() async {
    setState(() {
      installing = true;
      message = 'Verificando o APK...';
    });
    try {
      final state = await updater.install();
      if (mounted) {
        setState(() => message = state == 'permission'
            ? 'Autorize o CINESHOW a instalar atualizações. Ao voltar, o instalador será aberto.'
            : 'Confirme a instalação no Android. O APK será removido após a atualização.');
      }
    } on PlatformException catch (error) {
      if (mounted) {
        setState(() =>
            message = error.message ?? 'Não foi possível abrir o instalador.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => message = 'Não foi possível abrir o instalador.');
      }
    } finally {
      if (mounted) setState(() => installing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final downloading = updateState == 'downloading' || updateState == 'paused';
    final fraction =
        total > 0 ? (downloaded / total).clamp(0.0, 1.0).toDouble() : null;
    String megabytes(int bytes) => (bytes / 1048576).toStringAsFixed(1);
    return ListView(padding: const EdgeInsets.all(24), children: [
      const Text('CINESHOW',
          style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900)),
      Text('Versão $version'),
      const SizedBox(height: 24),
      const Text(
          'Catálogo de filmes, séries e novelas. Puxe o início para atualizar. Os vídeos abrem na fonte original.'),
      const SizedBox(height: 24),
      OutlinedButton.icon(
          onPressed: () => Navigator.push(context,
              MaterialPageRoute<void>(builder: (_) => const DownloadsPage())),
          icon: const Icon(Icons.download_outlined),
          label: const Text('Meus downloads')),
      FilledButton.icon(
          onPressed: checking || downloading || installing ? null : _updates,
          icon: const Icon(Icons.system_update),
          label: Text(checking ? 'Consultando...' : 'Verificar atualização')),
      if (available != null && !downloading && updateState != 'ready')
        FilledButton.icon(
            onPressed: checking ? null : _download,
            icon: const Icon(Icons.download),
            label: Text('Baixar versão ${available!.version}')),
      if (downloading) ...[
        const SizedBox(height: 16),
        LinearProgressIndicator(value: fraction),
        const SizedBox(height: 8),
        Text(updateState == 'paused'
            ? 'Aguardando conexão...'
            : fraction == null
                ? 'Baixando: ${megabytes(downloaded)} MB'
                : '${(fraction * 100).toStringAsFixed(0)}% · ${megabytes(downloaded)} / ${megabytes(total)} MB'),
        TextButton(onPressed: _cancel, child: const Text('Cancelar download')),
      ],
      if (updateState == 'ready') ...[
        FilledButton.icon(
            onPressed: installing ? null : _install,
            icon: const Icon(Icons.install_mobile),
            label:
                Text(installing ? 'Verificando...' : 'Instalar atualização')),
        TextButton(
            onPressed: installing ? null : _cancel,
            child: const Text('Excluir APK baixado')),
      ],
      if (message.isNotEmpty)
        Padding(padding: const EdgeInsets.only(top: 16), child: Text(message)),
    ]);
  }
}
