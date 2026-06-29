import 'package:flutter/material.dart';
import 'whisper_service.dart';

class AiModelsScreen extends StatefulWidget {
  const AiModelsScreen({super.key});
  @override State<AiModelsScreen> createState() => _AiModelsScreenState();
}

class _AiModelsScreenState extends State<AiModelsScreen> {
  final Map<String,bool>   _dl   = {};
  final Map<String,double> _prog = {};
  final Map<String,bool>   _busy = {};
  String? _active;
  bool _loading = true;

  @override void initState(){ super.initState(); _refresh(); }

  Future<void> _refresh() async {
    final a = await WhisperService.getActiveModel();
    final Map<String,bool> dl={};
    for(final m in kWhisperModels) dl[m.model.modelName]=await WhisperService.isDownloaded(m);
    if(mounted) setState((){ _dl.addAll(dl); _active=a?.model.modelName; _loading=false; });
  }

  Future<void> _download(WhisperModelDef m) async {
    final key = m.model.modelName;
    setState((){ _busy[key]=true; _prog[key]=0; });

    // feedback فوری که دانلود شروع شد
    if(mounted) ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content:Text('دانلود ${m.name} شروع شد (${m.sizeMb}MB)...'),
        duration:const Duration(seconds:3), backgroundColor:const Color(0xFF7C3AED)));

    try {
      await for(final p in WhisperService.downloadModel(m)){
        if(!mounted) break;
        setState(()=> _prog[key]= p<0 ? (_prog[key]??0)+0.01 : p );
      }
      await _refresh();
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content:Text('✓ مدل ${m.name} دانلود شد'),
          backgroundColor:Colors.green, duration:const Duration(seconds:3)));
    } catch(e){
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content:Text('خطا: $e'), backgroundColor:Colors.red,
          duration:const Duration(seconds:6)));
    } finally {
      if(mounted) setState(()=>_busy[key]=false);
    }
  }

  void _cancel(WhisperModelDef m){
    WhisperService.cancelDownload();
    setState(()=>_busy[m.model.modelName]=false);
  }

  @override
  Widget build(BuildContext ctx) => Scaffold(
    backgroundColor:const Color(0xFF0F0F14),
    appBar: AppBar(
      backgroundColor:const Color(0xFF1C1C22),
      title:const Text('مدل‌های AI زیرنویس',style:TextStyle(color:Colors.white,fontSize:16)),
      leading:IconButton(icon:const Icon(Icons.arrow_back,color:Colors.white),onPressed:()=>Navigator.pop(ctx)),
    ),
    body: _loading
      ? const Center(child:CircularProgressIndicator(color:Color(0xFF7C3AED)))
      : ListView(padding:const EdgeInsets.all(16), children:[
          _infoCard(),
          const SizedBox(height:12),
          ...kWhisperModels.map(_buildCard),
        ]),
  );

  Widget _infoCard() => Container(
    padding:const EdgeInsets.all(12),
    decoration:BoxDecoration(color:const Color(0xFF1C1C22).withOpacity(0.8),borderRadius:BorderRadius.circular(12)),
    child:const Row(children:[
      Icon(Icons.info_outline,color:Color(0xFF7C3AED),size:18),
      SizedBox(width:8),
      Expanded(child:Text('فقط یک‌بار دانلود کنید — بعد کاملاً آفلاین کار می‌کند',
        style:TextStyle(color:Colors.white70,fontSize:12))),
    ]),
  );

  Widget _buildCard(WhisperModelDef m){
    final key = m.model.modelName;
    final dl    = _dl[key]   ?? false;
    final busy  = _busy[key] ?? false;
    final prog  = _prog[key] ?? 0.0;
    final act   = _active == key;

    return Container(
      margin:const EdgeInsets.only(bottom:12),
      decoration:BoxDecoration(
        color:const Color(0xFF1C1C22),
        borderRadius:BorderRadius.circular(16),
        border:Border.all(color: act?const Color(0xFF7C3AED):Colors.white12, width:act?2:1),
      ),
      child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[

        // ── عنوان ──
        Row(children:[
          _tag(m.name, const Color(0xFF7C3AED)),
          const SizedBox(width:8),
          if(act)_tag('فعال', Colors.green),
          if(dl && !act)_tag('دانلود شده', Colors.blue),
          const Spacer(),
          Text('~${m.sizeMb} MB',style:const TextStyle(color:Colors.white54,fontSize:12)),
        ]),
        const SizedBox(height:6),
        Text(m.desc,style:const TextStyle(color:Colors.white70,fontSize:12)),
        const SizedBox(height:6),

        // ── ستاره‌ها ──
        Row(children:[
          _stars('سرعت',m.speedStars), const SizedBox(width:16), _stars('دقت',m.accStars),
        ]),

        // ── progress ──
        if(busy)...[
          const SizedBox(height:12),
          LinearProgressIndicator(
            value: prog>0&&prog<=1 ? prog : null,
            backgroundColor:const Color(0xFF2A2A35),
            color:const Color(0xFF7C3AED), minHeight:6,
            borderRadius:BorderRadius.circular(3),
          ),
          const SizedBox(height:4),
          Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[
            Text(prog>0&&prog<=1 ? '${(prog*100).toInt()}% از ${m.sizeMb}MB'
                : 'در حال دانلود...',
              style:const TextStyle(color:Colors.white54,fontSize:11)),
            TextButton(onPressed:()=>_cancel(m),
              child:const Text('لغو',style:TextStyle(color:Colors.red,fontSize:11))),
          ]),
        ],

        // ── دکمه‌ها ──
        if(!busy)...[
          const SizedBox(height:12),
          Row(children:[
            if(!dl) Expanded(child:FilledButton.icon(
              onPressed:()=>_download(m),
              icon:const Icon(Icons.download,size:16),
              label:Text('دانلود ${m.name} (~${m.sizeMb}MB)'),
              style:FilledButton.styleFrom(backgroundColor:const Color(0xFF7C3AED),
                shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(10))),
            )),
            if(dl&&!act) Expanded(child:FilledButton.icon(
              onPressed:()async{ await WhisperService.setActive(m); await _refresh(); },
              icon:const Icon(Icons.check_circle,size:16),
              label:const Text('انتخاب'),
              style:FilledButton.styleFrom(backgroundColor:Colors.green,
                shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(10))),
            )),
            if(dl)...[
              const SizedBox(width:8),
              IconButton(
                icon:const Icon(Icons.delete_outline,color:Colors.red,size:20),
                tooltip:'حذف مدل',
                onPressed:()async{
                  final ok=await showDialog<bool>(context:context,builder:(_)=>AlertDialog(
                    backgroundColor:const Color(0xFF1C1C22),
                    title:const Text('حذف مدل',style:TextStyle(color:Colors.white)),
                    content:Text('مدل ${m.name} (${m.sizeMb}MB) حذف شود؟',style:const TextStyle(color:Colors.white70)),
                    actions:[
                      TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('لغو')),
                      FilledButton(onPressed:()=>Navigator.pop(context,true),
                        style:FilledButton.styleFrom(backgroundColor:Colors.red),
                        child:const Text('حذف')),
                    ],
                  ));
                  if(ok==true){await WhisperService.deleteModel(m);await _refresh();}
                },
              ),
            ],
          ]),
        ],

      ])),
    );
  }

  Widget _tag(String t, Color c) => Container(
    padding:const EdgeInsets.symmetric(horizontal:8,vertical:3),
    decoration:BoxDecoration(color:c.withOpacity(0.2),borderRadius:BorderRadius.circular(6)),
    child:Text(t,style:TextStyle(color:c,fontSize:11,fontWeight:FontWeight.bold)),
  );

  Widget _stars(String label, int n) => Row(mainAxisSize:MainAxisSize.min,children:[
    Text('$label: ',style:const TextStyle(color:Colors.white54,fontSize:11)),
    ...List.generate(5,(i)=>Icon(i<n?Icons.star:Icons.star_border,size:12,
      color:i<n?const Color(0xFF7C3AED):Colors.white24)),
  ]);
}

