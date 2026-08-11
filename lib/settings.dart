// lib/settings.dart — تنظیمات پلیر
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';
import 'store.dart';
import 'whisper_service.dart' show WhisperService;
import 'ytdlp_service.dart';
import 'gemini_live_service.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'l10n.dart';
import 'vosk_models_screen.dart';
import 'ytdlp_service.dart';
import 'gemini_live_service.dart';
import 'package:http/http.dart' as http;
import 'main.dart' show showSnack;

class PlayerSettings extends StatefulWidget {
  final VideoSettings vs;
  final ValueChanged<VideoSettings> onChanged;
  final VideoSettings? vs2;
  final ValueChanged<VideoSettings>? onChanged2;
  final bool sub1Visible, sub2Visible;
  final ValueChanged<bool> onSub1Visible, onSub2Visible;
  final String? sub2Path;
  final int subDelayMs, subDelay2Ms, audioDelayMs;
  final ValueChanged<int> onSubDelayMs, onSubDelay2Ms, onAudioDelayMs;
  final Color color2;
  final ValueChanged<Color> onColor2;
  final VoidCallback onPickSub1, onPickSub2, onPickFont, onSaveForVideo;
  final double speed, ampVolume;
  final ValueChanged<double> onSpeed, onAmpVolume;
  final bool hwDecode;
  final ValueChanged<bool> onHwDecode;
  final bool embeddedSubEnabled;
  final ValueChanged<bool> onEmbeddedSubEnabled;
  final int? videoWidth, videoHeight;

  const PlayerSettings({
    super.key,
    required this.vs, required this.onChanged,
    this.vs2, this.onChanged2,
    required this.sub1Visible, required this.onSub1Visible,
    required this.sub2Visible, required this.onSub2Visible,
    this.sub2Path,
    required this.subDelayMs, required this.onSubDelayMs,
    required this.subDelay2Ms, required this.onSubDelay2Ms,
    required this.audioDelayMs, required this.onAudioDelayMs,
    required this.color2, required this.onColor2,
    required this.onPickSub1, required this.onPickSub2,
    required this.onPickFont, required this.onSaveForVideo,
    required this.speed, required this.onSpeed,
    required this.ampVolume, required this.onAmpVolume,
    required this.hwDecode, required this.onHwDecode,
    required this.embeddedSubEnabled, required this.onEmbeddedSubEnabled,
    this.videoWidth, this.videoHeight,
  });

  @override State<PlayerSettings> createState()=>_SettingsState();
}

class _SettingsState extends State<PlayerSettings> with SingleTickerProviderStateMixin{
  late TabController _tab;
  late VideoSettings _vs;
  late int _sd1, _sd2, _ad;
  late Color _c2;
  late double _speed, _amp;
  late bool _s1v, _s2v;

  final List<Color> _textColors=const[Colors.white,Color(0xFFFFEB3B),Color(0xFF69F0AE),Color(0xFF40C4FF),Color(0xFFFF8A65),Color(0xFFFF80AB)];
  final List<Color> _bgColors=const[Colors.black,Color(0xFF0D1B2A),Color(0xFF1B2E1B),Color(0xFF2A1B1B),Color(0xFF1B1B2E),Colors.transparent];

  bool _hwDecode=true;
  bool _embeddedSub=true;
  final TextEditingController _d1Ctrl=TextEditingController();
  final TextEditingController _d2Ctrl=TextEditingController();
  final TextEditingController _adCtrl=TextEditingController();

  @override
  void initState(){
    super.initState();
    _tab=TabController(length:4,vsync:this);
    _embeddedSub=widget.embeddedSubEnabled;
    _vs=widget.vs;_sd1=widget.subDelayMs;_sd2=widget.subDelay2Ms;_ad=widget.audioDelayMs;
    _c2=widget.color2;_speed=widget.speed;_amp=widget.ampVolume;
    _s1v=widget.sub1Visible;_s2v=widget.sub2Visible;
    _hwDecode=widget.hwDecode;
    _d1Ctrl.text='$_sd1';_d2Ctrl.text='$_sd2';_adCtrl.text='$_ad';
  }
  @override void dispose(){_tab.dispose();_d1Ctrl.dispose();_d2Ctrl.dispose();_adCtrl.dispose();super.dispose();}

  void _ch(VoidCallback fn){fn();setState((){});widget.onChanged(_vs);}

