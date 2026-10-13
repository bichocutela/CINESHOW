import 'package:cineshow/main.dart';
import 'package:cineshow/core/models/media_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
void main(){
 testWidgets('card abre detalhes ao tocar',(tester)async{
  var opened=false;
  const item=MediaItem(id:'1',title:'Uma novela',description:'',genre:'',year:0,durationMinutes:0,kind:'novela');
  await tester.pumpWidget(MaterialApp(home:Scaffold(body:SizedBox(width:150,height:260,child:PosterCard(item:item,onOpen:()=>opened=true)))));
  await tester.tap(find.text('Uma novela'));expect(opened,isTrue);expect(find.text('Novela'),findsOneWidget);
 });
}
