import 'package:flutter/material.dart';

class TitleRatings extends StatelessWidget {
  const TitleRatings({super.key, required this.data, required this.onImdb, required this.onRotten});
  final Map<String, dynamic> data;
  final VoidCallback onImdb, onRotten;

  Widget _score(String symbol, String label, String value, String hint, VoidCallback open) =>
      Expanded(child: Tooltip(message: hint, child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        child: InkWell(onTap: open, borderRadius: BorderRadius.circular(12), child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 12),
          child: Column(children: [
            Text(symbol, style: const TextStyle(fontSize: 22)),
            const SizedBox(height: 5),
            FittedBox(child: Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
            const SizedBox(height: 4),
            FittedBox(child: Text(label, style: const TextStyle(fontSize: 12)))
          ]))))));

  @override
  Widget build(BuildContext context) {
    final imdb = data['imdbRating'] as num?;
    String percent(String field) => data[field] is num ? '${data[field]}%' : '—';
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _score('⭐', 'IMDb', imdb == null ? '—' : '${imdb.toStringAsFixed(1).replaceAll('.', ',')}/10',
        '${data['imdbRatingSource'] ?? 'IMDb'} · toque para abrir a ficha', onImdb),
      _score('🍅', 'Tomatometer', percent('rtRating'), 'Críticos · Rotten Tomatoes', onRotten),
      _score('🍿', 'Popcornmeter', percent('rtAudienceRating'), 'Público · Rotten Tomatoes', onRotten)
    ]);
  }
}
