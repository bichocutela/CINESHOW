import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../core/services/iptv_catalog.dart';
import '../../core/services/live_playback.dart';

class LivePlayerPage extends StatefulWidget {
  const LivePlayerPage({super.key, required this.channel, this.selected = 0});
  final TvChannel channel;
  final int selected;
  @override
  State<LivePlayerPage> createState() => _LivePlayerPageState();
}

class _LivePlayerPageState extends State<LivePlayerPage>
    with WidgetsBindingObserver {
  late final plan = LivePlaybackPlan(widget.channel, selected: widget.selected);
  Player? player;
  VideoController? video;
  final subscriptions = <StreamSubscription<dynamic>>[];
  int generation = 0, source = 0;
  bool loading = true, software = false, foreground = true;
  String? error, detail;
  Timer? watchdog;
  DateTime lastProgress = DateTime.now();

  @override
  void initState() {
    super.initState();
    MediaKit.ensureInitialized();
    WidgetsBinding.instance.addObserver(this);
    if (plan.next case final index?) {
      _open(index);
    } else {
      loading = false;
      error = 'Este canal não tem fontes disponíveis.';
    }
  }

  Future<void> _open(int index, {bool reset = false}) async {
    final request = ++generation;
    watchdog?.cancel();
    if (reset) plan.attempted.clear();
    plan.attempted.add(index);
    setState(() {
      source = index;
      loading = true;
      error = null;
      detail = null;
      video = null;
    });
    final previousSubscriptions =
        List<StreamSubscription<dynamic>>.of(subscriptions);
    subscriptions.clear();
    final previous = player;
    player = null;
    for (final subscription in previousSubscriptions) {
      await subscription.cancel();
    }
    await previous?.dispose();
    if (!mounted || request != generation) return;
    try {
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
        if (!mounted || request != generation) return;
        detail = safePlaybackDetail(message);
        if (loading || !next.state.playing) _failed(request, message);
      }));
      subscriptions.add(next.stream.completed.listen((completed) {
        if (completed && mounted && request == generation) {
          _failed(request, 'A transmissão foi encerrada pela fonte.');
        }
      }));
      var previousPosition = Duration.zero;
      subscriptions.add(next.stream.position.listen((position) {
        if (mounted && request == generation && position != previousPosition) {
          previousPosition = position;
          lastProgress = DateTime.now();
        }
      }));
      subscriptions.add(next.stream.playing.listen((playing) {
        if (playing && mounted && request == generation) {
          lastProgress = DateTime.now();
        }
      }));
      final media = plan.source(index);
      await (() async {
        await next
            .open(Media(media.streamUrl!, httpHeaders: media.streamHeaders));
        await controller.waitUntilFirstFrameRendered;
      })()
          .timeout(const Duration(seconds: 35));
      if (!mounted || request != generation) return;
      setState(() => loading = false);
      lastProgress = DateTime.now();
      watchdog = Timer.periodic(const Duration(seconds: 5), (_) {
        if (mounted &&
            request == generation &&
            foreground &&
            next.state.playing &&
            DateTime.now().difference(lastProgress) >
                const Duration(seconds: 30)) {
          _failed(request, 'Timeout: transmissão sem progresso.');
        }
      });
    } catch (exception) {
      _failed(request, exception.toString());
    }
  }

  void _failed(int request, String message) {
    if (!mounted || request != generation) return;
    watchdog?.cancel();
    final alternative = plan.next;
    if (alternative != null) {
      unawaited(_open(alternative));
      return;
    }
    generation++;
    unawaited(player?.pause() ?? Future<void>.value());
    setState(() {
      loading = false;
      error = livePlaybackError(message);
      detail = safePlaybackDetail(message);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    lastProgress = DateTime.now();
    if (!foreground) player?.pause();
  }

  @override
  void dispose() {
    generation++;
    watchdog?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    for (final subscription in subscriptions) {
      unawaited(subscription.cancel());
    }
    player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: Text(widget.channel.name), actions: [
        PopupMenuButton<int>(
            tooltip: 'Escolher fonte',
            onSelected: (index) => _open(index, reset: true),
            itemBuilder: (_) => [
                  for (var i = 0; i < widget.channel.streams.length; i++)
                    PopupMenuItem(
                        value: i,
                        child: Text(
                            'Fonte ${i + 1} · ${widget.channel.streams[i]['quality'] ?? ''}'))
                ]),
        IconButton(
            tooltip: software
                ? 'Voltar ao modo automático'
                : 'Modo compatível para tela preta ou erro de vídeo',
            icon: Icon(software
                ? Icons.settings_backup_restore
                : Icons.settings_suggest),
            onPressed: () {
              software = !software;
              _open(source, reset: true);
            }),
      ]),
      body: SafeArea(
          child: Column(children: [
        Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
                '● AO VIVO · Fonte ${source + 1}/${widget.channel.streams.length}${software ? ' · Modo compatível' : ''}',
                style: const TextStyle(color: Colors.redAccent))),
        Expanded(
            child: Stack(alignment: Alignment.center, children: [
          if (video != null)
            Video(key: ValueKey(generation), controller: video!),
          if (loading) const Center(child: CircularProgressIndicator()),
          if (error != null)
            ColoredBox(
                color: Colors.black87,
                child: Center(
                    child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          Text(error!, textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                              onPressed: () =>
                                  _open(widget.selected, reset: true),
                              icon: const Icon(Icons.refresh),
                              label: const Text('Tentar fontes novamente')),
                          if (!software)
                            TextButton(
                                onPressed: () {
                                  software = true;
                                  _open(widget.selected, reset: true);
                                },
                                child: const Text('Tentar modo compatível')),
                          if (detail != null)
                            ExpansionTile(
                                title: const Text('Detalhes do erro'),
                                children: [
                                  SelectableText(detail!,
                                      style: const TextStyle(fontSize: 12)),
                                ]),
                        ])))),
        ])),
      ])));
}
