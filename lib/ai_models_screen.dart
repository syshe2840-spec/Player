import 'package:flutter/material.dart';
import 'whisper_service.dart';
import 'whisper_v2_test_screen.dart';

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
  String _filter = 'all'; // all | quantized | full

  @override void initState(){ super.initState(); _refresh(); }

  Future<void> _refresh() async {
    final a = await WhisperService.getActiveModel();
    final Map<String,bool> dl={};
    for(final m in kWhisperModels) dl[m.id]=await WhisperService.isDownloaded(m);
    if(mounted) setState((){ _dl..clear()..addAll(dl); _active=a?.id; _loading=false; });
  }

  Future<void> _download(WhisperModelDef m) async {
    final key = m.id;
    setState((){ _busy[key]=true; _prog[key]=0; });
    if(mounted) ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content:Text('دانلود ${m.name} شروع شد (${m.sizeMb}MB)...'),
        duration:const Duration(seconds:3), backgroundColor:const Color(0xFF7C3AED)));
    try {
      await for(final p in WhisperService.downloadModel(m)){
        if(!mounted) break;
        setState(()=> _prog[key]=p);
      }
      await _refresh();
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content:Text('✓ مدل ${m.name} دانلود شد'),
          backgroundColor:Colors.green, duration:const Duration(seconds:3)));
    } catch(e){
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content:Text('دانلود متوقف شد — دوباره بزنید تا ادامه دهد\n$e'),
          backgroundColor:Colors.orange, duration:const Duration(seconds:5)));
    } finally {
      if(mounted) setState(()=>_busy[key]=false);
    }
  }

  void _cancel(WhisperModelDef m){
    WhisperService.cancelDownload();
    setState(()=>_busy[m.id]=false);
  }

  List<WhisperModelDef> get _filtered {
    if(_filter=='quantized') return kWhisperModels.where((m)=>m.isQuantized).toList();
    if(_filter=='full') return kWhisperModels.where((m)=>!m.isQuantized).toList();
    return kWhisperModels;
  }

  @override
  Widget build(BuildContext ctx) => Scaffold(
    backgroundColor:const Color(0xFF0F0F14),
    appBar: AppBar(
      backgroundColor:const Color(0xFF1C1C22),
      title:const Text('مدل‌های AI زیرنویس',style:TextStyle(color:Colors.white,fontSize:16)),
      leading:IconButton(icon:const Icon(Icons.arrow_back,color:Colors.white),onPressed:()=>Navigator.pop(ctx)),
      actions:[
        IconButton(
          icon:const Icon(Icons.science_outlined,color:Color(0xFF7C3AED)),
          tooltip:'تست AI v2 (آزمایشی)',
          onPressed:()=>Navigator.push(ctx,MaterialPageRoute(builder:(_)=>const WhisperV2TestScreen())),
        ),
      ],
    ),
    body: _loading
      ? const Center(child:CircularProgressIndicator(color:Color(0xFF7C3AED)))
      : Column(children:[
          _infoCard(),
          _filterBar(),
          Expanded(child:ListView(padding:const EdgeInsets.fromLTRB(16,8,16,16),
            children:_filtered.map(_buildCard).toList())),
        ]),
  );

  Widget _infoCard() => Padding(
    padding:const EdgeInsets.fromLTRB(16,12,16,0),
    child:Container(
      padding:const EdgeInsets.all(12),
      decoration:BoxDecoration(color:const Color(0xFF1C1C22).withOpacity(0.8),borderRadius:BorderRadius.circular(12)),
      child:const Row(children:[
        Icon(Icons.info_outline,color:Color(0xFF7C3AED),size:18),
        SizedBox(width:8),
        Expanded(child:Text('می‌توانید چند مدل دانلود کنید — هنگام ساخت زیرنویس انتخاب می‌کنید',
          style:TextStyle(color:Colors.white70,fontSize:12))),
      ]),
    ),
  );

  Widget _filterBar() => Padding(
    padding:const EdgeInsets.fromLTRB(16,12,16,0),
    child:Row(children:[
      _chip('همه','all'), const SizedBox(width:8),
      _chip('فشرده (Quantized)','quantized'), const SizedBox(width:8),
      _chip('کامل','full'),
    ]),
  );
  Widget _chip(String label,String v) => GestureDetector(
    onTap:()=>setState(()=>_filter=v),
    child:Container(
      padding:const EdgeInsets.symmetric(horizontal:12,vertical:6),
      decoration:BoxDecoration(
        color:_filter==v?const Color(0xFF7C3AED):const Color(0xFF1C1C22),
        borderRadius:BorderRadius.circular(20)),
      child:Text(label,style:TextStyle(color:_filter==v?Colors.white:Colors.white60,fontSize:12)),
    ),
  );

  Widget _buildCard(WhisperModelDef m){
    final key = m.id;
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

        Row(children:[
          _tag(m.name, const Color(0xFF7C3AED)),
          if(m.isQuantized)...[const SizedBox(width:6),_tag(m.variant.toUpperCase(), Colors.teal)],
          const SizedBox(width:8),
          if(act)_tag('فعال', Colors.green),
          if(dl && !act)_tag('دانلود شده', Colors.blue),
          const Spacer(),
          Text('~${m.sizeMb>=1000 ? "${(m.sizeMb/1000).toStringAsFixed(1)}GB" : "${m.sizeMb}MB"}',
            style:const TextStyle(color:Colors.white54,fontSize:12)),
        ]),
        const SizedBox(height:6),
        Text(m.desc,style:const TextStyle(color:Colors.white70,fontSize:12)),
        const SizedBox(height:6),
        Row(children:[_stars('سرعت',m.speedStars), const SizedBox(width:16), _stars('دقت',m.accStars)]),

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
            Text('${(prog*100).clamp(0,100).toInt()}%',
              style:const TextStyle(color:Colors.white54,fontSize:11)),
            TextButton(onPressed:()=>_cancel(m),
              child:const Text('لغو (قابل ادامه)',style:TextStyle(color:Colors.orange,fontSize:11))),
          ]),
        ],

        if(!busy)...[
          const SizedBox(height:12),
          Row(children:[
            if(!dl) Expanded(child:FilledButton.icon(
              onPressed:()=>_download(m),
              icon:const Icon(Icons.download,size:16),
              label:Text('دانلود (~${m.sizeMb>=1000 ? "${(m.sizeMb/1000).toStringAsFixed(1)}GB" : "${m.sizeMb}MB"})',
                style:const TextStyle(fontSize:12)),
              style:FilledButton.styleFrom(backgroundColor:const Color(0xFF7C3AED),
                shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(10))),
            )),
            if(dl&&!act) Expanded(child:FilledButton.icon(
              onPressed:()async{ await WhisperService.setActive(m); await _refresh(); },
              icon:const Icon(Icons.check_circle,size:16),
              label:const Text('فعال‌سازی'),
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
                    content:Text('مدل ${m.name} حذف شود؟',style:const TextStyle(color:Colors.white70)),
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

