import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/media_item.dart';
import 'playback_gateway.dart';

class ContinueEntry {
  ContinueEntry(this.item, this.source, this.pageUrl, this.position,
      {this.playerLabel});
  final String? playerLabel;
  final MediaItem item;
  final MediaSource source;
  final String pageUrl;
  final PlaybackPosition position;
}

class ContinueWatching {
  static Future<void> _pending = Future.value();
  static const key = 'cineshow.continue.entries.v1';
  Future<void> save(
      MediaItem item, MediaSource source, String pageUrl, String playbackId,
      {String? playerLabel}) {
    final result = _pending
        .catchError((Object _) {})
        .then((_) => _save(item, source, pageUrl, playbackId, playerLabel));
    _pending = result;
    return result;
  }

  Future<void> _save(MediaItem item, MediaSource source, String pageUrl,
      String playbackId, String? playerLabel) async {
    final prefs = await SharedPreferences.getInstance();
    final rows = <Map<String, dynamic>>[];
    try {
      rows.addAll((jsonDecode(prefs.getString(key) ?? '[]') as List)
          .whereType<Map>()
          .map((v) => Map<String, dynamic>.from(v))
          .where(
              (v) => v['item'] is Map && (v['item'] as Map)['id'] != item.id));
    } catch (_) {
      /* A damaged entry must not prevent saving the current video. */
    }
    var page = pageUrl;
    if (source.provider == 'xonados') {
      final date = Uri.parse(pageUrl).queryParameters['date'];
      page = Uri.parse(source.pageUrl).replace(
          queryParameters: {if (date != null) 'date': date}).toString();
    }
    rows.insert(0, {
      'item': item.toJson(),
      'source': source.toJson(),
      'page': page,
      'playbackId': playbackId,
      if (playerLabel != null) 'playerLabel': playerLabel
    });
    await prefs.setString(key, jsonEncode(rows.take(30).toList()));
  }

  Future<List<ContinueEntry>> list() async {
    await _pending.catchError((Object _) {});
    final prefs = await SharedPreferences.getInstance();
    final positions = {
      for (final p in await PersistentPlaybackGateway().loadContinueWatching())
        p.mediaId: p
    };
    final result = <ContinueEntry>[];
    try {
      for (final row in (jsonDecode(prefs.getString(key) ?? '[]')) as List) {
        if (row is! Map) continue;
        try {
          final position = positions[row['playbackId']];
          if (position == null) continue;
          result.add(ContinueEntry(
              MediaItem.fromJson(Map<String, dynamic>.from(row['item'] as Map)),
              MediaSource.fromJson(
                  Map<String, dynamic>.from(row['source'] as Map)),
              row['page'] as String,
              position,
              playerLabel: row['playerLabel'] as String?));
        } catch (_) {/* Continue reading the remaining valid titles. */}
      }
    } catch (_) {
      /* Invalid JSON is an empty history, not a playback failure. */
    }
    return result;
  }
}