  @override
  Widget build(BuildContext context){
    return Column(mainAxisSize:MainAxisSize.min,children:[
      const SizedBox(height:10),
      Center(child:Container(width:40,height:4,decoration:BoxDecoration(color:Colors.white24,borderRadius:BorderRadius.circular(2)))),
      TabBar(controller:_tab,isScrollable:true,tabs:[
        Tab(text:L.subtitle,icon:Icon(Icons.subtitles,size:16)),
        Tab(text:L.playback,icon:Icon(Icons.volume_up,size:16)),
        Tab(text:L.subtitle2,icon:Icon(Icons.subtitles_outlined,size:16)),
        Tab(text:L.other,icon:Icon(Icons.more_horiz,size:16)),
      ]),
      SizedBox(height:MediaQuery.of(context).size.height*0.48,child:TabBarView(controller:_tab,children:[
        _sub1Tab(),_audioTab(),_sub2Tab(),_otherTab(),
      ])),
      SizedBox(height:MediaQuery.of(context).viewPadding.bottom+4),
    ]);
  }

  // ──────── تب زیرنویس ۱ ────────
  Widget _sub1Tab()=>SingleChildScrollView(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    SwitchListTile(contentPadding:EdgeInsets.zero,title:Text(L.subtitleDisplay),value:_s1v,
        onChanged:(v){setState(()=>_s1v=v);widget.onSub1Visible(v);}),
    SwitchListTile(contentPadding:EdgeInsets.zero,
        title:Text(L.showSubToolbar),
        subtitle:Text(L.subToolbarDesc),
        value:_vs.showSubToolbar,
        onChanged:(v)=>_ch(()=>_vs.showSubToolbar=v)),

    // اندازه فونت
    Text('${L.fontSize}: ${_vs.fontSize.round()}'),
    Slider(min:6,max:100,value:_vs.fontSize,onChanged:(v)=>_ch(()=>_vs.fontSize=v)),

    SwitchListTile(contentPadding:EdgeInsets.zero,title:Text(L.boldLabel),value:_vs.bold,
        onChanged:(v)=>_ch(()=>_vs.bold=v)),

    // دیلی زیرنویس با عدد
    Text(L.subDelay),const SizedBox(height:6),
    Row(children:[
      IconButton(icon:const Icon(Icons.remove),onPressed:(){setState(()=>_sd1-=100);widget.onSubDelayMs(_sd1);_d1Ctrl.text='$_sd1';}),
      Expanded(child:TextField(controller:_d1Ctrl,keyboardType:const TextInputType.numberWithOptions(signed:true),
        textAlign:TextAlign.center,
        onChanged:(v){final n=int.tryParse(v);if(n!=null){setState(()=>_sd1=n);widget.onSubDelayMs(n);}},
        decoration:InputDecoration(suffixText:'ms',border:OutlineInputBorder(),isDense:true))),
      IconButton(icon:const Icon(Icons.add),onPressed:(){setState(()=>_sd1+=100);widget.onSubDelayMs(_sd1);_d1Ctrl.text='$_sd1';}),
    ]),
    Slider(min:-10000,max:10000,value:_sd1.toDouble().clamp(-10000,10000),
        onChanged:(v){setState(()=>_sd1=v.round());widget.onSubDelayMs(_sd1);_d1Ctrl.text='$_sd1';}),

    // موقعیت
    Text('${L.position}: ${_vs.bottomPadding.round()}px'),
    Slider(min:0,max:900,value:_vs.bottomPadding.clamp(0,900),onChanged:(v)=>_ch(()=>_vs.bottomPadding=v)),

    const SizedBox(height:8),Text(L.alignment),const SizedBox(height:8),
    SegmentedButton<int>(
      segments:[
        ButtonSegment(value:1,label:Text(L.right),icon:Icon(Icons.format_align_right,size:16)),
        ButtonSegment(value:2,label:Text(L.center),icon:Icon(Icons.format_align_center,size:16)),
        ButtonSegment(value:0,label:Text(L.left),icon:Icon(Icons.format_align_left,size:16)),
      ],
      selected:{_vs.textAlign},onSelectionChanged:(s)=>_ch(()=>_vs.textAlign=s.first),
    ),

    const SizedBox(height:12),Text(L.textColor),const SizedBox(height:8),
    Wrap(spacing:10,children:_textColors.map((c)=>GestureDetector(onTap:()=>_ch(()=>_vs.textColor=c.value),
      child:Container(width:34,height:34,decoration:BoxDecoration(color:c,shape:BoxShape.circle,
          border:Border.all(color:c.value==_vs.textColor?Colors.white:Colors.transparent,width:3))))).toList()),

    const SizedBox(height:12),Text(L.bgColor),const SizedBox(height:8),
    Wrap(spacing:10,children:_bgColors.map((c){
      final sel=c.value==_vs.bgColor;
      return GestureDetector(onTap:()=>_ch(()=>_vs.bgColor=c.value),child:Container(width:34,height:34,
        decoration:BoxDecoration(color:c==Colors.transparent?null:c,shape:BoxShape.circle,
            border:Border.all(color:sel?Colors.white:Colors.white24,width:sel?3:1)),
        child:c==Colors.transparent?const Center(child:Icon(Icons.block,size:18,color:Colors.white38)):null));
    }).toList()),
    Text('${L.transparency}: ${(_vs.bgOpacity*100).round()}%'),
    Slider(min:0,max:1,value:_vs.bgOpacity,onChanged:(v)=>_ch(()=>_vs.bgOpacity=v)),

    const Divider(height:20),Text(L.font),const SizedBox(height:8),
    // فونت‌های پیش‌فرض
    Wrap(spacing:6,runSpacing:6,children:kDefaultFonts.map(((String label,String family) f)=>GestureDetector(
      onTap:()=>_ch(()=>_vs.fontFamily=f.$2),
      child:Container(
        padding:const EdgeInsets.symmetric(horizontal:10,vertical:6),
        decoration:BoxDecoration(
          color:_vs.fontFamily==f.$2?const Color(0xFF7C3AED):const Color(0xFF2A2A3A),
          borderRadius:BorderRadius.circular(8),
          border:Border.all(color:_vs.fontFamily==f.$2?const Color(0xFF7C3AED):const Color(0xFF3A3A4A))),
        child:Text(f.$1,style:TextStyle(fontFamily:f.$2.isEmpty?null:f.$2,
          color:_vs.fontFamily==f.$2?Colors.white:const Color(0xFFB0B0C0),fontSize:12))),
    )).toList()),
    const SizedBox(height:8),
    OutlinedButton.icon(onPressed:(){Navigator.pop(context);widget.onPickFont();},
        icon:const Icon(Icons.font_download),label:Text(L.customFont)),

    const Divider(height:20),
    // border و سایه
    Row(children:[
      Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text('Border: ${_vs.borderSize.toStringAsFixed(1)}',style:const TextStyle(fontSize:12)),
        Slider(min:0,max:8,divisions:16,value:_vs.borderSize,
          onChanged:(v)=>_ch(()=>_vs.borderSize=v)),
      ])),
      const SizedBox(width:8),
      Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text('${L.shadow}: ${_vs.shadowSize.toStringAsFixed(1)}',style:const TextStyle(fontSize:12)),
        Slider(min:0,max:5,divisions:10,value:_vs.shadowSize,
          onChanged:(v)=>_ch(()=>_vs.shadowSize=v)),
      ])),
    ]),
    const Divider(height:20),
    // ابزارهای زیرنویس زنده
    Text(L.liveSubtitleTools),const SizedBox(height:8),
    Row(children:[
      Expanded(child:OutlinedButton.icon(icon:const Icon(Icons.copy,size:16),label:Text(L.copy),
          onPressed:(){Navigator.pop(context);})),
      const SizedBox(width:8),
      Expanded(child:OutlinedButton.icon(icon:const Icon(Icons.translate,size:16),label:Text(L.translationLabel),
          onPressed:(){
            Navigator.pop(context);
            showSnack(context, L.translatePaste);
          })),
      const SizedBox(width:8),
      Expanded(child:OutlinedButton.icon(icon:const Icon(Icons.book,size:16),label:Text(L.dictionary),
          onPressed:(){
            Navigator.pop(context);
            showSnack(context, L.dictionarySearch);
          })),
    ]),

    const Divider(height:20),
    OutlinedButton.icon(onPressed:(){Navigator.pop(context);widget.onPickSub1();},
        icon:const Icon(Icons.file_open),label:Text(L.chooseSub1)),
  ]));

  // ──────── تب صدا / پخش ────────
  Widget _audioTab()=>SingleChildScrollView(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    // دیلی صدا
    Text(L.audioDelay),const SizedBox(height:6),
    Row(children:[
      IconButton(icon:const Icon(Icons.remove),onPressed:(){setState(()=>_ad-=100);widget.onAudioDelayMs(_ad);_adCtrl.text='$_ad';}),
      Expanded(child:TextField(controller:_adCtrl,keyboardType:const TextInputType.numberWithOptions(signed:true),
        textAlign:TextAlign.center,
        onChanged:(v){final n=int.tryParse(v);if(n!=null){setState(()=>_ad=n);widget.onAudioDelayMs(n);}},
        decoration:InputDecoration(suffixText:'ms',border:OutlineInputBorder(),isDense:true,
            helperText:L.hwDecode))),
      IconButton(icon:const Icon(Icons.add),onPressed:(){setState(()=>_ad+=100);widget.onAudioDelayMs(_ad);_adCtrl.text='$_ad';}),
    ]),

    const Divider(height:24),
    // تقویت صدا
    Text(L.volumeBoost),
    Text('${_amp.round()}%',style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold)),
    Slider(min:100,max:300,value:_amp,onChanged:(v){setState(()=>_amp=v);widget.onAmpVolume(v);}),

    const Divider(height:24),
    // سرعت
    SwitchListTile(contentPadding:EdgeInsets.zero,
      title:Text(L.seekPreview),
      subtitle:Text(L.seekPreviewDesc),
      value:_vs.showSeekPreview,
      onChanged:(v)=>_ch(()=>_vs.showSeekPreview=v),
    ),
    const Divider(height:12),
    Text('${L.speed}: ${_speed%1==0?_speed.toInt():_speed}x'),
    Slider(min:0.25,max:10,divisions:39,value:_speed,
        onChanged:(v){final s=(v*4).round()/4;setState(()=>_speed=s);widget.onSpeed(s);_ch(()=>_vs.speed=s);}),
    Wrap(spacing:6,runSpacing:6,children:[0.5,1.0,1.5,2.0,3.0,5.0,10.0].map((s)=>GestureDetector(
      onTap:()=>_ch(()=>_vs.speed=s),
      child:Container(
        padding:const EdgeInsets.symmetric(horizontal:10,vertical:6),
        decoration:BoxDecoration(
          color:_vs.speed==s?const Color(0xFF7C3AED):const Color(0xFF2A2A3A),
          borderRadius:BorderRadius.circular(8),
          border:Border.all(color:_vs.speed==s?const Color(0xFF7C3AED):const Color(0xFF3A3A4A))),
        child:Text('${s}x',style:TextStyle(color:_vs.speed==s?Colors.white:const Color(0xFFB0B0C0),fontSize:12))),
    )).toList()),

    const Divider(height:24),
    // حالت شب
    Text('${L.nightMode}: ${(_vs.nightOpacity*100).round()}%'),
    Slider(min:0,max:1,value:_vs.nightOpacity,activeColor:Colors.orange,onChanged:(v)=>_ch(()=>_vs.nightOpacity=v)),
  ]));

  // ──────── تب زیرنویس ۲ ────────
  Widget _sub2Tab(){
    final vs2 = widget.vs2 ?? VideoSettings(fontSize:26,bold:false,textColor:0xFFFFFF99,bgOpacity:0.4,bottomPadding:90);
    void ch2(void Function() fn){
      setState(fn);
      widget.onChanged2?.call(vs2);
    }
    return SingleChildScrollView(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      SwitchListTile(contentPadding:EdgeInsets.zero,title:Text(L.subtitle2),value:_s2v,
          onChanged:(v){setState(()=>_s2v=v);widget.onSub2Visible(v);}),
      OutlinedButton.icon(onPressed:(){Navigator.pop(context);widget.onPickSub2();},
          icon:const Icon(Icons.file_open),label:Text(L.loadSubSub2)),
      if(widget.sub2Path!=null)Text('${L.files}: '+p.basename(widget.sub2Path!),style:const TextStyle(fontSize:11,color:Colors.white54)),
      const SizedBox(height:8),
      SwitchListTile(contentPadding:EdgeInsets.zero,
        title:Text(L.subDragCopy),
        subtitle:Text(L.subDragCopy,style:TextStyle(fontSize:11)),
        value:vs2.showSubToolbar,
        onChanged:(v)=>ch2(()=>vs2.showSubToolbar=v)),
      const SizedBox(height:8),
      Text(L.fontSize),const SizedBox(height:4),
      Row(children:[
        IconButton(icon:const Icon(Icons.remove),onPressed:(){ch2(()=>vs2.fontSize=(vs2.fontSize-1).clamp(8,80));}),
        Expanded(child:Slider(min:8,max:80,value:vs2.fontSize,onChanged:(v)=>ch2(()=>vs2.fontSize=v))),
        Text('${vs2.fontSize.round()}',style:const TextStyle(fontWeight:FontWeight.bold)),
        IconButton(icon:const Icon(Icons.add),onPressed:(){ch2(()=>vs2.fontSize=(vs2.fontSize+1).clamp(8,80));}),
      ]),
      SwitchListTile(contentPadding:EdgeInsets.zero,title:const Text('Bold'),value:vs2.bold,onChanged:(v)=>ch2(()=>vs2.bold=v)),
      Text(L.textColor),const SizedBox(height:8),
      Wrap(spacing:10,children:[Colors.white,const Color(0xFFFFFF99),const Color(0xFFFFEB3B),const Color(0xFF69F0AE),const Color(0xFF40C4FF),const Color(0xFFFF8A65)].map((c)=>
        GestureDetector(onTap:()=>ch2(()=>vs2.textColor=c.value),
          child:Container(width:34,height:34,decoration:BoxDecoration(color:c,shape:BoxShape.circle,
            border:Border.all(color:c.value==vs2.textColor?Colors.white:Colors.transparent,width:3))))).toList()),
      const SizedBox(height:12),
      Text(L.transparency),
      Slider(min:0,max:1,value:vs2.bgOpacity,onChanged:(v)=>ch2(()=>vs2.bgOpacity=v)),
      const SizedBox(height:8),

      // ── رنگ پس‌زمینه ──
      Text(L.bgColor),const SizedBox(height:8),
      Wrap(spacing:10,children:[Colors.black,const Color(0xFF1A1A2E),const Color(0xFF16213E),Colors.transparent].map((c)=>
        GestureDetector(onTap:()=>ch2(()=>vs2.bgColor=c.value),
          child:Container(width:34,height:34,decoration:BoxDecoration(color:c==Colors.transparent?Colors.white12:c,shape:BoxShape.circle,
            border:Border.all(color:c.value==vs2.bgColor?Colors.white:Colors.white24,width:c.value==vs2.bgColor?3:1)),
            child:c==Colors.transparent?const Icon(Icons.block,size:18,color:Colors.white38):null))).toList()),
      const SizedBox(height:12),

      // ── چینش ──
      Text(L.alignment),const SizedBox(height:8),
      Row(mainAxisAlignment:MainAxisAlignment.start,children:[
        for(final e in [(L.left,0),(L.center,2),(L.right,1)])...[
          GestureDetector(onTap:()=>ch2(()=>vs2.textAlign=e.$2),
            child:Container(padding:const EdgeInsets.symmetric(horizontal:12,vertical:6),
              decoration:BoxDecoration(color:vs2.textAlign==e.$2?const Color(0xFF7C3AED):const Color(0xFF2A2A35),borderRadius:BorderRadius.circular(8)),
              child:Text(e.$1,style:TextStyle(color:vs2.textAlign==e.$2?Colors.white:Colors.white60,fontSize:12)))),
          const SizedBox(width:6),
        ],
      ]),
      const SizedBox(height:12),

      // ── سایه ──
      Row(children:[
        Text(L.shadow,style:TextStyle(fontSize:13)),
        const SizedBox(width:8),
        Expanded(child:Slider(min:0,max:3,value:vs2.shadowSize,onChanged:(v)=>ch2(()=>vs2.shadowSize=v))),
        Text('${vs2.shadowSize.toStringAsFixed(1)}',style:const TextStyle(fontSize:12)),
      ]),
      const SizedBox(height:12),

      // ── انتخاب فونت ──
      const Divider(color:Colors.white12),
      Text(L.font,style:TextStyle(fontSize:13)),const SizedBox(height:8),
      Wrap(spacing:8,runSpacing:6,children:['','Vazirmatn','IRANSansMobile','Roboto','Tahoma'].map((f)=>
        GestureDetector(onTap:()=>ch2(()=>vs2.fontFamily=f),
          child:Container(padding:const EdgeInsets.symmetric(horizontal:10,vertical:6),
            decoration:BoxDecoration(color:vs2.fontFamily==f?const Color(0xFF7C3AED):const Color(0xFF2A2A35),borderRadius:BorderRadius.circular(8)),
            child:Text(f.isEmpty?L.defaultFont:f,style:TextStyle(color:vs2.fontFamily==f?Colors.white:Colors.white60,fontSize:12,fontFamily:f.isEmpty?null:f))))).toList()),
      const SizedBox(height:12),

      // ── دیلی ──
      Text(L.subDelay2),const SizedBox(height:6),
      Row(children:[
        IconButton(icon:const Icon(Icons.remove),onPressed:(){setState(()=>_sd2-=100);widget.onSubDelay2Ms(_sd2);_d2Ctrl.text='$_sd2';}),
        Expanded(child:TextField(controller:_d2Ctrl,keyboardType:const TextInputType.numberWithOptions(signed:true),
          textAlign:TextAlign.center,
          onChanged:(v){final n=int.tryParse(v);if(n!=null){setState(()=>_sd2=n);widget.onSubDelay2Ms(n);}},
          decoration:InputDecoration(suffixText:'ms',border:OutlineInputBorder(),isDense:true))),
        IconButton(icon:const Icon(Icons.add),onPressed:(){setState(()=>_sd2+=100);widget.onSubDelay2Ms(_sd2);_d2Ctrl.text='$_sd2';}),
      ]),
      Slider(min:-10000,max:10000,value:_sd2.toDouble().clamp(-10000,10000),
        onChanged:(v){setState(()=>_sd2=v.round());widget.onSubDelay2Ms(_sd2);_d2Ctrl.text='$_sd2';}),
    ]));
  }
  // ──────── تب سایر ────────
  Widget _otherTab()=>SingleChildScrollView(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    // ── انتخاب زبان ──
    Text(L.language, style:const TextStyle(color:Colors.white70,fontSize:13)),
    const SizedBox(height:10),
    Wrap(spacing:8,runSpacing:8,children:[
      for(final lang in kSupportedLangs)
        GestureDetector(
          onTap:()async{await L.set(lang);if(mounted)setState((){});},
          child:Container(
            padding:const EdgeInsets.symmetric(horizontal:14,vertical:8),
            decoration:BoxDecoration(
              color:L.current==lang?const Color(0xFF7C3AED):const Color(0xFF23233A),
              borderRadius:BorderRadius.circular(20),
              border:Border.all(
                color:L.current==lang?const Color(0xFF7C3AED):Colors.white24,
                width:1.5)),
            child:Text(kLangNames[lang]!,style:TextStyle(
              color:L.current==lang?Colors.white:Colors.white70,
              fontSize:13,fontWeight:L.current==lang?FontWeight.w600:FontWeight.normal))),
        ),
    ]),
    const Divider(height:24,color:Colors.white12),
    // پیش‌نمایش اسکراب (دسترسی سریع)
    SwitchListTile(contentPadding:EdgeInsets.zero,
      title:Text(L.seekPreview),
      subtitle:Text(L.seekPreviewDesc),
      secondary:const Icon(Icons.video_stable_rounded),
      value:_vs.showSeekPreview,
      onChanged:(v)=>_ch(()=>_vs.showSeekPreview=v),
    ),
    const Divider(height:16),
    FilledButton.icon(onPressed:widget.onSaveForVideo,icon:const Icon(Icons.save),
        label:Text(L.saveVideoSettings)),
    const SizedBox(height:6),
    Text(L.saveVideoSettingsDesc,
        style:TextStyle(fontSize:12,color:Colors.white54)),
    const Divider(height:28),
    Text(L.guide,style:TextStyle(fontWeight:FontWeight.bold)),const SizedBox(height:8),
    _helpRow(L.swipeHorizontal,L.seekVideo),
    _helpRow(L.swipeLeft,L.adjustBrightness),
    _helpRow(L.swipeRight,L.adjustVolume),
    _helpRow(L.swipeBottomSub,L.moveSubtitle),
    _helpRow(L.twoFingers,L.zoomMove),
    _helpRow(L.doubleTapLeft,L.tenSecBack),
    _helpRow(L.doubleTapRight,L.tenSecForward),
    _helpRow(L.doubleTapCenter,L.playPause),
    _helpRow(L.holdDown,L.playPause),
    const Divider(height:24),
    // کنترل زیرنویس داخلی
    SwitchListTile(contentPadding:EdgeInsets.zero,
      title:Text(L.embeddedSubtitle),
      subtitle:Text(L.enableEmbeddedSub),
      value:_embeddedSub,
      onChanged:(v){setState(()=>_embeddedSub=v);widget.onEmbeddedSubEnabled(v);},
    ),
    const Divider(height:16),
    Text(L.decoder,style:TextStyle(fontWeight:FontWeight.bold)),const SizedBox(height:8),
    SegmentedButton<bool>(
      segments:[
        ButtonSegment(value:true,label:Text('HW'),icon:Icon(Icons.memory,size:16)),
        ButtonSegment(value:false,label:Text('SW'),icon:Icon(Icons.computer,size:16)),
      ],
      selected:{_hwDecode},
      onSelectionChanged:(s){setState(()=>_hwDecode=s.first);widget.onHwDecode(s.first);},
    ),
    const SizedBox(height:4),
    Text('HW: ${L.hwDecode} | SW: ${L.swDecode}',style:TextStyle(fontSize:11,color:Colors.white54)),
    if(widget.videoWidth!=null&&widget.videoHeight!=null)...[
      const Divider(height:18),
      Text(L.resolution,style:TextStyle(fontSize:12,color:Colors.white54)),const SizedBox(height:4),
      Text('${widget.videoWidth}×${widget.videoHeight}',style:const TextStyle(fontSize:14,color:Colors.greenAccent,fontWeight:FontWeight.bold)),
    ],
  ]));

  Widget _helpRow(String key,String val)=>Padding(
    padding:const EdgeInsets.symmetric(vertical:3),
    child:Row(children:[
      SizedBox(width:160,child:Text(key,style:const TextStyle(color:Colors.white70,fontSize:12))),
      Text(val,style:const TextStyle(color:Colors.white54,fontSize:12)),
    ]),
  );
}

