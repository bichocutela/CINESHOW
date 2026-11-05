import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/media_item.dart';

String legacyMediaId(MediaItem item) =>
    '${item.kind}:${item.title.toLowerCase().trim()}:${item.year}';

bool sameCatalogItem(MediaItem a, MediaItem b) =>
    a.kind == b.kind &&
    (a.id == b.id ||
        legacyMediaId(a) == legacyMediaId(b) ||
        a.sources.any((left) => b.sources.any((right) =>
            left.provider == right.provider &&
            left.sourceId == right.sourceId)));

class FavoriteState {
  const FavoriteState(this.ids, this.items);
  final Set<String> ids;
  final List<MediaItem> items;
  bool contains(MediaItem item) =>
      ids.contains(item.id) ||
      ids.contains(legacyMediaId(item)) ||
      items.any((saved) => sameCatalogItem(saved, item));
}

/// Save the complete item: search/actor/anime favorites need not be on Home.
class Favorites {
  static const key = 'cineshow.favorites.v2';
  static Future<void> _pending = Future.value();

  Future<FavoriteState> _read() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = (prefs.getStringList('favorites') ?? []).toSet();
    final items = <MediaItem>[];
    try {
      final raw = jsonDecode(prefs.getString(key) ?? '[]') as List;
      for (final row in raw.whereType<Map>()) {
        try {
          items.add(MediaItem.fromJson(Map<String, dynamic>.from(row)));
        } catch (_) {/* One invalid saved item must not erase the others. */}
      }
    } catch (_) {
      /* Preserve legacy IDs even if the newer snapshot is invalid. */
    }
    ids.addAll(items.map((v) => v.id));
    return FavoriteState(ids, items);
  }

  Future<void> _write(FavoriteState state) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        key, jsonEncode(state.items.map((v) => v.toJson()).toList()));
    await prefs.setStringList('favorites', state.ids.toList());
  }

  Future<FavoriteState> _serial(Future<FavoriteState> Function() operation) {
    final result = _pending.catchError((Object _) {}).then((_) => operation());
    _pending =
        result.then<void>((_) {}, onError: (Object _, StackTrace stack) {});
    return result;
  }

  Future<FavoriteState> load({Iterable<MediaItem> known = const []}) =>
      _serial(() async {
        final old = await _read();
        final items = [...old.items];
        final ids = {...old.ids};
        for (final item in known) {
          if (!old.contains(item)) continue;
          final previous =
              items.where((saved) => sameCatalogItem(saved, item)).toList();
          for (final saved in previous) {
            ids.remove(saved.id);
            ids.remove(legacyMediaId(saved));
          }
          items.removeWhere((saved) => sameCatalogItem(saved, item));
          items.add(item);
          ids.remove(legacyMediaId(item));
          ids.add(item.id);
        }
        final next = FavoriteState(ids, items);
        await _write(next);
        return next;
      });

  Future<FavoriteState> toggle(MediaItem item) => _serial(() async {
        final old = await _read();
        final ids = {...old.ids};
        final items = [...old.items];
        final selected = old.contains(item);
        for (final previous in items.where((v) => sameCatalogItem(v, item))) {
          ids.remove(previous.id);
          ids.remove(legacyMediaId(previous));
        }
        items.removeWhere((v) => sameCatalogItem(v, item));
        ids.remove(item.id);
        ids.remove(legacyMediaId(item));
        if (!selected) {
          ids.add(item.id);
          items.add(item);
        }
        final next = FavoriteState(ids, items);
        await _write(next);
        return next;
      });
}
