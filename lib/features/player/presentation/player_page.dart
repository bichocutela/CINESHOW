import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import '../../../core/models/media_item.dart';
import '../../../core/services/playback_gateway.dart';

class PlayerPage extends StatefulWidget {
  const PlayerPage({
    super.key,
    required this.media,
    this.playbackGateway,
    this.onNext,
    this.onPrevious,
  });
  final MediaItem media;
  final PlaybackGateway? playbackGateway;
  final VoidCallback? onNext, onPrevious;
  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> with WidgetsBindingObserver {
  late final PlaybackGateway gateway;
  VideoPlayerController? controller;
  Timer? saveTimer, hideTimer;
  String? error;
  bool loading = true, controls = true, fullscreen = false, locked = false;
  BoxFit fit = BoxFit.contain;
  double speed = 1;

  @override
  void initState() {
    super.initState();
    gateway = widget.playbackGateway ?? PersistentPlaybackGateway();
    WidgetsBinding.instance.addObserver(this);
    saveTimer = Timer.periodic(const Duration(seconds: 10), (_) => _save());
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final url = widget.media.streamUrl;
      if (url == null || Uri.tryParse(url)?.scheme != 'https') {
        throw StateError('Sem vídeo');
      }
      final video = VideoPlayerController.networkUrl(Uri.parse(url));
      controller = video;
      await video.initialize();
      if (!mounted) return;
      final position = await gateway.loadPosition(widget.media.id);
      if (!mounted) return;
      if (position != null &&
          position.progress < .95 &&
          position.position < video.value.duration) {
        await video.seekTo(position.position);
      }
      if (!mounted) return;
      setState(() => loading = false);
      await video.play();
      _showControls();
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
          error = 'Não foi possível reproduzir o vídeo. Tente outra fonte.';
        });
      }
    }
  }

  Future<void> _save() async {
    final video = controller;
    if (video == null || !video.value.isInitialized) return;
    try {
      await gateway.savePosition(
        PlaybackPosition(
          mediaId: widget.media.id,
          position: video.value.position,
          duration: video.value.duration,
        ),
      );
    } catch (_) {
      /* Saving progress must not interrupt playback. */
    }
  }

  void _showControls() {
    hideTimer?.cancel();
    if (mounted) setState(() => controls = true);
    hideTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && controller?.value.isPlaying == true) {
        setState(() => controls = false);
      }
    });
  }

  Future<void> _toggle() async {
    final video = controller;
    if (video == null) return;
    if (video.value.isPlaying) {
      await video.pause();
    } else {
      if (video.value.position >= video.value.duration) {
        await video.seekTo(Duration.zero);
      }
      await video.play();
    }
    _showControls();
  }

  Future<void> _seek(int seconds) async {
    final video = controller;
    if (video == null) return;
    final milliseconds = (video.value.position.inMilliseconds + seconds * 1000)
        .clamp(0, video.value.duration.inMilliseconds)
        .toInt();
    await video.seekTo(Duration(milliseconds: milliseconds));
    _showControls();
  }

  Future<void> _fullscreen(bool value) async {
    setState(() => fullscreen = value);
    await SystemChrome.setEnabledSystemUIMode(
      value ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
    await SystemChrome.setPreferredOrientations(
      value
          ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
          : DeviceOrientation.values,
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
    saveTimer?.cancel();
    hideTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_save());
    controller?.dispose();
    if (fullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    }
    super.dispose();
  }

  String _time(Duration duration) {
    final seconds = duration.inSeconds;
    final minutes = (seconds ~/ 60) % 60;
    return '${seconds >= 3600 ? '${seconds ~/ 3600}:' : ''}${minutes.toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final video = controller;
    return PopScope(
      canPop: !fullscreen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && fullscreen) _fullscreen(false);
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: fullscreen
            ? null
            : AppBar(
                title: Text(widget.media.title),
                backgroundColor: Colors.black,
              ),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(error!, textAlign: TextAlign.center),
                    ),
                  )
                : video == null
                    ? const SizedBox.shrink()
                    : ValueListenableBuilder<VideoPlayerValue>(
                        valueListenable: video,
                        builder: (context, value, _) {
                          if (value.hasError) {
                            return const Center(
                              child: Text(
                                'A reprodução foi interrompida. Volte e escolha outra fonte.',
                              ),
                            );
                          }
                          final duration =
                              value.duration.inMilliseconds.toDouble();
                          return GestureDetector(
                            onTap: _showControls,
                            onDoubleTapDown: locked
                                ? null
                                : (details) => _seek(
                                      details.localPosition.dx <
                                              MediaQuery.sizeOf(context).width /
                                                  2
                                          ? -10
                                          : 10,
                                    ),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Center(
                                  child: SizedBox.expand(
                                    child: FittedBox(
                                      fit: fit,
                                      child: SizedBox(
                                        width: value.size.width,
                                        height: value.size.height,
                                        child: VideoPlayer(video),
                                      ),
                                    ),
                                  ),
                                ),
                                if (value.isBuffering)
                                  const Center(
                                      child: CircularProgressIndicator()),
                                if (controls && locked)
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: IconButton.filled(
                                      tooltip: 'Desbloquear controles',
                                      onPressed: () {
                                        setState(() => locked = false);
                                        _showControls();
                                      },
                                      icon: const Icon(Icons.lock_open),
                                    ),
                                  ),
                                if (controls && !locked)
                                  Container(
                                    color: Colors.black45,
                                    child: SafeArea(
                                      child: Column(
                                        children: [
                                          Row(
                                            children: [
                                              if (fullscreen)
                                                IconButton(
                                                  tooltip: 'Sair da tela cheia',
                                                  onPressed: () =>
                                                      _fullscreen(false),
                                                  icon: const Icon(
                                                      Icons.arrow_back),
                                                ),
                                              Expanded(
                                                child: Text(
                                                  widget.media.title,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                              IconButton(
                                                tooltip: 'Bloquear controles',
                                                onPressed: () => setState(
                                                    () => locked = true),
                                                icon: const Icon(
                                                    Icons.lock_outline),
                                              ),
                                            ],
                                          ),
                                          const Spacer(),
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              IconButton(
                                                tooltip: 'Episódio anterior',
                                                onPressed: widget.onPrevious,
                                                icon: const Icon(
                                                    Icons.skip_previous),
                                              ),
                                              IconButton(
                                                tooltip: 'Voltar 10 segundos',
                                                onPressed: () => _seek(-10),
                                                icon:
                                                    const Icon(Icons.replay_10),
                                                iconSize: 36,
                                              ),
                                              IconButton(
                                                tooltip: value.isPlaying
                                                    ? 'Pausar'
                                                    : 'Reproduzir',
                                                onPressed: _toggle,
                                                icon: Icon(
                                                  value.isPlaying
                                                      ? Icons.pause_circle
                                                      : Icons.play_circle,
                                                ),
                                                iconSize: 58,
                                              ),
                                              IconButton(
                                                tooltip: 'Avançar 10 segundos',
                                                onPressed: () => _seek(10),
                                                icon: const Icon(
                                                    Icons.forward_10),
                                                iconSize: 36,
                                              ),
                                              IconButton(
                                                tooltip: 'Próximo episódio',
                                                onPressed: widget.onNext,
                                                icon:
                                                    const Icon(Icons.skip_next),
                                              ),
                                            ],
                                          ),
                                          const Spacer(),
                                          Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                            ),
                                            child: Row(
                                              children: [
                                                Text(_time(value.position)),
                                                Expanded(
                                                  child: Slider(
                                                    value: duration > 0
                                                        ? value.position
                                                            .inMilliseconds
                                                            .clamp(0, duration)
                                                            .toDouble()
                                                        : 0,
                                                    max: duration > 0
                                                        ? duration
                                                        : 1,
                                                    onChanged: duration > 0
                                                        ? (position) {
                                                            video.seekTo(
                                                              Duration(
                                                                milliseconds:
                                                                    position
                                                                        .toInt(),
                                                              ),
                                                            );
                                                            _showControls();
                                                          }
                                                        : null,
                                                  ),
                                                ),
                                                Text(_time(value.duration)),
                                              ],
                                            ),
                                          ),
                                          Wrap(
                                            alignment: WrapAlignment.center,
                                            crossAxisAlignment:
                                                WrapCrossAlignment.center,
                                            children: [
                                              IconButton(
                                                tooltip: value.volume == 0
                                                    ? 'Ativar som'
                                                    : 'Silenciar',
                                                onPressed: () =>
                                                    video.setVolume(
                                                  value.volume == 0 ? 1 : 0,
                                                ),
                                                icon: Icon(
                                                  value.volume == 0
                                                      ? Icons.volume_off
                                                      : Icons.volume_up,
                                                ),
                                              ),
                                              SizedBox(
                                                width: 100,
                                                child: Slider(
                                                  value: value.volume,
                                                  onChanged: video.setVolume,
                                                ),
                                              ),
                                              PopupMenuButton<double>(
                                                tooltip: 'Velocidade',
                                                initialValue: speed,
                                                onSelected: (rate) {
                                                  setState(() => speed = rate);
                                                  video.setPlaybackSpeed(rate);
                                                  _showControls();
                                                },
                                                itemBuilder: (_) => [
                                                  for (final rate in [
                                                    .5,
                                                    .75,
                                                    1.0,
                                                    1.25,
                                                    1.5,
                                                    2.0,
                                                  ])
                                                    PopupMenuItem(
                                                      value: rate,
                                                      child: Text('${rate}x'),
                                                    ),
                                                ],
                                                child: Padding(
                                                  padding:
                                                      const EdgeInsets.all(12),
                                                  child: Text('${speed}x'),
                                                ),
                                              ),
                                              IconButton(
                                                tooltip: 'Ajustar imagem',
                                                onPressed: () => setState(
                                                  () => fit =
                                                      fit == BoxFit.contain
                                                          ? BoxFit.cover
                                                          : BoxFit.contain,
                                                ),
                                                icon: const Icon(
                                                    Icons.aspect_ratio),
                                              ),
                                              IconButton(
                                                tooltip: fullscreen
                                                    ? 'Sair da tela cheia'
                                                    : 'Tela cheia',
                                                onPressed: () =>
                                                    _fullscreen(!fullscreen),
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
                              ],
                            ),
                          );
                        },
                      ),
      ),
    );
  }
}
