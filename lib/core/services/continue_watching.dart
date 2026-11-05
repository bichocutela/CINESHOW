import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/media_item.dart';
import 'playback_gateway.dart';

class ContinueEntry {
  ContinueEntry(this.item, this.source, this.pageUrl, this.position);
  final MediaItem item;
  final MediaSource source;
  final String pageUrl;
  final PlaybackPosition position;
}

class ContinueWatching {
  static const key = 'cineshow.continue.entries.v1';
  Future<void> save(MediaItem item, MediaSource source,
      String pageUrl, String playbackId) async {
    final prefs = await SharedPreferences.getInstance();
    final rows = ((jsonDecode(prefs.getString(key) ?? '[]')) as List)
        .map((v) => Map<String, dynamic>.from(v as Map)).toList();
    rows.removeWhere((v) => (v['item'] as Map)['id'] == item.id);
    var page = pageUrl;
    if (source.provider == 'xonados') {
      final date = Uri.parse(pageUrl).queryParameters['date'];
      page = Uri.parse(source.pageUrl).replace(queryParameters: {
        if (date != null) 'date': date
      }).toString();
    }
    rows.insert(0, {'item': item.toJson(), 'source': source.toJson(),
      'page': page, 'playbackId': playbackId});
    await prefs.setString(key, jsonEncode(rows.take(30).toList()));
  }

  Future<List<ContinueEntry>> list() async {
    final prefs = await SharedPreferences.getInstance();
    final positions = {for (final p in await PersistentPlaybackGateway().loadContinueWatching()) p.mediaId: p};
    final result = <ContinueEntry>[];
    try {
      for (final row in (jsonDecode(prefs.getString(key) ?? '[]')) as List) {
        final position = positions[row['playbackId']];
        if (position == null) continue;
        result.add(ContinueEntry(
            MediaItem.fromJson(Map<String, dynamic>.from(row['item'] as Map)),
            MediaSource.fromJson(Map<String, dynamic>.from(row['source'] as Map)),
            row['page'] as String, position));
      }
    } catch (_) { return []; }
    return result;
  }
}
