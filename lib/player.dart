// lib/player.dart — پلیر ویدیو
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:file_picker/file_picker.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';
import 'store.dart';
import 'settings.dart';

enum _GMode{none,seek,brightness,volume,zoom,pan,subtitlePos}
enum _Repeat{none,one,all}

class PlayerScreen extends StatefulWidget {
  final String? subtitlePath;
  final List<File> playlist;
  final int playlistIndex;
  const PlayerScreen({super.key,this.subtitlePath,required this.playlist,required this.playlistIndex});
  @override State<PlayerScreen> createState()=>_PlayerState();
}

class _PlayerState extends State<PlayerScreen>{
  late final Player player=Player();
  late final VideoController controller=VideoController(player);
  late int _idx;

  Duration _position=Duration.zero,_duration=Duration.zero;
  bool _playing=true;
  final List<StreamSubscription> _subs=[];

  // زیرنویس
  List<SubEntry> _sub1=[];
  List<SubEntry> _sub2=[];
  bool _sub1Visible=true,_sub2Visible=false;
  String? _sub2Path;
  List<AudioTrack> _audioTracks=[];
  List<SubtitleTrack> _subtitleTracks=[];
  // soft-sub embedded در ویدیو
  bool _embeddedSubEnabled=false; // خودکار فعال می‌شه

  // تنظیمات قابل ذخیره
  late VideoSettings _vs=VideoSettings();
  int _subDelayMs=0,_subDelay2Ms=0,_audioDelayMs=0;
  Color _color2=const Color(0xFFFFEB3B);

  // پخش
  BoxFit _fit=BoxFit.contain;
  bool _landscape=false;
  _Repeat _repeatMode=_Repeat.none;
  bool _muted=false,_hwDecode=true;
  double _currentAmpVolume=100.0;
  double _savedVol=100;
  double _rotationDeg=0;

  // اطلاعات ویدیو
  int? _videoWidth,_videoHeight;
  VideoParams? _videoParams;

  // HDR detection — فقط pixelformat موجود در media_kit 1.2.6
  bool get _isHDR {
    if(_videoParams==null) return false;
    final pf=(_videoParams!.pixelformat??'').toLowerCase();
    return pf.contains('p10')||pf.contains('p12')||pf.contains('10le')||pf.contains('16le');
  }
  String get _codecStr => '';   // media_kit 1.2.6 این فیلد را ندارد
  String get _fpsStr => '';     // media_kit 1.2.6 این فیلد را ندارد
  String get _bitrateStr => ''; // media_kit 1.2.6 این فیلد را ندارد
  String get _resStr => (_videoWidth!=null&&_videoHeight!=null)?'${_videoWidth}×${_videoHeight}':'';
  String get _pixelFmtStr => _videoParams?.pixelformat??'';

  // A-B
  Duration? _repeatA,_repeatB;
  bool _abActive=false;

  // Sleep
  Timer? _sleepTimer;
  DateTime? _sleepAt;

  // اسلایدر پیش‌نمایش
  bool _seekDragging=false;
  double _seekDragMs=0;
  // Fast seek (long press)
  bool _fastSeeking=false;
  bool _fastSeekRight=false;
  double _fastSeekSpeed=3.0; // ثانیه در ثانیه
  double _fastSeekBaseSpeed=3.0;
  Timer? _fastSeekTimer;
  Timer? _thumbTimer;

  // UI
  bool _controlsVisible=true,_locked=false;
  Timer? _hideTimer,_overlayTimer;
  String? _overlay;
  double _scale=1.0,_baseScale=1.0;
  Offset _offset=Offset.zero,_baseOffset=Offset.zero;
  _GMode _mode=_GMode.none;
  Offset _startFocal=Offset.zero,_doubleTapPos=Offset.zero;
  int _seekStartMs=0,_seekTargetMs=0;
  double _startBrightness=0.5,_startSysVol=0.5;
  double _subPaddingStart=50;
  Size _size=Size.zero;
  final GlobalKey _videoKey=GlobalKey();

  String get _curPath=>widget.playlist[_idx].path;
  bool get _hasPrev=>_idx>0;
  bool get _hasNext=>_idx<widget.playlist.length-1;

  // فقط external subtitle — embedded رو libmpv مستقیم render می‌کنه
  String? get _subText{
    if(!_sub1Visible||_sub1.isEmpty)return null;
    final adj=_position-Duration(milliseconds:_subDelayMs);
    for(final e in _sub1){if(adj>=e.start&&adj<=e.end)return e.text;}
    return null;
  }
  String? get _sub2Text{
    if(!_sub2Visible||_sub2.isEmpty)return null;
    final adj=_position-Duration(milliseconds:_subDelay2Ms);
    for(final e in _sub2){if(adj>=e.start&&adj<=e.end)return e.text;}
    return null;
  }

  @override
  void initState(){
    super.initState();
    _idx=widget.playlistIndex.clamp(0,(widget.playlist.length-1).clamp(0,999999));
    final saved=Store.loadVideoSettings(_curPath);
    if(saved!=null)_vs=saved;
    WakelockPlus.enable();
    VolumeController.instance.showSystemUI=false;
    _subs.add(player.stream.position.listen((pos){
      _position=pos; _maybeWatched();
      if(_abActive&&_repeatA!=null&&_repeatB!=null&&_position>=_repeatB!) player.seek(_repeatA!);
      if(mounted)setState((){});
    }));
    _subs.add(player.stream.duration.listen((d){
      _duration=d;
      if(d.inSeconds>0)Store.saveDur(_curPath,d.inSeconds);
      if(mounted)setState((){});
    }));
    _subs.add(player.stream.playing.listen((pl){_playing=pl;if(mounted)setState((){});}));
    _subs.add(player.stream.tracks.listen((t){
      if(!mounted)return;
      final newSubTracks=t.subtitle.where((s)=>s.id!='no'&&s.id!='auto').toList();
      setState((){
        _audioTracks=t.audio;
        _subtitleTracks=newSubTracks;
      });
      // خودکار اولین تراک embedded رو فعال کن (اگه هنوز فعال نشده)
      if(newSubTracks.isNotEmpty&&!_embeddedSubEnabled){
        setState(()=>_embeddedSubEnabled=true);
        player.setSubtitleTrack(newSubTracks.first);
      }
    }));

    _subs.add(player.stream.width.listen((w){if(mounted&&w!=null)setState(()=>_videoWidth=w);}));
    _subs.add(player.stream.height.listen((h){if(mounted&&h!=null)setState(()=>_videoHeight=h);}));
    _subs.add(player.stream.videoParams.listen((vp){if(mounted)setState(()=>_videoParams=vp);}));
    _subs.add(player.stream.completed.listen((done){
      if(!done)return;
      switch(_repeatMode){
        case _Repeat.one:player.seek(Duration.zero);player.play();break;
        case _Repeat.all:_switchVideo((_idx+1)%widget.playlist.length);break;
        case _Repeat.none:if(_hasNext)_switchVideo(_idx+1);break;
      }
    }));
    _start(); _startHideTimer();
  }

