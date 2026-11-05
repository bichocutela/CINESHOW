import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../models/media_item.dart';

class MediaDownloads {
  MediaDownloads({http.Client Function()? clientFactory})
      : clientFactory = clientFactory ?? http.Client.new;
  final http.Client Function() clientFactory;
  static const channel = MethodChannel('cineshow/media_downloads');
  static final instance = MediaDownloads();
  final pending = <String, Future<int>>{};

  Future<int> start(MediaItem item) {
    return pending.putIfAbsent(item.id, () async {
      try {
        return await _start(item);
      } finally {
        pending.remove(item.id);
      }
    });
  }

  Future<int> _start(MediaItem item) async {
    final uri = Uri.tryParse(item.streamUrl ?? '');
    if (item.kind == 'live' ||
        uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw StateError('Esta fonte não oferece um arquivo para download.');
    }
    final headers = <String, String>{
      for (final entry in item.streamHeaders.entries)
        if (['referer', 'user-agent'].contains(entry.key.toLowerCase()))
          entry.key: entry.value
    };
    final client = clientFactory();
    var mp4 = false;
    try {
      final request = http.Request('GET', uri)
        ..headers.addAll({...headers, 'Range': 'bytes=0-1023'});
      final response =
          await client.send(request).timeout(const Duration(seconds: 15));
      if (![200, 206].contains(response.statusCode)) {
        await response.stream.listen((_) {}).cancel();
        throw StateError('A fonte recusou o download.');
      }
      final bytes = <int>[];
      await for (final chunk
          in response.stream.timeout(const Duration(seconds: 15))) {
        bytes.addAll(chunk.take(8 - bytes.length));
        if (bytes.length >= 8) {
          mp4 = bytes[4] == 102 &&
              bytes[5] == 116 &&
              bytes[6] == 121 &&
              bytes[7] == 112;
          break;
        }
      }
    } finally {
      client.close();
    }
    if (!mp4) {
      throw StateError(
          'Download disponível apenas quando a fonte fornece MP4 direto. Este player não oferece esse arquivo.');
    }
    return (await channel.invokeMethod<int>('start', {
      'mediaId': item.id,
      'url': uri.toString(),
      'title': item.title,
      'headers': headers
    }))!;
  }

  Future<List<Map<String, dynamic>>> list() async =>
      ((await channel.invokeListMethod<dynamic>('list')) ?? [])
          .map((v) => Map<String, dynamic>.from(v as Map))
          .toList();
  Future<void> open(int id) => channel.invokeMethod<void>('open', {'id': id});
  Future<void> remove(int id) =>
      channel.invokeMethod<void>('remove', {'id': id});
}
