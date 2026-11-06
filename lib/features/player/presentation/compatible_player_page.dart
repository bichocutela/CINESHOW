import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../../core/models/media_item.dart';
import '../../../core/services/playback_gateway.dart';
import '../../../core/services/playback_recovery.dart';
import '../../../core/services/live_playback.dart' show safePlaybackDetail;
import '../widgets/playback_controls.dart';

/// Alternative decoding engine for direct video, retaining the same history ID.
class CompatiblePlayerPage extends StatefulWidget {
  const CompatiblePlayerPage(
      {super.key,
      required this.media,
      this.renewMedia,
      required this.playbackGateway,
      this.onNext,
      this.initialFullscreen = false});
  final MediaItem media;
  final Future<MediaItem> Function()? renewMedia;
  final PlaybackGateway playbackGateway;
  final Future<void> Function(bool fullscreen)? onNext;
  final bool initialFullscreen;
  @override
  State<CompatiblePlayerPage> createState() => _CompatiblePlayerState();
}

class _CompatiblePlayerState extends State<CompatiblePlayerPage>
    with WidgetsBindingObserver {
  late final recovery =
      PlaybackRecovery(widget.media, renew: widget.renewMedia);
  Player? player;
  VideoController? video;
  final subscriptions = <StreamSubscription<dynamic>>[];
  Timer? saveTimer;
  int generation = 0;
  bool loading = true, software = false, advancing = false, completed = false;
  bool fullscreen = false, handingOff = false;
  String? error, detail;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    saveTimer =
        Timer.periodic(const Duration(seconds: 10), (_) => unawaited(_save()));
    _open(renew: widget.renewMedia != null);
    if (widget.initialFullscreen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fullscreen();
      });
    }
  }

  Future<void> _open({bool renew = false}) async {
    final request = ++generation;
    if (!mounted) return;
    final saved = _save();
    setState(() {
      loading = true;
      error = null;
      detail = null;
      video = null;
      completed = false;
    });
    await saved;
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    subscriptions.clear();
    final old = player;
    player = null;
    await old?.dispose();
    if (!mounted || request != generation) return;
    setState(() {
      loading = true;
      error = null;
      detail = null;
      video = null;
      completed = false;
    });
    try {
      if (renew) await recovery.retry();
      if (!mounted || request != generation) return;
      MediaKit.ensureInitialized();
      final next = Player(
          configuration: const PlayerConfiguration(
              title: 'CINESHOW',
              protocolWhitelist: [
            'http',
            'https',
            'tcp',
            'tls',
            'crypto',
            'data'
          ]));
      player = next;
      final controller = VideoController(next,
          configuration: VideoControllerConfiguration(
              enableHardwareAcceleration: !software,
              hwdec: software ? 'no' : null));
      setState(() => video = controller);
      subscriptions.add(next.stream.error.listen((message) {
        if (mounted && request == generation) {
          unawaited(next.pause());
          setState(() {
            error = 'O player compatível não conseguiu reproduzir este vídeo.';
            detail = safePlaybackDetail(message);
            loading = false;
          });
        }
      }));
      void changed() {
        if (mounted && request == generation) {
          setState(() {});
        }
      }

      subscriptions.add(next.stream.position.listen((_) => changed()));
      subscriptions.add(next.stream.duration.listen((_) => changed()));
      subscriptions.add(next.stream.playing.listen((_) => changed()));
      subscriptions.add(next.stream.buffering.listen((_) => changed()));
      subscriptions.add(next.stream.completed.listen((value) {
        if (value &&
            mounted &&
            request == generation &&
            !completed &&
            !loading &&
            error == null) {
          completed = true;
          if (widget.onNext != null) unawaited(_advance());
        }
      }));
      final media = recovery.media;
      await (() async {
        final url = await const StreamResolver().resolve(media);
        await next.open(Media(url, httpHeaders: media.streamHeaders));
        final saved = await widget.playbackGateway.loadPosition(media.id);
        if (!mounted || request != generation) return;
        if (saved != null && saved.progress < .95) {
          await next.seek(saved.position);
        }
        await controller.waitUntilFirstFrameRendered;
      })()
          .timeout(const Duration(seconds: 75));
      if (mounted && request == generation && error == null) {
        setState(() => loading = false);
      }
    } catch (exception) {
      unawaited(player?.pause() ?? Future<void>.value());
      if (mounted && request == generation) {
        setState(() {
          loading = false;
          error = 'Não foi possível iniciar o vídeo nesta fonte.';
          detail = safePlaybackDetail(exception.toString());
        });
      }
    }
  }

  Future<void> _save() async {
    final current = player;
    if (loading ||
        error != null ||
        current == null ||
        current.state.duration <= Duration.zero ||
        recovery.media.kind == 'live') {
      return;
    }
    try {
      await widget.playbackGateway.savePosition(PlaybackPosition(
          mediaId: recovery.media.id,
          position: current.state.position,
          duration: current.state.duration));
    } catch (_) {/* Storage errors must not interrupt video. */}
  }

  Future<void> _advance() async {
    if (advancing || widget.onNext == null) return;
    setState(() => advancing = true);
    handingOff = true;
    try {
      await _save();
      await widget.onNext!(fullscreen);
    } catch (_) {
      handingOff = false;
      completed = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Não foi possível abrir o próximo capítulo. Tente novamente.')));
      }
    } finally {
      if (mounted) setState(() => advancing = false);
    }
  }

  Future<void> _fullscreen() async {
    setState(() => fullscreen = !fullscreen);
    await SystemChrome.setEnabledSystemUIMode(
        fullscreen ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
    await SystemChrome.setPreferredOrientations(fullscreen
        ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
        : []);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      unawaited(_save());
      player?.pause();
    }
  }

  @override
  void dispose() {
    generation++;
    saveTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_save());
    for (final subscription in subscriptions) {
      unawaited(subscription.cancel());
    }
    player?.dispose();
    if (fullscreen && !handingOff) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations([]);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !fullscreen,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && fullscreen) _fullscreen();
      },
      child: Scaffold(
          backgroundColor: Colors.black,
          appBar: fullscreen
              ? null
              : AppBar(title: Text(recovery.media.title), actions: [
                  IconButton(
                      tooltip: software
                          ? 'Decodificação automática'
                          : 'Decodificação por software',
                      icon: const Icon(Icons.settings_suggest),
                      onPressed: loading
                          ? null
                          : () {
                              software = !software;
                              _open();
                            })
                ]),
          body: SafeArea(
              child: Stack(alignment: Alignment.center, children: [
            if (video != null && error == null)
              PlaybackControls(
                  position: player!.state.position,
                  duration: player!.state.duration,
                  playing: player!.state.playing,
                  buffering: player!.state.buffering,
                  fullscreen: fullscreen,
                  live: recovery.media.kind == 'live',
                  seekable: recovery.media.kind != 'live',
                  onToggle: player!.playOrPause,
                  onSeek: player!.seek,
                  onFullscreen: _fullscreen,
                  onNext: widget.onNext == null || advancing
                      ? null
                      : () => unawaited(_advance()),
                  child: Video(
                      controller: video!,
                      controls: (_) => const SizedBox.shrink())),
            if (loading) const Center(child: CircularProgressIndicator()),
            if (error != null)
              Center(
                  child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(error!, textAlign: TextAlign.center),
                        FilledButton.icon(
                            onPressed: () => _open(renew: true),
                            icon: const Icon(Icons.refresh),
                            label: const Text('Renovar link e tentar')),
                        TextButton(
                            onPressed: () => Navigator.maybePop(context),
                            child: const Text('Escolher outra fonte')),
                        if (detail != null)
                          ExpansionTile(
                              title: const Text('Detalhes do erro'),
                              children: [SelectableText(detail!)])
                      ])))
          ]))));
}
