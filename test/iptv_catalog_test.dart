import 'package:cineshow/core/models/media_item.dart';
import 'package:cineshow/core/services/iptv_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('joins only playable channels, deduplicates and preserves headers', () {
    final channels = IptvCatalog.parse(
      [
        {
          'id': 'one',
          'name': 'Canal',
          'country': 'BR',
          'categories': ['news'],
        },
        {'id': 'missing', 'name': 'Sem transmissão'},
        {'id': 'adult', 'name': 'Adult', 'is_nsfw': true},
      ],
      [
        {
          'channel': 'one',
          'url': 'https://example.org/live.m3u8',
          'referrer': 'https://example.org',
          'user_agent': 'Player',
        },
        {'channel': 'one', 'url': 'https://example.org/live.m3u8'},
        {'channel': 'one', 'url': 'file:///local'},
        {'channel': 'adult', 'url': 'https://example.org/a.m3u8'},
      ],
      [
        {
          'channel': 'one',
          'in_use': true,
          'url': 'https://example.org/logo.png',
        },
      ],
    );
    expect(channels, hasLength(1));
    expect(channels.single.streams, hasLength(1));
    expect(channels.single.logo, 'https://example.org/logo.png');
    expect(
      channels.single.media(0).streamHeaders['Referer'],
      'https://example.org',
    );
    expect(channels.single.media(0).kind, 'live');
  });
  test('catalog round trip preserves direct playback and headers', () {
    const media = MediaItem(
      id: 'test',
      title: 'Test',
      description: '',
      genre: '',
      year: 2026,
      durationMinutes: 90,
      streamUrl: 'https://example.org/movie.mp4',
      streamHeaders: {'Referer': 'https://example.org'},
    );
    final decoded = MediaItem.fromJson(media.toJson());
    expect(decoded.streamUrl, media.streamUrl);
    expect(decoded.streamHeaders, media.streamHeaders);
    expect(decoded.durationMinutes, 90);
  });
}
