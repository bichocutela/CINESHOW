import '../models/media_item.dart';
import 'iptv_catalog.dart';

/// Retains source-specific headers and tries only alternatives of this channel.
class LivePlaybackPlan {
  LivePlaybackPlan(this.channel, {int selected = 0})
      : order = [
          for (var offset = 0; offset < channel.streams.length; offset++)
            (selected + offset) % channel.streams.length
        ];
  final TvChannel channel;
  final List<int> order;
  final Set<int> attempted = {};
  int? get next {
    for (final index in order) {
      if (!attempted.contains(index)) return index;
    }
    return null;
  }

  MediaItem source(int index) => channel.media(index);
}

String livePlaybackError(String detail) {
  final text = detail.toLowerCase();
  if (text.contains('403') ||
      text.contains('401') ||
      text.contains('forbidden')) {
    return 'A fonte recusou o acesso. Ela pode exigir autorização ou ter restrição de região.';
  }
  if (text.contains('codec') || text.contains('decoder')) {
    return 'Não foi possível decodificar o vídeo. Experimente o modo compatível.';
  }
  if (text.contains('404') || text.contains('not found')) {
    return 'O endereço desta fonte não está disponível.';
  }
  if (text.contains('timeout') || text.contains('timed out')) {
    return 'A fonte não enviou imagem no tempo esperado.';
  }
  if (text.contains('certificate') ||
      text.contains('tls') ||
      text.contains('ssl')) {
    return 'Não foi possível validar a conexão segura da fonte.';
  }
  return 'A fonte não conseguiu iniciar ou interrompeu a transmissão.';
}

String safePlaybackDetail(String detail) => detail
    .replaceAllMapped(RegExp(r'https?://[^\s\]\)]+'), (m) {
      final uri = Uri.tryParse(m[0]!);
      return uri == null ? '[endereço]' : '${uri.scheme}://${uri.host}/…';
    })
    .replaceAll(
        RegExp(r'(token|authorization|cookie)[=:][^\s,;]+',
            caseSensitive: false),
        '[credencial omitida]')
    .split('\n')
    .take(5)
    .join('\n');
