import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/media_item.dart';

class TvChannel {
  const TvChannel(
    this.id,
    this.name,
    this.country,
    this.categories,
    this.logo,
    this.streams,
  );
  final String id, name, country;
  final List<String> categories;
  final String? logo;
  final List<Map<String, dynamic>> streams;
  MediaItem media(int index) => MediaItem(
        id: 'tv:$id',
        title: name,
        description: '',
        genre: categories.join(', '),
        year: 0,
        durationMinutes: 0,
        kind: 'live',
        posterUrl: logo,
        streamUrl: streams[index]['url'] as String,
        streamHeaders: {
          if (streams[index]['referrer'] is String)
            'Referer': streams[index]['referrer'] as String,
          if (streams[index]['user_agent'] is String)
            'User-Agent': streams[index]['user_agent'] as String,
        },
      );
}

class IptvCatalog {
  IptvCatalog({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;
  static const cacheKey = 'cineshow.iptv.v1';
  void close() => _client.close();

  static List<TvChannel> parse(List channels, List streams, List logos) {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final raw in streams.whereType<Map>()) {
      final url = Uri.tryParse('${raw['url']}');
      final id = raw['channel'] as String?;
      if (id == null ||
          url == null ||
          !['https', 'http'].contains(url.scheme) ||
          url.host.isEmpty) continue;
      final list = grouped.putIfAbsent(id, () => []);
      if (!list.any((s) => s['url'] == raw['url']))
        list.add(Map<String, dynamic>.from(raw));
    }
    final images = <String, String>{};
    for (final logo in logos.whereType<Map>()) {
      if (logo['channel'] is String &&
          logo['url'] is String &&
          logo['in_use'] == true) {
        images.putIfAbsent(
          logo['channel'] as String,
          () => logo['url'] as String,
        );
      }
    }
    final result = <TvChannel>[];
    for (final c in channels.whereType<Map>()) {
      final id = c['id'] as String?;
      if (id == null || c['is_nsfw'] == true || !grouped.containsKey(id))
        continue;
      result.add(
        TvChannel(
          id,
          c['name'] as String,
          c['country'] as String? ?? '',
          ((c['categories'] as List?) ?? []).cast<String>(),
          images[id],
          grouped[id]!,
        ),
      );
    }
    result.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return result;
  }

  Future<List<TvChannel>> cached() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final data = jsonDecode(prefs.getString(cacheKey) ?? '{}') as Map;
      return parse(
        data['channels'] as List,
        data['streams'] as List,
        data['logos'] as List,
      );
    } catch (_) {
      return [];
    }
  }

  Future<List<TvChannel>> refresh() async {
    final data = await Future.wait(
      ['channels', 'streams', 'logos'].map((name) async {
        final response = await _client
            .get(Uri.https('iptv-org.github.io', '/api/$name.json'))
            .timeout(const Duration(seconds: 30));
        if (response.statusCode != 200)
          throw StateError('Catálogo indisponível');
        return jsonDecode(utf8.decode(response.bodyBytes)) as List;
      }),
    );
    final result = parse(data[0], data[1], data[2]);
    if (result.isEmpty) throw StateError('Catálogo vazio');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      cacheKey,
      jsonEncode({'channels': data[0], 'streams': data[1], 'logos': data[2]}),
    );
    return result;
  }
}
