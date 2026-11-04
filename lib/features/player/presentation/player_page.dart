import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import '../../../core/models/media_item.dart';
import '../../../core/services/playback_gateway.dart';

class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key, required this.media, this.playbackGateway});
  final MediaItem media;
  final PlaybackGateway? playbackGateway;
  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> with WidgetsBindingObserver {
  late final PlaybackGateway gateway =
      widget.playbackGateway ?? PersistentPlaybackGateway();
  VideoPlayerController? controller;
  Timer? timer;
  String? error;
  bool loading = true, fullscreen = false;
  int generation = 0;
  bool get live => widget.media.kind == 'live';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    timer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => unawaited(_save()),
    );
    _initialize();
  }

  Future<void> _initialize() async {
    final request = ++generation;
    setState(() {
      loading = true;
      error = null;
    });
    final old = controller;
    controller = null;
    await old?.dispose();
    if (!mounted || request != generation) return;
    VideoPlayerController? next;
    try {
      final url = await const StreamResolver().resolve(widget.media);
      next = VideoPlayerController.networkUrl(
        Uri.parse(url),
        httpHeaders: widget.media.streamHeaders,
      );
      controller = next;
      next.addListener(_changed);
      await next.initialize().timeout(const Duration(seconds: 30));
      if (!mounted || request != generation) return;
      if (!live) {
        final saved = await gateway.loadPosition(widget.media.id);
        if (!mounted || request != generation) return;
        if (saved != null &&
            saved.progress < .95 &&
            saved.position < next.value.duration)
          await next.seekTo(saved.position);
      }
      if (!mounted || request != generation) return;
      setState(() => loading = false);
      await next.play();
    } catch (_) {
      if (!mounted || request != generation) return;
      controller = null;
      await next?.dispose();
      if (mounted)
        setState(() {
          loading = false;
          error =
              'Não foi possível reproduzir. Tente novamente ou selecione outra fonte na lista de canais.';
        });
    }
  }

  void _changed() {
    if (!mounted) return;
    setState(() {
      if (controller?.value.hasError == true) {
        error = 'A transmissão foi interrompida. Tente novamente.';
        loading = false;
      }
    });
  }

  Future<void> _save() async {
    final c = controller;
    if (live || c == null || !c.value.isInitialized) return;
    try {
      await gateway.savePosition(
        PlaybackPosition(
          mediaId: widget.media.id,
          position: c.value.position,
          duration: c.value.duration,
        ),
      );
    } catch (_) {
      /* A storage failure must not interrupt playback. */
    }
  }

  Future<void> _fullscreen() async {
    setState(() => fullscreen = !fullscreen);
    await SystemChrome.setEnabledSystemUIMode(
      fullscreen ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
    await SystemChrome.setPreferredOrientations(
      fullscreen
          ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
          : [],
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      unawaited(_save());
      controller?.pause();
    }
  }

  @override
  void dispose() {
    generation++;
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_save());
    controller?.removeListener(_changed);
    controller?.dispose();
    if (fullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations([]);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return PopScope(
      canPop: !fullscreen,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && fullscreen) _fullscreen();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: fullscreen
            ? null
            : AppBar(
                title: Text(widget.media.title),
                backgroundColor: Colors.black,
              ),
        body: SafeArea(
          child: Center(
            child: loading
                ? const CircularProgressIndicator()
                : error != null
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(error!, textAlign: TextAlign.center),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: _initialize,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Tentar novamente'),
                            ),
                          ],
                        ),
                      )
                    : c == null
                        ? const SizedBox.shrink()
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Center(
                                  child: AspectRatio(
                                    aspectRatio: c.value.aspectRatio > 0
                                        ? c.value.aspectRatio
                                        : 16 / 9,
                                    child: Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        VideoPlayer(c),
                                        if (c.value.isBuffering)
                                          const CircularProgressIndicator(),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              if (!live)
                                VideoProgressIndicator(
                                  c,
                                  allowScrubbing: true,
                                  padding: const EdgeInsets.all(12),
                                ),
                              Row(
                                children: [
                                  IconButton(
                                    tooltip: c.value.isPlaying
                                        ? 'Pausar'
                                        : 'Reproduzir',
                                    onPressed: () => c.value.isPlaying
                                        ? c.pause()
                                        : c.play(),
                                    icon: Icon(
                                      c.value.isPlaying
                                          ? Icons.pause
                                          : Icons.play_arrow,
                                    ),
                                  ),
                                  if (!live)
                                    IconButton(
                                      tooltip: 'Avançar 10 segundos',
                                      onPressed: () {
                                        final target = c.value.position +
                                            const Duration(seconds: 10);
                                        c.seekTo(
                                          target > c.value.duration
                                              ? c.value.duration
                                              : target,
                                        );
                                      },
                                      icon: const Icon(Icons.forward_10),
                                    ),
                                  Expanded(
                                    child: Text(
                                      live
                                          ? '● AO VIVO'
                                          : '${_time(c.value.position)} / ${_time(c.value.duration)}',
                                      style: TextStyle(
                                        color: live
                                            ? Colors.redAccent
                                            : Colors.white70,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Tela cheia',
                                    onPressed: _fullscreen,
                                    icon: Icon(
                                      fullscreen
                                          ? Icons.fullscreen_exit
                                          : Icons.fullscreen,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
          ),
        ),
      ),
    );
  }

  String _time(Duration d) =>
      '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
}
