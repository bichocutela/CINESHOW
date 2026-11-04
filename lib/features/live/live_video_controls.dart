import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../player/widgets/playback_controls.dart';

class LiveVideoControls extends StatefulWidget {
  const LiveVideoControls({super.key, required this.videoState});
  final VideoState videoState;
  @override
  State<LiveVideoControls> createState() => _LiveVideoControlsState();
}

class _LiveVideoControlsState extends State<LiveVideoControls> {
  final subscriptions = <StreamSubscription<dynamic>>[];
  bool seekable = false, checking = false;
  Player get player => widget.videoState.widget.controller.player;
  @override
  void initState() {
    super.initState();
    subscriptions.add(player.stream.position.listen((_) => _changed()));
    subscriptions.add(player.stream.playing.listen((_) => _changed()));
    subscriptions.add(player.stream.buffering.listen((_) => _changed()));
    subscriptions.add(player.stream.duration.listen((_) {
      _changed();
      _range();
    }));
    unawaited(_range());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _range() async {
    if (checking) return;
    checking = true;
    try {
      final native = player.platform;
      final available = native is NativePlayer &&
          player.state.duration > Duration.zero &&
          await native.getProperty('seekable') == 'yes';
      if (mounted) setState(() => seekable = available);
    } catch (_) {
      if (mounted) setState(() => seekable = false);
    } finally {
      checking = false;
    }
  }

  @override
  void dispose() {
    for (final subscription in subscriptions) {
      unawaited(subscription.cancel());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PlaybackControls(
      child: const SizedBox.expand(),
      position: player.state.position,
      duration: player.state.duration,
      playing: player.state.playing,
      buffering: player.state.buffering,
      live: true,
      seekable: seekable,
      fullscreen: widget.videoState.isFullscreen(),
      onToggle: player.playOrPause,
      onSeek: player.seek,
      onFullscreen: widget.videoState.toggleFullscreen);
}
