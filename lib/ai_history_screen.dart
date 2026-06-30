import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'whisper_service.dart';
import 'player.dart';

/// تاریخچه‌ی ویدیوهایی که برایشان زیرنویس AI ساخته شده
class AiHistoryScreen extends StatefulWidget {
  const AiHistoryScreen({super.key});
  @override State<AiHistoryScreen> createState() => _AiHistoryScreenState();
}

class _AiHistoryScreenState extends State<AiHistoryScreen> {
  List<String> _videos = [];
  bool _loading = true;

  @override void initState(){ super.initState(); _load(); }

  Future<void> _load() async {
    final list = await WhisperService.getHistoryVideos();
    if(mounted) setState((){ _videos=list; _loading=false; });
  }

  Future<void> _remove(String path) async {
    final ok = await showDialog<bool>(context:context, builder:(_)=>AlertDialog(
      backgroundColor:const Color(0xFF1C1C22),
      title:const Text('حذف از تاریخچه',style:TextStyle(color:Colors.white,fontSize:15)),
      content:const Text('فقط از این لیست حذف می‌شود؛ خود فایل‌های زیرنویس پاک نمی‌شوند.',
        style:TextStyle(color:Colors.white70,fontSize:12)),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('لغو')),
        FilledButton(onPressed:()=>Navigator.pop(context,true),
          style:FilledButton.styleFrom(backgroundColor:Colors.red),child:const Text('حذف')),
      ],
    ));
    if(ok==true){ await WhisperService.removeFromHistory(path); await _load(); }
  }

  Future<void> _openVideo(String path) async {
    await Navigator.push(context,MaterialPageRoute(
      builder:(_)=>PlayerScreen(playlist:[File(path)],playlistIndex:0),
    ));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor:const Color(0xFF0F0F14),
    appBar:AppBar(
      backgroundColor:const Color(0xFF1C1C22),
      title:const Text('تاریخچه زیرنویس AI',style:TextStyle(color:Colors.white,fontSize:15)),
      leading:IconButton(icon:const Icon(Icons.arrow_back,color:Colors.white),onPressed:()=>Navigator.pop(context)),
    ),
    body: _loading
      ? const Center(child:CircularProgressIndicator(color:Color(0xFF7C3AED)))
      : _videos.isEmpty
        ? const Center(child:Padding(
            padding:EdgeInsets.all(24),
            child:Text('هنوز برای هیچ ویدیویی زیرنویس AI نساخته‌اید',
              style:TextStyle(color:Colors.white38,fontSize:13),textAlign:TextAlign.center)))
        : ListView.builder(
            padding:const EdgeInsets.all(12),
            itemCount:_videos.length,
            itemBuilder:(_,i){
              final path = _videos[i];
              final langs = WhisperService.existingLanguages(path);
              return Container(
                margin:const EdgeInsets.only(bottom:8),
                decoration:BoxDecoration(color:const Color(0xFF1C1C22),borderRadius:BorderRadius.circular(12)),
                child:ListTile(
                  onTap:()=>_openVideo(path),
                  leading:const Icon(Icons.movie_outlined,color:Color(0xFF7C3AED)),
                  title:Text(p.basename(path),style:const TextStyle(color:Colors.white,fontSize:13),
                    overflow:TextOverflow.ellipsis),
                  subtitle:Wrap(spacing:4,runSpacing:2,children:langs.map((l)=>Container(
                    padding:const EdgeInsets.symmetric(horizontal:6,vertical:2),
                    decoration:BoxDecoration(color:const Color(0xFF7C3AED).withOpacity(0.2),borderRadius:BorderRadius.circular(6)),
                    child:Text(kLanguages[l]??l,style:const TextStyle(color:Color(0xFF7C3AED),fontSize:10)),
                  )).toList()),
                  trailing:IconButton(
                    icon:const Icon(Icons.close,color:Colors.white38,size:18),
                    onPressed:()=>_remove(path),
                  ),
                ),
              );
            },
          ),
  );
}