// ──────── تب ابزارها — بکاپ و ایمپورت مدل‌های AI ────────
class ToolsTabBody extends StatefulWidget {
  const ToolsTabBody({super.key});
  @override State<ToolsTabBody> createState() => ToolsTabBodyState();
}

class ToolsTabBodyState extends State<ToolsTabBody> {
  bool _loading = false;
  String _status = '';

  Future<void> _backupAll() async {
    setState(() { _loading = true; _status = L.backingUp; });
    try {
      await const MethodChannel('com.vezoo.player/whisper')
        .invokeMethod<List>('backupModels', {'destDir': '/storage/emulated/0/Download/Vezoo/Backup'});
      setState(() { _status = 'SUCCESS: ${L.backup}'; });
    } catch (e) { setState(() { _status = L.errorMsg(e); }); }
    finally { setState(() { _loading = false; }); }
  }

  Future<void> _importModel() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.any);
    if (res == null || res.files.single.path == null) return;
    setState(() { _loading = true; _status = L.importing; });
    try {
      final modelsRoot = await WhisperService.getModelsRoot();
      await Directory(modelsRoot).create(recursive: true);
      final savedPath = await const MethodChannel('com.vezoo.player/whisper')
        .invokeMethod<String>('importModel', {'path': res.files.single.path!, 'modelsDir': modelsRoot});
      setState(() { _status = 'SUCCESS: $savedPath'; });
    } catch (e) { setState(() { _status = L.errorMsg(e); }); }
    finally { setState(() { _loading = false; }); }
  }

  @override
  Widget build(BuildContext ctx) => SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // ── Gemini Live ──
      _GeminiApiKeyCard(),
      // ── yt-dlp ──
      _YtDlpCard(),
      const SizedBox(height: 12),

      // ── Vosk Models ──
      ListTile(
        tileColor: const Color(0xFF1A1A2A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        leading: const Icon(Icons.record_voice_over_rounded, color: Color(0xFF7C3AED)),
        title: const Text('Vosk — مدل‌های زبان', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        subtitle: const Text('آفلاین • ۱۸ زبان • زیرنویس زنده بدون اینترنت', style: TextStyle(color: Colors.white38, fontSize: 11)),
        trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white38),
        onTap: () => Navigator.push(ctx, MaterialPageRoute(builder: (_) => const VoskModelsScreen()))),
      const SizedBox(height: 12),

      Container(padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: const Color(0xFF2A2A35), borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.psychology_rounded, color: Color(0xFF22c55e), size: 18),
            const SizedBox(width: 8),
            Text(L.backupImport, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 4),
          Text(L.backupPath, style: const TextStyle(color: Colors.white54, fontSize: 11)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: FilledButton.icon(
              onPressed: _loading ? null : _backupAll,
              icon: const Icon(Icons.save_alt_rounded, size: 16),
              label: Text(L.backup),
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF22c55e)))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton.icon(
              onPressed: _loading ? null : _importModel,
              icon: const Icon(Icons.upload_file_rounded, size: 16),
              label: Text(L.importModel))),
          ]),
          if (_loading) ...[const SizedBox(height:8), const LinearProgressIndicator()],
          if (_status.isNotEmpty) Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_status, style: const TextStyle(color: Colors.white60, fontSize: 11))),
        ]),
      ),
    ]),
  );
}

