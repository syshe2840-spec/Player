import 'package:flutter/material.dart';
import 'whisper_service.dart';
import 'ai_models_screen.dart';

class AiSubtitleSheet extends StatefulWidget {
  final String videoPath;
  final void Function(String srtPath) onDone;
  const AiSubtitleSheet({super.key, required this.videoPath, required this.onDone});

  static Future<void> show(BuildContext ctx, String videoPath, void Function(String) onDone) =>
    showModalBottomSheet(
      context:ctx, isScrollControlled:true,
      backgroundColor:const Color(0xFF1C1C22),
      shape:const RoundedRectangleBorder(borderRadius:BorderRadius.vertical(top:Radius.circular(20))),
      builder:(_)=>AiSubtitleSheet(videoPath:videoPath, onDone:onDone),
    );

  @override State<AiSubtitleSheet> createState() => _State();
}

class _State extends State<AiSubtitleSheet> {
  List<WhisperModelDef> _downloaded = [];
  WhisperModelDef? _selected;
  String _lang = 'fa';
  bool _useVad = true;
  bool _running = false;
  bool _done = false;
  String _status = '';
  double _progress = 0;
  String? _srtPath;
  bool _alreadyExists = false;
  bool _loading = true;
  bool _improving = false;

  @override void initState(){ super.initState(); _load(); }

  Future<void> _load() async {
    final list = await WhisperService.downloadedModels();
    final active = await WhisperService.getActiveModel();
    final exists = WhisperService.subtitleExists(widget.videoPath);
    if(mounted) setState((){
      _downloaded = list;
      _selected = active ?? (list.isNotEmpty ? list.first : null);
      _alreadyExists = exists;
      _loading = false;
    });
  }

  Future<void> _start({bool force=false}) async {
    if(_selected==null) return;
    if(_alreadyExists && !force){
      // پرسش — استفاده از موجود یا ساخت مجدد
      final action = await showDialog<String>(context:context, builder:(_)=>AlertDialog(
        backgroundColor:const Color(0xFF1C1C22),
        title:const Text('زیرنویس قبلاً ساخته شده',style:TextStyle(color:Colors.white,fontSize:15)),
        content:const Text('برای این ویدیو قبلاً زیرنویس AI ساخته شده. می‌خواهید از همان استفاده کنید یا دوباره بسازید؟',
          style:TextStyle(color:Colors.white70,fontSize:13)),
        actions:[
          TextButton(onPressed:()=>Navigator.pop(context,'cancel'),child:const Text('لغو')),
          TextButton(onPressed:()=>Navigator.pop(context,'rebuild'),child:const Text('ساخت مجدد')),
          FilledButton(onPressed:()=>Navigator.pop(context,'use'),
            style:FilledButton.styleFrom(backgroundColor:const Color(0xFF7C3AED)),
            child:const Text('استفاده از موجود')),
        ],
      ));
      if(action=='cancel'||action==null) return;
      if(action=='use'){
        setState((){ _done=true; _srtPath=WhisperService.srtPath(widget.videoPath); });
        return;
      }
      // rebuild → ادامه میدیم پایین
    }

    setState((){ _running=true; _progress=0; _status='شروع...'; });
    try {
      final path = await WhisperService.transcribe(
        videoPath: widget.videoPath,
        language: _lang,
        model: _selected!,
        useVad: _useVad,
        onStatus:(s,p){ if(mounted) setState((){ _status=s; _progress=p; }); },
      );
      if(mounted) setState((){ _running=false; _done=true; _srtPath=path; });
    } catch(e){
      if(mounted) setState((){ _running=false; _status='خطا: $e'; });
    }
  }

