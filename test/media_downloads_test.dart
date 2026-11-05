import 'dart:async';
import 'package:cineshow/core/models/media_item.dart';
import 'package:cineshow/core/services/media_downloads.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('downloads enqueue only verified MP4 and preserve required headers',
      () async {
    MethodCall? called;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MediaDownloads.channel, (call) async {
      called = call;
      return 42;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MediaDownloads.channel, null));
    final service = MediaDownloads(
        clientFactory: () => MockClient.streaming((req, body) async {
              await body.drain<void>();
              expect(req.headers['Range'], 'bytes=0-1023');
              expect(req.headers['Referer'], 'https://source.example/');
              expect(req.headers.containsKey('Authorization'), isFalse);
              return http.StreamedResponse(
                  Stream.fromIterable([
                    [0, 0, 0],
                    [24, 102],
                    [116, 121, 112]
                  ]),
                  206);
            }));
    const item = MediaItem(
        id: 'episode1',
        title: 'Capítulo 1',
        description: '',
        genre: '',
        year: 0,
        durationMinutes: 0,
        kind: 'novela',
        streamUrl: 'https://cdn.example/video',
        streamHeaders: {
          'Referer': 'https://source.example/',
          'Authorization': 'unused'
        });
    expect(await service.start(item), 42);
    expect(called!.method, 'start');
    expect((called!.arguments as Map)['mediaId'], 'episode1');
  });
  test('HTML and HLS are never downloaded as fake MP4 files', () async {
    for (final body in ['<html>player</html>', '#EXTM3U\n#EXT-X-VERSION:3']) {
      final service = MediaDownloads(
          clientFactory: () =>
              MockClient((_) async => http.Response(body, 200)));
      const item = MediaItem(
          id: 'movie',
          title: 'Filme',
          description: '',
          genre: '',
          year: 0,
          durationMinutes: 0,
          streamUrl: 'https://cdn.example/video');
      await expectLater(service.start(item), throwsStateError);
    }
  });
}
