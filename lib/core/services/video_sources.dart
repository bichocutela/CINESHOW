import 'dart:convert';
import '../models/media_item.dart';
import 'live_catalog.dart';

class VideoSource {
  const VideoSource(this.label, this.url, {this.native = false});
  final String label, url;
  final bool native;
}

class VideoSources {
  static String? safeUrl(String value, String base) {
    final uri = Uri.parse(base).resolve(value.replaceAll('&amp;', '&'));
    return uri.scheme == 'https' && uri.host.isNotEmpty && uri.userInfo.isEmpty
        ? uri.toString()
        : null;
  }

  static List<Map<String, String>> selections(String markup) {
    final seen = <String>{};
    final result = <Map<String, String>>[];
    for (final tag in RegExp(r'<li\b[^>]*>').allMatches(markup)) {
      final a = attributes(tag[0]!);
      final post = a['data-post'],
          type = a['data-type'],
          source = a['data-nume'];
      if (post == null ||
          type == null ||
          source == null ||
          !RegExp(r'^\d+$').hasMatch(post) ||
          !RegExp(r'^[a-zA-Z0-9-]+$').hasMatch(type) ||
          !RegExp(r'^[a-zA-Z0-9-]+$').hasMatch(source) ||
          source == 'trailer' ||
          !seen.add('$post/$type/$source')) {
        continue;
      }
      result.add({'post': post, 'type': type, 'source': source});
    }
    return result;
  }

  Future<List<VideoSource>> resolve(
    MediaItem media,
    MediaSource source,
    String pageUrl,
  ) async {
    final direct = media.streamUrl;
    if (direct != null && safeUrl(direct, pageUrl) != null) {
      return [VideoSource('Vídeo', direct, native: true)];
    }
    final origin = Uri.parse(pageUrl).origin;
    if (!providerPage(source.provider, pageUrl)) {
      throw StateError('Fonte inválida');
    }
    final session = SourceSession(origin);
    try {
      final page = await session.get(pageUrl);
      if (source.provider == 'xonados') {
        final frames = <VideoSource>[];
        for (final match in RegExp(r'<iframe\b[^>]*>').allMatches(page)) {
          final src = attributes(match[0]!)['src'];
          if (src == null) continue;
          final url = safeUrl(src, pageUrl);
          if (url != null && !frames.any((f) => f.url == url)) {
            frames.add(VideoSource('Player ${frames.length + 1}', url));
          }
        }
        if (frames.isNotEmpty)
          return [...frames, VideoSource('Player da fonte', pageUrl)];
      } else {
        final result = <VideoSource>[];
        for (final selection in selections(page)) {
          try {
            final response = jsonDecode(
              await session.get(
                '/wp-json/dooplayer/v2/${selection['post']}/${selection['type']}/${selection['source']}',
              ),
            ) as Map;
            final raw = response['embed_url'];
            if (raw is! String) continue;
            final url = safeUrl(raw, pageUrl);
            if (url != null && !result.any((v) => v.url == url)) {
              result.add(VideoSource('Servidor ${result.length + 1}', url));
            }
          } catch (_) {
            /* Other advertised servers can remain available. */
          }
        }
        if (result.isNotEmpty)
          return [...result, VideoSource('Player da fonte', pageUrl)];
      }
    } catch (_) {
      // The original public player remains accessible inside the WebView.
    } finally {
      session.close();
    }
    return [VideoSource('Player da fonte', pageUrl)];
  }
}
