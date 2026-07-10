import 'package:flutter/material.dart';
import 'whisper_service.dart';
import 'ai_batch_queue_screen.dart';
import 'ai_history_screen.dart';
import 'main.dart' show showSnack;
import 'l10n.dart';

class AiModelsScreen extends StatefulWidget {
  const AiModelsScreen({super.key});
  @override State<AiModelsScreen> createState() => _AiModelsScreenState();
}

class _AiModelsScreenState extends State<AiModelsScreen> {
  final Map<String,bool>   _dl   = {};
  final Map<String,double> _prog = {};
  final Map<String,bool>   _busy = {};
  List<WhisperModelDef> _importedModels = [];
  String? _active;
  bool _loading = true;
  String _filter = 'all'; // all | quantized | full
  String? _recommendedId;
  int? _ramMb;
  double _cacheMb = 0;
  int _cacheCount = 0;
  bool _clearingCache = false;

  @override void initState(){ super.initState(); _refresh(); _loadRecommendation(); _loadCacheInfo(); }

  Future<void> _loadCacheInfo() async {
    final mb = await WhisperService.getAudioCacheSizeMb();
    final c = await WhisperService.getAudioCacheCount();
    if(mounted) setState((){ _cacheMb=mb; _cacheCount=c; });
  }

  Future<void> _clearCache() async {
    final ok = await showDialog<bool>(context:context, builder:(_)=>AlertDialog(
      backgroundColor:const Color(0xFF1C1C22),
      title:Text(L.clearAudioCache,style:TextStyle(color:Colors.white,fontSize:15)),
      content:Text('${L.clearAudioCache}?',
        style:const TextStyle(color:Colors.white70,fontSize:12)),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(context,false),child:Text(L.cancel)),
        FilledButton(onPressed:()=>Navigator.pop(context,true),
          style:FilledButton.styleFrom(backgroundColor:Colors.red),child:Text(L.cleanUp)),
      ],
    ));
    if(ok!=true) return;
    setState(()=>_clearingCache=true);
    await WhisperService.clearAudioCache();
    await _loadCacheInfo();
    if(mounted){
      setState(()=>_clearingCache=false);
      showSnack(context, L.cacheCleared, color: Colors.green);
    }
  }

  Future<void> _loadRecommendation() async {
    try {
      final ram = await WhisperService.getDeviceRamMb();
      final rec = WhisperService.recommendedModel(ram);
      if(mounted) setState((){ _ramMb=ram; _recommendedId=rec.id; });
    } catch(_){ /* روی بعضی دستگاه‌ها ممکنه پشتیبانی نشه — مهم نیست */ }
  }

  Future<void> _refresh() async {
    final a = await WhisperService.getActiveModel();
    final Map<String,bool> dl={};
    // همه مدل‌های شناخته‌شده
    for(final m in kWhisperModels) dl[m.id]=await WhisperService.isDownloaded(m);
    // مدل‌های ایمپورتی
    final imported = await WhisperService.allDownloadedModels();
    for(final m in imported) { if(m.isCustom) dl[m.id]=true; }
    if(mounted) setState((){
      _dl..clear()..addAll(dl);
      _active=a?.id;
      _loading=false;
      // مدل‌های ایمپورتی رو هم ذخیره کن
      _importedModels = imported.where((m)=>m.isCustom).toList();
    });
  }

  Future<void> _download(WhisperModelDef m) async {
    final key = m.id;
    setState((){ _busy[key]=true; _prog[key]=0; });
    if(mounted) showSnack(context, '${L.downloading} \${m.name} (\${m.sizeMb}MB)', seconds: 3);
    try {
      await for(final p in WhisperService.downloadModel(m)){
        if(!mounted) break;
        setState(()=> _prog[key]=p);
      }
      await _refresh();
      if(mounted) showSnack(context, '✓ \${m.name} ${L.downloaded}');
    } catch(e){
      if(mounted) showSnack(context, '${L.cancelResume}\n\$e');
    } finally {
      if(mounted) setState(()=>_busy[key]=false);
    }
  }

  void _cancel(WhisperModelDef m){
    WhisperService.cancelDownload();
    setState(()=>_busy[m.id]=false);
  }

  List<WhisperModelDef> get _filtered {
    final base = _filter=='quantized' ? kWhisperModels.where((m)=>m.isQuantized).toList()
      : _filter=='full' ? kWhisperModels.where((m)=>!m.isQuantized).toList()
      : List<WhisperModelDef>.from(kWhisperModels);
    // مدل‌های ایمپورتی همیشه نشون داده میشن
    return [...base, ..._importedModels];
  }

  @override
  Widget build(BuildContext ctx) => Scaffold(
    backgroundColor:const Color(0xFF0F0F14),
    appBar: AppBar(
      backgroundColor:const Color(0xFF1C1C22),
      title:Text(L.aiModelsLabel,style:TextStyle(color:Colors.white,fontSize:16)),
      leading:IconButton(icon:const Icon(Icons.arrow_back,color:Colors.white),onPressed:()=>Navigator.pop(ctx)),
      actions:[
        IconButton(
          icon:const Icon(Icons.history,color:Color(0xFF7C3AED)),
          tooltip:L.subtitleHistory,
          onPressed:()=>Navigator.push(ctx,MaterialPageRoute(builder:(_)=>const AiHistoryScreen())),
        ),
        IconButton(
          icon:const Icon(Icons.playlist_add_check,color:Color(0xFF7C3AED)),
          tooltip:L.batchQueue,
          onPressed:()=>Navigator.push(ctx,MaterialPageRoute(builder:(_)=>const AiBatchQueueScreen())),
        ),
      ],
    ),
    body: _loading
      ? const Center(child:CircularProgressIndicator(color:Color(0xFF7C3AED)))
      : Column(children:[
          _infoCard(),
          _cacheCard(),
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
      child:Row(children:[
        const Icon(Icons.info_outline,color:Color(0xFF7C3AED),size:18),
        const SizedBox(width:8),
        Expanded(child:Text(
          _ramMb!=null
            ? '${L.recommended}: ~\${(_ramMb!/1024).toStringAsFixed(1)}GB'
            : L.canDownloadMultiple,
          style:const TextStyle(color:Colors.white70,fontSize:12))),
      ]),
    ),
  );

  Widget _cacheCard() => Padding(
    padding:const EdgeInsets.fromLTRB(16,8,16,0),
    child:Container(
      padding:const EdgeInsets.all(12),
      decoration:BoxDecoration(color:const Color(0xFF1C1C22).withOpacity(0.8),borderRadius:BorderRadius.circular(12)),
      child:Row(children:[
        const Icon(Icons.storage,color:Colors.amber,size:18),
        const SizedBox(width:8),
        Expanded(child:Text(
          _cacheCount>0
            ? '${L.cacheAudio}: \$_cacheCount (${L.downloading} \${_cacheMb.toStringAsFixed(1)}MB)'
            : L.noAudioCache,
          style:const TextStyle(color:Colors.white70,fontSize:12))),
        if(_cacheCount>0) TextButton(
          onPressed:_clearingCache?null:_clearCache,
          child:_clearingCache
            ? SizedBox(width:14,height:14,child:CircularProgressIndicator(strokeWidth:2,color:Colors.red))
            : Text(L.cleanUp,style:TextStyle(color:Colors.red,fontSize:12)),
        ),
      ]),
    ),
  );

  Widget _filterBar() => Padding(
    padding:const EdgeInsets.fromLTRB(16,12,16,0),
    child:Row(children:[
      _chip(L.allItems,'all'), const SizedBox(width:8),
      _chip(L.quantized,'quantized'), const SizedBox(width:8),
      _chip(L.full,'full'),
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
    final recommended = _recommendedId == key;

    return Container(
      margin:const EdgeInsets.only(bottom:12),
      decoration:BoxDecoration(
        color:const Color(0xFF1C1C22),
        borderRadius:BorderRadius.circular(16),
        border:Border.all(color: act?const Color(0xFF7C3AED):(recommended?Colors.amber:Colors.white12), width:act||recommended?2:1),
      ),
      child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[

        Row(children:[
          _tag(m.name, const Color(0xFF7C3AED)),
          if(m.isQuantized)...[const SizedBox(width:6),_tag(m.variant.toUpperCase(), Colors.teal)],
          if(m.isCustom)...[const SizedBox(width:6),_tag(L.importModel, Colors.orange)],
          const SizedBox(width:8),
          if(act)_tag(L.active, Colors.green),
          if(recommended)...[const SizedBox(width:6),_tag(L.recommended, Colors.amber)],
          if(dl && !act)_tag(L.downloaded, Colors.blue),
          const Spacer(),
          Text('~${m.sizeMb>=1000 ? "${(m.sizeMb/1000).toStringAsFixed(1)}GB" : "${m.sizeMb}MB"}',
            style:const TextStyle(color:Colors.white54,fontSize:12)),
        ]),
        const SizedBox(height:6),
        Text(m.desc,style:const TextStyle(color:Colors.white70,fontSize:12)),
        const SizedBox(height:6),
        Row(children:[_stars(L.speed,m.speedStars), const SizedBox(width:16), _stars(L.accuracy,m.accStars)]),

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
              child:Text(L.cancelResume,style:TextStyle(color:Colors.orange,fontSize:11))),
          ]),
        ],

        if(!busy)...[
          const SizedBox(height:12),
          Row(children:[
            if(!dl) Expanded(child:FilledButton.icon(
              onPressed:()=>_download(m),
              icon:const Icon(Icons.download,size:16),
              label:Text('${L.download} (~\${m.sizeMb>=1000 ? "\${(m.sizeMb/1000).toStringAsFixed(1)}GB" : "\${m.sizeMb}MB"})',
                style:const TextStyle(fontSize:12)),
              style:FilledButton.styleFrom(backgroundColor:const Color(0xFF7C3AED),
                shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(10))),
            )),
            if(dl&&!act) Expanded(child:FilledButton.icon(
              onPressed:()async{ await WhisperService.setActive(m); await _refresh(); },
              icon:const Icon(Icons.check_circle,size:16),
              label:Text(L.activate),
              style:FilledButton.styleFrom(backgroundColor:Colors.green,
                shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(10))),
            )),
            if(dl)...[
              const SizedBox(width:8),
              IconButton(
                icon:const Icon(Icons.delete_outline,color:Colors.red,size:20),
                tooltip:L.delete,
                onPressed:()async{
                  final ok=await showDialog<bool>(context:context,builder:(_)=>AlertDialog(
                    backgroundColor:const Color(0xFF1C1C22),
                    title:Text(L.delete,style:TextStyle(color:Colors.white)),
                    content:Text('\${m.name}?',style:const TextStyle(color:Colors.white70)),
                    actions:[
                      TextButton(onPressed:()=>Navigator.pop(context,false),child:Text(L.cancel)),
                      FilledButton(onPressed:()=>Navigator.pop(context,true),
                        style:FilledButton.styleFrom(backgroundColor:Colors.red),
                        child:Text(L.delete)),
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
