import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/media_item.dart';

class PlaybackPosition {
  const PlaybackPosition(
      {required this.mediaId, required this.position, required this.duration});
  final String mediaId;
  final Duration position, duration;
  double get progress => duration.inMilliseconds == 0
      ? 0
      : (position.inMilliseconds / duration.inMilliseconds)
          .clamp(0.0, 1.0)
          .toDouble();
}

abstract interface class PlaybackGateway {
  Future<void> savePosition(PlaybackPosition position);
  Future<PlaybackPosition?> loadPosition(String mediaId);
  Future<List<PlaybackPosition>> loadContinueWatching();
}

class InMemoryPlaybackGateway implements PlaybackGateway {
  final Map<String, PlaybackPosition> _positions = {};
  @override
  Future<void> savePosition(PlaybackPosition p) async {
    _positions[p.mediaId] = p;
  }

  @override
  Future<PlaybackPosition?> loadPosition(String id) async => _positions[id];
  @override
  Future<List<PlaybackPosition>> loadContinueWatching() async =>
      _positions.values
          .where((p) => p.progress > 0 && p.progress < .95)
          .toList();
}

class PersistentPlaybackGateway implements PlaybackGateway {
  static const key = 'cineshow.progress.v1';
  static Future<void> _pending = Future.value();
  Future<Map<String, dynamic>> _read() async {
    final p = await SharedPreferences.getInstance();
    try {
      return Map<String, dynamic>.from(
          jsonDecode(p.getString(key) ?? '{}') as Map);
    } catch (_) {
      return {};
    }
  }

  PlaybackPosition? _decode(String id, Map value) {
    final position = value['position'], duration = value['duration'];
    if (position is! num ||
        duration is! num ||
        !position.isFinite ||
        !duration.isFinite ||
        position < 0 ||
        duration <= 0) {
      return null;
    }
    return PlaybackPosition(
        mediaId: id,
        position: Duration(milliseconds: position.toInt()),
        duration: Duration(milliseconds: duration.toInt()));
  }

  @override
  Future<void> savePosition(PlaybackPosition position) {
    final result = _pending.catchError((Object _) {}).then((_) async {
      final all = await _read();
      all[position.mediaId] = {
        'position': position.position.inMilliseconds,
        'duration': position.duration.inMilliseconds
      };
      final p = await SharedPreferences.getInstance();
      await p.setString(key, jsonEncode(all));
    });
    _pending = result;
    return result;
  }

  @override
  Future<PlaybackPosition?> loadPosition(String id) async {
    await _pending.catchError((Object _) {});
    final data = await _read();
    return data[id] is Map ? _decode(id, data[id] as Map) : null;
  }

  @override
  Future<List<PlaybackPosition>> loadContinueWatching() async {
    await _pending.catchError((Object _) {});
    final data = await _read();
    return data.entries
        .where((e) => e.value is Map)
        .map((e) => _decode(e.key, e.value as Map))
        .whereType<PlaybackPosition>()
        .where((p) => p.progress > 0 && p.progress < .95)
        .toList();
  }
}

class StreamResolver {
  const StreamResolver();
  Future<String> resolve(MediaItem item) async {
    final url = item.streamUrl;
    if (url == null || url.isEmpty) {
      throw StateError(
          'Nenhuma fonte autorizada foi configurada para ${item.title}.');
    }
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw StateError('Endereço de reprodução inválido.');
    }
    return url;
  }
}
