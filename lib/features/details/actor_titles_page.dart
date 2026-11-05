import 'package:flutter/material.dart';
import '../../core/models/media_item.dart';
import '../../core/services/actor_catalog.dart';
import '../../core/services/poster_sources.dart';

class ActorTitlesPage extends StatelessWidget {
  const ActorTitlesPage({super.key, required this.name, required this.onOpen});
  final String name;
  final ValueChanged<MediaItem> onOpen;
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: Text(name)),
      body: SafeArea(child: FutureBuilder<List<MediaItem>>(
        future: ActorCatalog().titles(name), builder: (context, snapshot) {
          final items = snapshot.data ?? [];
          return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 32), children: [
            const Text('Títulos com este nome no elenco já identificado no catálogo. A lista usa créditos confirmados nas fichas consultadas.'),
            if (snapshot.connectionState == ConnectionState.waiting) const LinearProgressIndicator(),
            if (snapshot.hasData && items.isEmpty) const Padding(padding: EdgeInsets.all(24),
                child: Text('Nenhum outro título identificado até agora.')),
            for (final item in items) ListTile(
              leading: posterSources(item).isEmpty ? const Icon(Icons.movie_outlined) :
                Image.network(posterSources(item).first, width: 40, height: 60, fit: BoxFit.cover,
                  errorBuilder: (_, e, stack) => const Icon(Icons.movie_outlined)),
              title: Text(item.title), subtitle: Text('${item.typeLabel}${item.year > 0 ? ' · ${item.year}' : ''}'),
              onTap: () { Navigator.pop(context); onOpen(item); })
          ]);
        })));
}
