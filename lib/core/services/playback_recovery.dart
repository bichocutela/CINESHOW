import '../models/media_item.dart';

/// A retry must renew expiring source URLs rather than reopen the failed URL.
class PlaybackRecovery {
  PlaybackRecovery(this.media, {this.renew});
  MediaItem media;
  final Future<MediaItem> Function()? renew;
  Future<MediaItem> retry() async {
    final refreshed = renew == null ? media : await renew!();
    final uri = Uri.tryParse(refreshed.streamUrl ?? '');
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw StateError('A fonte não retornou um endereço de vídeo válido.');
    }
    media = refreshed;
    return media;
  }
}
