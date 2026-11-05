import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/media_item.dart';

class CatalogNotices {
  static final instance = CatalogNotices();
  static Future<void> _pending = Future.value();
  Future<T> _transaction<T>(Future<T> Function() operation) {
    final result = _pending.catchError((Object _) {}).then((_) => operation());
    _pending =
        result.then<void>((_) {}, onError: (Object _, StackTrace stack) {});
    return result;
  }

  final unread = ValueNotifier<int>(0);
  static const _events = 'cineshow.notices.v1';
  static const _seen = 'cineshow.notices.catalog.v1';
  static const _watch = 'cineshow.notices.watch.v1';

  Future<List<Map<String, dynamic>>> events() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      return ((jsonDecode(prefs.getString(_events) ?? '[]')) as List)
          .whereType<Map>()
          .map((v) => Map<String, dynamic>.from(v as Map))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> refreshBadge() async {
    unread.value = (await events()).where((v) => v['read'] != true).length;
  }

  Future<void> markRead() => _transaction(_markRead);
  Future<void> _markRead() async {
    final rows = await events();
    for (final row in rows) {
      row['read'] = true;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_events, jsonEncode(rows));
    unread.value = 0;
  }

  Future<void> _add(List<Map<String, dynamic>> next) async {
    if (next.isEmpty) return;
    final rows = await events();
    final ids = rows.map((v) => v['id']).toSet();
    final merged = [...next.where((v) => !ids.contains(v['id'])), ...rows]
        .take(100)
        .toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_events, jsonEncode(merged));
    await refreshBadge();
  }

  Future<void> syncCatalog(List<MediaItem> items) =>
      _transaction(() => _syncCatalog(items));
  Future<void> _syncCatalog(List<MediaItem> items) async {
    if (items.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_seen);
    final seen = (stored ?? []).toSet();
    final next = <Map<String, dynamic>>[];
    if (stored != null) {
      for (final item in items) {
        if (!seen.contains(item.id)) {
          next.add({
            'id': 'catalog:${item.id}',
            'title': item.title,
            'body':
                'Novo no catálogo · ${item.typeLabel}${item.year > 0 ? ' · ${item.year}' : ''}',
            'item': item.toJson(),
            'created': DateTime.now().toIso8601String(),
            'read': false
          });
        }
      }
    }
    seen.addAll(items.map((v) => v.id));
    await prefs.setStringList(_seen, seen.toList());
    await _add(next);
  }

  Future<List<Map<String, dynamic>>> watched() async {
    final prefs = await SharedPreferences.getInstance();
    final rows = <Map<String, dynamic>>[];
    try {
      for (final raw in (jsonDecode(prefs.getString(_watch) ?? '[]') as List)
          .whereType<Map>()) {
        try {
          final item =
              MediaItem.fromJson(Map<String, dynamic>.from(raw['item'] as Map));
          final source = MediaSource.fromJson(
              Map<String, dynamic>.from(raw['source'] as Map));
          rows.add({'item': item.toJson(), 'source': source.toJson()});
        } catch (_) {/* Preserve the other followed titles. */}
      }
    } catch (_) {
      /* An invalid cache must not interrupt catalog synchronization. */
    }
    return rows;
  }

  Future<bool> isFollowing(String id) async =>
      (await watched()).any((v) => (v['item'] as Map)['id'] == id);

  String _chapterKey(MediaSource source) =>
      'cineshow.notices.chapters.${source.provider}:${source.sourceId}';

  Future<bool> toggle(MediaItem item, MediaSource source,
          List<Map<String, dynamic>> chapters) =>
      _transaction(() => _toggle(item, source, chapters));

  Future<bool> _toggle(MediaItem item, MediaSource source,
      List<Map<String, dynamic>> chapters) async {
    final rows = await watched();
    final existing =
        rows.where((v) => (v['item'] as Map)['id'] == item.id).toList();
    final prefs = await SharedPreferences.getInstance();
    if (existing.isNotEmpty) {
      rows.removeWhere((v) => (v['item'] as Map)['id'] == item.id);
    } else {
      if (rows.length >= 10) {
        throw StateError('Acompanhe até 10 títulos por vez.');
      }
      rows.add({'item': item.toJson(), 'source': source.toJson()});
      await prefs.remove(_chapterKey(source));
      if (chapters.isNotEmpty) {
        await prefs.setStringList(
            _chapterKey(source), chapters.map((e) => '${e['id']}').toList());
      }
    }
    await prefs.setString(_watch, jsonEncode(rows));
    return existing.isEmpty;
  }

  Future<void> syncChapters(MediaItem item, MediaSource source,
          List<Map<String, dynamic>> chapters) =>
      _transaction(() => _syncChapters(item, source, chapters));

  Future<void> _syncChapters(MediaItem item, MediaSource source,
      List<Map<String, dynamic>> chapters) async {
    if (chapters.isEmpty) return;
    final rows = await watched();
    if (!rows.any((v) =>
        (v['item'] as Map)['id'] == item.id &&
        (v['source'] as Map)['provider'] == source.provider &&
        (v['source'] as Map)['source_id'].toString() == source.sourceId)) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final key = _chapterKey(source);
    final stored = prefs.getStringList(key);
    final seen = (stored ?? []).toSet();
    final next = <Map<String, dynamic>>[];
    if (stored != null) {
      for (final chapter in chapters) {
        final id = '${chapter['id']}';
        if (seen.contains(id)) continue;
        next.add({
          'id': 'chapter:${source.provider}:${source.sourceId}:$id',
          'title': item.title,
          'body': '${source.label} · ${chapter['title']}',
          'item': item.toJson(),
          'created': DateTime.now().toIso8601String(),
          'read': false
        });
      }
    }
    seen.addAll(chapters.map((e) => '${e['id']}'));
    await prefs.setStringList(key, seen.toList());
    await _add(next);
  }
}
