import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';
import 'package:cineshow/core/services/provider_playback.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:cineshow/core/models/media_item.dart';
import 'package:cineshow/core/services/playback_recovery.dart';
import 'package:cineshow/core/services/playback_gateway.dart';
import 'package:cineshow/features/player/presentation/player_page.dart';

MediaItem media(String url, {String referer = 'https://source.test/episode'}) =>
    MediaItem(
        id: 'episode-5',
        title: 'Capítulo 05/11',
        description: '',
        genre: '',
        year: 2026,
        durationMinutes: 50,
        kind: 'novela',
        streamUrl: url,
        streamHeaders: {'Referer': referer});

class RefusingController extends VideoPlayerController {
  RefusingController()
      : super.networkUrl(Uri.parse('https://video.test/test.mp4'));
  @override
  Future<void> initialize() async =>
      throw StateError('decoder failed https://video.test/file?token=private');
  @override
  Future<void> dispose() async {
    // No native player is allocated by this failing test controller.
    await super.dispose().catchError((Object _) {});
  }
}

class RenewalResolver extends ProviderPlaybackResolver {
  RenewalResolver(this.options)
      : super(client: MockClient((_) async => http.Response('', 500)));
  final List<ProviderPlaybackOption> options;
  @override
  Future<List<ProviderPlaybackOption>> resolve(
          MediaItem item, MediaSource source,
          {required String pageUrl}) async =>
      options;
  @override
  Future<List<ProviderPlaybackOption>> expand(
          ProviderPlaybackOption option) async =>
      [option];
}

void main() {
  test('retry obtains fresh URL and headers while preserving episode identity',
      () async {
    var calls = 0;
    final recovery =
        PlaybackRecovery(media('https://cdn.test/expired'), renew: () async {
      calls++;
      return media('https://cdn.test/fresh-$calls',
          referer: 'https://source.test/new-session');
    });
    final first = await recovery.retry();
    final second = await recovery.retry();
    expect(calls, 2);
    expect(first.streamUrl, endsWith('fresh-1'));
    expect(second.streamUrl, endsWith('fresh-2'));
    expect(second.id, 'episode-5');
    expect(second.streamHeaders['Referer'], 'https://source.test/new-session');
  });
  test('failed renewal retains previous state without pretending to refresh',
      () async {
    final original = media('https://cdn.test/old');
    final recovery = PlaybackRecovery(original,
        renew: () async => throw StateError('source unavailable'));
    await expectLater(recovery.retry(), throwsStateError);
    expect(identical(recovery.media, original), isTrue);
  });
  test('invalid renewed media cannot replace a usable entry', () async {
    final original = media('https://cdn.test/old');
    final recovery = PlaybackRecovery(original, renew: () async => media(''));
    await expectLater(recovery.retry(), throwsStateError);
    expect(identical(recovery.media, original), isTrue);
  });
  test('renewal keeps the selected server instead of changing audio', () async {
    final resolver = RenewalResolver(const [
      ProviderPlaybackOption(
          url: 'https://video.test/dub',
          label: 'Dublado',
          direct: true,
          id: 'dub'),
      ProviderPlaybackOption(
          url: 'https://video.test/sub',
          label: 'Legendado',
          direct: true,
          id: 'sub')
    ]);
    addTearDown(resolver.close);
    const source = MediaSource(
        provider: 'rtfilmes',
        sourceId: '1',
        pageUrl: 'https://source.test/film');
    final option = await resolver.renew(media('https://video.test/old'), source,
        pageUrl: source.pageUrl, optionId: 'sub', label: 'Legendado');
    expect(option.id, 'sub');
    await expectLater(
        resolver.renew(media('https://video.test/old'), source,
            pageUrl: source.pageUrl, optionId: 'gone', label: 'Missing'),
        throwsStateError);
  });
  testWidgets(
      'retry renews source instead of reopening expired video and exposes compatible player',
      (tester) async {
    var renewed = 0;
    final opened = <MediaItem>[];
    await tester.pumpWidget(MaterialApp(
        home: PlayerPage(
            media: media('https://cdn.test/expired'),
            playbackGateway: InMemoryPlaybackGateway(),
            renewMedia: () async {
              renewed++;
              return media('https://cdn.test/fresh');
            },
            controllerFactory: (item) {
              opened.add(item);
              return RefusingController();
            })));
    await tester.pumpAndSettle();
    expect(find.text('Tentar player compatível'), findsOneWidget);
    await tester.tap(find.text('Renovar link e tentar'));
    await tester.pumpAndSettle();
    expect(renewed, 1);
    expect(opened.map((v) => v.streamUrl),
        ['https://cdn.test/expired', 'https://cdn.test/fresh']);
    expect(find.textContaining('lista de canais'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
