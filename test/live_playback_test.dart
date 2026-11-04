import 'package:cineshow/core/services/iptv_catalog.dart';
import 'package:cineshow/core/services/live_playback.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('starts at selected source and exhausts only this channel once', () {
    const channel = TvChannel(
        'test',
        'TV',
        'BR',
        [],
        null,
        [
          {'url': 'https://one.example/live.m3u8'},
          {
            'url': 'http://two.example:8080/',
            'referrer': 'https://two.example/',
            'user_agent': 'SourceAgent'
          },
          {'url': 'https://three.example/live.m3u8'},
        ]);
    final plan = LivePlaybackPlan(channel, selected: 1);
    expect(plan.next, 1);
    expect(plan.source(1).streamHeaders,
        {'Referer': 'https://two.example/', 'User-Agent': 'SourceAgent'});
    expect(plan.source(1).streamUrl, 'http://two.example:8080/');
    plan.attempted.add(1);
    expect(plan.next, 2);
    plan.attempted.add(2);
    expect(plan.next, 0);
    plan.attempted.add(0);
    expect(plan.next, isNull);
  });
  test('empty source list does not divide by zero', () {
    final plan =
        LivePlaybackPlan(const TvChannel('empty', 'TV', 'BR', [], null, []));
    expect(plan.next, isNull);
  });
  test('errors distinguish authorization, missing source and decoding', () {
    expect(livePlaybackError('HTTP 403 Forbidden'), contains('recusou'));
    expect(livePlaybackError('HTTP 404 Not Found'), contains('endereço'));
    expect(livePlaybackError('decoder not found'), contains('modo compatível'));
    expect(livePlaybackError('TimeoutException'), contains('tempo esperado'));
  });
  test('technical details remove URL queries and credentials', () {
    final detail = safePlaybackDetail(
        'Failed https://example.org/live?token=secret Authorization=hidden');
    expect(detail, isNot(contains('secret')));
    expect(detail, isNot(contains('hidden')));
    expect(detail, contains('example.org'));
  });
}
