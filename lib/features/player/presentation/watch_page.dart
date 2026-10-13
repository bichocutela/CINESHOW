import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import '../../../core/models/media_item.dart';
import '../../../core/services/video_sources.dart';
import '../../../core/services/playback_gateway.dart';
import 'player_page.dart';

class WatchPage extends StatefulWidget {
  const WatchPage({
    super.key,
    required this.media,
    required this.source,
    required this.pageUrl,
    this.episodes = const [],
    this.episodeIndex = -1,
  });
  final MediaItem media;
  final MediaSource source;
  final String pageUrl;
  final List<Map<String, dynamic>> episodes;
  final int episodeIndex;
  @override
  State<WatchPage> createState() => _WatchState();
}

class _WatchState extends State<WatchPage> with WidgetsBindingObserver {
  final gateway = PersistentPlaybackGateway();
  WebViewController? web;
  List<VideoSource> sources = [];
  int selected = 0, loading = 0, generation = 0, webRequest = 0;
  late int episodeIndex = widget.episodeIndex;
  late String pageUrl = widget.pageUrl;
  String? error;
  bool resolving = true, full = false, paused = true, hasVideo = false;
  bool restored = false, foreground = true;
  double position = 0, duration = 0, volume = 1, rate = 1;
  List<String> captions = [];
  Timer? saveTimer;
  Future<PlaybackPosition?>? saved;
  Route<void>? videoRoute;
  String get title => episodeIndex >= 0
      ? '${widget.media.title} · ${widget.episodes[episodeIndex]['title']}'
      : widget.media.title;
  String get mediaId => '${widget.media.id}:$pageUrl';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    saveTimer = Timer.periodic(const Duration(seconds: 10), (_) => _save());
    _resolve();
  }

  Future<void> _resolve() async {
    final request = ++generation;
    final old = web;
    web = null;
    if (old != null) {
      unawaited(
        old
            .runJavaScript('window.cineVideo?.pause();')
            .catchError((Object _) {}),
      );
    }
    setState(() {
      resolving = true;
      error = null;
      hasVideo = false;
      restored = false;
    });
    try {
      final options = await VideoSources().resolve(
        widget.media,
        widget.source,
        pageUrl,
      );
      if (!mounted || request != generation) return;
      setState(() {
        sources = options;
        selected = 0;
        resolving = false;
      });
      if (!options.first.native) await _loadWeb();
    } catch (_) {
      if (mounted && request == generation) {
        setState(() {
          resolving = false;
          error = 'Não foi possível carregar esta fonte.';
        });
      }
    }
  }

  Future<void> _loadWeb() async {
    final request = ++webRequest;
    final old = web;
    web = null;
    if (old != null) {
      try {
        await old.runJavaScript('window.cineVideo?.pause();');
        await old.loadRequest(Uri.parse('about:blank'));
      } catch (_) {}
    }
    if (!mounted || request != webRequest) return;
    hasVideo = false;
    restored = false;
    position = 0;
    duration = 0;
    saved = gateway.loadPosition(mediaId);
    final controller = WebViewController();
    web = controller;
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await controller.setBackgroundColor(Colors.black);
    await controller.addJavaScriptChannel(
      'CineVideoState',
      onMessageReceived: (message) async {
        if (!mounted || web != controller || message.message.length > 8192) {
          return;
        }
        try {
          final value = jsonDecode(message.message) as Map;
          double number(String key, double fallback) {
            final v = value[key];
            return v is num && v.toDouble().isFinite ? v.toDouble() : fallback;
          }

          setState(() {
            hasVideo = value['found'] == true;
            position = number('position', 0).clamp(0, 864000).toDouble();
            duration = number('duration', 0).clamp(0, 864000).toDouble();
            volume = number('volume', 1).clamp(0, 1).toDouble();
            rate = number('rate', 1);
            paused = value['paused'] != false;
            captions = (value['captions'] as List? ?? [])
                .take(20)
                .map((v) => v.toString())
                .toList();
          });
          if (hasVideo && duration > 0 && !restored) {
            restored = true;
            final previous = await saved;
            if (mounted &&
                web == controller &&
                previous != null &&
                previous.progress < .95) {
              await _command(
                'v.currentTime=${previous.position.inMilliseconds / 1000};',
              );
            }
          }
        } catch (_) {
          /* Ignore malformed messages from embedded pages. */
        }
      },
    );
    await controller.setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: (request) =>
            ['https', 'about'].contains(Uri.tryParse(request.url)?.scheme)
                ? NavigationDecision.navigate
                : NavigationDecision.prevent,
        onProgress: (value) {
          if (mounted && web == controller) setState(() => loading = value);
        },
        onPageStarted: (_) {
          if (mounted && web == controller) {
            setState(() {
              hasVideo = false;
              error = null;
            });
          }
        },
        onPageFinished: (_) async {
          if (web == controller) await controller.runJavaScript(_bridge);
        },
        onWebResourceError: (event) {
          if (event.isForMainFrame == true && mounted && web == controller) {
            setState(
              () => error =
                  'O player não carregou. Tente outro servidor ou recarregue.',
            );
          }
        },
      ),
    );
    if (controller.platform is AndroidWebViewController) {
      final android = controller.platform as AndroidWebViewController;
      await android.setMediaPlaybackRequiresUserGesture(true);
      await android.setCustomWidgetCallbacks(
        onShowCustomWidget: (custom, onHidden) {
          if (!mounted || videoRoute != null) return;
          final route = MaterialPageRoute<void>(
            fullscreenDialog: true,
            builder: (_) =>
                Scaffold(backgroundColor: Colors.black, body: custom),
          );
          videoRoute = route;
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
          Navigator.of(context).push(route).whenComplete(() {
            videoRoute = null;
            onHidden();
            SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
          });
        },
        onHideCustomWidget: () {
          final route = videoRoute;
          if (mounted && route != null && route.isActive) {
            Navigator.of(context).removeRoute(route);
          }
        },
      );
    }
    if (!mounted || web != controller) return;
    await controller.loadRequest(Uri.parse(sources[selected].url));
    if (mounted) setState(() {});
  }

  Future<void> _command(String command) async {
    try {
      await web?.runJavaScript(
        '(() => { const v=window.cineVideo; if(v) { $command } })();',
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Este controle não está disponível neste player.'),
          ),
        );
      }
    }
  }

  Future<void> _save() async {
    if (!hasVideo || duration <= 0) return;
    try {
      await gateway.savePosition(
        PlaybackPosition(
          mediaId: mediaId,
          position: Duration(milliseconds: (position * 1000).round()),
          duration: Duration(milliseconds: (duration * 1000).round()),
        ),
      );
    } catch (_) {
      /* Do not interrupt playback for a storage failure. */
    }
  }

  void _episode(int index) {
    unawaited(_save());
    setState(() {
      episodeIndex = index;
      pageUrl = widget.episodes[index]['page_url'] as String;
    });
    _resolve();
  }

  VoidCallback? get previous =>
      episodeIndex > 0 ? () => _episode(episodeIndex - 1) : null;
  VoidCallback? get next =>
      episodeIndex >= 0 && episodeIndex + 1 < widget.episodes.length
          ? () => _episode(episodeIndex + 1)
          : null;

  Future<void> _fullscreen() async {
    setState(() => full = !full);
    await SystemChrome.setEnabledSystemUIMode(
      full ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
    await SystemChrome.setPreferredOrientations(
      full
          ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
          : DeviceOrientation.values,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (!foreground) {
      unawaited(_save());
      unawaited(_command('v.pause();'));
    }
  }

  @override
  void dispose() {
    generation++;
    webRequest++;
    saveTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_save());
    unawaited(_command('v.pause();'));
    web?.loadRequest(Uri.parse('about:blank'));
    if (full) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    }
    super.dispose();
  }

  String _time(double seconds) =>
      '${seconds ~/ 60}:${(seconds.toInt() % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    if (!resolving && sources.isNotEmpty && sources[selected].native) {
      final media = MediaItem(
        id: mediaId,
        title: title,
        description: '',
        genre: widget.media.genre,
        year: widget.media.year,
        durationMinutes: 0,
        streamUrl: sources[selected].url,
      );
      return PlayerPage(
        key: ValueKey(mediaId),
        media: media,
        onNext: next,
        onPrevious: previous,
      );
    }
    return PopScope(
      canPop: !full,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && full) _fullscreen();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: full
            ? null
            : AppBar(
                title: Text(title),
                actions: [
                  IconButton(
                    tooltip: 'Recarregar player',
                    onPressed: resolving
                        ? null
                        : () {
                            web?.reload();
                          },
                    icon: const Icon(Icons.refresh),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (_) async {
                      await launchUrl(
                        Uri.parse(pageUrl),
                        mode: LaunchMode.externalApplication,
                      );
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'external',
                        child: Text('Abrir no navegador'),
                      ),
                    ],
                  ),
                ],
              ),
        body: resolving
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  if (!full && sources.isNotEmpty)
                    Row(
                      children: [
                        IconButton(
                          tooltip: 'Episódio anterior',
                          onPressed: previous,
                          icon: const Icon(Icons.skip_previous),
                        ),
                        Expanded(
                          child: DropdownButton<int>(
                            isExpanded: true,
                            value: selected,
                            items: [
                              for (var i = 0; i < sources.length; i++)
                                DropdownMenuItem(
                                  value: i,
                                  child: Text(sources[i].label),
                                ),
                            ],
                            onChanged: (index) async {
                              if (index == null) return;
                              unawaited(_save());
                              setState(() => selected = index);
                              await _loadWeb();
                            },
                          ),
                        ),
                        IconButton(
                          tooltip: 'Próximo episódio',
                          onPressed: next,
                          icon: const Icon(Icons.skip_next),
                        ),
                        IconButton(
                          tooltip: 'Tela cheia',
                          onPressed: _fullscreen,
                          icon: const Icon(Icons.fullscreen),
                        ),
                      ],
                    ),
                  if (loading < 100)
                    LinearProgressIndicator(value: loading / 100),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(error!),
                    ),
                  Expanded(
                    child: web == null
                        ? const SizedBox.shrink()
                        : WebViewWidget(controller: web!),
                  ),
                  if (hasVideo)
                    SafeArea(
                      top: false,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: Text(_time(position)),
                              ),
                              Expanded(
                                child: Slider(
                                  value: position
                                      .clamp(0, duration > 0 ? duration : 1)
                                      .toDouble(),
                                  max: duration > 0 ? duration : 1,
                                  onChanged: duration > 0
                                      ? (value) =>
                                          _command('v.currentTime=$value;')
                                      : null,
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: Text(_time(duration)),
                              ),
                            ],
                          ),
                          Wrap(
                            alignment: WrapAlignment.center,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              IconButton(
                                tooltip: 'Voltar 10 segundos',
                                onPressed: () => _command(
                                  'v.currentTime=Math.max(0,v.currentTime-10);',
                                ),
                                icon: const Icon(Icons.replay_10),
                              ),
                              IconButton(
                                tooltip: paused ? 'Reproduzir' : 'Pausar',
                                onPressed: () => _command(
                                  'if(v.paused)v.play();else v.pause();',
                                ),
                                icon: Icon(
                                  paused ? Icons.play_arrow : Icons.pause,
                                ),
                              ),
                              IconButton(
                                tooltip: 'Avançar 10 segundos',
                                onPressed: () => _command(
                                  'v.currentTime=Math.min(v.duration,v.currentTime+10);',
                                ),
                                icon: const Icon(Icons.forward_10),
                              ),
                              IconButton(
                                tooltip:
                                    volume == 0 ? 'Ativar som' : 'Silenciar',
                                onPressed: () => _command(
                                  'v.volume=v.volume===0?1:0;v.muted=false;',
                                ),
                                icon: Icon(
                                  volume == 0
                                      ? Icons.volume_off
                                      : Icons.volume_up,
                                ),
                              ),
                              SizedBox(
                                width: 90,
                                child: Slider(
                                  value: volume,
                                  onChanged: (value) => _command(
                                    'v.volume=$value;v.muted=false;',
                                  ),
                                ),
                              ),
                              PopupMenuButton<double>(
                                tooltip: 'Velocidade',
                                initialValue: rate,
                                onSelected: (value) =>
                                    _command('v.playbackRate=$value;'),
                                itemBuilder: (_) => [
                                  for (final value in [
                                    .5,
                                    .75,
                                    1.0,
                                    1.25,
                                    1.5,
                                    2.0,
                                  ])
                                    PopupMenuItem(
                                      value: value,
                                      child: Text('${value}x'),
                                    ),
                                ],
                                child: Padding(
                                  padding: const EdgeInsets.all(10),
                                  child: Text('${rate}x'),
                                ),
                              ),
                              if (captions.isNotEmpty)
                                PopupMenuButton<int>(
                                  tooltip: 'Legendas',
                                  onSelected: (index) => _command(
                                    'for(let i=0;i<v.textTracks.length;i++)v.textTracks[i].mode=i===$index?"showing":"disabled";',
                                  ),
                                  itemBuilder: (_) => [
                                    const PopupMenuItem(
                                      value: -1,
                                      child: Text('Sem legendas'),
                                    ),
                                    for (var i = 0; i < captions.length; i++)
                                      PopupMenuItem(
                                        value: i,
                                        child: Text(captions[i]),
                                      ),
                                  ],
                                  icon: const Icon(Icons.closed_caption),
                                ),
                              IconButton(
                                tooltip:
                                    full ? 'Sair da tela cheia' : 'Tela cheia',
                                onPressed: _fullscreen,
                                icon: Icon(
                                  full
                                      ? Icons.fullscreen_exit
                                      : Icons.fullscreen,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  if (!hasVideo && !full)
                    const Padding(
                      padding: EdgeInsets.all(10),
                      child: Text(
                        'Toque em reproduzir no player. Os controles, legendas e qualidade disponíveis dependem desta fonte.',
                        style: TextStyle(fontSize: 12, color: Colors.white60),
                        textAlign: TextAlign.center,
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

const _bridge = r'''
(() => {
  if(window.cineTimer)clearInterval(window.cineTimer);
  function findVideo(doc) {
    const videos=[...doc.querySelectorAll('video')];
    let best=videos.find(v=>!v.paused)||videos.find(v=>v.duration>0)||videos[0];
    if(best)return best;
    for(const frame of doc.querySelectorAll('iframe')){
      try{const inner=frame.contentDocument;if(inner){best=findVideo(inner);if(best)return best;}}catch(e){}
    }
    return null;
  }
  window.cineTimer=setInterval(()=>{
    const v=findVideo(document);window.cineVideo=v;
    if(v)v.controls=true;
    CineVideoState.postMessage(JSON.stringify(v?{found:true,position:v.currentTime,duration:Number.isFinite(v.duration)?v.duration:0,
      volume:v.muted?0:v.volume,rate:v.playbackRate,paused:v.paused,captions:[...v.textTracks].map(t=>t.label||t.language||'Legenda')}:{found:false}));
  },750);
})();
''';
