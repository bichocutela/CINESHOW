import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/models/media_item.dart';
import '../../core/services/title_information.dart';
import 'actor_titles_page.dart';
import 'title_ratings.dart';
import 'published_cast.dart';

class TitleInformation extends StatefulWidget {
  const TitleInformation(
      {super.key,
      required this.item,
      required this.source,
      required this.onOpenTitle});
  final MediaItem item;
  final MediaSource? source;
  final ValueChanged<MediaItem> onOpenTitle;
  @override
  State<TitleInformation> createState() => _TitleInformationState();
}

class _TitleInformationState extends State<TitleInformation> {
  late Future<Map<String, dynamic>> future;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant TitleInformation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id ||
        oldWidget.source?.provider != widget.source?.provider ||
        oldWidget.source?.sourceId != widget.source?.sourceId) {
      _load();
    }
  }

  void _load({bool force = false}) {
    future = TitleInformationService.instance
        .load(widget.item, widget.source, force: force);
  }

  Future<void> _open(Uri uri) async {
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw StateError('Não foi possível abrir.');
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Não foi possível abrir a consulta.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
      future: future,
      builder: (context, snapshot) {
        final data = snapshot.data ??
            <String, dynamic>{
              'plot': widget.item.description,
              'plotSource': 'Catálogo'
            };
        final plot = data['plot'] as String? ?? '';
        final title = data['title'] as String? ?? widget.item.title;
        final year = data['year'] as num? ?? widget.item.year;
        final query = '$title${year > 0 ? ' $year' : ''}';
        final id = data['imdbId'] as String?;
        final imdbUri = id != null && RegExp(r'^tt\d{7,10}$').hasMatch(id)
            ? Uri.https('www.imdb.com', '/title/$id/')
            : Uri.https('www.imdb.com', '/find/', {'q': query});
        final rtUri = data['rtUrl'] is String
            ? Uri.parse(data['rtUrl'] as String)
            : Uri.https(
                'www.rottentomatoes.com', '/search/', {'search': query});
        final loading = snapshot.connectionState == ConnectionState.waiting;
        return Padding(
            padding: const EdgeInsets.only(top: 20),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Expanded(
                    child: Text('Sinopse',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold))),
                IconButton(
                    tooltip: 'Atualizar informações',
                    onPressed: loading
                        ? null
                        : () => setState(() => _load(force: true)),
                    icon: const Icon(Icons.refresh))
              ]),
              if (loading) const LinearProgressIndicator(),
              const SizedBox(height: 8),
              SelectableText(
                  plot.isEmpty ? 'Sinopse não disponível nesta fonte.' : plot),
              if (plot.isNotEmpty)
                Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('Sinopse: ${data['plotSource'] ?? 'Catálogo'}',
                        style: const TextStyle(
                            fontSize: 12, color: Colors.white60))),
              if (title != widget.item.title ||
                  (year > 0 && year != widget.item.year))
                Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                        'Ficha de referência: $title${year > 0 ? ' ($year)' : ''}',
                        style: const TextStyle(color: Colors.white70))),
              if (year > 0)
                Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text('Ano: $year')),
              if ((data['released'] as String? ?? '').isNotEmpty)
                Text('Lançamento: ${data['released']}'),
              if ((data['director'] as String? ?? '').isNotEmpty)
                Text('Direção: ${data['director']}'),
              if ((data['runtime'] as String? ?? '').isNotEmpty)
                Text('Duração: ${data['runtime']}'),
              if ((data['cast'] as List?)?.isNotEmpty == true) ...[
                const SizedBox(height: 12),
                PublishedCast(names: (data['cast'] as List).whereType<String>().toList(),
                  details: (data['castDetails'] as List? ?? []).whereType<Map>().toList(),
                  onActor: (actor) => Navigator.push(context, MaterialPageRoute<void>(
                    builder: (_) => ActorTitlesPage(name: actor, onOpen: widget.onOpenTitle))))
              ],
              const SizedBox(height: 18),
              const Text('Avaliações',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TitleRatings(data: data, onImdb: () => _open(imdbUri), onRotten: () => _open(rtUri)),
              if (data['imdbRatingSource'] != null)
                Padding(padding: const EdgeInsets.only(top: 6), child: Text('${data['imdbRatingSource']}',
                    style: const TextStyle(fontSize: 11, color: Colors.white60))),
              Wrap(spacing: 8, children: [
                OutlinedButton.icon(
                    onPressed: () => _open(imdbUri),
                    icon: const Icon(Icons.open_in_new),
                    label: Text(id == null
                        ? 'Pesquisar no IMDb'
                        : 'Ver ficha no IMDb')),
                OutlinedButton.icon(
                    onPressed: () => _open(rtUri),
                    icon: const Icon(Icons.open_in_new),
                    label: Text(data['rtUrl'] == null
                        ? 'Pesquisar no Rotten Tomatoes'
                        : 'Ver ficha no Rotten Tomatoes'))
              ])
            ]));
      });
}
