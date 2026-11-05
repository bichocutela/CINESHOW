import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:cineshow/core/models/media_item.dart';
import 'package:cineshow/core/services/provider_playback.dart';

void main() {
  test(
      'Amyflix uses its declared admin AJAX player route and retains audio label',
      () async {
    final calls = <String>[];
    final resolver =
        ProviderPlaybackResolver(client: MockClient((request) async {
      calls.add(request.url.path);
      if (request.method == 'POST') {
        expect(request.url.path, '/wp-admin/admin-ajax.php');
        expect(request.body,
            'action=doo_player_ajax&post=20425&type=movie&nume=1');
        return http.Response(
            jsonEncode({
              'type': 'iframe',
              'embed_url': 'https://vidmoly.org/embed-example.html'
            }),
            200);
      }
      return http.Response('''Amy dooplay
<script>var dtAjax={"url":"/wp-admin/admin-ajax.php","play_method":"admin_ajax"};</script>
<li data-post="20425" data-type="movie" data-nume="1">Legendado</li>''', 200);
    }));
    try {
      const item = MediaItem(
          id: 'amy-movie',
          title: 'Filme',
          description: '',
          genre: '',
          year: 2018,
          durationMinutes: 0);
      final result = await resolver.resolve(
          item,
          const MediaSource(
              provider: 'amyflix',
              sourceId: '20425',
              pageUrl: 'https://amyflix.net/filme/example/'),
          pageUrl: 'https://amyflix.net/filme/example/');
      expect(result.single.direct, isFalse);
      expect(result.single.label, contains('Legendado'));
      expect(calls.any((path) => path.contains('/wp-json/')), isFalse);
    } finally {
      resolver.close();
    }
  });
}
