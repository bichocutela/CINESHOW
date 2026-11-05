import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cineshow/core/models/media_item.dart';
import 'package:cineshow/core/services/audio_metadata.dart';
import 'package:cineshow/core/services/chapter_queue.dart';
import 'package:cineshow/core/services/continue_watching.dart';
import 'package:cineshow/core/services/playback_gateway.dart';

void main() {
  test('audio badge ignores generic page text and uses explicit quality', () {
    expect(catalogAudio('<p>Filmes dublados e legendados</p>'), '');
    expect(catalogAudio('<span class="quality">LEGENDADO</span>'), 'Legendado');
    expect(cleanAudioTitle('Minha série – Legendado'), 'Minha série');
    expect(audioLabel('Dublado Legendado'), 'Dublado e legendado');
  });
  test('next chapter orders numerically and skips alternative versions', () {
    final series = [
      {'page_url':'https://source.example/episodio/test-1x10/'},
      {'page_url':'https://source.example/episodio/test-1x2/'},
      {'page_url':'https://source.example/episodio/test-2x1/'}
    ];
    expect(chapterUrl(nextChapter(series, 'https://source.example/episodio/test-1x2/')!), endsWith('1x10/'));
    final novels = [
      {'page_url':'/ast/OnW/?date=20261105_1&y=temp'},
      {'page_url':'/ast/OnW/?date=20261104&y=temp'},
      {'page_url':'/ast/OnW/?date=20261105&y=temp'}
    ];
    expect(orderedChapters(novels), hasLength(2));
    expect(chapterUrl(nextChapter(novels, '/ast/OnW/?date=20261104&y=expired')!), contains('date=20261105&'));
    expect(nextChapter(novels, '/ast/OnW/?date=20261105'), isNull);
  });
  test('continue watching renews chapter source instead of storing session token', () async {
    SharedPreferences.setMockInitialValues({});
    const source = MediaSource(provider:'xonados', sourceId:'5', pageUrl:'https://www.xonados.com/');
    const item = MediaItem(id:'novela:quem ama cuida:0', title:'Quem Ama Cuida',
        description:'', genre:'', year:0, durationMinutes:0, kind:'novela', sources:[source]);
    await ContinueWatching().save(item, source,
        '/ast/OnW/?date=20261105&y=expired-token', 'playback-chapter');
    await PersistentPlaybackGateway().savePosition(const PlaybackPosition(
        mediaId:'playback-chapter', position:Duration(minutes:12), duration:Duration(minutes:45)));
    final rows = await ContinueWatching().list();
    expect(rows.single.pageUrl, 'https://www.xonados.com/?date=20261105');
    expect(rows.single.position.position, const Duration(minutes:12));
    expect(rows.single.pageUrl, isNot(contains('expired-token')));
  });
}
