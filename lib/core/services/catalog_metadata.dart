import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/media_item.dart';
import 'live_catalog.dart';
import 'video_sources.dart';

class CatalogMetadata {
  int _generation = 0;
  void cancel() {
    _generation++;
  }

  static const cacheKey = 'cineshow.metadata.v1';
  static Map<String, dynamic> parse(String page, String pageUrl) {
    final genres = <String>{};
    String? poster;
    final group = RegExp(
      r'''<div\b[^>]*class=["'][^"']*\bsgeneros\b[^"']*["'][^>]*>(.*?)</div>''',
      dotAll: true,
    ).firstMatch(page);
    if (group != null) {
      for (final link in RegExp(
        r'<a\b[^>]*>(.*?)</a>',
        dotAll: true,
      ).allMatches(group[1]!)) {
        final name = plain(link[1]!);
        if (name.isNotEmpty &&
            !RegExp(r'stream$', caseSensitive: false).hasMatch(name)) {
          genres.add(name);
        }
      }
    }
    final image = RegExp(
      r'''<div\b[^>]*class=["'][^"']*\bposter\b[^"']*["'][^>]*>(.*?)</div>''',
      dotAll: true,
    ).firstMatch(page);
    if (image != null) {
      final tag = RegExp(r'<img\b[^>]*>').firstMatch(image[1]!);
      if (tag != null) {
        final a = attributes(tag[0]!);
        final url = a['data-src'] ?? a['src'];
        if (url != null) poster = VideoSources.safeUrl(url, pageUrl);
      }
    }
    if (Uri.parse(pageUrl).host == 'www.xonados.com' &&
        Uri.parse(pageUrl).path.startsWith('/@novela/')) {
      for (final tag in RegExp(r'<meta\b[^>]*>').allMatches(page)) {
        final a = attributes(tag[0]!);
        if (a['property'] == 'og:image' && a['content'] != null) {
          poster ??= VideoSources.safeUrl(a['content']!, pageUrl);
        }
      }
    }
    for (final script in RegExp(
      r'''<script[^>]*type=["']application/ld\+json["'][^>]*>(.*?)</script>''',
      dotAll: true,
    ).allMatches(page)) {
      try {
        final raw = jsonDecode(script[1]!);
        final entries = raw is List
            ? raw
            : raw is Map && raw['@graph'] is List
                ? raw['@graph'] as List
                : [raw];
        for (final entry in entries) {
          if (entry is! Map ||
              !['Movie', 'TVSeries', 'TVEpisode'].contains(entry['@type'])) {
            continue;
          }
          final genre = entry['genre'];
          for (final name in genre is List
              ? genre
              : genre is String
                  ? [genre]
                  : []) {
            if (name is String && name.trim().isNotEmpty) {
              genres.add(name.trim());
            }
          }
          final img = entry['image'];
          final url = img is String
              ? img
              : img is Map
                  ? img['url']
                  : img is List && img.isNotEmpty
                      ? img.first
                      : null;
          if (url is String) poster ??= VideoSources.safeUrl(url, pageUrl);
        }
      } catch (_) {
        /* Other schema types and invalid data are ignored. */
      }
    }
    return {
      'genre': genres.join(', '),
      if (poster != null) 'poster_url': poster,
    };
  }

  Future<List<MediaItem>> cached(List<MediaItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    Map<String, dynamic> data;
    try {
      data =
          jsonDecode(prefs.getString(cacheKey) ?? '{}') as Map<String, dynamic>;
    } catch (_) {
      data = {};
    }
    return items.map((item) => _apply(item, data[item.id])).toList();
  }

  MediaItem _apply(MediaItem item, dynamic entry) {
    if (entry is! Map) return item;
    final genre = entry['genre'] as String?;
    return item.copyWith(
      genre: genre != null && genre.isNotEmpty ? genre : null,
      posterUrl: entry['poster_url'] as String? ?? item.posterUrl,
    );
  }

  Future<void> enrich(
    List<MediaItem> items,
    void Function(MediaItem) onItem,
  ) async {
    final generation = ++_generation;
    final prefs = await SharedPreferences.getInstance();
    Map<String, dynamic> data;
    try {
      data =
          jsonDecode(prefs.getString(cacheKey) ?? '{}') as Map<String, dynamic>;
    } catch (_) {
      data = {};
    }
    var cursor = 0;
    Future<void> worker() async {
      while (cursor < items.length && generation == _generation) {
        final item = items[cursor++];
        final previous = data[item.id];
        final time = previous is Map ? previous['checked'] as int? ?? 0 : 0;
        if (DateTime.now().millisecondsSinceEpoch - time <
            const Duration(days: 1).inMilliseconds) {
          onItem(_apply(item, previous));
          continue;
        }
        final combined = <String, dynamic>{};
        var fetched = false;
        for (final source in item.sources) {
          if (!providerPage(source.provider, source.pageUrl)) {
            continue;
          }
          final session = SourceSession(Uri.parse(source.pageUrl).origin);
          try {
            final page = await session.get(source.pageUrl);
            fetched = true;
            final metadata = parse(page, source.pageUrl);
            if ((metadata['genre'] as String).isNotEmpty) {
              combined['genre'] = metadata['genre'];
            }
            combined['poster_url'] ??= metadata['poster_url'];
            if (combined['genre'] != null &&
                (item.posterUrl != null || combined['poster_url'] != null)) {
              break;
            }
          } catch (_) {
            /* Try the other source for this title. */
          } finally {
            session.close();
          }
        }
        if (fetched) {
          data[item.id] = {
            ...combined,
            'checked': DateTime.now().millisecondsSinceEpoch,
          };
        }
        onItem(_apply(item, combined));
        if (cursor % 20 == 0 && generation == _generation) {
          await prefs.setString(cacheKey, jsonEncode(data));
        }
      }
    }

    await Future.wait([worker(), worker(), worker()]);
    if (generation == _generation) {
      await prefs.setString(cacheKey, jsonEncode(data));
    }
  }
}
