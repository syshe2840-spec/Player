import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'whisper_service.dart';
import 'ai_models_screen.dart';
import 'srt_editor_screen.dart';

class AiSubtitleSheet extends StatefulWidget {
  final String videoPath;
  final void Function(String srtPath) onDone;
  final void Function(String srtPath)? onPreview;
  const AiSubtitleSheet({super.key, required this.videoPath, required this.onDone, this.onPreview});

  static Future<void> show(
    BuildContext ctx, String videoPath, void Function(String) onDone, {
    void Function(String)? onPreview,
  }) =>
    showModalBottomSheet(
      context:ctx, isScrollControlled:true,
      backgroundColor:const Color(0xFF1C1C22),
      shape:const RoundedRectangleBorder(borderRadius:BorderRadius.vertical(top:Radius.circular(20))),
      builder:(_)=>AiSubtitleSheet(videoPath:videoPath, onDone:onDone, onPreview:onPreview),
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
  bool _loading = true;
  bool _improving = false;
  List<String> _existingLangs = [];
  String _mode = 'pick'; // pick | new | running | done
  WhisperEngine _engine = WhisperEngine.v1;
  bool _translate = false;

  @override void initState(){ super.initState(); _load(); }

  Future<void> _load() async {
    final list = await WhisperService.downloadedModels();
    final active = await WhisperService.getActiveModel();
    final existing = WhisperService.existingLanguages(widget.videoPath);
    final engine = await WhisperService.getActiveEngine();
    if(mounted) setState((){
      _downloaded = list;
      _selected = active ?? (list.isNotEmpty ? list.first : null);
      _existingLangs = existing;
      _mode = existing.isNotEmpty ? 'pick' : 'new';
      _engine = engine;
      _loading = false;
    });
  }

  Future<void> _start() async {
    if(_selected==null) return;
    setState((){ _running=true; _mode='running'; _progress=0; _status='شروع...'; });
    try {
      final path = await WhisperService.transcribe(
        videoPath: widget.videoPath,
        language: _lang,
        model: _selected!,
        useVad: _useVad,
        engine: _engine,
        isTranslate: _translate,
        onStatus:(s,p){ if(mounted) setState((){ _status=s; _progress=p; }); },
      );
      if(mounted) setState((){ _running=false; _mode='done'; _srtPath=path; });
    } catch(e){
      if(mounted) setState((){ _running=false; _mode='new'; _status='خطا: $e'; });
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

  Future<void> _deleteLang(String lang) async {
    final ok = await showDialog<bool>(context:context, builder:(_)=>AlertDialog(
      backgroundColor:const Color(0xFF1C1C22),
      title:const Text('حذف زیرنویس',style:TextStyle(color:Colors.white,fontSize:15)),
      content:Text('زیرنویس ${kLanguages[lang]??lang} حذف شود؟',style:const TextStyle(color:Colors.white70)),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('لغو')),
        FilledButton(onPressed:()=>Navigator.pop(context,true),
          style:FilledButton.styleFrom(backgroundColor:Colors.red),child:const Text('حذف')),
      ],
    ));
    if(ok==true){
      WhisperService.deleteLanguage(widget.videoPath, lang);
      await _load();
    }
  }

  Future<void> _deleteAll() async {
    final ok = await showDialog<bool>(context:context, builder:(_)=>AlertDialog(
      backgroundColor:const Color(0xFF1C1C22),
      title:const Text('حذف همه زیرنویس‌های AI',style:TextStyle(color:Colors.white,fontSize:15)),
      content:Text('همه ${_existingLangs.length} زیرنویس ساخته‌شده برای این ویدیو حذف شوند؟',
        style:const TextStyle(color:Colors.white70)),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('لغو')),
        FilledButton(onPressed:()=>Navigator.pop(context,true),
          style:FilledButton.styleFrom(backgroundColor:Colors.red),child:const Text('حذف همه')),
      ],
    ));
    if(ok==true){
      WhisperService.deleteAllSubtitles(widget.videoPath);
      await _load();
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

            if(_mode=='pick')    ..._buildPick()
            else if(_mode=='new')..._buildNew()
            else if(_mode=='running')..._buildRunning()
            else if(_mode=='done')..._buildDone(),

            const SizedBox(height:8),
          ]),
    ),
  );

  // ── حالت انتخاب: زبان‌های موجود + ساخت جدید ──
  List<Widget> _buildPick()=>[
    const Padding(
      padding: EdgeInsets.only(bottom:8),
      child: Align(alignment:Alignment.centerRight,
        child:Text('زیرنویس‌های ساخته‌شده:',style:TextStyle(color:Colors.white60,fontSize:12))),
    ),

    ..._existingLangs.map((lang){
      final improved = WhisperService.improvedExists(widget.videoPath, lang);
      return Container(
        margin:const EdgeInsets.only(bottom:8),
        padding:const EdgeInsets.symmetric(horizontal:12,vertical:10),
        decoration:BoxDecoration(color:const Color(0xFF2A2A35),borderRadius:BorderRadius.circular(12)),
        child:Row(children:[
          const Icon(Icons.star,color:Colors.amber,size:16),
          const SizedBox(width:8),
          Expanded(child:Row(children:[
            Text(kLanguages[lang]??lang,style:const TextStyle(color:Colors.white,fontSize:14)),
            if(improved)...[
              const SizedBox(width:6),
              Container(padding:const EdgeInsets.symmetric(horizontal:6,vertical:2),
                decoration:BoxDecoration(color:const Color(0xFF7C3AED).withOpacity(0.2),borderRadius:BorderRadius.circular(6)),
                child:const Text('بهبودیافته',style:TextStyle(color:Color(0xFF7C3AED),fontSize:10))),
            ],
          ])),
          IconButton(
            icon:const Icon(Icons.delete_outline,color:Colors.red,size:18),
            onPressed:()=>_deleteLang(lang),
            constraints:const BoxConstraints(),padding:const EdgeInsets.all(6),
          ),
          const SizedBox(width:4),
          FilledButton(
            onPressed:(){
              widget.onDone(WhisperService.bestSrtPath(widget.videoPath, lang));
              Navigator.pop(context);
            },
            style:FilledButton.styleFrom(backgroundColor:const Color(0xFF7C3AED),
              minimumSize:const Size(0,32),padding:const EdgeInsets.symmetric(horizontal:14),
              shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(8))),
            child:const Text('استفاده',style:TextStyle(fontSize:12)),
          ),
        ]),
      );
    }),

    const SizedBox(height:8),
    Row(children:[
      Expanded(child:OutlinedButton.icon(
        onPressed:()=>setState(()=>_mode='new'),
        icon:const Icon(Icons.add,size:16,color:Color(0xFF7C3AED)),
        label:const Text('ساخت زبان جدید',style:TextStyle(color:Color(0xFF7C3AED),fontSize:13)),
        style:OutlinedButton.styleFrom(side:const BorderSide(color:Color(0xFF7C3AED)),
          padding:const EdgeInsets.symmetric(vertical:12),
          shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(10))),
      )),
      const SizedBox(width:8),
      OutlinedButton.icon(
        onPressed:_deleteAll,
        icon:const Icon(Icons.delete_sweep,size:16,color:Colors.red),
        label:const Text('حذف همه',style:TextStyle(color:Colors.red,fontSize:13)),
        style:OutlinedButton.styleFrom(side:const BorderSide(color:Colors.red),
          padding:const EdgeInsets.symmetric(vertical:12,horizontal:12),
          shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(10))),
      ),
    ]),
  ];

  // ── حالت ساخت جدید ──
  List<Widget> _buildNew()=>[
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
      items:kLanguages.entries.map((e){
        final has = _existingLangs.contains(e.key);
        return DropdownMenuItem(value:e.key,child:Row(children:[
          Text(e.value),
          if(has)...[const SizedBox(width:6),const Icon(Icons.star,color:Colors.amber,size:12)],
        ]));
      }).toList(),
      onChanged:(v){ if(v!=null) setState(()=>_lang=v); },
    )),
    const SizedBox(height:10),

    // ── ترجمه به انگلیسی (همیشه در دسترس) ──
    Container(
      padding:const EdgeInsets.symmetric(horizontal:12,vertical:6),
      decoration:BoxDecoration(color:const Color(0xFF2A2A35),borderRadius:BorderRadius.circular(12)),
      child:Row(children:[
        const Icon(Icons.translate,color:Color(0xFF7C3AED),size:18),
        const SizedBox(width:10),
        const Expanded(child:Text('ترجمه به انگلیسی (به‌جای زیرنویس هم‌زبان)',
          style:TextStyle(color:Colors.white,fontSize:12))),
        Switch(value:_translate,activeColor:const Color(0xFF7C3AED),
          onChanged:(v)=>setState(()=>_translate=v)),
      ]),
    ),
    const SizedBox(height:10),

    // ── انتخاب موتور — V1 و V2 همیشه هر دو در دسترس‌اند ──
    Container(
      padding:const EdgeInsets.all(10),
      decoration:BoxDecoration(color:const Color(0xFF2A2A35),borderRadius:BorderRadius.circular(12)),
      child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Row(children:const [
          Icon(Icons.settings_suggest,color:Color(0xFF7C3AED),size:16),
          SizedBox(width:8),
          Text('موتور تشخیص گفتار',style:TextStyle(color:Colors.white70,fontSize:12)),
        ]),
        const SizedBox(height:8),
        Row(children:[
          Expanded(child:_engineChip(WhisperEngine.v1,'V1','پایدار')),
          const SizedBox(width:8),
          Expanded(child:_engineChip(WhisperEngine.v2,'V2','آزمایشی، سریع‌تر')),
        ]),
      ]),
    ),
    const SizedBox(height:10),

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

    if(_existingLangs.contains(_lang))
      Container(
        margin:const EdgeInsets.only(bottom:10),
        padding:const EdgeInsets.all(10),
        decoration:BoxDecoration(color:Colors.orange.withOpacity(0.15),borderRadius:BorderRadius.circular(10)),
        child:const Row(children:[
          Icon(Icons.warning_amber,color:Colors.orange,size:16),
          SizedBox(width:8),
          Expanded(child:Text('این زبان قبلاً ساخته شده — با ساخت مجدد جایگزین می‌شود',
            style:TextStyle(color:Colors.orange,fontSize:11))),
        ]),
      ),

    Row(children:[
      if(_existingLangs.isNotEmpty)...[
        OutlinedButton(
          onPressed:()=>setState(()=>_mode='pick'),
          style:OutlinedButton.styleFrom(side:const BorderSide(color:Colors.white24),
            padding:const EdgeInsets.symmetric(vertical:14,horizontal:16),
            shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(12))),
          child:const Icon(Icons.arrow_back,color:Colors.white70,size:18),
        ),
        const SizedBox(width:8),
      ],
      Expanded(child:FilledButton.icon(
        onPressed:_downloaded.isEmpty ? null : _start,
        icon:const Icon(Icons.subtitles),
        label:const Text('تولید زیرنویس',style:TextStyle(fontSize:15)),
        style:FilledButton.styleFrom(
          backgroundColor:const Color(0xFF7C3AED),
          padding:const EdgeInsets.symmetric(vertical:14),
          shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(12)),
        ),
      )),
    ]),

    if(_status.startsWith('خطا'))Padding(
      padding:const EdgeInsets.only(top:8),
      child:Text(_status,style:const TextStyle(color:Colors.red,fontSize:11),textAlign:TextAlign.center),
    ),
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
      onPressed:()async{ await WhisperService.cancelExtraction(); if(mounted) setState((){ _running=false; _mode='new'; }); },
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
    Text('زیرنویس ${kLanguages[_lang]??_lang} آماده شد',
      style:const TextStyle(color:Colors.white,fontSize:16,fontWeight:FontWeight.bold)),
    const SizedBox(height:4),
    Text(_srtPath?.split('/').last??'',
      style:const TextStyle(color:Colors.white54,fontSize:11),textAlign:TextAlign.center),
    const SizedBox(height:14),

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

    // ── اشتراک‌گذاری / ویرایش / پیش‌نمایش ──
    Row(children:[
      Expanded(child:OutlinedButton.icon(
        onPressed:()=>SharePlus.instance.share(ShareParams(files:[XFile(_srtPath!)],text:'زیرنویس Vezoo')),
        icon:const Icon(Icons.share,size:15,color:Colors.white70),
        label:const Text('اشتراک',style:TextStyle(color:Colors.white70,fontSize:12)),
        style:OutlinedButton.styleFrom(side:const BorderSide(color:Colors.white24),
          padding:const EdgeInsets.symmetric(vertical:10),
          shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(10))),
      )),
      const SizedBox(width:8),
      Expanded(child:OutlinedButton.icon(
        onPressed:()async{
          await Navigator.push(context,MaterialPageRoute(builder:(_)=>SrtEditorScreen(srtPath:_srtPath!)));
          if(mounted)setState((){}); // رفرش بعد از برگشت از ویرایشگر
        },
        icon:const Icon(Icons.edit,size:15,color:Colors.white70),
        label:const Text('ویرایش',style:TextStyle(color:Colors.white70,fontSize:12)),
        style:OutlinedButton.styleFrom(side:const BorderSide(color:Colors.white24),
          padding:const EdgeInsets.symmetric(vertical:10),
          shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(10))),
      )),
      if(widget.onPreview!=null)...[
        const SizedBox(width:8),
        Expanded(child:OutlinedButton.icon(
          onPressed:(){
            widget.onPreview!(_srtPath!);
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content:Text('روی پلیر بارگذاری شد برای پیش‌نمایش'),
              backgroundColor:Color(0xFF7C3AED),duration:Duration(seconds:2)));
          },
          icon:const Icon(Icons.visibility,size:15,color:Colors.white70),
          label:const Text('پیش‌نمایش',style:TextStyle(color:Colors.white70,fontSize:12)),
          style:OutlinedButton.styleFrom(side:const BorderSide(color:Colors.white24),
            padding:const EdgeInsets.symmetric(vertical:10),
            shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(10))),
        )),
      ],
    ]),
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

  Widget _engineChip(WhisperEngine e, String label, String sub){
    final active = _engine==e;
    return GestureDetector(
      onTap:()async{
        setState(()=>_engine=e);
        await WhisperService.setActiveEngine(e);
      },
      child:Container(
        padding:const EdgeInsets.symmetric(vertical:8,horizontal:8),
        decoration:BoxDecoration(
          color:active?const Color(0xFF7C3AED):const Color(0xFF1C1C22),
          borderRadius:BorderRadius.circular(10),
          border:Border.all(color:active?const Color(0xFF7C3AED):Colors.white12),
        ),
        child:Column(children:[
          Text(label,style:TextStyle(color:active?Colors.white:Colors.white70,fontSize:13,fontWeight:FontWeight.bold)),
          const SizedBox(height:2),
          Text(sub,style:TextStyle(color:active?Colors.white70:Colors.white38,fontSize:10)),
        ]),
      ),
    );
  }

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

