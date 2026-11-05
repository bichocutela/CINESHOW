import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/media_item.dart';

class ActorCatalog {
  static const key = 'cineshow.actor.catalog.v1';
  String normalize(String name) => name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  Future<void> record(MediaItem item, List<String> actors) async {
    if (actors.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    Map<String, dynamic> all;
    try { all = Map<String, dynamic>.from(jsonDecode(prefs.getString(key) ?? '{}') as Map); }
    catch (_) { all = {}; }
    all[item.id] = {'item': item.toJson(), 'actors': actors.map(normalize).toSet().toList()};
    await prefs.setString(key, jsonEncode(all));
  }
  Future<List<MediaItem>> titles(String actor) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final all = jsonDecode(prefs.getString(key) ?? '{}') as Map;
      return all.values.whereType<Map>().where((v) =>
          ((v['actors'] as List?) ?? []).contains(normalize(actor)))
          .map((v) => MediaItem.fromJson(Map<String, dynamic>.from(v['item'] as Map))).toList()
          ..sort((a, b) => b.year.compareTo(a.year));
    } catch (_) { return []; }
  }
}
