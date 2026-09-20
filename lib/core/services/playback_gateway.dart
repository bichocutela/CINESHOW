import '../models/media_item.dart';

class PlaybackPosition {
  const PlaybackPosition({
    required this.mediaId,
    required this.position,
    required this.duration,
  });

  final String mediaId;
  final Duration position;
  final Duration duration;

  double get progress {
    if (duration.inMilliseconds == 0) return 0;
    return (position.inMilliseconds / duration.inMilliseconds)
        .clamp(0.0, 1.0);
  }
}

abstract interface class PlaybackGateway {
  Future<void> savePosition(PlaybackPosition position);
  Future<PlaybackPosition?> loadPosition(String mediaId);
  Future<List<PlaybackPosition>> loadContinueWatching();
}

class InMemoryPlaybackGateway implements PlaybackGateway {
  final Map<String, PlaybackPosition> _positions = {};

  @override
  Future<void> savePosition(PlaybackPosition position) async {
    _positions[position.mediaId] = position;
  }

  @override
  Future<PlaybackPosition?> loadPosition(String mediaId) async {
    return _positions[mediaId];
  }

  @override
  Future<List<PlaybackPosition>> loadContinueWatching() async {
    return _positions.values
        .where((item) => item.progress > 0 && item.progress < 0.95)
        .toList(growable: false);
  }
}

class StreamResolver {
  const StreamResolver();

  Future<String> resolve(MediaItem item) async {
    final streamUrl = item.streamUrl;
    if (streamUrl == null || streamUrl.isEmpty) {
      throw StateError(
        'Nenhuma fonte autorizada foi configurada para ${item.title}.',
      );
    }
    return streamUrl;
  }
}
