import 'package:cineshow/features/player/widgets/playback_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget harness(
        {bool playing = false,
        bool live = false,
        bool seekable = true,
        Duration duration = const Duration(minutes: 2),
        Future<void> Function(Duration)? seek}) =>
    MaterialApp(
        home: Scaffold(
            body: SizedBox(
                width: 400,
                height: 240,
                child: PlaybackControls(
                  child: const ColoredBox(color: Colors.black),
                  position: const Duration(seconds: 5),
                  duration: duration,
                  playing: playing,
                  live: live,
                  seekable: seekable,
                  onToggle: () async {},
                  onSeek: seek ?? (_) async {},
                  onFullscreen: () {},
                ))));

void main() {
  testWidgets('controls hide and return on touch in the video area',
      (tester) async {
    await tester.pumpWidget(harness(playing: true));
    await tester.pump(const Duration(seconds: 4));
    expect(
        tester
            .widget<IgnorePointer>(
                find.byKey(const Key('playback-controls-hit-test')))
            .ignoring,
        isTrue);
    await tester.tap(find.byKey(const Key('video-touch-surface')));
    await tester.pump();
    expect(
        tester
            .widget<IgnorePointer>(
                find.byKey(const Key('playback-controls-hit-test')))
            .ignoring,
        isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('rewind clamps to start and timeline seeks to the selected time',
      (tester) async {
    Duration? target;
    await tester.pumpWidget(harness(seek: (value) async {
      target = value;
    }));
    await tester.tap(find.byTooltip('Voltar 10 segundos'));
    await tester.pump();
    expect(target, Duration.zero);
    final slider =
        tester.widget<Slider>(find.byKey(const Key('playback-timeline')));
    slider.onChangeEnd!(60000);
    await tester.pump();
    expect(target, const Duration(minutes: 1));
    await tester.tap(find.byTooltip('Voltar ao início'));
    await tester.pump();
    expect(target, Duration.zero);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('live without DVR does not advertise seeking', (tester) async {
    await tester.pumpWidget(
        harness(live: true, seekable: false, duration: Duration.zero));
    expect(find.byType(Slider), findsNothing);
    expect(find.text('● AO VIVO · sem retorno disponível'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  test('seek targets remain within the available duration', () {
    expect(
        boundedPlaybackPosition(
            const Duration(seconds: -10), const Duration(minutes: 1)),
        Duration.zero);
    expect(
        boundedPlaybackPosition(
            const Duration(minutes: 2), const Duration(minutes: 1)),
        const Duration(minutes: 1));
  });
}
