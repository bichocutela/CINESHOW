import 'package:cineshow/core/models/media_item.dart';
import 'package:cineshow/core/services/playback_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('calcula o progresso de reprodução', () {
    const position = PlaybackPosition(
      mediaId: 'demo',
      position: Duration(minutes: 5),
      duration: Duration(minutes: 20),
    );

    expect(position.progress, 0.25);
  });

  test('recusa conteúdo sem fonte de reprodução', () async {
    const resolver = StreamResolver();
    const item = MediaItem(
      id: 'demo',
      title: 'Demo',
      description: 'Demo',
      genre: 'Drama',
      year: 2026,
      durationMinutes: 90,
    );

    expect(
      () => resolver.resolve(item),
      throwsA(isA<StateError>()),
    );
  });
}