  Future<void> _improve() async {
    if(_srtPath==null) return;
    setState(()=>_improving=true);
    try {
      final improved = await WhisperService.improveSrt(_srtPath!);
      setState((){ _srtPath=improved; _improving=false; });
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content:Text('✨ زیرنویس بهبود یافت'), backgroundColor:Color(0xFF7C3AED)));
    } catch(e){
      setState(()=>_improving=false);
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content:Text('خطا: $e'), backgroundColor:Colors.red));
    }
  }

  @override
  Widget build(BuildContext ctx) => SafeArea(
    child:Padding(
      padding:EdgeInsets.only(left:16,right:16,top:16,bottom:MediaQuery.of(ctx).viewInsets.bottom+16),
      child:_loading
        ? const SizedBox(height:120,child:Center(child:CircularProgressIndicator(color:Color(0xFF7C3AED))))
        : Column(mainAxisSize:MainAxisSize.min,children:[
            Container(width:40,height:4,decoration:BoxDecoration(
              color:Colors.white24,borderRadius:BorderRadius.circular(2))),
            const SizedBox(height:14),
            Row(children:[
              const Icon(Icons.auto_awesome,color:Color(0xFF7C3AED),size:20),
              const SizedBox(width:8),
              const Text('زیرنویس AI',style:TextStyle(color:Colors.white,fontSize:17,fontWeight:FontWeight.bold)),
              const Spacer(),
              TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('بستن')),
            ]),
            const SizedBox(height:12),
            if(_done)        ..._buildDone()
            else if(_running)..._buildRunning()
            else             ..._buildIdle(),
            const SizedBox(height:8),
          ]),
    ),
  );

  List<Widget> _buildIdle()=>[
    if(_downloaded.isEmpty)
      _row(icon:Icons.memory, child:const Text('هیچ مدلی دانلود نشده',style:TextStyle(color:Colors.orange,fontSize:13)),
        trailing:FilledButton.icon(
          onPressed:(){ Navigator.pop(context); Navigator.push(context,MaterialPageRoute(builder:(_)=>const AiModelsScreen())); },
          icon:const Icon(Icons.download,size:14),label:const Text('دانلود',style:TextStyle(fontSize:12)),
          style:FilledButton.styleFrom(backgroundColor:const Color(0xFF7C3AED),
            minimumSize:const Size(0,32),padding:const EdgeInsets.symmetric(horizontal:12)),
        ))
    else _row(
      icon:Icons.memory,
      child:DropdownButton<WhisperModelDef>(
        value:_selected, dropdownColor:const Color(0xFF2A2A35),
        underline:const SizedBox(), isExpanded:true,
        style:const TextStyle(color:Colors.white,fontSize:13),
        items:_downloaded.map((m)=>DropdownMenuItem(value:m,
          child:Text('${m.name} ${m.isQuantized?"(${m.variant})":""}'))).toList(),
        onChanged:(v){ if(v!=null) setState(()=>_selected=v); },
      ),
    ),
    const SizedBox(height:10),

    _row(icon:Icons.language, child:DropdownButton<String>(
      value:_lang, dropdownColor:const Color(0xFF2A2A35),
      underline:const SizedBox(), isExpanded:true,
      style:const TextStyle(color:Colors.white,fontSize:13),
      items:kLanguages.entries.map((e)=>DropdownMenuItem(value:e.key,child:Text(e.value))).toList(),
      onChanged:(v){ if(v!=null) setState(()=>_lang=v); },
    )),
    const SizedBox(height:10),

    // ── VAD ──
    Container(
      padding:const EdgeInsets.symmetric(horizontal:12,vertical:6),
      decoration:BoxDecoration(color:const Color(0xFF2A2A35),borderRadius:BorderRadius.circular(12)),
      child:Row(children:[
        const Icon(Icons.graphic_eq,color:Color(0xFF7C3AED),size:18),
        const SizedBox(width:10),
        const Expanded(child:Text('تشخیص سکوت (VAD)',style:TextStyle(color:Colors.white,fontSize:13))),
        Switch(value:_useVad,activeColor:const Color(0xFF7C3AED),
          onChanged:(v)=>setState(()=>_useVad=v)),
      ]),
    ),
    const SizedBox(height:14),

    if(_alreadyExists)
      Container(
        margin:const EdgeInsets.only(bottom:10),
        padding:const EdgeInsets.all(10),
        decoration:BoxDecoration(color:Colors.blue.withOpacity(0.15),borderRadius:BorderRadius.circular(10)),
        child:const Row(children:[
          Icon(Icons.info_outline,color:Colors.blue,size:16),
          SizedBox(width:8),
          Expanded(child:Text('زیرنویس قبلاً ساخته شده',style:TextStyle(color:Colors.blue,fontSize:12))),
        ]),
      ),

    SizedBox(width:double.infinity,child:FilledButton.icon(
      onPressed:_downloaded.isEmpty ? null : ()=>_start(),
      icon:const Icon(Icons.subtitles),
      label:Text(_alreadyExists?'بررسی زیرنویس':'تولید زیرنویس',style:const TextStyle(fontSize:15)),
      style:FilledButton.styleFrom(
        backgroundColor:const Color(0xFF7C3AED),
        padding:const EdgeInsets.symmetric(vertical:14),
        shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(12)),
      ),
    )),
  ];

  List<Widget> _buildRunning()=>[
    const SizedBox(height:8),
    Text(_status,style:const TextStyle(color:Colors.white,fontSize:14),textAlign:TextAlign.center),
    const SizedBox(height:12),
    LinearProgressIndicator(
      value:_progress>0&&_progress<=1 ? _progress : null,
      backgroundColor:const Color(0xFF2A2A35),
      color:const Color(0xFF7C3AED), minHeight:6,
      borderRadius:BorderRadius.circular(3),
    ),
    const SizedBox(height:4),
    Text(_progress>0 ? '${(_progress*100).clamp(0,100).toInt()}%':'',
      style:const TextStyle(color:Colors.white54,fontSize:12),textAlign:TextAlign.center),
    const SizedBox(height:12),
    OutlinedButton.icon(
      onPressed:()async{ await WhisperService.cancelExtraction(); if(mounted) setState(()=>_running=false); },
      icon:const Icon(Icons.stop_circle_outlined,color:Colors.red),
      label:const Text('لغو',style:TextStyle(color:Colors.red)),
      style:OutlinedButton.styleFrom(side:const BorderSide(color:Colors.red)),
    ),
    const SizedBox(height:6),
    const Text('اپ هنگ نکرده — در پس‌زمینه پردازش می‌شود',
      style:TextStyle(color:Colors.white38,fontSize:11),textAlign:TextAlign.center),
  ];

  List<Widget> _buildDone()=>[
    const SizedBox(height:4),
    const Icon(Icons.check_circle,color:Colors.green,size:44),
    const SizedBox(height:6),
    const Text('زیرنویس آماده شد',
      style:TextStyle(color:Colors.white,fontSize:16,fontWeight:FontWeight.bold)),
    const SizedBox(height:4),
    Text(_srtPath?.split('/').last??'',
      style:const TextStyle(color:Colors.white54,fontSize:11),textAlign:TextAlign.center),
    const SizedBox(height:14),

    // ── دکمه بهبود ──
    SizedBox(width:double.infinity,child:OutlinedButton.icon(
      onPressed:_improving?null:_improve,
      icon:_improving
        ? const SizedBox(width:14,height:14,child:CircularProgressIndicator(strokeWidth:2,color:Color(0xFF7C3AED)))
        : const Icon(Icons.auto_fix_high,size:16,color:Color(0xFF7C3AED)),
      label:Text(_improving?'در حال بهبود...':'✨ بهبود زیرنویس',
        style:const TextStyle(color:Color(0xFF7C3AED),fontSize:13)),
      style:OutlinedButton.styleFrom(
        side:const BorderSide(color:Color(0xFF7C3AED)),
        padding:const EdgeInsets.symmetric(vertical:12),
        shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(12)),
      ),
    )),
    const SizedBox(height:8),

    SizedBox(width:double.infinity,child:FilledButton.icon(
      onPressed:(){ Navigator.pop(context); widget.onDone(_srtPath!); },
      icon:const Icon(Icons.subtitles),
      label:const Text('بارگذاری زیرنویس'),
      style:FilledButton.styleFrom(
        backgroundColor:const Color(0xFF7C3AED),
        padding:const EdgeInsets.symmetric(vertical:14),
        shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(12)),
      ),
    )),
  ];

  Widget _row({required IconData icon, required Widget child, Widget? trailing})=>Container(
    padding:const EdgeInsets.symmetric(horizontal:12,vertical:10),
    decoration:BoxDecoration(color:const Color(0xFF2A2A35),borderRadius:BorderRadius.circular(12)),
    child:Row(children:[
      Icon(icon,color:const Color(0xFF7C3AED),size:18),
      const SizedBox(width:10),
      Expanded(child:child),
      if(trailing!=null) trailing,
    ]),
  );
}