// ── Widget آپدیت yt-dlp ──
class _YtDlpCard extends StatefulWidget {
  @override State<_YtDlpCard> createState() => _YtDlpCardState();
}

class _YtDlpCardState extends State<_YtDlpCard> {
  String _version = '...';
  String _status = '';
  bool _updating = false;
  bool _cancelled = false;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final v = await YtDlpService.getVersion();
    if (mounted) setState(() => _version = v);
  }

  Future<void> _update() async {
    setState(() { _updating = true; _cancelled = false; _status = ''; });
    await YtDlpService.updateWithProgress((s) {
      if (mounted && !_cancelled) setState(() => _status = s);
    });
    if (mounted) {
      setState(() => _updating = false);
      await _loadVersion();
    }
  }

  @override
  Widget build(BuildContext ctx) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFF1A1A2A),
      borderRadius: BorderRadius.circular(12)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.download_for_offline_rounded, color: Color(0xFF7C3AED), size: 18),
        const SizedBox(width: 8),
        const Text('yt-dlp', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(6)),
          child: Text('v$_version', style: const TextStyle(color: Colors.white54, fontSize: 10))),
      ]),
      const SizedBox(height: 4),
      const Text('پشتیبانی از ۱۰۰۰+ سایت', style: TextStyle(color: Colors.white38, fontSize: 11)),
      if (_status.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text(_status, style: TextStyle(
          color: _status.startsWith('❌') ? Colors.redAccent :
                 _status.startsWith('✅') ? Colors.greenAccent : Colors.white60,
          fontSize: 11)),
      ],
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: FilledButton.icon(
          onPressed: _updating ? null : _update,
          icon: _updating
            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.update_rounded, size: 16),
          label: Text(_updating ? 'در حال آپدیت...' : 'آپدیت yt-dlp'),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF7C3AED),
            padding: const EdgeInsets.symmetric(vertical: 8)))),
        if (_updating) ...[
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: () => setState(() { _cancelled = true; _updating = false; _status = 'لغو شد'; }),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: const BorderSide(color: Colors.red),
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12)),
            child: const Text('لغو')),
        ],
      ]),
    ]),
  );
}