  Future<void> _start()async{
    await player.open(Media(_curPath));
    await Store.addToHistory(_curPath);
    final saved=await Store.getPos(_curPath);
    if(saved.inSeconds>5&&mounted){
      final resume=await showDialog<bool>(
        context:context,barrierDismissible:false,
        builder:(ctx)=>AlertDialog(backgroundColor:const Color(0xFF1C1C22),title:const Text('ادامه پخش'),
          content:Text('از ${fmt(saved)} ادامه دهیم؟'),
          actions:[
            TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('از ابتدا')),
            FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('ادامه')),
          ]),
      );
      if(resume==true&&mounted)await player.seek(saved);
    }
    // امتحان همه زیرنویس‌های موجود به ترتیب اولویت
    final subPath=widget.subtitlePath??matchSubtitle(_curPath);
    if(subPath!=null)await _loadSub(subPath,secondary:false);
    if(_vs.speed!=1.0)player.setRate(_vs.speed);
  }

  Future<void> _switchVideo(int idx)async{
    await Store.savePos(_curPath,_position);
    _idx=idx; _position=Duration.zero; _duration=Duration.zero;
    _sub1=[]; _sub2=[]; _repeatA=null; _repeatB=null; _abActive=false;
    _videoWidth=null; _videoHeight=null;
    final newVs=Store.loadVideoSettings(_curPath);
    if(newVs!=null)_vs=newVs;
    setState((){});
    await player.open(Media(_curPath));
    await Store.addToHistory(_curPath);
    final sv=await Store.getPos(_curPath);
    if(sv.inSeconds>5)await player.seek(sv);
    final sub=matchSubtitle(_curPath);
    if(sub!=null)await _loadSub(sub,secondary:false);
    if(_vs.speed!=1.0)player.setRate(_vs.speed);
  }

  void _maybeWatched(){
    if(_duration.inSeconds>0&&_position.inSeconds>_duration.inSeconds*0.9) Store.markWatched(_curPath);
  }

  Future<void> _loadSub(String path,{required bool secondary})async{
    try{
      final bytes=await File(path).readAsBytes();
      String content;
      try{content=utf8.decode(bytes);}catch(_){content=utf8.decode(bytes,allowMalformed:true);}
      final ext=p.extension(path).toLowerCase();
      var entries=parseSubtitle(content,ext);
      // اگه خالی بود، سعی کن فرمت‌های دیگه همون ویدیو رو پیدا کن
      if(entries.isEmpty&&!secondary){
        final videoPath=_curPath;
        final allSubs=findAllSubtitles(videoPath);
        for(final altPath in allSubs){
          if(altPath==path)continue;
          try{
            final altBytes=await File(altPath).readAsBytes();
            String altContent;
            try{altContent=utf8.decode(altBytes);}catch(_){altContent=utf8.decode(altBytes,allowMalformed:true);}
            final altEntries=parseSubtitle(altContent,p.extension(altPath).toLowerCase());
            if(altEntries.isNotEmpty){
              entries=altEntries;
              if(mounted)ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content:Text('زیرنویس خالی بود — استفاده از: \${p.basename(altPath)}')));
              break;
            }
          }catch(_){}
        }
      }
      if(secondary){setState((){_sub2=entries;_sub2Path=path;_sub2Visible=entries.isNotEmpty;});}
      else{setState(()=>_sub1=entries);}
    }catch(e){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content:Text('خطا در بارگذاری زیرنویس: \${p.basename(path)}')));
    }
  }

  Future<void> _pickSub({required bool secondary})async{
    final res=await FilePicker.platform.pickFiles(type:FileType.custom,allowedExtensions:['srt','vtt','ass','ssa','sub','sbv','smi','lrc','sup','idx']);
    if(res?.files.single.path!=null)await _loadSub(res!.files.single.path!,secondary:secondary);
  }

  Future<void> _pickFont()async{
    final res=await FilePicker.platform.pickFiles(type:FileType.custom,allowedExtensions:['ttf','otf']);
    if(res?.files.single.path==null)return;
    final path=res!.files.single.path!;
    final name='SubFont_${DateTime.now().millisecondsSinceEpoch}';
    try{
      final loader=FontLoader(name);
      final bytes=await File(path).readAsBytes();
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
      await loader.load();
      setState(()=>_vs.fontFamily=name);
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('فونت بارگذاری شد')));
    }catch(_){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('خطا در فونت')));}
  }

  void _copySubText(){
    final text=_subText??_sub2Text;
    if(text!=null){
      Clipboard.setData(ClipboardData(text:text));
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('کپی شد')));
    }
  }

  Future<void> _translateSubText()async{
    final text=_subText??_sub2Text;
    if(text==null)return;
    final url=Uri.parse('https://translate.google.com/?text=${Uri.encodeComponent(text)}&hl=fa');
    try{await launchUrl(url,mode:LaunchMode.externalApplication);}catch(_){
      Clipboard.setData(ClipboardData(text:text));
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('متن کپی شد — در اپ ترجمه paste کنید')));
    }
  }

  Future<void> _dictionarySubText()async{
    final text=_subText??_sub2Text;
    if(text==null)return;
    final word=text.split(RegExp(r'\s+')).first.replaceAll(RegExp(r'[^a-zA-Z]'),'');
    if(word.isEmpty){Clipboard.setData(ClipboardData(text:text));return;}
    final url=Uri.parse('https://dictionary.cambridge.org/dictionary/english/${Uri.encodeComponent(word)}');
    try{await launchUrl(url,mode:LaunchMode.externalApplication);}catch(_){
      Clipboard.setData(ClipboardData(text:text));
    }
  }

  Future<void> _takeScreenshot()async{
    try{
      final boundary=_videoKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if(boundary==null)return;
      final image=await boundary.toImage(pixelRatio:2.0);
      final byteData=await image.toByteData(format:ui.ImageByteFormat.png);
      if(byteData==null)return;
      final ts=DateTime.now().millisecondsSinceEpoch;
      final path='/storage/emulated/0/Pictures/screenshot_$ts.png';
      await File(path).writeAsBytes(byteData.buffer.asUint8List());
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('ذخیره شد: Pictures/screenshot_$ts.png')));
    }catch(_){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('خطا در اسکرین‌شات')));}
  }

  Future<void> _saveVsForVideo()async{
    await Store.saveVideoSettings(_curPath,_vs);
    if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('تنظیمات برای این ویدیو ذخیره شد')));
  }

  // ── Thumbnail preview — فقط timestamp نمایش داده می‌شه ──
  void _onSeekDragUpdate(double ms) {
    setState(() => _seekDragMs = ms);
    _thumbTimer?.cancel();
    _thumbTimer = Timer(const Duration(milliseconds: 100), () {
      // در آینده می‌توان frame واقعی را اینجا نمایش داد
    });
  }

  void _showSleepDialog(){
    int min=30;
    showDialog(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,ss)=>AlertDialog(
      backgroundColor:const Color(0xFF1C1C22),title:const Text('تایمر خواب'),
      content:Column(mainAxisSize:MainAxisSize.min,children:[
        Text('$min دقیقه',style:const TextStyle(fontSize:24,fontWeight:FontWeight.bold)),
        Slider(min:1,max:180,divisions:179,value:min.toDouble(),onChanged:(v)=>ss(()=>min=v.round())),
        if(_sleepAt!=null)Text('باقی‌مانده: ${_sleepAt!.difference(DateTime.now()).inMinutes} دقیقه',style:const TextStyle(color:Colors.orange)),
      ]),
      actions:[
        if(_sleepAt!=null)TextButton(onPressed:(){_sleepTimer?.cancel();setState(()=>_sleepAt=null);Navigator.pop(ctx);},child:const Text('لغو',style:TextStyle(color:Colors.red))),
        TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('بستن')),
        FilledButton(onPressed:(){
          _sleepTimer?.cancel();
          final at=DateTime.now().add(Duration(minutes:min));
          setState(()=>_sleepAt=at);
          _sleepTimer=Timer(Duration(minutes:min),(){player.pause();setState(()=>_sleepAt=null);});
          Navigator.pop(ctx);
        },child:const Text('شروع')),
      ],
    )));
  }

  // انتخاب تراک زیرنویس embedded (softsub)
  void _showEmbeddedSubPicker(){
    showDialog(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,ss)=>AlertDialog(
      title:const Text('زیرنویس داخلی ویدیو'),
      content:Column(mainAxisSize:MainAxisSize.min,children:[
        // toggle کلی
        SwitchListTile(
          dense:true,
          title:const Text('فعال‌سازی زیرنویس داخلی'),
          subtitle:Text(_embeddedSubEnabled?'فعال — libmpv رندر می‌کنه':'غیرفعال'),
          value:_embeddedSubEnabled,
          onChanged:(v){
            setState(()=>_embeddedSubEnabled=v);ss((){});
            if(v&&_subtitleTracks.isNotEmpty){player.setSubtitleTrack(_subtitleTracks.first);}
          },
        ),
        const Divider(height:1),
        if(_subtitleTracks.isEmpty)const Padding(
          padding:EdgeInsets.all(12),
          child:Text('این ویدیو تراک زیرنویس داخلی ندارد',
              style:TextStyle(color:Color(0xFF94A3B8)),textAlign:TextAlign.center)),
        ..._subtitleTracks.asMap().entries.map((entry){
          final t=entry.value;
          return ListTile(dense:true,
            leading:const Icon(Icons.subtitles,size:18,color:Color(0xFF94A3B8)),
            title:Text(t.title??t.language??'Track ${t.id}'),
            subtitle:Text('زبان: ${t.language??'—'}',style:const TextStyle(fontSize:11)),
            trailing:FilledButton(
              style:FilledButton.styleFrom(padding:const EdgeInsets.symmetric(horizontal:12),minimumSize:const Size(60,30)),
              onPressed:(){
                player.setSubtitleTrack(t);
                setState(()=>_embeddedSubEnabled=true);ss((){});
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content:Text('تراک: ${t.title??t.language??t.id}')));
              },
              child:const Text('انتخاب',style:TextStyle(fontSize:12)),
            ),
          );
        }),
        const Divider(height:1),
        const Padding(padding:EdgeInsets.all(8),
          child:Text('⚡ زیرنویس داخلی + خارجی هم‌زمان نمایش داده می‌شن',
              style:TextStyle(fontSize:11,color:Color(0xFF7C3AED)))),
      ]),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('بستن'))],
    )));
  }

  void _showAudioPicker(){
    if(_audioTracks.isEmpty){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('تراک صوتی یافت نشد')));return;}
    showDialog(context:context,builder:(ctx)=>AlertDialog(
      backgroundColor:const Color(0xFF1C1C22),title:const Text('انتخاب تراک صوتی'),
      content:Column(mainAxisSize:MainAxisSize.min,
          children:_audioTracks.map((t)=>ListTile(
            title:Text(t.title??t.language??'Track ${t.id}'),
            leading:const Icon(Icons.music_note),
            onTap:(){player.setAudioTrack(t);Navigator.pop(ctx);},
          )).toList()),
    ));
  }

  void _showVideoInfo(){
    showDialog(context:context,builder:(ctx)=>AlertDialog(
      title:Text(p.basename(_curPath),style:const TextStyle(fontSize:13)),
      content:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
        if(_resStr.isNotEmpty)_infoRow(Icons.aspect_ratio_rounded,const Color(0xFF0EA5E9),'رزولوشن',_resStr),
        if(_fpsStr.isNotEmpty)_infoRow(Icons.speed_rounded,const Color(0xFF7C3AED),'فریم ریت',_fpsStr),
        if(_codecStr.isNotEmpty)_infoRow(Icons.code_rounded,const Color(0xFF10B981),'کدک',_codecStr),
        if(_bitrateStr.isNotEmpty)_infoRow(Icons.network_check_rounded,const Color(0xFFF59E0B),'بیت‌ریت',_bitrateStr),
        if(_isHDR)_infoRow(Icons.hdr_on_rounded,const Color(0xFFEC4899),'HDR','فعال ✓'),
        if(_pixelFmtStr.isNotEmpty)_infoRow(Icons.palette_rounded,const Color(0xFF7C3AED),'Pixel Format',_pixelFmtStr),
        _infoRow(Icons.timer_outlined,const Color(0xFF94A3B8),'مدت',fmt(_duration)),
        _infoRow(Icons.memory_rounded,const Color(0xFF94A3B8),'دیکودر',_hwDecode?'سخت‌افزاری (HW)':'نرم‌افزاری (SW)'),
        if(_audioTracks.isNotEmpty)
          _infoRow(Icons.music_note_rounded,const Color(0xFF94A3B8),'تراک صوتی','${_audioTracks.length} تراک'),
        if(_hwDecode)_infoRow(Icons.developer_board_rounded,const Color(0xFF0EA5E9),'دیکودر','سخت‌افزاری فعال'),
      ]),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('بستن'))],
    ));
  }

  Widget _infoRow(IconData icon,Color iconColor,String label,String val)=>Padding(
    padding:const EdgeInsets.symmetric(vertical:4),
    child:Row(children:[
      Container(padding:const EdgeInsets.all(5),decoration:BoxDecoration(color:iconColor.withOpacity(0.1),borderRadius:BorderRadius.circular(6)),
          child:Icon(icon,size:13,color:iconColor)),
      const SizedBox(width:10),
      Text('$label',style:const TextStyle(color:Color(0xFF94A3B8),fontSize:12)),
      const Spacer(),
      Text(val,style:const TextStyle(fontSize:12,fontWeight:FontWeight.w500)),
    ]),
  );

  // دکمه ابزار زیرنویس
  // دکمه کوچک بالای زیرنویس
  Widget _subSmallBtn(IconData icon,String tooltip)=>Tooltip(
    message:tooltip,
    child:Container(
      padding:const EdgeInsets.all(6),
      decoration:BoxDecoration(
        color:Colors.black.withOpacity(0.65),
        borderRadius:BorderRadius.circular(8),
        border:Border.all(color:Colors.white.withOpacity(0.18)),
      ),
      child:Icon(icon,size:15,color:Colors.white60),
    ),
  );

  Widget _subToolBtn(IconData icon,String tooltip,VoidCallback onTap)=>Tooltip(
    message:tooltip,
    child:GestureDetector(
      onTap:onTap,
      child:Container(
        padding:const EdgeInsets.all(6),
        decoration:BoxDecoration(
          color:Colors.black.withOpacity(0.55),
          borderRadius:BorderRadius.circular(8),
          border:Border.all(color:Colors.white.withOpacity(0.15)),
        ),
        child:Icon(icon,size:16,color:Colors.white70),
      ),
    ),
  );

  // badge کوچک برای top bar
  Widget _infoBadge(String text,Color color)=>Container(
    padding:const EdgeInsets.symmetric(horizontal:5,vertical:1),
    decoration:BoxDecoration(color:color.withOpacity(0.15),borderRadius:BorderRadius.circular(4),
        border:Border.all(color:color.withOpacity(0.4),width:0.5)),
    child:Text(text,style:TextStyle(fontSize:9,color:color,fontWeight:FontWeight.w700)),
  );

  void _startFastSeek(bool forward){
    // forward=true → جلو (چپ صفحه)، forward=false → عقب (راست صفحه)
    if(_locked)return;
    _fastSeekTimer?.cancel();
    // نوار سمت راست = وقتی عقب میریم، سمت چپ = وقتی جلو
    setState((){_fastSeeking=true;_fastSeekRight=!forward;_fastSeekBaseSpeed=_fastSeekSpeed;});
    _fastSeekTimer=Timer.periodic(const Duration(milliseconds:80),(t){
      final delta=(_fastSeekSpeed*(forward?1:-1)*80).round();
      final ms=(_position.inMilliseconds+delta).clamp(0,_duration.inMilliseconds);
      player.seek(Duration(milliseconds:ms));
    });
  }

  void _stopFastSeek(){
    _fastSeekTimer?.cancel();
    setState(()=>_fastSeeking=false);
  }

  void _adjustFastSeekSpeed(double dy){
    // بالا = سریع‌تر، پایین = کندتر
    setState(()=>_fastSeekSpeed=(_fastSeekBaseSpeed-dy/60).clamp(1.0,20.0));
  }

  @override
  void dispose(){
    Store.savePos(_curPath,_position);
    for(final s in _subs)s.cancel();
    _hideTimer?.cancel();_overlayTimer?.cancel();_sleepTimer?.cancel();_thumbTimer?.cancel();
    WakelockPlus.disable();
    try{ScreenBrightness().resetApplicationScreenBrightness();}catch(_){}
    try{VolumeController.instance.showSystemUI=true;}catch(_){}
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    player.dispose();
    super.dispose();
  }

  void _startHideTimer(){_hideTimer?.cancel();_hideTimer=Timer(const Duration(seconds:4),(){if(mounted)setState(()=>_controlsVisible=false);});}
  void _toggleControls(){if(!_locked){setState(()=>_controlsVisible=!_controlsVisible);if(_controlsVisible)_startHideTimer();}}
  void _showOverlay(String text){
    setState(()=>_overlay=text);_overlayTimer?.cancel();
    _overlayTimer=Timer(const Duration(milliseconds:900),(){if(mounted)setState(()=>_overlay=null);});
  }

  // دابل‌تپ: راست=عقب، چپ=جلو (RTL)، وسط=pause/play
  void _onDoubleTap(){
    if(_locked)return;
    final third=_size.width/3;
    if(_doubleTapPos.dx>third*2){
      var t=_position-const Duration(seconds:10);
      if(t<Duration.zero)t=Duration.zero;
      player.seek(t);_showOverlay('⏮ ۱۰ ثانیه');
    }else if(_doubleTapPos.dx<third){
      player.seek(_position+const Duration(seconds:10));_showOverlay('۱۰ ثانیه ⏭');
    }else{
      _playing?player.pause():player.play();_showOverlay(_playing?'⏸':'▶');_startHideTimer();
    }
  }

  Future<double> _getBr()async{try{return await ScreenBrightness().application;}catch(_){return 0.5;}}
  Future<void> _setBr(double v)async{try{await ScreenBrightness().setApplicationScreenBrightness(v.clamp(0.0,1.0));}catch(_){}}

  void _onScaleStart(ScaleStartDetails d){
    if(_locked)return;
    _mode=_GMode.none;_baseScale=_scale;_baseOffset=_offset;
    _startFocal=d.localFocalPoint;_seekStartMs=_position.inMilliseconds;_subPaddingStart=_vs.bottomPadding;
    _getBr().then((b)=>_startBrightness=b);
    VolumeController.instance.getVolume().then((v)=>_startSysVol=v);
  }

  void _onScaleUpdate(ScaleUpdateDetails d){
    if(_locked)return;
    if(d.pointerCount>=2){
      _mode=_GMode.zoom;
      setState((){_scale=(_baseScale*d.scale).clamp(0.05,8.0);_offset=_offset+d.focalPointDelta;});
      return;
    }
    final dx=d.localFocalPoint.dx-_startFocal.dx;
    final dy=d.localFocalPoint.dy-_startFocal.dy;
    if(_mode==_GMode.none){
      if(dx.abs()<8&&dy.abs()<8)return;
      if(_scale>1.05&&dx.abs()<dy.abs()*2){_mode=_GMode.pan;}
      else if(dx.abs()>dy.abs()){_mode=_GMode.seek;}
      else if(_startFocal.dx>_size.width/2){_mode=_GMode.brightness;}
      else{_mode=_GMode.volume;}
    }
    switch(_mode){
      case _GMode.pan:setState(()=>_offset=_baseOffset+(d.localFocalPoint-_startFocal));break;
      case _GMode.seek:
        // RTL: کشیدن به راست = عقب (منهای dx)
        _seekTargetMs=(_seekStartMs+((-dx/_size.width)*90000).round()).clamp(0,_duration.inMilliseconds);
        _showOverlay('${fmt(Duration(milliseconds:_seekTargetMs))} / ${fmt(_duration)}');break;
      case _GMode.brightness:
        final nb=(_startBrightness-dy/_size.height).clamp(0.0,1.0);
        _setBr(nb);_showOverlay('☀ ${(nb*100).round()}%');break;
      case _GMode.volume:
        final nv=(_startSysVol-dy/_size.height).clamp(0.0,1.0);
        VolumeController.instance.setVolume(nv);_showOverlay('🔊 ${(nv*100).round()}%');break;
      default:break;
    }
  }

  void _onScaleEnd(ScaleEndDetails d){
    if(_mode==_GMode.seek)player.seek(Duration(milliseconds:_seekTargetMs));
    _mode=_GMode.none;
  }

  void _toggleOrientation(){
    setState(()=>_landscape=!_landscape);
    if(_landscape){
      SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft,DeviceOrientation.landscapeRight]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }else{
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }
  void _cycleFit(){setState(()=>_fit=_fit==BoxFit.contain?BoxFit.cover:_fit==BoxFit.cover?BoxFit.fill:BoxFit.contain);_showOverlay(_fit==BoxFit.contain?'عادی':_fit==BoxFit.cover?'پر':'کشیده');}
  void _cycleRepeat(){setState(()=>_repeatMode=_repeatMode==_Repeat.none?_Repeat.all:_repeatMode==_Repeat.all?_Repeat.one:_Repeat.none);_showOverlay(_repeatMode==_Repeat.none?'تکرار: خاموش':_repeatMode==_Repeat.all?'تکرار: همه':'تکرار: یک');}
  void _cycleRotation(){setState(()=>_rotationDeg=(_rotationDeg+90)%360);_showOverlay('چرخش: ${_rotationDeg.toInt()}°');}

  @override
  Widget build(BuildContext context){
    // اندازه صفحه بدون حساب navigation bar
    final mq=MediaQuery.of(context);
    _size=mq.size;
    final navBottom=mq.viewPadding.bottom;
    final bkm=Store.bookmarked.contains(_curPath);
    final sub=_subText,sub2=_sub2Text;
    final align=TextAlign.values[_vs.textAlign.clamp(0,TextAlign.values.length-1)];

    return Scaffold(
      backgroundColor:Colors.black,
      body:Stack(children:[
        // ── ویدیو ──
        Positioned.fill(child:ClipRect(child:Transform(
          alignment:Alignment.center,
          transform:Matrix4.identity()..translate(_offset.dx,_offset.dy)..scale(_scale,_scale)..rotateZ(_rotationDeg*3.14159/180),
          child:RepaintBoundary(key:_videoKey,child:Video(
            controller:controller,controls:NoVideoControls,fit:_fit,
            // embedded→libmpv | external→renderer خودمون
            // هر دو می‌تونن همزمان روی صفحه باشن
            subtitleViewConfiguration:_embeddedSubEnabled
              ?SubtitleViewConfiguration(
                style:TextStyle(
                  fontSize:_vs.fontSize,color:Color(_vs.textColor),
                  fontWeight:_vs.bold?FontWeight.bold:FontWeight.normal,
                  fontFamily:_vs.fontFamily.isEmpty?null:_vs.fontFamily,
                  height:1.4,shadows:const[Shadow(color:Colors.black,blurRadius:8)],
                ),
                // بالاتر از progress bar + navigation bar
                padding:EdgeInsets.only(
                  bottom:navBottom+56, // بالای progress bar
                  left:16,right:16,
                ),
              )
              :const SubtitleViewConfiguration(
                style:TextStyle(fontSize:0,color:Colors.transparent),padding:EdgeInsets.zero,
              ),
          )),
        ))),

        // ── زیرنویس ۱ ──
        if(sub!=null)Positioned(
          left:12,right:12,
          bottom:_vs.bottomPadding+navBottom,
          child:Align(
            alignment:_vs.textAlign==1?Alignment.bottomRight:_vs.textAlign==0?Alignment.bottomLeft:Alignment.bottomCenter,
            child:Container(
              padding:const EdgeInsets.symmetric(horizontal:10,vertical:5),
              decoration:BoxDecoration(color:Color(_vs.bgColor).withOpacity(_vs.bgOpacity),borderRadius:BorderRadius.circular(5)),
              child:Text(sub,textAlign:align,style:TextStyle(
                fontFamily:_vs.fontFamily.isEmpty?null:_vs.fontFamily,
                fontSize:_vs.fontSize,color:Color(_vs.textColor),
                fontWeight:_vs.bold?FontWeight.bold:FontWeight.normal,height:1.4)),
            ),
          ),
        ),

        // ── زیرنویس ۲ ──
        if(sub2!=null)Positioned(
          left:12,right:12,
          bottom:_vs.bottomPadding+navBottom+_vs.fontSize*1.9+10,
          child:Align(alignment:Alignment.bottomCenter,child:Container(
            padding:const EdgeInsets.symmetric(horizontal:10,vertical:5),
            decoration:BoxDecoration(color:Colors.black.withOpacity(0.55),borderRadius:BorderRadius.circular(5)),
            child:Text(sub2,textAlign:TextAlign.center,style:TextStyle(
              fontFamily:_vs.fontFamily.isEmpty?null:_vs.fontFamily,
              fontSize:_vs.fontSize*0.9,color:_color2,fontWeight:FontWeight.bold,height:1.4)),
          )),
        ),


        // ── A-B indicator ──
        if(_repeatA!=null||_repeatB!=null)
          Positioned(top:0,left:0,right:0,child:LinearProgressIndicator(
            value:(_duration.inMilliseconds>0&&_repeatA!=null&&_repeatB!=null)
                ?(_repeatB!.inMilliseconds-_repeatA!.inMilliseconds)/_duration.inMilliseconds:0,
            backgroundColor:Colors.white12,color:Colors.orangeAccent.withOpacity(0.6),
          )),

        // ── حالت شب ──
        if(_vs.nightOpacity>0)Positioned.fill(child:IgnorePointer(
            child:Container(color:const Color(0xFFFF7700).withOpacity(_vs.nightOpacity*0.35)))),

        // ── لایه اشاره (بدون onLongPress — تداخل با drag) ──
        if(!_locked)Positioned.fill(child:GestureDetector(
          behavior:HitTestBehavior.opaque,
          onTap:_toggleControls,
          onDoubleTapDown:(d)=>_doubleTapPos=d.localPosition,
          onDoubleTap:_onDoubleTap,
          onScaleStart:_onScaleStart,
          onScaleUpdate:_onScaleUpdate,
          onScaleEnd:_onScaleEnd,
          onLongPressStart:(d){
            final x=d.localPosition.dx;
            // RTL: راست = عقب، چپ = جلو
            if(x>_size.width*2/3)_startFastSeek(false);  // راست → عقب
            else if(x<_size.width/3)_startFastSeek(true); // چپ → جلو
          },
          onLongPressMoveUpdate:(d){
            if(_fastSeeking)_adjustFastSeekSpeed(d.offsetFromOrigin.dy);
          },
          onLongPressEnd:(_)=>_stopFastSeek(),
          onLongPressCancel:()=>_stopFastSeek(),
          child:const SizedBox.expand(),
        )),

        // ── سربرگ زیرنویس: فقط وقتی متن زیرنویس روی صفحه هست ──
        // شامل: دکمه کپی + drag handle برای جابجایی
        // بالای متن قرار می‌گیره تا روی متن نیاد
        if(sub!=null&&!_locked&&_vs.showSubToolbar)
          Positioned(
            right:8,
            bottom:_vs.bottomPadding+navBottom+_vs.fontSize*1.8+10,
            child:Row(mainAxisSize:MainAxisSize.min,children:[
              GestureDetector(
                onTap:_copySubText,
                child:_subSmallBtn(Icons.copy_all_rounded,'کپی'),
              ),
              const SizedBox(width:5),
              Listener(
                behavior:HitTestBehavior.opaque,
                onPointerDown:(_){_subPaddingStart=_vs.bottomPadding;},
                onPointerMove:(e)=>setState(()=>
                  _vs.bottomPadding=(_vs.bottomPadding-e.delta.dy).clamp(0.0,_size.height*0.85)),
                child:_subSmallBtn(Icons.drag_indicator,'جابجا کن'),
              ),
            ]),
          ),


        // ── thumbnail preview روی اسلایدر ──

        // ── نمایش timestamp هنگام کشیدن اسلایدر ──
        if(_seekDragging)
          Positioned(
            left:0,right:0,
            bottom:navBottom+52,
            child:Center(child:Container(
              padding:const EdgeInsets.symmetric(horizontal:16,vertical:8),
              decoration:BoxDecoration(
                color:Colors.black.withOpacity(0.75),
                borderRadius:BorderRadius.circular(8),
                border:Border.all(color:Colors.white24,width:1),
              ),
              child:Text(
                fmt(Duration(milliseconds:_seekDragMs.round())),
                style:const TextStyle(fontSize:16,fontWeight:FontWeight.bold,color:Colors.white),
              ),
            )),
          ),

        // ── نوار fast seek ──
        if(_fastSeeking)
          Positioned(
            left:_fastSeekRight?null:8,
            right:_fastSeekRight?8:null,
            top:_size.height*0.15,
            bottom:_size.height*0.15,
            width:52,
            child:Container(
              decoration:BoxDecoration(color:Colors.black.withOpacity(0.7),borderRadius:BorderRadius.circular(26)),
              padding:const EdgeInsets.symmetric(vertical:12,horizontal:6),
              child:Column(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[
                Icon(_fastSeekRight?Icons.fast_rewind:Icons.fast_forward,color:Colors.orange,size:20),
                // نوار سرعت (بکش بالا/پایین روی ویدیو تغییر می‌کنه)
                Expanded(child:Container(
                  margin:const EdgeInsets.symmetric(vertical:8,horizontal:8),
                  decoration:BoxDecoration(color:Colors.white12,borderRadius:BorderRadius.circular(4)),
                  child:Align(alignment:Alignment.bottomCenter,child:FractionallySizedBox(
                    heightFactor:((_fastSeekSpeed-1)/19).clamp(0.0,1.0),
                    child:Container(decoration:BoxDecoration(color:Colors.orange,borderRadius:BorderRadius.circular(4))),
                  )),
                )),
                Text('${_fastSeekSpeed.toStringAsFixed(1)}x',style:const TextStyle(fontSize:11,color:Colors.white,fontWeight:FontWeight.bold)),
              ]),
            ),
          ),

        // ── پیام وسط ──
        if(_overlay!=null)Center(child:Container(
          padding:const EdgeInsets.symmetric(horizontal:20,vertical:10),
          decoration:BoxDecoration(color:Colors.black.withOpacity(0.65),borderRadius:BorderRadius.circular(10)),
          child:Text(_overlay!,style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
        )),

        if(_controlsVisible&&!_locked)_buildControls(bkm,navBottom),

        if(_locked)Positioned(top:16,left:16,child:SafeArea(child:FloatingActionButton.small(
          backgroundColor:Colors.black54,onPressed:()=>setState(()=>_locked=false),child:const Icon(Icons.lock),
        ))),
      ]),
    );
  }

  Widget _buildControls(bool bkm,double navBottom){
    return Column(children:[
      // ── نوار بالا با SafeArea ──
      SafeArea(bottom:false,child:Container(
        decoration:const BoxDecoration(gradient:LinearGradient(
          begin:Alignment.topCenter,end:Alignment.bottomCenter,colors:[Colors.black54,Colors.transparent])),
        child:Row(children:[
          IconButton(icon:const Icon(Icons.arrow_back),onPressed:()=>Navigator.pop(context)),
          Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisSize:MainAxisSize.min,children:[
              Text(p.basename(_curPath),maxLines:1,overflow:TextOverflow.ellipsis,
                  style:const TextStyle(fontSize:13,fontWeight:FontWeight.w500)),
              if(_isHDR||_resStr.isNotEmpty||_fpsStr.isNotEmpty)
                Row(children:[
                  if(_isHDR)_infoBadge('HDR',const Color(0xFFEC4899)),
                  if(_resStr.isNotEmpty)...[const SizedBox(width:4),_infoBadge(_resStr,const Color(0xFF0EA5E9))],
                  if(_fpsStr.isNotEmpty)...[const SizedBox(width:4),_infoBadge(_fpsStr,const Color(0xFF7C3AED))],
                ]),
            ])),
          if(_sleepAt!=null)GestureDetector(onTap:_showSleepDialog,child:Padding(
              padding:const EdgeInsets.symmetric(horizontal:4),
              child:Row(mainAxisSize:MainAxisSize.min,children:[
                const Icon(Icons.bedtime,size:16,color:Colors.orange),const SizedBox(width:2),
                Text('${_sleepAt!.difference(DateTime.now()).inMinutes}م',style:const TextStyle(color:Colors.orange,fontSize:12)),
              ]))),
          IconButton(icon:Icon(bkm?Icons.bookmark:Icons.bookmark_border,color:bkm?Colors.amber:Colors.white),
              onPressed:()async{await Store.toggleBookmark(_curPath);setState((){});}),
          IconButton(icon:Icon(Store.favorited.contains(_curPath)?Icons.favorite:Icons.favorite_border,
              color:Store.favorited.contains(_curPath)?Colors.redAccent:Colors.white),
              onPressed:()async{await Store.toggleFavorite(_curPath);setState((){});}),
          // badge تراک زیرنویس داخلی — اگه موجود باشه نشون میده
          if(_subtitleTracks.isNotEmpty||_embeddedSubEnabled)
            GestureDetector(
              onTap:_showEmbeddedSubPicker,
              child:Container(
                margin:const EdgeInsets.symmetric(horizontal:2,vertical:10),
                padding:const EdgeInsets.symmetric(horizontal:8,vertical:4),
                decoration:BoxDecoration(
                  color:_embeddedSubEnabled?const Color(0xFF7C3AED):const Color(0xFF7C3AED).withOpacity(0.15),
                  borderRadius:BorderRadius.circular(6),
                  border:Border.all(color:const Color(0xFF7C3AED).withOpacity(_embeddedSubEnabled?0:0.4)),
                ),
                child:Row(mainAxisSize:MainAxisSize.min,children:[
                  Icon(Icons.subtitles_outlined,size:12,
                      color:_embeddedSubEnabled?Colors.white:const Color(0xFF7C3AED)),
                  const SizedBox(width:3),
                  Text('${_subtitleTracks.length} داخلی',
                      style:TextStyle(fontSize:10,fontWeight:FontWeight.w600,
                          color:_embeddedSubEnabled?Colors.white:const Color(0xFF7C3AED))),
                ]),
              ),
            ),
          IconButton(icon:const Icon(Icons.subtitles),onPressed:()=>showModalBottomSheet(
            context:context,isScrollControlled:true,backgroundColor:const Color(0xFF1C1C22),
            shape:const RoundedRectangleBorder(borderRadius:BorderRadius.vertical(top:Radius.circular(20))),
            builder:(ctx)=>PlayerSettings(
              vs:_vs,onChanged:(vs){setState(()=>_vs=vs);},
              sub1Visible:_sub1Visible,onSub1Visible:(v)=>setState(()=>_sub1Visible=v),
              sub2Visible:_sub2Visible,onSub2Visible:(v)=>setState(()=>_sub2Visible=v),
              sub2Path:_sub2Path,
              subDelayMs:_subDelayMs,onSubDelayMs:(v)=>setState(()=>_subDelayMs=v),
              subDelay2Ms:_subDelay2Ms,onSubDelay2Ms:(v)=>setState(()=>_subDelay2Ms=v),
              audioDelayMs:_audioDelayMs,onAudioDelayMs:(v)=>setState(()=>_audioDelayMs=v),
              color2:_color2,onColor2:(c)=>setState(()=>_color2=c),
              onPickSub1:()=>_pickSub(secondary:false),onPickSub2:()=>_pickSub(secondary:true),
              onPickFont:_pickFont,
              speed:_vs.speed,onSpeed:(s){setState(()=>_vs.speed=s);player.setRate(s);},
              ampVolume:_currentAmpVolume,onAmpVolume:(v){setState(()=>_currentAmpVolume=v);player.setVolume(v);},
              onSaveForVideo:_saveVsForVideo,
              hwDecode:_hwDecode,onHwDecode:(v)=>setState(()=>_hwDecode=v),
              embeddedSubEnabled:_embeddedSubEnabled,
              onEmbeddedSubEnabled:(v){setState(()=>_embeddedSubEnabled=v);
                if(v&&_subtitleTracks.isNotEmpty)player.setSubtitleTrack(_subtitleTracks.first);},
              videoWidth:_videoWidth,videoHeight:_videoHeight,
            ),
          )),
          IconButton(icon:Icon(_landscape?Icons.stay_current_portrait:Icons.screen_rotation),onPressed:_toggleOrientation),
          PopupMenuButton<String>(icon:const Icon(Icons.more_vert),
            onSelected:(v){
              switch(v){
                case 'fit':_cycleFit();break;case 'rotate':_cycleRotation();break;
                case 'repeat':_cycleRepeat();break;
                case 'night':setState(()=>_vs.nightOpacity=_vs.nightOpacity>0?0:0.6);break;
                case 'lock':setState((){_locked=true;_controlsVisible=false;});break;
                case 'mute':if(_muted){player.setVolume(_savedVol);setState(()=>_muted=false);}
                    else{_savedVol=player.state.volume;player.setVolume(0);setState(()=>_muted=true);}break;
                case 'embsub':_showEmbeddedSubPicker();break;
                case 'audio':_showAudioPicker();break;
                case 'sleep':_showSleepDialog();break;
                case 'screenshot':_takeScreenshot();break;
                case 'copy':_copySubText();break;
                case 'info':_showVideoInfo();break;
              }
            },
            itemBuilder:(_)=>[
              PopupMenuItem(value:'fit',child:Text('اندازه: ${_fit==BoxFit.contain?"عادی":_fit==BoxFit.cover?"پر":"کشیده"}')),
              PopupMenuItem(value:'rotate',child:Text('چرخش: ${_rotationDeg.toInt()}°')),
              PopupMenuItem(value:'repeat',child:Text('تکرار: ${_repeatMode==_Repeat.none?"خاموش":_repeatMode==_Repeat.all?"همه":"یک"}')),
              PopupMenuItem(value:'night',child:Text(_vs.nightOpacity>0?'خاموش حالت شب':'حالت شب')),
              PopupMenuItem(value:'mute',child:Text(_muted?'لغو بی‌صدا':'بی‌صدا')),
              const PopupMenuItem(value:'embsub',child:Text('زیرنویس داخلی (Softsub)')),
              const PopupMenuItem(value:'audio',child:Text('تراک صوتی')),
              const PopupMenuItem(value:'sleep',child:Text('تایمر خواب')),
              const PopupMenuItem(value:'screenshot',child:Text('اسکرین‌شات')),
              const PopupMenuItem(value:'copy',child:Text('کپی زیرنویس')),
              const PopupMenuItem(value:'info',child:Text('اطلاعات ویدیو')),
              const PopupMenuItem(value:'lock',child:Text('قفل صفحه')),
            ],
          ),
        ]),
      )),

      // ── وسط ──
      Expanded(child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[
        _abRow(),const SizedBox(height:8),
        Row(mainAxisAlignment:MainAxisAlignment.center,children:[
          IconButton(iconSize:44,icon:Icon(Icons.skip_previous,color:_hasPrev?Colors.white:Colors.white24),onPressed:_hasPrev?()=>_switchVideo(_idx-1):null),
          const SizedBox(width:24),
          IconButton(iconSize:68,icon:Icon(_playing?Icons.pause_circle_filled:Icons.play_circle_filled),
              onPressed:(){_playing?player.pause():player.play();_startHideTimer();}),
          const SizedBox(width:24),
          IconButton(iconSize:44,icon:Icon(Icons.skip_next,color:_hasNext?Colors.white:Colors.white24),onPressed:_hasNext?()=>_switchVideo(_idx+1):null),
        ]),
      ])),

      // ── نوار پایین با SafeArea کامل ──
      Container(
        decoration:const BoxDecoration(gradient:LinearGradient(
          begin:Alignment.bottomCenter,end:Alignment.topCenter,colors:[Colors.black54,Colors.transparent])),
        padding:EdgeInsets.fromLTRB(12,0,12,navBottom+4),
        child:Row(children:[
          Text(fmt(_seekDragging?Duration(milliseconds:_seekDragMs.round()):_position),style:const TextStyle(fontSize:12)),
          Expanded(child:SliderTheme(
            data:SliderTheme.of(context).copyWith(
              activeTrackColor:const Color(0xFF7C3AED),
              inactiveTrackColor:Colors.white.withOpacity(0.12),
              thumbColor:Colors.white,
              thumbShape:const RoundSliderThumbShape(enabledThumbRadius:5,elevation:0),
              overlayShape:SliderComponentShape.noOverlay,
              trackHeight:2.5,
            ),
            child:Slider(
            min:0,
            max:_duration.inMilliseconds<=0?1.0:_duration.inMilliseconds.toDouble(),
            value:(_seekDragging?_seekDragMs:_position.inMilliseconds.toDouble())
                .clamp(0,_duration.inMilliseconds<=0?0:_duration.inMilliseconds.toDouble()),
            onChangeStart:(v){
              setState((){_seekDragging=true;_seekDragMs=v;});
            },
            onChanged:(v){
              setState(()=>_seekDragMs=v);
            },
            onChangeEnd:(v){
              player.seek(Duration(milliseconds:v.round()));
              _thumbTimer?.cancel();
              setState((){_seekDragging=false;});
              _startHideTimer();
            },
          ))),  // SliderTheme
          Text(fmt(_duration),style:const TextStyle(fontSize:12)),
        ]),
      ),
    ]);
  }

  Widget _abRow()=>Row(mainAxisSize:MainAxisSize.min,children:[
    _abBtn('A',_repeatA,(){setState((){_repeatA=_position;});_showOverlay('A: ${fmt(_position)}');}),
    const SizedBox(width:8),
    _abBtn('B',_repeatB,(){if(_repeatA==null)return;setState((){_repeatB=_position;_abActive=true;});_showOverlay('B: ${fmt(_position)}');}),
    if(_repeatA!=null||_repeatB!=null)...[
      const SizedBox(width:8),
      GestureDetector(onTap:(){setState((){_repeatA=null;_repeatB=null;_abActive=false;});_showOverlay('A-B پاک شد');},
          child:Container(padding:const EdgeInsets.symmetric(horizontal:8,vertical:4),
              decoration:BoxDecoration(color:Colors.red.withOpacity(0.7),borderRadius:BorderRadius.circular(6)),
              child:const Icon(Icons.clear,size:16))),
    ],
  ]);

  Widget _abBtn(String label,Duration? val,VoidCallback onTap)=>GestureDetector(
    onTap:onTap,
    child:Container(padding:const EdgeInsets.symmetric(horizontal:10,vertical:4),
      decoration:BoxDecoration(color:val!=null?Colors.orangeAccent:Colors.white24,borderRadius:BorderRadius.circular(6)),
      child:Text(val!=null?'$label: ${fmt(val)}':label,style:const TextStyle(fontSize:12,fontWeight:FontWeight.bold)),
    ),
  );
}

