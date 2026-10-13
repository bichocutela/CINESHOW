class MediaSource {
  const MediaSource({required this.provider, required this.sourceId, required this.pageUrl});
  final String provider, sourceId, pageUrl;
  factory MediaSource.fromJson(Map<String, dynamic> j) => MediaSource(provider: j['provider'] as String, sourceId: j['source_id'].toString(), pageUrl: j['page_url'] as String);
  Map<String,dynamic> toJson() => {'provider':provider,'source_id':sourceId,'page_url':pageUrl};
  String get label => switch(provider) {'rtfilmes'=>'Pobreflix','tontons'=>'TopFlix','xonados'=>'Xonados',_=>provider};
}
class MediaItem {
  const MediaItem({required this.id, required this.title, required this.description, required this.genre, required this.year, required this.durationMinutes, this.posterUrl, this.backdropUrl, this.streamUrl, this.isSeries=false, this.kind='movie', this.sources=const []});
  final String id,title,description,genre,kind;
  final int year,durationMinutes;
  final String? posterUrl,backdropUrl,streamUrl;
  final bool isSeries;
  final List<MediaSource> sources;
  factory MediaItem.fromJson(Map<String,dynamic> j) => MediaItem(id:j['id'].toString(),title:j['title'] as String,description:(j['description'] as String?)??'',genre:(j['genre'] as String?)??'',year:(j['year'] as num?)?.toInt()??0,durationMinutes:0,posterUrl:j['poster_url'] as String?,kind:(j['kind'] as String?)??'movie',isSeries:j['kind']=='series',sources:((j['sources'] as List?)??[]).map((s)=>MediaSource.fromJson(Map<String,dynamic>.from(s as Map))).toList());
  Map<String,dynamic> toJson()=>{'id':id,'title':title,'description':description,'genre':genre,'year':year,'poster_url':posterUrl,'kind':kind,'sources':sources.map((s)=>s.toJson()).toList()};
  MediaItem copyWith({String? streamUrl,String? posterUrl,String? backdropUrl})=>MediaItem(id:id,title:title,description:description,genre:genre,year:year,durationMinutes:durationMinutes,posterUrl:posterUrl??this.posterUrl,backdropUrl:backdropUrl??this.backdropUrl,streamUrl:streamUrl??this.streamUrl,isSeries:isSeries,kind:kind,sources:sources);
  String get typeLabel=>switch(kind){'series'=>'Série','novela'=>'Novela','reality'=>'Reality',_=>'Filme'};
}