// ── کارت Gemini API Key ──
class _GeminiApiKeyCard extends StatefulWidget {
  @override State<_GeminiApiKeyCard> createState() => _GeminiApiKeyCardState();
}
class _GeminiApiKeyCardState extends State<_GeminiApiKeyCard> {
  String? _key;
  bool _show = false;
  bool _testing = false;
  String? _testResult;
  final _ctrl = TextEditingController();

  @override void initState() { super.initState(); _load(); }
  @override void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    final k = await GeminiLiveService.getApiKey();
    if (mounted) setState(() { _key = k; _ctrl.text = k ?? ''; });
  }

  Future<void> _testKey() async {
    final k = _key;
    if (k == null || k.isEmpty) return;
    setState(() { _testing = true; _testResult = null; });
    try {
      // تست با Gemini REST API
      final url = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models?key=$k');
      final resp = await http.get(url).timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final body = resp.body;
        final hasLive = body.contains('gemini') && body.contains('live');
        setState(() => _testResult = hasLive
          ? '✅ API Key valid — Gemini Live models found'
          : '✅ API Key valid — but Gemini Live model may not be available');
      } else if (resp.statusCode == 400) {
        setState(() => _testResult = '❌ Invalid API key (400)');
      } else if (resp.statusCode == 403) {
        setState(() => _testResult = '❌ API key disabled or no access (403)');
      } else {
        setState(() => _testResult = '❌ Error: HTTP \${resp.statusCode}');
      }
    } catch (e) {
      setState(() => _testResult = '❌ Network error: \${e.toString().substring(0, e.toString().length.clamp(0, 60))}');
    } finally {
      setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    color: const Color(0xFF12122A),
    child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.translate_rounded, color: Color(0xFF7C3AED), size: 18),
        const SizedBox(width: 8),
        const Text('Gemini Live Translation', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
        const Spacer(),
        if (_key != null && _key!.isNotEmpty)
          const Icon(Icons.check_circle_rounded, color: Colors.green, size: 16),
      ]),
      const SizedBox(height: 4),
      const Text('Real-time AI translation · Requires API key from Google AI Studio',
        style: TextStyle(color: Colors.white54, fontSize: 11)),
      const SizedBox(height: 12),
      TextField(
        controller: _ctrl,
        obscureText: !_show,
        style: const TextStyle(color: Colors.white, fontSize: 12),
        decoration: InputDecoration(
          hintText: 'AIza...',
          hintStyle: const TextStyle(color: Colors.white24),
          filled: true, fillColor: const Color(0xFF0D0D1E),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          suffixIcon: IconButton(
            icon: Icon(_show ? Icons.visibility_off_rounded : Icons.visibility_rounded, size: 18, color: Colors.white38),
            onPressed: () => setState(() => _show = !_show))),
      ),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: FilledButton(
          onPressed: () async {
            final k = _ctrl.text.trim();
            if (k.isEmpty) return;
            await GeminiLiveService.saveApiKey(k);
            setState(() => _key = k);
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('✅ Gemini API key saved'), backgroundColor: Colors.green, duration: Duration(seconds: 2)));
          },
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF7C3AED), padding: const EdgeInsets.symmetric(vertical: 8)),
          child: const Text('Save Key', style: TextStyle(fontSize: 13)))),
        if (_key != null && _key!.isNotEmpty) ...[
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: () async {
              await GeminiLiveService.clearApiKey();
              _ctrl.clear();
              setState(() => _key = null);
            },
            style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red), padding: const EdgeInsets.symmetric(vertical: 8)),
            child: const Text('Remove', style: TextStyle(fontSize: 13))),
        ],
      ]),
      const SizedBox(height: 8),
      if (_key != null && _key!.isNotEmpty) ...[
        SizedBox(width: double.infinity, child: OutlinedButton.icon(
          onPressed: _testing ? null : _testKey,
          icon: _testing
            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.wifi_tethering_rounded, size: 16),
          label: Text(_testing ? 'Testing...' : 'Test API Key'),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF10B981),
            side: const BorderSide(color: Color(0xFF10B981)),
            padding: const EdgeInsets.symmetric(vertical: 8)))),
        if (_testResult != null) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _testResult!.startsWith('✅') ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6)),
            child: Text(_testResult!, style: TextStyle(
              color: _testResult!.startsWith('✅') ? Colors.green : Colors.red,
              fontSize: 11))),
        ],
        const SizedBox(height: 8),
      ],
      InkWell(
        onTap: () {}, // لینک به AI Studio
        child: const Text('Get free API key → aistudio.google.com',
          style: TextStyle(color: Color(0xFF7C3AED), fontSize: 11, decoration: TextDecoration.underline))),
    ])));
}
