import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../core/models/media_item.dart';
import '../../../core/services/playback_gateway.dart';

class PlayerPage extends StatefulWidget {
  const PlayerPage({
    super.key,
    required this.media,
    this.playbackGateway,
  });

  final MediaItem media;
  final PlaybackGateway? playbackGateway;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  late final PlaybackGateway _playbackGateway;
  VideoPlayerController? _controller;
  String? _errorMessage;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _playbackGateway =
        widget.playbackGateway ?? InMemoryPlaybackGateway();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    final streamUrl = widget.media.streamUrl;
    if (streamUrl == null || streamUrl.isEmpty) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage =
            'Este conteúdo ainda não possui uma fonte autorizada configurada.';
      });
      return;
    }

    try {
      final controller = VideoPlayerController.networkUrl(Uri.parse(streamUrl));
      await controller.initialize();

      final savedPosition = await _playbackGateway.loadPosition(widget.media.id);
      if (savedPosition != null &&
          savedPosition.position < controller.value.duration) {
        await controller.seekTo(savedPosition.position);
      }

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _controller = controller;
        _isLoading = false;
      });
      await controller.play();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Não foi possível carregar este vídeo agora.';
      });
    }
  }

  Future<void> _togglePlayback() async {
    final controller = _controller;
    if (controller == null) return;

    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      await controller.play();
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    final controller = _controller;
    if (controller != null && controller.value.isInitialized) {
      _playbackGateway.savePosition(
        PlaybackPosition(
          mediaId: widget.media.id,
          position: controller.value.position,
          duration: controller.value.duration,
        ),
      );
    }
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.media.title),
        backgroundColor: Colors.black,
      ),
      body: Center(
        child: _isLoading
            ? const CircularProgressIndicator()
            : _errorMessage != null
                ? Padding(
                    padding: const EdgeInsets.all(28),
                    child: Text(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  )
                : controller == null
                    ? const SizedBox.shrink()
                    : _VideoSurface(
                        controller: controller,
                        onTogglePlayback: _togglePlayback,
                      ),
      ),
    );
  }
}

class _VideoSurface extends StatelessWidget {
  const _VideoSurface({
    required this.controller,
    required this.onTogglePlayback,
  });

  final VideoPlayerController controller;
  final VoidCallback onTogglePlayback;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: controller.value.aspectRatio,
      child: Stack(
        alignment: Alignment.center,
        children: [
          VideoPlayer(controller),
          IconButton.filled(
            onPressed: onTogglePlayback,
            iconSize: 34,
            icon: Icon(
              controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
            ),
          ),
        ],
      ),
    );
  }
}
