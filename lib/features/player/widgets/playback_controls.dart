import 'dart:async';
import 'package:flutter/material.dart';

Duration boundedPlaybackPosition(Duration position, Duration duration) =>
    Duration(
        milliseconds: position.inMilliseconds
            .clamp(0, duration.inMilliseconds > 0 ? duration.inMilliseconds : 0)
            .toInt());

class PlaybackControls extends StatefulWidget {
  const PlaybackControls(
      {super.key,
      required this.child,
      required this.position,
      required this.duration,
      required this.playing,
      required this.onToggle,
      required this.onSeek,
      required this.onFullscreen,
      this.fullscreen = false,
      this.live = false,
      this.seekable = true,
      this.buffering = false,
      this.onNext});
  final Widget child;
  final Duration position, duration;
  final bool playing, fullscreen, live, seekable, buffering;
  final Future<void> Function() onToggle;
  final Future<void> Function(Duration) onSeek;
  final VoidCallback onFullscreen;
  final VoidCallback? onNext;
  @override
  State<PlaybackControls> createState() => _PlaybackControlsState();
}

class _PlaybackControlsState extends State<PlaybackControls> {
  Timer? timer;
  bool visible = true;
  double? drag;
  bool get canSeek => widget.seekable && widget.duration > Duration.zero;
  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(covariant PlaybackControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playing != widget.playing ||
        oldWidget.fullscreen != widget.fullscreen) {
      visible = true;
      _schedule();
    }
  }

  void _schedule() {
    timer?.cancel();
    if (!widget.playing || drag != null) return;
    timer = Timer(const Duration(seconds: 3), () {
      if (mounted &&
          MediaQuery.maybeOf(context)?.accessibleNavigation != true) {
        setState(() => visible = false);
      }
    });
  }

  void _touch() {
    setState(() => visible = !visible);
    _schedule();
  }

  Future<void> _seek(Duration target) async {
    try {
      await widget.onSeek(boundedPlaybackPosition(target, widget.duration));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
            content: Text('A fonte não permite ir até esse momento.')));
      }
    }
    if (!mounted) return;
    setState(() {
      drag = null;
      visible = true;
    });
    _schedule();
  }

  Future<void> _toggle() async {
    await widget.onToggle();
    if (!mounted) return;
    setState(() => visible = true);
    _schedule();
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  String _time(Duration d) {
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    final minutes = (d.inMinutes % 60).toString().padLeft(2, '0');
    return d.inHours > 0
        ? '${d.inHours}:$minutes:$seconds'
        : '${d.inMinutes}:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final position = boundedPlaybackPosition(widget.position, widget.duration);
    final preview = Duration(
        milliseconds: (drag ?? position.inMilliseconds.toDouble()).round());
    return Stack(fit: StackFit.expand, children: [
      GestureDetector(
          key: const Key('video-touch-surface'),
          behavior: HitTestBehavior.opaque,
          onTap: _touch,
          child: widget.child),
      if (widget.buffering)
        const IgnorePointer(child: Center(child: CircularProgressIndicator())),
      IgnorePointer(
          key: const Key('playback-controls-hit-test'),
          ignoring: !visible,
          child: AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: const Duration(milliseconds: 180),
            child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _touch,
                child: ColoredBox(
                    color: Colors.black45,
                    child: SafeArea(
                        child: Column(children: [
                      const Spacer(),
                      Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (canSeek)
                              IconButton(
                                  tooltip: 'Voltar 10 segundos',
                                  onPressed: () => _seek(widget.position -
                                      const Duration(seconds: 10)),
                                  icon: const Icon(Icons.replay_10),
                                  iconSize: 32,
                                  color: Colors.white),
                            IconButton(
                                tooltip:
                                    widget.playing ? 'Pausar' : 'Reproduzir',
                                onPressed: _toggle,
                                icon: Icon(widget.playing
                                    ? Icons.pause_circle_filled
                                    : Icons.play_circle_filled),
                                iconSize: 48,
                                color: Colors.white),
                            if (canSeek)
                              IconButton(
                                  tooltip: 'Avançar 10 segundos',
                                  onPressed: () => _seek(widget.position +
                                      const Duration(seconds: 10)),
                                  icon: const Icon(Icons.forward_10),
                                  iconSize: 32,
                                  color: Colors.white),
                          ]),
                      const Spacer(),
                      if (canSeek)
                        Slider(
                            key: const Key('playback-timeline'),
                            value: (drag ?? position.inMilliseconds.toDouble())
                                .clamp(0,
                                    widget.duration.inMilliseconds.toDouble())
                                .toDouble(),
                            max: widget.duration.inMilliseconds.toDouble(),
                            semanticFormatterCallback: (v) =>
                                _time(Duration(milliseconds: v.round())),
                            onChangeStart: (v) {
                              timer?.cancel();
                              setState(() => drag = v);
                            },
                            onChanged: (v) => setState(() => drag = v),
                            onChangeEnd: (v) =>
                                _seek(Duration(milliseconds: v.round()))),
                      Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Row(children: [
                            if (canSeek)
                              IconButton(
                                  tooltip: widget.live
                                      ? 'Início do trecho disponível'
                                      : 'Voltar ao início',
                                  onPressed: () => _seek(Duration.zero),
                                  icon: const Icon(Icons.skip_previous),
                                  color: Colors.white),
                            Expanded(
                                child: Text(
                                    canSeek
                                        ? '${_time(preview)} / ${_time(widget.duration)}${widget.live ? ' · DVR' : ''}'
                                        : widget.live
                                            ? '● AO VIVO · sem retorno disponível'
                                            : _time(widget.position),
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 12))),
                            if (widget.onNext != null)
                              IconButton(
                                  tooltip: 'Próximo capítulo',
                                  onPressed: widget.onNext,
                                  icon: const Icon(Icons.skip_next),
                                  color: Colors.white),
                            IconButton(
                                tooltip: widget.fullscreen
                                    ? 'Sair da tela cheia'
                                    : 'Tela cheia',
                                onPressed: () {
                                  widget.onFullscreen();
                                  _schedule();
                                },
                                icon: Icon(widget.fullscreen
                                    ? Icons.fullscreen_exit
                                    : Icons.fullscreen),
                                color: Colors.white),
                          ])),
                    ])))),
          )),
    ]);
  }
}
