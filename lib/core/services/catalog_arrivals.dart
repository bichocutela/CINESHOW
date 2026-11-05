import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/media_item.dart';

class CatalogArrivals {
  static const key = 'cineshow.arrivals.v1';
  Future<List<MediaItem>> recordAndSort(List<MediaItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    Map<String, dynamic> data;
    try { data = Map<String, dynamic>.from(jsonDecode(prefs.getString(key) ?? '{}') as Map); }
    catch (_) { data = {}; }
    final now = DateTime.now().millisecondsSinceEpoch;
    for (var i = 0; i < items.length; i++) {
      data.putIfAbsent(items[i].id, () => now - i);
    }
    await prefs.setString(key, jsonEncode(data));
    return [...items]..sort((a, b) => (data[b.id] as num).compareTo(data[a.id] as num));
  }
}
