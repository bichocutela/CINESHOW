import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/media_item.dart';
import 'live_catalog.dart';
import 'source_origins.dart';

String actorSlug(String name) {
  var slug = name.trim().toLowerCase();
  const accents = 'áàâãäåéèêëíìîïóòôõöúùûüçñ';
  const ascii = 'aaaaaaeeeeiiiiooooouuuucn';
  for (var i = 0; i < accents.length; i++) {
    slug = slug.replaceAll(accents[i], ascii[i]);
  }
  return slug
      .replaceAll(RegExp(r"['’]"), '')
      .replaceAll(RegExp(r'[^a-z0-9\u00c0-\uffff]+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
}

List<MediaItem> parseActorArchive(String html, String name, String provider) {
  final heading =
      RegExp(r'<h1\b[^>]*>(.*?)</h1>', dotAll: true).firstMatch(html);
  if (heading == null || actorSlug(plain(heading[1]!)) != actorSlug(name)) {
    throw StateError('A fonte não confirmou o nome do ator.');
  }
  final section = html
      .substring(heading.end)
      .split(RegExp(
          r'''<(?:div|aside)\b[^>]*(?:class=["'][^"']*\bsidebar\b|id=["']sidebar)'''))
      .first;
  if (!section.contains('<article')) return [];
  return LiveCatalog().parseProviderCards(section, provider);
}

class ActorSearchResult {
  const ActorSearchResult(this.items, this.hasMore, this.errors);
  final List<MediaItem> items;
  final bool hasMore;
  final List<String> errors;
}

class ActorCatalog {
  ActorCatalog({SourceSession Function(String)? sessionFactory})
      : sessionFactory = sessionFactory ?? SourceSession.new;
  final SourceSession Function(String) sessionFactory;
  static const key = 'cineshow.actor.catalog.v1';
  final _pages = <String, int>{};
  final _paths = <String, String>{};
  final _ended = <String>{};
  List<MediaItem> _items = [];
  String _actor = '';
  String normalize(String name) =>
      name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  Future<void> record(MediaItem item, List<String> actors) async {
    if (actors.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    Map<String, dynamic> all;
    try {
      all = Map<String, dynamic>.from(
          jsonDecode(prefs.getString(key) ?? '{}') as Map);
    } catch (_) {
      all = {};
    }
    all[item.id] = {
      'item': item.toJson(),
      'actors': actors.map(normalize).toSet().toList()
    };
    await prefs.setString(key, jsonEncode(all));
  }

  Future<List<MediaItem>> titles(String actor) async {
    final prefs = await SharedPreferences.getInstance();
    final items = <MediaItem>[];
    try {
      final all = jsonDecode(prefs.getString(key) ?? '{}') as Map;
      items.addAll(all.values
          .whereType<Map>()
          .where(
              (v) => ((v['actors'] as List?) ?? []).contains(normalize(actor)))
          .map((v) =>
              MediaItem.fromJson(Map<String, dynamic>.from(v['item'] as Map))));
      final found = jsonDecode(
          prefs.getString('cineshow.actor.search.v1:${normalize(actor)}') ??
              '[]') as List;
      items.addAll(found
          .whereType<Map>()
          .map((v) => MediaItem.fromJson(Map<String, dynamic>.from(v))));
    } catch (_) {/* A missing index does not prevent a live search. */}
    return LiveCatalog().mergeItems(items)
      ..sort((a, b) => b.year.compareTo(a.year));
  }

  Future<ActorSearchResult> search(String name,
      {bool reset = false, List<String> archiveUrls = const []}) async {
    if (reset || _paths.isEmpty || _actor != normalize(name)) {
      _actor = normalize(name);
      _pages.clear();
      _paths.clear();
      _ended.clear();
      _items = await titles(name);
      for (final value in archiveUrls) {
        final uri = Uri.tryParse(canonicalSourceUrl(value));
        if (uri == null || uri.scheme != 'https' || uri.userInfo.isNotEmpty) {
          continue;
        }
        final provider = origins.entries
            .where((v) => v.value == uri.origin)
            .firstOrNull
            ?.key;
        if (!['rtfilmes', 'tontons', 'amyflix'].contains(provider) ||
            !RegExp(r'^/(?:melhores-elenco|cast|elenco|atores)/[^/]+/?$')
                .hasMatch(uri.path)) {
          continue;
        }
        _paths.putIfAbsent(
            provider!, () => '${uri.path.replaceFirst(RegExp(r'/$'), '')}/');
      }
      final slug = actorSlug(name);
      if (slug.isNotEmpty) {
        for (final provider in ['rtfilmes', 'tontons']) {
          _paths.putIfAbsent(
              provider, () => '/melhores-elenco/${Uri.encodeComponent(slug)}/');
        }
      }
    }
    final errors = <String>[];
    final batches = await Future.wait(_paths.entries.map((entry) async {
      if (_ended.contains(entry.key)) return <MediaItem>[];
      final session = sessionFactory(origins[entry.key]!);
      final page = _pages[entry.key] ?? 1;
      try {
        final html = await session
            .get('${entry.value}${page == 1 ? '' : 'page/$page/'}');
        final rows = parseActorArchive(html, name, entry.key);
        _pages[entry.key] = page + 1;
        if (!html.contains('${entry.value}page/${page + 1}/')) {
          _ended.add(entry.key);
        }
        return rows;
      } catch (_) {
        errors.add(entry.key);
        return <MediaItem>[];
      } finally {
        session.close();
      }
    }));
    _items = LiveCatalog().mergeItems([..._items, ...batches.expand((v) => v)])
      ..sort((a, b) => b.year.compareTo(a.year));
    if (batches.any((v) => v.isNotEmpty)) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cineshow.actor.search.v1:${normalize(name)}',
          jsonEncode(_items.map((v) => v.toJson()).toList()));
    }
    return ActorSearchResult(
        _items, _ended.length < _paths.length, errors.toSet().toList());
  }
}
