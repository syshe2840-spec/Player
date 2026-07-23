// lib/player.dart — پلیر ویدیو
import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:media_kit/src/player/native/player/real.dart';
import 'package:file_picker/file_picker.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';
import 'store.dart';
import 'vez_service.dart';
import 'ai_subtitle_sheet.dart';
import 'opensubtitles_search_sheet.dart';
import 'live_sub_sheet.dart';
import 'srt_translate_sheet.dart';
import 'srt_translation_service.dart' show SrtTranslationService, SrtTranslationServiceStatus, kTranslateLangDisplay;
import 'lyrics_sheet.dart';
import 'live_translation_sync.dart';
import 'subtitle_storage.dart';
import 'whisper_service.dart';
import 'settings.dart';
import 'main.dart' show showSnack;
import 'l10n.dart';
import 'deepgram_service.dart';
import 'vosk_service.dart';
import 'android_stt_service.dart';
import 'srt_editor_screen.dart';
import 'package:permission_handler/permission_handler.dart' as permission_handler;

enum _GMode{none,seek,brightness,volume,zoom,pan,subtitlePos}
enum _Repeat{none,one,all}

class PlayerScreen extends StatefulWidget {
  final String? subtitlePath;
  final List<File> playlist;
  final int playlistIndex;
  final bool isOnlineUrl; // آدرس آنلاین (نه فایل محلی)
  final bool isLive; // پخش زنده IPTV
  const PlayerScreen({super.key,this.subtitlePath,required this.playlist,required this.playlistIndex,this.isOnlineUrl=false,this.isLive=false});
  @override State<PlayerScreen> createState()=>_PlayerState();
}

class _PlayerState extends State<PlayerScreen>{
  late final Player player=Player();
  late final VideoController controller=VideoController(player);
  late int _idx;

  Duration _position=Duration.zero,_duration=Duration.zero;
  bool _playing=true;
  bool _buffering=false;
  String _bufferStatus='';
  DateTime? _bufferStart;
  List<String> _liveLog=[];
  bool _showLiveLog=true;
  bool _dgActive=false;
  String _dgText='';
  String _dgConfirmed=''; // متن تأیید شده (final)
  String _dgPartial='';  // متن در حال تشخیص (partial)
  String _dgLang='fa';
  StreamSubscription? _dgSub;
  List<String> _aiLog=[];
  bool _useVosk = true;
  bool _useAndroidStt = false;
  String? _title; // عنوان ویدیوی جاری
  Timer? _voskPollTimer;
  Timer? _androidSttPollTimer;
  bool _mounted = true; // safe async flag
  // ── ذخیره SRT زنده ──
  List<_SrtEntry> _voskSrtEntries = [];
  DateTime? _voskStartTime;
  DateTime? _lastFinalTime;
  bool _voskTranslate = false;
  String _voskTranslateTo = 'fa';
  int _voskPollMs = 100;

  // زبان‌هایی که partial رو Latin برمیگردونن — فقط final نشون بده

  static const _langNames = {
    'fa':'Persian','en':'English','ar':'Arabic','zh':'Chinese','ru':'Russian',
    'es':'Spanish','fr':'French','de':'German','tr':'Turkish','hi':'Hindi',
    'ja':'Japanese','ko':'Korean','it':'Italian','pt':'Portuguese','nl':'Dutch',
    'pl':'Polish','uk':'Ukrainian','sv':'Swedish','da':'Danish','fi':'Finnish',
    'no':'Norwegian','cs':'Czech','ro':'Romanian','hu':'Hungarian','el':'Greek',
    'bg':'Bulgarian','hr':'Croatian','sk':'Slovak','lt':'Lithuanian','lv':'Latvian',
    'sl':'Slovenian','et':'Estonian','sr':'Serbian','he':'Hebrew','ur':'Urdu',
    'sw':'Swahili','th':'Thai','vi':'Vietnamese','id':'Indonesian','ms':'Malay',
    'tl':'Filipino','km':'Khmer','bn':'Bengali','ta':'Tamil','te':'Telugu',
    'ka':'Georgian','hy':'Armenian','az':'Azerbaijani','kk':'Kazakh','uz':'Uzbek',
    'mn':'Mongolian','my':'Burmese','si':'Sinhala','ne':'Nepali','am':'Amharic',
    'so':'Somali','ha':'Hausa','yo':'Yoruba','ht':'Haitian Creole','mi':'Maori',
    'cy':'Welsh','ga':'Irish','eu':'Basque','ca':'Catalan','la':'Latin',
    'eo':'Esperanto','yi':'Yiddish','ps':'Pashto','ku':'Kurdish','lo':'Lao',
    'zh-cn':'Chinese Simplified','zh-tw':'Chinese Traditional',
  };
  static const _nonLatinLangs = {'fa','ar','zh','ja','ko','ru','uk','hi','he','el','ka','am','bn','gu','kn','ml','mr','ne','pa','si','ta','te','ur','ky','kk','tg','mn','my','km','lo','th'};
  bool get _voskFinalOnly => _nonLatinLangs.contains(_dgLang);
  bool _isFullscreen=false;
  final List<StreamSubscription> _subs=[];

  // زیرنویس
  List<SubEntry> _sub1=[];
  List<SubEntry> _sub2=[];
  bool _sub1Visible=true,_sub2Visible=false;
  String? _sub1Path; // مسیر زیرنویس اصلی فعال (برای ترجمه)
  String? _sub2Path;
  List<AudioTrack> _audioTracks=[];
  List<SubtitleTrack> _subtitleTracks=[];
  // soft-sub embedded در ویدیو
  bool _embeddedSubEnabled=false; // خودکار فعال می‌شه

  // تنظیمات قابل ذخیره
  late VideoSettings _vs=VideoSettings();
  late VideoSettings _vs2=VideoSettings(fontSize:26,bold:false,textColor:0xFFFFFF99,bgOpacity:0.4,bottomPadding:90);
  int _subDelayMs=0,_subDelay2Ms=0,_audioDelayMs=0;
  Color _color2=const Color(0xFFFFEB3B);

  // پخش
  BoxFit _fit=BoxFit.contain;
  bool _landscape=false;
  _Repeat _repeatMode=_Repeat.none;
  bool _muted=false,_hwDecode=true;
  double _currentAmpVolume=100.0;
  // ── PiP + Notification ──
  static const _pipCh=MethodChannel('ir.subteam.subtitle_player/pip');
  static const _thumbCh=MethodChannel('ir.subteam.subtitle_player/thumbnail');
  bool _inPipMode=false;
  String? _vezTempPath; // مسیر temp فایل رمزگشایی‌شده
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
  String? _embeddedSubText; // متن embedded از stream
  double _seekDragMs=0;
  int _seekSession=0; // هر drag جدید → session جدید
  Uint8List? _seekThumbData;
  Timer? _seekThumbTimer;
  // Fast seek (long press)
  bool _fastSeeking=false;
  bool _fastSeekRight=false;
  double _fastSeekSpeed=3.0; // ثانیه در ثانیه
  double _fastSeekBaseSpeed=3.0;
  Timer? _fastSeekTimer;
  bool _fastSeekLocked=false;
  double _fastSeekDragStartY=0;

  // ── زیرنویس زنده ──
  bool _liveSubActive=false;
  LiveTranslationSync? _liveTransSync; // همگام‌سازی ترجمه با زیرنویس زنده
  // ── ترجمه پس‌زمینه ──
  bool _translating=false;
  String _translatingLang='';
  String _translatingStatus='';
  String? _translatingPartialPath;
  String? _liveSubSrtPath;
  Timer? _liveSubRefreshTimer;
  Timer? _liveSubSecondTimer;
  final _liveStopwatch = Stopwatch(); // کل زمان از شروع زیرنویس زنده
  int _liveChunkEstSec = 30;
  int _liveTotalEstSec = 0;
  bool _liveSubPaused=false;
  bool _liveBadgeVisible=true; // دکمه 👁 مخفی/نمایش badge
  LiveBehindAction _liveBehindAction=LiveBehindAction.pause;
  double _liveBehindSpeed=0.75;
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

  String get _curPath => widget.isOnlineUrl
    ? widget.playlist[_idx].path  // برای URL، path = خود URL
    : widget.playlist[_idx].path;
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
      // موقع درگ اسلایدر setState نزن — مانع jump اسلایدر
      if(mounted&&!_seekDragging)setState((){});
    }));
    _subs.add(player.stream.duration.listen((d){
      _duration=d;
      if(d.inSeconds>0)Store.saveDur(_curPath,d.inSeconds);
      if(mounted&&!_seekDragging)setState((){});
    }));
    _subs.add(player.stream.playing.listen((pl){
      if(widget.isLive&&pl)_addLiveLog('▶ Playback started!');
      _playing=pl;
      if(mounted){if(!_seekDragging)setState((){});_notifUpdate();}
    }));
    // embedded subtitle text از libmpv stream
    _subs.add(player.stream.subtitle.listen((lines){
      if(!mounted||!_embeddedSubEnabled)return;
      final text=lines.where((s)=>s.trim().isNotEmpty).join('\n').trim();
      if(!_seekDragging)setState(()=>_embeddedSubText=text.isEmpty?null:text);
    }));

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

    _subs.add(player.stream.width.listen((w){if(mounted&&w!=null&&!_seekDragging)setState(()=>_videoWidth=w);}));
    _subs.add(player.stream.height.listen((h){if(mounted&&h!=null&&!_seekDragging)setState(()=>_videoHeight=h);}));
    _subs.add(player.stream.videoParams.listen((vp){if(mounted)setState((){_videoParams=vp;if(widget.isLive&&vp.pixelformat!=null)_addLiveLog('Video: ${vp.pixelformat} ${_videoWidth??0}x${_videoHeight??0}');});}));
    _subs.add(player.stream.buffering.listen((buf){
      if(mounted) setState((){
        _buffering=buf;
        if(buf){
          _bufferStart??=DateTime.now();
          _bufferStatus='Buffering...';
          _addLiveLog('Buffering...');
        } else {
          final elapsed=_bufferStart!=null?DateTime.now().difference(_bufferStart!).inSeconds:0;
          _bufferStart=null;
          _bufferStatus='';
          _addLiveLog('Buffer done (${elapsed}s) — playing');
        }
      });
    }));
    // ── MPV error stream ──
    _subs.add(player.stream.error.listen((err){
      if(err.isNotEmpty)_addLiveLog('⚠ Error: $err');
    }));
    // ── MPV native log stream ──
    if(widget.isLive){
      _subs.add(player.stream.log.listen((log){
        if(log.level=='error'||log.level=='warn'||log.level=='fatal')
          _addLiveLog('[${log.level}] ${log.prefix}: ${log.text}');
      }));
    }

    // ── position change — detect stall ──
    if(widget.isLive){
      Duration _lastPos=Duration.zero;
      int _stallCount=0;
      _subs.add(Stream.periodic(const Duration(seconds:2)).listen((_){
        if(!mounted||!_buffering)return;
        if(_position==_lastPos&&_position>Duration.zero){
          _stallCount++;
          _addLiveLog('⏸ Stalled ${_stallCount*2}s at ${_position.inSeconds}s');
        } else if(_position!=_lastPos){
          _stallCount=0;
          _addLiveLog('▶ Position: ${_position.inSeconds}s (live)');
        }
        _lastPos=_position;
      }));

      // log هر ۵ ثانیه وضعیت
      _subs.add(Stream.periodic(const Duration(seconds:5)).take(20).listen((_){
        if(!mounted)return;
        final native=player.platform as NativePlayer;
        _addLiveLog('📊 buffering=$_buffering pos=${_position.inSeconds}s w=${_videoWidth??0}x${_videoHeight??0}');
      }));
    }

    _subs.add(player.stream.completed.listen((done){
      if(!done)return;
      switch(_repeatMode){
        case _Repeat.one:player.seek(Duration.zero);player.play();break;
        case _Repeat.all:_switchVideo((_idx+1)%widget.playlist.length);break;
        case _Repeat.none:if(_hasNext)_switchVideo(_idx+1);break;
      }
    }));
    _start(); _startHideTimer();
    _initPipChannel();
  }

  Future<void> _start()async{
    // اگه فایل .vez هست رمزگشایی کن
    if(VezService.isVez(_curPath)){
      WidgetsBinding.instance.addPostFrameCallback((_)=>_playVez(_curPath));
      return;
    }
    // آنلاین stream options — سرعت بیشتر
    final isOnline = widget.isLive || widget.isOnlineUrl || 
      _curPath.startsWith('http') || _curPath.startsWith('rtmp') || _curPath.startsWith('rtsp');
    if(isOnline){
      final native=player.platform as NativePlayer;
      try{
        native.setProperty('cache','no');
        native.setProperty('cache-pause','no');
        native.setProperty('stream-lavf-o','timeout=10000000');
        native.setProperty('demuxer-readahead-secs','3');
        if(widget.isLive){
          native.setProperty('demuxer-lavf-o','fflags=nobuffer,http_persistent=1,reconnect=1,reconnect_at_eof=1,reconnect_streamed=1,reconnect_on_network_error=1');
          native.setProperty('http-header-fields','User-Agent: TiviMate/4.7.0 (Linux;Android 13) ExoPlayerLib/2.18.1');
          native.setProperty('tls-verify','no');
        }
      }catch(_){}
    }
    if(widget.isLive||widget.isOnlineUrl||_curPath.startsWith('http'))
      setState(()=>_buffering=true);
    if(widget.isLive){_addLiveLog('Opening stream...');_addLiveLog('URL: ${_curPath.substring(0,_curPath.length.clamp(0,60))}...');}
    final isHttp = _curPath.startsWith('http');
    final media = isHttp
      ? Media(_curPath, httpHeaders: {
          'User-Agent': 'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/112.0.0.0 Mobile Safari/537.36',
          'Connection': 'keep-alive',
          'Accept': '*/*',
        })
      : Media(_curPath);

    await player.open(media);
    if(widget.isLive)_addLiveLog('Stream opened — waiting for data...');
    await Store.addToHistory(_curPath);
    final saved=await Store.getPos(_curPath);
    if(saved.inSeconds>5&&mounted){
      final resume=await showDialog<bool>(
        context:context,barrierDismissible:false,
        builder:(ctx)=>AlertDialog(backgroundColor:const Color(0xFF1C1C22),title:Text(L.continuePlaying),
          content:Text('${L.resumeFrom} (${fmt(saved)})'),
          actions:[
            TextButton(onPressed:()=>Navigator.pop(ctx,false),child:Text(L.fromBeginning)),
            FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:Text(L.continue_)),
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
    if(widget.isLive||widget.isOnlineUrl||_curPath.startsWith('http'))
      setState(()=>_buffering=true);
    if(widget.isLive){_addLiveLog('Opening stream...');_addLiveLog('URL: ${_curPath.substring(0,_curPath.length.clamp(0,60))}...');}
    final isHttp = _curPath.startsWith('http');
    final media = isHttp
      ? Media(_curPath, httpHeaders: {
          'User-Agent': 'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/112.0.0.0 Mobile Safari/537.36',
          'Connection': 'keep-alive',
          'Accept': '*/*',
        })
      : Media(_curPath);

    await player.open(media);
    if(widget.isLive)_addLiveLog('Stream opened — waiting for data...');
    await Store.addToHistory(_curPath);
    final sv=await Store.getPos(_curPath);
    if(sv.inSeconds>5)await player.seek(sv);
    final sub=matchSubtitle(_curPath);
    if(sub!=null)await _loadSub(sub,secondary:false);
    if(_vs.speed!=1.0)player.setRate(_vs.speed);
  }

  Future<void> _saveVoskSrt({bool silent = false}) async {
    if (_voskSrtEntries.isEmpty) {
      if (silent && _mounted) setState((){_aiLog.add('[SRT] skip — no entries');});
      return;
    }

    // تولید نام فایل
    // تمیز کردن نام فایل از کاراکترهای غیرمجاز
    String _sanitize(String s) {
      return s.replaceAll(RegExp(r'[<>:"/\|?* -]'), '_')
              .replaceAll(RegExp(r'_{2,}'), '_')
              .substring(0, s.length.clamp(0, 60));
    }

    String baseName;
    final path = _curPath ?? '';
    if (path.isEmpty) {
      final now = DateTime.now();
      baseName = 'subtitle_${now.year}${now.month.toString().padLeft(2,"0")}_${now.day.toString().padLeft(2,"0")}_${now.hour.toString().padLeft(2,"0")}${now.minute.toString().padLeft(2,"0")}';
    } else if (path.contains('youtube') || path.contains('youtu.be')) {
      final title = path.split('/').last.split('?').first;
      baseName = '${title.isEmpty ? "youtube" : title}-youtube';
    } else if (path.contains('.m3u8') || path.contains('iptv') || widget.isLive) {
      final seg = path.split('/').lastWhere((s) => s.isNotEmpty, orElse: () => 'live');
      baseName = '${seg.split(".").first}-iptv';
    } else {
      // فایل معمولی
      final fname = path.split('/').last.split('?').first;
      baseName = _sanitize(fname.contains('.') ? fname.substring(0, fname.lastIndexOf('.')) : fname);
    }

    // اضافه کردن زبان ترجمه
    if (_voskTranslate && _voskTranslateTo.isNotEmpty) {
      baseName += '-translated-to-$_voskTranslateTo';
    }

    // ذخیره فایل
    final srtContent = _voskSrtEntries.map((e) => e.toSrt()).join('\n');
    String? savedPath;
    try {
      final dir = Directory('/storage/emulated/0/Download/Vezoo/Subtitles');
      await dir.create(recursive: true);
      final file = File('${dir.path}/$baseName.srt');
      await file.writeAsString(srtContent, flush: true);
      savedPath = file.path;
      if (_mounted) setState((){_aiLog.add('[SRT] ✅ saved: $baseName.srt (${_voskSrtEntries.length} lines)');});

    } catch (e) {
      return;
    }
    if (!silent && _mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('✅ زیرنویس ذخیره شد: $baseName.srt'),
      backgroundColor: const Color(0xFF7C3AED),
      duration: const Duration(seconds: 4),
      action: SnackBarAction(label: 'بارگذاری روی ویدیو', textColor: Colors.white,
        onPressed: () async {
          await _loadSub(savedPath!, secondary: false);
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text('✅ زیرنویس بارگذاری شد'),
            backgroundColor: Colors.green, duration: const Duration(seconds: 2),
            action: SnackBarAction(label: 'ویرایش', textColor: Colors.white,
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) =>
                SrtEditorScreen(srtPath: savedPath!))))));
        }),
    ));
  }

  Future<String> _translateWithWorker(String text, String targetLang) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 15);
      final req = await client.postUrl(Uri.parse('https://player.lastofanarchy.workers.dev/translate-srt'));
      req.headers.set('Content-Type', 'application/json');
      final langName = _langNames[targetLang] ?? targetLang;
      final body2 = jsonEncode({'lines': [text], 'target_lang': langName});
      req.write(body2);
      final res = await req.close();
      final body = await res.transform(const Utf8Decoder()).join();
      if (!_mounted) return text;
      setState((){_aiLog.add('[translate] resp: ${body.substring(0, body.length.clamp(0,80))}');});
      final json = jsonDecode(body);
      return (json['lines'] as List?)?.first?.toString() ?? text;
    } catch (e) {
      if (_mounted) setState((){_aiLog.add('[TRANS] ❌ ${e.toString().substring(0, e.toString().length.clamp(0,100))}');});
      return text;
    }
  }

  void _toggleDeeepgram()async{
    if(_dgActive){
      await DeepgramService.stop();
      _dgSub?.cancel();
      setState((){_dgActive=false;_dgText='';});
    } else {
      // انتخاب زبان + تنظیمات ترجمه
      final result=await showDialog<Map<String,dynamic>>(context:context,builder:(ctx)=>_VoskSettingsDialog());
      if(result==null)return;
      final lang=result['lang'] as String;
      _voskTranslate=result['translate'] as bool;
      _voskTranslateTo=result['translateTo'] as String;
      _voskPollMs=result['pollMs'] as int;
      final modelId=result['modelId'] as String?;
      final engine=result['engine'] as String? ?? 'vosk';
      _useAndroidStt = engine == 'android';
      _useVosk = engine == 'vosk';
      // درخواست permission میکروفون
      final micStatus = await permission_handler.Permission.microphone.request();
      if (!micStatus.isGranted) {
        setState((){_dgActive=false;});
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('❌ دسترسی میکروفون لازمه'),
          backgroundColor: Colors.red, duration: Duration(seconds: 3)));
        return;
      }
      setState((){_dgActive=true;_dgLang=lang;_dgText='⏳ Connecting...';});
      _dgSub=DeepgramService.events().listen((e){
        final type=e['type'] as String;
        final data=e['data'];
        final ts=DateTime.now();
        final tsStr='${ts.hour.toString().padLeft(2,'0')}:${ts.minute.toString().padLeft(2,'0')}:${ts.second.toString().padLeft(2,'0')}';
        if(type=='transcript'){
          final t=(data as Map)['text'] as String;
          final isFinal=(data)['final'] as bool;
          _aiLog.add('[$tsStr] 📝 "$t" final=$isFinal');
          if(t.isNotEmpty&&mounted){
            setState((){
              _dgText=isFinal?t:'$t...';
              if(_aiLog.length>30)_aiLog.removeAt(0);
            });
          }
        } else if(type=='status'){
          if(mounted)setState((){
            // status فقط به log میره، _dgText رو عوض نمیکنه
            _aiLog.add('[$tsStr] 🔗 $data');
            if(_aiLog.length>30)_aiLog.removeAt(0);
          });
        } else if(type=='error'){
          if(mounted)setState((){
            _dgActive=false;_dgText='';
            _aiLog.add('[$tsStr] ❌ error: $data');
          });
        } else {
          if(mounted)setState((){_aiLog.add('[$tsStr] ℹ $type: $data');});
        }
      });
      if(mounted)setState((){_aiLog.add('[${DateTime.now().hour}:${DateTime.now().minute}:${DateTime.now().second}] 🚀 Starting AI subtitle...');});
      if (_useVosk) {
        // Vosk — آفلاین + MediaProjection
        final effectiveLang = lang == 'multi' ? 'en' : lang;
        if (!VoskService.hasAnyModelForLang(effectiveLang)) {
          setState((){_dgActive=false;});
          if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:Text('هیچ مدلی برای این زبان دانلود نشده — به Settings > Vosk Models برو'),
            backgroundColor:Colors.orange, duration:const Duration(seconds:4)));
          return;
        }
        _dgSub=VoskService.events().listen((e){
          final type=e['type'] as String;
          final data=e['data'];
          final ts=DateTime.now();
          final tsStr="${ts.hour.toString().padLeft(2,'0')}:${ts.minute.toString().padLeft(2,'0')}:${ts.second.toString().padLeft(2,'0')}";
          if(type=='transcript'){
            final t=(data as Map)['text'] as String;
            final isFinal=(data as Map)['final'] as bool;
            if(t.isNotEmpty){
              if(isFinal){
                // SRT
                if (_voskStartTime != null) {
                  final now=DateTime.now();
                  final el=now.difference(_voskStartTime!);
                  _voskSrtEntries.add(_SrtEntry(_voskSrtEntries.length+1,el-const Duration(seconds:2),el,t));
                  _saveVoskSrt(silent:true);
                }
                // ترجمه
                if(_voskTranslate && _voskTranslateTo.isNotEmpty){
                  setState((){_aiLog.add('[TRANS] → $_voskTranslateTo: "$t"');});
                  _translateWithWorker(t,_voskTranslateTo).then((r){
                    if(_mounted){
                      setState((){_aiLog.add('[TRANS] result: "$r"');});
                      if(r.isNotEmpty&&r!=t)setState(()=>_dgText=r);
                    }
                  });
                }
              }
              if(mounted)setState((){
                _dgText=isFinal?t:'$t...';
              });
            }
          } else if(type=='status'){
            if(mounted)setState((){_aiLog.add('[$tsStr] 🔗 $data');if(_aiLog.length>30)_aiLog.removeAt(0);});
          } else if(type=='error'){
            if(mounted)setState((){_dgActive=false;_dgText='';_aiLog.add('[$tsStr] ❌ $data');});
          }
        });
        _voskSrtEntries = [];
        _voskStartTime = DateTime.now();
        _lastFinalTime = DateTime.now();
        await Future.delayed(const Duration(milliseconds:300));
        // اگه از dialog modelId اومد استفاده کن وگرنه اولین دانلود شده
        // ── Android Built-in STT ──
        if (_useAndroidStt) {
          _dgSub = AndroidSttService.events().listen((e) {
            final type = e['type'] as String;
            final data = e['data'];
            final tsStr = DateTime.now().toString().substring(11, 19);
            _aiLog.add('[$tsStr] [Android] $type: $data');
            if (_aiLog.length > 50) _aiLog.removeAt(0);
            if (type == 'transcript') {
              final t = (data as Map)['text'] as String;
              final fin = (data as Map)['final'] as bool;
              if (t.isNotEmpty) {
                if (!fin && _voskFinalOnly) return;
                final newText = fin ? t : '$t...';
                if (newText != _dgText) {
                  setState(() {
                    _dgText = newText;
                    if (fin && _voskTranslate) {
                      _translateWithWorker(t, _voskTranslateTo).then((r) {
                        if (mounted && r.isNotEmpty && r != t) setState(() => _dgText = r);
                      });
                    }
                  });
                }
              }
            } else if (type == 'error') {
              setState(() { _dgActive = false; _dgText = ''; _aiLog.add('[$tsStr] ❌ $data'); });
            }
          });
          _androidSttPollTimer = Timer.periodic(Duration(milliseconds: _voskPollMs), (_) async {
            if (!mounted || _androidSttPollTimer == null) return;
          });
          setState(() { _dgActive = true; _dgText = ''; });
          await AndroidSttService.start(lang);
          return;
        }

        final finalModelId = modelId ?? VoskService.downloadedModels
            .where((m) => m.langCode == (lang == 'multi' ? 'en' : lang)).toList().firstOrNull?.id;
        await VoskService.start(lang=='multi'?'en':lang, modelId: finalModelId);
        // polling هر 200ms
        _voskPollTimer = Timer.periodic(Duration(milliseconds:_voskPollMs), (_) async {
          if (!_mounted || _voskPollTimer == null) return;
          final event = await VoskService.getNextEvent();
          if (event == null || !_mounted) return;
          final type = event['type'] as String;
          final data = event['data'];
          final ts = DateTime.now();
          final tsStr = '${ts.hour.toString().padLeft(2,'0')}:${ts.minute.toString().padLeft(2,'0')}:${ts.second.toString().padLeft(2,'0')}';
          if (type == 'transcript') {
            final t = (data as Map)['text'] as String;
            final fin = (data as Map)['final'] as bool;
            if (t.isNotEmpty) {
              setState(() {
                if (fin) {
                  _dgText = t;
                                // ذخیره SRT با timing دقیق
                  if (_voskStartTime != null) {
                    final now = DateTime.now();
                    final endTime = now.difference(_voskStartTime!);
                    final startTime = _lastFinalTime != null
                        ? _lastFinalTime!.difference(_voskStartTime!)
                        : (endTime > const Duration(milliseconds: 500)
                            ? endTime - const Duration(milliseconds: 500)
                            : Duration.zero);
                    _lastFinalTime = now;

                    if (_voskTranslate && _voskTranslateTo.isNotEmpty) {
                      // ترجمه → entry با متن ترجمه شده ذخیره بشه
                      _translateWithWorker(t, _voskTranslateTo).then((r) {
                        final text = (r.isNotEmpty && r != t) ? r : t;
                        _voskSrtEntries.add(_SrtEntry(_voskSrtEntries.length + 1, startTime, endTime, text));
                        if (_mounted) {
                          setState(() => _dgText = text);
                          _saveVoskSrt(silent: true);
                        }
                      });
                    } else {
                      _voskSrtEntries.add(_SrtEntry(_voskSrtEntries.length + 1, startTime, endTime, t));
                      _saveVoskSrt(silent: true);
                    }
                  }
                } else {
                  if (!_voskFinalOnly) _dgPartial = t;
                }
              });
            }
          } else if (type == 'status') {
            // status log حذف شد
          } else if (type == 'error') {
            setState(() {
              _dgActive = false; _dgText = '';
              _aiLog.add('[$tsStr] ❌ $data');
            });
          }
        });
      } else {
        await DeepgramService.start(language:lang, streamUrl:_curPath);
      }
    }
  }

  void _showAiLogDialog(){
    showDialog(context:context,barrierColor:Colors.black54,builder:(ctx)=>StatefulBuilder(
      builder:(ctx,ss){
        // آپدیت هر ثانیه
        Future.delayed(const Duration(seconds:1),()=>ss((){}));
        return AlertDialog(
          backgroundColor:const Color(0xFF0E0E1A),
          insetPadding:const EdgeInsets.all(16),
          titlePadding:const EdgeInsets.fromLTRB(16,16,16,0),
          contentPadding:const EdgeInsets.all(12),
          title:Row(children:[
            Icon(Icons.bug_report_rounded,color:_dgActive?Colors.green:Colors.white38,size:18),
            const SizedBox(width:8),
            Text('AI Subtitle Log',style:const TextStyle(color:Colors.white,fontSize:14)),
            const Spacer(),
            Container(padding:const EdgeInsets.symmetric(horizontal:8,vertical:2),
              decoration:BoxDecoration(
                color:_dgActive?Colors.green.withOpacity(0.2):Colors.red.withOpacity(0.2),
                borderRadius:BorderRadius.circular(8)),
              child:Text(_dgActive?'ACTIVE':'OFF',style:TextStyle(
                color:_dgActive?Colors.green:Colors.red,fontSize:10,fontWeight:FontWeight.bold))),
            const SizedBox(width:8),
            IconButton(icon:const Icon(Icons.close,color:Colors.white54,size:18),
              padding:EdgeInsets.zero,constraints:const BoxConstraints(),
              onPressed:()=>Navigator.pop(ctx)),
          ]),
          content:SizedBox(width:double.maxFinite,height:300,
            child:_aiLog.isEmpty
              ?const Center(child:Text('Press AI button to start\nThen tap this log to see status',
                style:TextStyle(color:Colors.white38,fontSize:12),textAlign:TextAlign.center))
              :ListView.builder(
                reverse:true,
                itemCount:_aiLog.length,
                itemBuilder:(_,i){
                  final log=_aiLog[_aiLog.length-1-i];
                  final color=log.contains('❌')?Colors.redAccent:
                    log.contains('✓')?Colors.greenAccent:
                    log.contains('🔗')?Colors.blueAccent:Colors.white60;
                  return Padding(padding:const EdgeInsets.only(bottom:3),
                    child:Text(log,style:TextStyle(color:color,fontSize:10,fontFamily:'monospace')));
                })),
          actions:[
            TextButton(onPressed:(){setState((){_aiLog.clear();});ss((){});},
              child:const Text('Clear',style:TextStyle(color:Colors.white54))),
          ]);
      }));
  }

  void _showLogDialog(){
    showDialog(context:context,barrierColor:Colors.black54,builder:(ctx)=>StatefulBuilder(
      builder:(ctx,ss)=>AlertDialog(
        backgroundColor:const Color(0xFF0E0E1A),
        insetPadding:const EdgeInsets.all(16),
        titlePadding:const EdgeInsets.fromLTRB(16,16,16,0),
        contentPadding:const EdgeInsets.all(12),
        title:Row(children:[
          const Icon(Icons.terminal_rounded,color:Color(0xFF7C3AED),size:18),
          const SizedBox(width:8),
          const Text('Live Stream Log',style:TextStyle(color:Colors.white,fontSize:14)),
          const Spacer(),
          IconButton(icon:const Icon(Icons.close,color:Colors.white54,size:18),
            padding:EdgeInsets.zero,constraints:const BoxConstraints(),
            onPressed:()=>Navigator.pop(ctx)),
        ]),
        content:SizedBox(width:double.maxFinite,height:300,
          child:_liveLog.isEmpty
            ?const Center(child:Text('No logs yet...',style:TextStyle(color:Colors.white38)))
            :ListView.builder(
              reverse:true,
              itemCount:_liveLog.length,
              itemBuilder:(_,i){
                final log=_liveLog[_liveLog.length-1-i];
                final color=log.contains('▶')?const Color(0xFF22c55e):
                  log.contains('Error')||log.contains('error')?Colors.redAccent:
                  log.contains('Buffering')?Colors.orange:Colors.white60;
                return Padding(padding:const EdgeInsets.only(bottom:4),
                  child:Text(log,style:TextStyle(color:color,fontSize:11,fontFamily:'monospace')));
              })),
        actions:[
          TextButton(onPressed:(){setState((){_liveLog.clear();});ss((){});},
            child:const Text('Clear',style:TextStyle(color:Colors.white54))),
        ])));
  }

  void _addLiveLog(String msg){
    if(!widget.isLive)return;
    final t=DateTime.now();
    final ts='${t.hour.toString().padLeft(2,'0')}:${t.minute.toString().padLeft(2,'0')}:${t.second.toString().padLeft(2,'0')}';
    if(mounted)setState((){
      _liveLog.add('[$ts] $msg');
      if(_liveLog.length>20)_liveLog.removeAt(0);
    });
  }

  void _toggleFullscreen(){
    setState(()=>_isFullscreen=!_isFullscreen);
    if(_isFullscreen){
      SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft,DeviceOrientation.landscapeRight]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
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
              if(mounted)showSnack(context, L.subtitleEmpty);
              break;
            }
          }catch(_){}
        }
      }
      if(secondary){setState((){_sub2=entries;_sub2Path=path;_sub2Visible=entries.isNotEmpty;});}
      else{setState((){_sub1=entries;_sub1Path=path;});}
    }catch(e){
      if(mounted)showSnack(context, L.errorShort(e), color: Colors.red);
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
      if(mounted)showSnack(context, L.fontLoaded);
    }catch(_){if(mounted)showSnack(context, L.fontError);}
  }

  void _copySubText(){
    final text=_subText??_sub2Text;
    if(text!=null){
      Clipboard.setData(ClipboardData(text:text));
      if(mounted)showSnack(context, L.copied);
    }
  }

  void _copyToClipboard(String text){
    Clipboard.setData(ClipboardData(text:text));
    if(mounted)showSnack(context, L.copied,
              seconds: 2);
  }

  Future<void> _translateSubText()async{
    final text=_subText??_sub2Text;
    if(text==null)return;
    final url=Uri.parse('https://translate.google.com/?text=${Uri.encodeComponent(text)}&hl=fa');
    try{await launchUrl(url,mode:LaunchMode.externalApplication);}catch(_){
      Clipboard.setData(ClipboardData(text:text));
      if(mounted)showSnack(context, L.textCopied);
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
      if(mounted)showSnack(context, '${L.screenshotSaved}: Pictures/screenshot_$ts.png');
    }catch(_){if(mounted)showSnack(context, L.screenshotError);}
  }

  Future<void> _saveVsForVideo()async{
    await Store.saveVideoSettings(_curPath,_vs);
    if(mounted)showSnack(context, L.settingsSaved);
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
      backgroundColor:const Color(0xFF1C1C22),title:Text(L.sleepTimer),
      content:Column(mainAxisSize:MainAxisSize.min,children:[
        Text('$min ${L.minutes}',style:const TextStyle(fontSize:24,fontWeight:FontWeight.bold)),
        Slider(min:1,max:180,divisions:179,value:min.toDouble(),onChanged:(v)=>ss(()=>min=v.round())),
        if(_sleepAt!=null)Text('${L.remaining}: ${_sleepAt!.difference(DateTime.now()).inMinutes} ${L.minutes}',style:const TextStyle(color:Colors.orange)),
      ]),
      actions:[
        if(_sleepAt!=null)TextButton(onPressed:(){_sleepTimer?.cancel();setState(()=>_sleepAt=null);Navigator.pop(ctx);},child:Text(L.cancel,style:TextStyle(color:Colors.red))),
        TextButton(onPressed:()=>Navigator.pop(ctx),child:Text(L.close)),
        FilledButton(onPressed:(){
          _sleepTimer?.cancel();
          final at=DateTime.now().add(Duration(minutes:min));
          setState(()=>_sleepAt=at);
          _sleepTimer=Timer(Duration(minutes:min),(){player.pause();setState(()=>_sleepAt=null);});
          Navigator.pop(ctx);
        },child:Text(L.start)),
      ],
    )));
  }

  // انتخاب تراک زیرنویس embedded (softsub)
  void _showEmbeddedSubPicker(){
    showDialog(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,ss)=>AlertDialog(
      title:Text(L.embeddedSubtitleVideo),
      content:Column(mainAxisSize:MainAxisSize.min,children:[
        // toggle کلی
        SwitchListTile(
          dense:true,
          title:Text(L.enableEmbeddedSub),
          subtitle:Text(_embeddedSubEnabled?L.internalEmbedded:L.disabled),
          value:_embeddedSubEnabled,
          onChanged:(v){
            setState(()=>_embeddedSubEnabled=v);ss((){});
            if(v&&_subtitleTracks.isNotEmpty){player.setSubtitleTrack(_subtitleTracks.first);}
          },
        ),
        const Divider(height:1),
        if(_subtitleTracks.isEmpty)Padding(
          padding:EdgeInsets.all(12),
          child:Text(L.noEmbeddedSubtitle,
              style:TextStyle(color:Color(0xFF94A3B8)),textAlign:TextAlign.center)),
        ..._subtitleTracks.asMap().entries.map((entry){
          final t=entry.value;
          return ListTile(dense:true,
            leading:const Icon(Icons.subtitles,size:18,color:Color(0xFF94A3B8)),
            title:Text(t.title??t.language??'Track ${t.id}'),
            subtitle:Text('${L.language}: ${t.language??""}',style:const TextStyle(fontSize:11)),
            trailing:FilledButton(
              style:FilledButton.styleFrom(padding:const EdgeInsets.symmetric(horizontal:12),minimumSize:const Size(60,30)),
              onPressed:(){
                player.setSubtitleTrack(t);
                setState(()=>_embeddedSubEnabled=true);
                showSnack(context, '${L.select}: ${t.title??t.language??t.id}');
              },
              child:Text(L.select,style:TextStyle(fontSize:12)),
            ),
          );
        }),
        const Divider(height:1),
        Padding(padding:EdgeInsets.all(8),
          child:Text(L.bothAtOnce,
              style:TextStyle(fontSize:11,color:Color(0xFF7C3AED)))),
      ]),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:Text(L.close))],
    )));
  }

  void _showAudioPicker(){
    if(_audioTracks.isEmpty){showSnack(context, L.audioTrackNotFound);return;}
    showDialog(context:context,builder:(ctx)=>AlertDialog(
      backgroundColor:const Color(0xFF1C1C22),title:Text(L.selectAudioTrack),
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
        if(_resStr.isNotEmpty)_infoRow(Icons.aspect_ratio_rounded,const Color(0xFF0EA5E9),L.resolution,_resStr),
        if(_fpsStr.isNotEmpty)_infoRow(Icons.speed_rounded,const Color(0xFF7C3AED),L.frameRate,_fpsStr),
        if(_codecStr.isNotEmpty)_infoRow(Icons.code_rounded,const Color(0xFF10B981),L.codec,_codecStr),
        if(_bitrateStr.isNotEmpty)_infoRow(Icons.network_check_rounded,const Color(0xFFF59E0B),L.bitrate,_bitrateStr),

        if(_buffering&&widget.isLive)Positioned(
          top:0,left:0,right:0,bottom:0,
          child:Container(
            color:Colors.black54,
            child:Center(child:Column(mainAxisSize:MainAxisSize.min,children:[
              const CircularProgressIndicator(color:Color(0xFF7C3AED),strokeWidth:3),
              const SizedBox(height:16),
              Text('📡 Connecting to live stream...',style:const TextStyle(color:Colors.white,fontSize:14,fontWeight:FontWeight.w500)),
              if(_bufferStart!=null)Padding(padding:const EdgeInsets.only(top:6),
                child:Text('${DateTime.now().difference(_bufferStart!).inSeconds}s',
                  style:const TextStyle(color:Colors.white54,fontSize:12))),
            ])))),
        if(_isHDR)_infoRow(Icons.hdr_on_rounded,const Color(0xFFEC4899),'HDR',L.activeTick),
        if(_pixelFmtStr.isNotEmpty)_infoRow(Icons.palette_rounded,const Color(0xFF7C3AED),'Pixel Format',_pixelFmtStr),
        _infoRow(Icons.timer_outlined,const Color(0xFF94A3B8),L.duration,fmt(_duration)),
        _infoRow(Icons.memory_rounded,const Color(0xFF94A3B8),L.decoder,_hwDecode?L.hwDecode:L.swDecode),
        if(_audioTracks.isNotEmpty)
          _infoRow(Icons.music_note_rounded,const Color(0xFF94A3B8),L.audioTracks,'${_audioTracks.length} ${L.audioTracks}'),
        if(_hwDecode)_infoRow(Icons.developer_board_rounded,const Color(0xFF0EA5E9),L.decoder,L.hwActive),
      ]),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:Text(L.close))],
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

  Future<void> _playVez(String path)async{
    if(!mounted)return;
    showSnack(context, '${L.decoding} ${path.split("/").last}', seconds: 120);
    try{
      final temp=await VezService.decryptToTemp(path);
      _vezTempPath=temp;
      if(mounted){
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        player.open(Media(temp));
      }
    }catch(e){
      if(mounted){
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        showDialog(context:context,builder:(ctx)=>AlertDialog(
          title:Text(L.decodeError),
          content:SingleChildScrollView(child:Text(e.toString())),
          actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:Text(L.close))],
        ));
      }
    }
  }



  void _initPipChannel(){
    _pipCh.setMethodCallHandler((call)async{
      if(!mounted)return;
      switch(call.method){
        case 'playerAction':
          final a=call.arguments['action']as String?;
          if(a=='play')player.play();
          else if(a=='pause')player.pause();
          else if(a=='close'){
            await _pipCh.invokeMethod('hideNotif');
            if(mounted)Navigator.pop(context);
          }
          break;
        case 'pipModeChanged':
          if(mounted)setState(()=>_inPipMode=call.arguments['inPip']as bool? ??false);
          break;
      }
    });
  }

  Future<void> _enterPip()async{
    try{
      final ok=await _pipCh.invokeMethod<bool>('enterPip',{'playing':_playing,'title':p.basename(_curPath)});
      if(ok!=true&&mounted){
        showSnack(context, L.pipNotSupported);
      }
    }catch(e){
      if(mounted)showSnack(context, 'PiP: $e');
    }
  }

  Future<void> _fetchSeekThumb(int ms,int session)async{
    try{
      final data=await _thumbCh.invokeMethod<Uint8List>('getThumbnail',
          {'path':_curPath,'timeMs':ms});
      // فقط اگه همین session هنوز فعاله → بذار
      if(mounted&&_seekDragging&&_seekSession==session)setState(()=>_seekThumbData=data);
    }catch(_){}
  }

  // اعمال تنظیمات subtitle روی libmpv (برای embedded ASS/SSA)
  // تبدیل Color به فرمت MPV: 0xBBGGRRAA
  String _toMpvColor(Color c,[double opacity=1.0]){
    final a=(opacity*255).round();
    String h(int n)=>n.toRadixString(16).padLeft(2,'0');
    return '0x${h(c.blue)}${h(c.green)}${h(c.red)}${h(a)}';
  }

  void _applySubMpvSettings(){
    if(!_embeddedSubEnabled)return;
    try{
      final native=player.platform as NativePlayer;
      native.setProperty('sub-ass-override','force');
      // سایز
      native.setProperty('sub-font-size',_vs.fontSize.round().toString());
      // موقعیت عمودی
      native.setProperty('sub-margin-y',_vs.bottomPadding.round().toString());
      // موقعیت افقی
      final align=['left','center','right'][_vs.textAlign.clamp(0,2)];
      native.setProperty('sub-align-x',align);
      // فونت
      if(_vs.fontFamily.isNotEmpty)native.setProperty('sub-font',_vs.fontFamily);
      // استایل
      native.setProperty('sub-bold',_vs.bold?'yes':'no');
      // رنگ متن
      native.setProperty('sub-color',_toMpvColor(Color(_vs.textColor)));
      // پس‌زمینه با شفافیت
      final bg=Color(_vs.bgColor);
      native.setProperty('sub-back-color',_toMpvColor(bg,_vs.bgOpacity));
      // border
      native.setProperty('sub-border-size',_vs.borderSize.toStringAsFixed(1));
      // سایه
      native.setProperty('sub-shadow-offset',_vs.shadowSize.toStringAsFixed(1));
      if(_vs.shadowSize>0)native.setProperty('sub-shadow-color','0x00000080');
    }catch(_){}
  }

  void _notifUpdate(){
    try{
      _pipCh.invokeMethod('updateState',{'playing':_playing,'title':p.basename(_curPath)});
    }catch(e){
      debugPrint('Notification error: $e');
    }
  }

  // ══════════════════════════════════════════════════════════
  //  زیرنویس زنده
  // ══════════════════════════════════════════════════════════
  Future<void> _startLiveSub(LiveSubConfig config) async {
    _liveBehindAction = config.behindAction;
    _liveBehindSpeed  = config.behindSpeed;
    LiveSubState.reset();
    _liveBadgeVisible = true; // هر session جدید badge دیده میشه
    setState(() => _liveSubActive = true);

    final srtPath = await liveSrtPath(_curPath, config.language);
    _liveSubSrtPath = srtPath;

    // timer بررسی sync + refresh SRT هر ۳ ثانیه
    _liveSubRefreshTimer?.cancel(); _liveSubSecondTimer?.cancel();
    _liveSubRefreshTimer = Timer.periodic(const Duration(seconds: 3), (_) => _liveSubTick());

    // timer هر ثانیه — stopwatch یک‌بار شروع میشه، reset نمیشه
    _liveStopwatch.reset();
    _liveStopwatch.start();
    _liveSubSecondTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final totalSec = LiveSubState.totalMs ~/ 1000;
      final chunkSec = LiveSubState.chunksTotal > 0 ? totalSec ~/ LiveSubState.chunksTotal : 30;
      final remaining = (LiveSubState.chunksTotal - LiveSubState.chunksDone) * chunkSec;
      setState(() {
        _liveChunkEstSec = chunkSec;
        _liveTotalEstSec = remaining > 0 ? remaining : 0;
      });
    });

    // ── همگام‌سازی ترجمه آنلاین ──
    if (config.syncTranslate) {
      _liveTransSync?.cancel();
      _liveTransSync = LiveTranslationSync(targetLangCode: config.syncTranslateLang);
      _liveTransSync!.onUpdated = (translatedPath) {
        // SRT ترجمه‌شده آماده شد — بارگذاری به‌عنوان زیرنویس دوم
        if (mounted) _loadSub(translatedPath, secondary: true);
      };
    }

    // شروع transcription در پس‌زمینه
    transcribeLive(
      videoPath: _curPath,
      config: config,
      onChunk: (startMs, totalMs, done, total) {
        // stopwatch ادامه میده — reset نمیشه
      },
      onSrtUpdated: () {
        if (mounted) _loadSub(srtPath, secondary: false);
        if (config.syncTranslate && _liveTransSync != null) {
          // async wrapper برای await داخل callback معمولی
          () async {
            final outputPath = await LiveTranslationSync.outputPath(_curPath, config.syncTranslateLang);
            _liveTransSync!.onLiveSubUpdated(srtPath, outputPath);
          }();
        }
      },

    ).then((_) {
      if (mounted) {
        setState(() => _liveSubActive = false);
        _liveSubRefreshTimer?.cancel(); _liveSubSecondTimer?.cancel();
        _liveStopwatch.stop();
        if (_liveSubPaused) { _liveSubPaused = false; player.play(); }
        showSnack(context, L.liveDone, color: Color(0xFF7C3AED));
      }
    }).catchError((e) {
      if (mounted) {
        setState(() => _liveSubActive = false);
        _liveSubRefreshTimer?.cancel(); _liveSubSecondTimer?.cancel();
        _liveStopwatch.stop();
        if (_liveSubPaused) { _liveSubPaused = false; player.play(); }
        if (!e.toString().contains(L.cancel)) {
          showSnack(context, L.errorMsg(e), color: Colors.red);
        }
      }
    });
  }

  void _showTranslationPanel() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C22),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _TranslationInfoPanel(
        onCancel: () {
          Navigator.pop(context);
          SrtTranslationService.cancel();
          setState((){_translating=false; _translatingStatus='';});
          showSnack(context, L.translationCancelled, color: Colors.orange);
        },
      ),
    );
  }

  void _showLivePanel() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C22),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _LivePanelSheet(
        stopwatch: _liveStopwatch,
        onStop: () { Navigator.pop(context); _stopLiveSub(); },
        onSkipChunk: () { Navigator.pop(context); _skipCurrentChunk(); },
        onToggleVideo: () {
          Navigator.pop(context);
          if (_liveSubPaused) { _liveSubPaused = false; player.play(); }
          else player.pause();
        },
      ),
    );
  }

  void _skipCurrentChunk() {
    // لغو chunk جاری با reset flag — loop بعدی خودش می‌ره chunk بعدی
    // در حال حاضر با cancel/restart پیاده میشه
    // TODO: پیاده‌سازی skip واقعی در آینده
    showSnack(context, L.skipChunk);
  }

  void _stopLiveSub() {
    cancelLiveSub();
    _liveTransSync?.cancel();
    _liveTransSync = null;
    _liveSubRefreshTimer?.cancel(); _liveSubSecondTimer?.cancel();
    _liveStopwatch.stop();
    if (_liveSubPaused) { _liveSubPaused = false; player.play(); }
    setState(() => _liveSubActive = false);
  }

  void _liveSubTick() {
    if (!_liveSubActive || !mounted) return;
    final posMs = _position.inMilliseconds;
    final transcribed = LiveSubState.transcribedMs;
    final buffer = LiveSubState.totalMs > 0 ? 5000 : 0; // ۵ ثانیه buffer

    if (transcribed == 0) return; // هنوز اول کار

    if (posMs > transcribed - buffer) {
      // پشت ماند — اعمال استراتژی
      if (_liveBehindAction == LiveBehindAction.pause) {
        if (!_liveSubPaused) { _liveSubPaused = true; player.pause(); }
      } else {
        if (_liveSubPaused) { _liveSubPaused = false; }
        player.setRate(_liveBehindSpeed);
      }
    } else {
      // به خودش رسید — برگشت به حالت عادی
      if (_liveSubPaused) { _liveSubPaused = false; player.play(); }
      if (_vs.speed != 1.0 && _liveBehindAction == LiveBehindAction.slowDown) player.setRate(_vs.speed);
    }
  }

  void _startFastSeek(bool forward){
    // forward=true → جلو (چپ صفحه)، forward=false → عقب (راست صفحه)
    if(_locked)return;
    _fastSeekTimer?.cancel();
    // نوار سمت راست = وقتی عقب میریم، سمت چپ = وقتی جلو
    setState((){_fastSeeking=true;_fastSeekRight=!forward;_fastSeekBaseSpeed=_fastSeekSpeed;_fastSeekLocked=false;_fastSeekDragStartY=0;});
    _fastSeekTimer=Timer.periodic(const Duration(milliseconds:80),(t){
      final delta=(_fastSeekSpeed*(forward?1:-1)*80).round();
      final ms=(_position.inMilliseconds+delta).clamp(0,_duration.inMilliseconds);
      player.seek(Duration(milliseconds:ms));
    });
  }

  void _stopFastSeek(){
    _fastSeekTimer?.cancel();
    setState((){_fastSeeking=false;_fastSeekLocked=false;});
  }

  void _adjustFastSeekSpeed(double dy){
    if(_fastSeekDragStartY==0)_fastSeekDragStartY=dy;
    // بالا = سریع‌تر، پایین = کندتر
    setState(()=>_fastSeekSpeed=(_fastSeekBaseSpeed-dy/60).clamp(1.0,20.0));
    // کشیدن بیش از ۸۰ پیکسل به سمت بالا → قفل میشود (با رهاکردن انگشت هم متوقف نمیشود)
    if(!_fastSeekLocked&&(dy-_fastSeekDragStartY)< -80){
      setState(()=>_fastSeekLocked=true);
      _overlay=L.locked;
      _overlayTimer?.cancel();
      _overlayTimer=Timer(const Duration(seconds:2),()=>setState(()=>_overlay=null));
    }
  }

  @override
  void dispose(){
    Store.savePos(_curPath,_position);
    for(final s in _subs)s.cancel();
    _voskPollTimer?.cancel(); _voskPollTimer = null;
    _androidSttPollTimer?.cancel(); _androidSttPollTimer = null;
    _dgSub?.cancel();
    if(_dgActive){
      _dgActive = false;
      if(_useAndroidStt) { try { AndroidSttService.stop(); } catch(_){} }
      else if(_useVosk) { try { VoskService.stop(); } catch(_){} }
      else { try { DeepgramService.stop(); } catch(_){} }
    }
    // ذخیره SRT اگه چیزی ضبط شده
    if (_voskSrtEntries.isNotEmpty) _saveVoskSrt(silent: true); // dispose — بدون snackbar
    _hideTimer?.cancel();_overlayTimer?.cancel();_sleepTimer?.cancel();_thumbTimer?.cancel();
    VezService.cleanup(_vezTempPath);
    try{_pipCh.invokeMethod('hideNotif');}catch(_){}
    WakelockPlus.disable();
    try{ScreenBrightness().resetApplicationScreenBrightness();}catch(_){}
    try{VolumeController.instance.showSystemUI=true;}catch(_){}
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _liveSubRefreshTimer?.cancel(); _liveSubSecondTimer?.cancel();
    if (_liveSubActive) cancelLiveSub();
    _mounted = false;
    player.dispose();
    super.dispose();
  }

  void _startHideTimer(){
    _hideTimer?.cancel();
    _hideTimer=Timer(const Duration(seconds:4),(){
      if(mounted&&!_seekDragging)setState(()=>_controlsVisible=false); // موقع drag مخفی نکن!
    });
  }
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
      player.seek(t);_showOverlay(L.tenSecBack);
    }else if(_doubleTapPos.dx<third){
      player.seek(_position+const Duration(seconds:10));_showOverlay(L.tenSecForward);
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
  void _cycleFit(){setState(()=>_fit=_fit==BoxFit.contain?BoxFit.cover:_fit==BoxFit.cover?BoxFit.fill:BoxFit.contain);_showOverlay(_fit==BoxFit.contain?L.normal:_fit==BoxFit.cover?L.fill:L.stretch);}
  void _cycleRepeat(){setState(()=>_repeatMode=_repeatMode==_Repeat.none?_Repeat.all:_repeatMode==_Repeat.all?_Repeat.one:_Repeat.none);_showOverlay(_repeatMode==_Repeat.none?L.repeatOff:_repeatMode==_Repeat.all?L.repeatAll:L.repeatOne);}
  void _cycleRotation(){setState(()=>_rotationDeg=(_rotationDeg+90)%360);_showOverlay('${L.rotate}: ${_rotationDeg.toInt()}°');}

  @override
  Widget build(BuildContext context){
    // اندازه صفحه بدون حساب navigation bar
    final mq=MediaQuery.of(context);
    _size=mq.size;
    final navBottom=mq.viewPadding.bottom;
    final bkm=Store.bookmarked.contains(_curPath);
    final sub=_subText,sub2=_sub2Text;
    final align=TextAlign.values[_vs.textAlign.clamp(0,TextAlign.values.length-1)];

    // در حالت PiP فقط ویدیو — بدون کنترل‌ها
    if(_inPipMode){
      return Scaffold(backgroundColor:Colors.black,body:Stack(children:[
        Positioned.fill(child:Video(controller:controller,controls:NoVideoControls,fit:_fit,
          subtitleViewConfiguration:const SubtitleViewConfiguration(
            style:TextStyle(fontSize:0,color:Colors.transparent),padding:EdgeInsets.zero),
        )),
        if(_embeddedSubEnabled&&_embeddedSubText!=null)Positioned(left:4,right:4,bottom:4,child:Container(
          padding:const EdgeInsets.symmetric(horizontal:6,vertical:3),
          color:Color(_vs.bgColor).withOpacity(_vs.bgOpacity),
          child:Text(_embeddedSubText!,textAlign:TextAlign.center,style:TextStyle(
            fontSize:_vs.fontSize*0.7,color:Color(_vs.textColor),fontWeight:FontWeight.bold)),
        ))
        else if(_subText!=null)Positioned(left:4,right:4,bottom:4,child:Container(
          padding:const EdgeInsets.symmetric(horizontal:6,vertical:3),
          color:Color(_vs.bgColor).withOpacity(_vs.bgOpacity),
          child:Text(_subText!,textAlign:TextAlign.center,style:TextStyle(
            fontSize:_vs.fontSize*0.7,color:Color(_vs.textColor),fontWeight:FontWeight.bold)),
        )),
      ]));
    }

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
            // همیشه transparent — ما خودمون رندر می‌کنیم
            subtitleViewConfiguration:const SubtitleViewConfiguration(
              style:TextStyle(fontSize:0,color:Colors.transparent),padding:EdgeInsets.zero,
            ),
          )),
        ))),

        // ── Deepgram AI Subtitle ──
        if(_dgActive&&_dgText.isNotEmpty&&!_dgText.startsWith('⏳'))Positioned(
          bottom:_vs.bottomPadding+navBottom+80,left:16,right:16,
          child:IgnorePointer(child:Container(
            padding:const EdgeInsets.symmetric(horizontal:12,vertical:8),
            decoration:BoxDecoration(
              color:Color(_vs.bgColor).withOpacity(_vs.bgOpacity.clamp(0.5,0.95)),
              borderRadius:BorderRadius.circular(10)),
            child:Text(_dgText,
              textAlign:TextAlign.center,
              style:TextStyle(
                color:Color(_vs.textColor),
                fontSize:_vs.fontSize,height:1.4,
                fontWeight:_vs.bold?FontWeight.bold:FontWeight.w500,
                shadows:[Shadow(color:Colors.black,blurRadius:_vs.shadowSize*2+4)]))))),

        // ── زیرنویس embedded (همون موقعیت و تنظیمات sub1) ──
        if(_embeddedSubEnabled&&_embeddedSubText!=null)Positioned(
          left:12,right:12,
          bottom:_vs.bottomPadding+navBottom,
          child:Align(
            alignment:_vs.textAlign==1?Alignment.bottomRight:_vs.textAlign==0?Alignment.bottomLeft:Alignment.bottomCenter,
            child:Container(
              padding:const EdgeInsets.symmetric(horizontal:10,vertical:5),
              decoration:BoxDecoration(
                color:Color(_vs.bgColor).withOpacity(_vs.bgOpacity),
                borderRadius:BorderRadius.circular(5),
                border:_vs.borderSize>0?Border.all(color:Colors.black26,width:_vs.borderSize*0.5):null,
              ),
              child:Text(_embeddedSubText!,textAlign:align,style:TextStyle(
                fontFamily:_vs.fontFamily.isEmpty?null:_vs.fontFamily,
                fontSize:_vs.fontSize,color:Color(_vs.textColor),
                fontWeight:_vs.bold?FontWeight.bold:FontWeight.normal,height:1.4,
                shadows:_vs.shadowSize>0?[Shadow(color:Colors.black,blurRadius:_vs.shadowSize*2,offset:Offset(_vs.shadowSize,_vs.shadowSize))]:null,
              )),
            ),
          ),
        ),

        // ── زیرنویس ۱ (خارجی) — فقط اگه embedded نداریم ──
        if(sub!=null&&!(_embeddedSubEnabled&&_embeddedSubText!=null))Positioned(
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

        // ── زیرنویس ۲ — متن با تنظیمات کامل مستقل ──
        if(sub2!=null)Positioned(
          left:12,right:12,
          bottom:_vs2.bottomPadding+navBottom,
          child:Align(
            alignment:_vs2.textAlign==1?Alignment.bottomRight:_vs2.textAlign==0?Alignment.bottomLeft:Alignment.bottomCenter,
            child:Container(
              padding:const EdgeInsets.symmetric(horizontal:10,vertical:5),
              decoration:BoxDecoration(color:Color(_vs2.bgColor).withOpacity(_vs2.bgOpacity),borderRadius:BorderRadius.circular(5)),
              child:Text(sub2,
                textAlign:TextAlign.values.elementAt(_vs2.textAlign.clamp(0,2)),
                style:TextStyle(
                  fontFamily:_vs2.fontFamily.isEmpty?null:_vs2.fontFamily,
                  fontSize:_vs2.fontSize,color:Color(_vs2.textColor),
                  fontWeight:_vs2.bold?FontWeight.bold:FontWeight.normal,height:1.4,
                  shadows:_vs2.shadowSize>0?[Shadow(blurRadius:_vs2.shadowSize*4,color:Colors.black87)]:null,
                )),
            ),
          ),
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
          onTap:(){
            if(_fastSeeking&&_fastSeekLocked){_stopFastSeek();return;}
            _toggleControls();
          },
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
          onLongPressEnd:(_){ if(!_fastSeekLocked)_stopFastSeek(); },
          onLongPressCancel:(){ if(!_fastSeekLocked)_stopFastSeek(); },
          child:const SizedBox.expand(),
        )),


        // ── toolbar زیرنویس ۲ (بعد از GestureDetector — روی همه چیز) ──
        if(sub2!=null&&!_locked&&_vs2.showSubToolbar)
          Positioned(
            right:8,
            bottom:_vs2.bottomPadding+navBottom+_vs2.fontSize*1.8+10,
            child:Row(mainAxisSize:MainAxisSize.min,children:[
              GestureDetector(onTap:()=>_copyToClipboard(sub2!),child:_subSmallBtn(Icons.copy_all_rounded,L.copy)),
              const SizedBox(width:5),
              Listener(
                behavior:HitTestBehavior.opaque,
                onPointerMove:(e)=>setState(()=>_vs2.bottomPadding=(_vs2.bottomPadding-e.delta.dy).clamp(0.0,_size.height*0.85)),
                child:_subSmallBtn(Icons.drag_indicator,L.moveSub),
              ),
            ]),
          ),

        // ── سربرگ زیرنویس: فقط وقتی متن زیرنویس روی صفحه هست ──
        if(sub!=null&&!_locked&&_vs.showSubToolbar)
          Positioned(
            right:8,
            bottom:_vs.bottomPadding+navBottom+_vs.fontSize*1.8+10,
            child:Row(mainAxisSize:MainAxisSize.min,children:[
              GestureDetector(
                onTap:_copySubText,
                child:_subSmallBtn(Icons.copy_all_rounded,L.copy),
              ),
              const SizedBox(width:5),
              Listener(
                behavior:HitTestBehavior.opaque,
                onPointerDown:(_){_subPaddingStart=_vs.bottomPadding;},
                onPointerMove:(e)=>setState(()=>
                  _vs.bottomPadding=(_vs.bottomPadding-e.delta.dy).clamp(0.0,_size.height*0.85)),
                child:_subSmallBtn(Icons.drag_indicator,L.moveSub),
              ),
            ]),
          ),


        // ── thumbnail preview روی اسلایدر ──

        // ── نمایش timestamp هنگام کشیدن اسلایدر ──
        if(_seekDragging)
          Positioned(
            left:0,right:0,
            bottom:navBottom+52,
            child:Center(child:Column(mainAxisSize:MainAxisSize.min,children:[
              if(_seekThumbData!=null&&_vs.showSeekPreview)ClipRRect(
                borderRadius:BorderRadius.circular(8),
                child:Image.memory(_seekThumbData!,width:160,height:90,fit:BoxFit.cover)),
              Container(
                margin:EdgeInsets.only(top:_seekThumbData!=null?4:0),
                padding:const EdgeInsets.symmetric(horizontal:14,vertical:6),
                decoration:BoxDecoration(color:Colors.black.withOpacity(0.75),borderRadius:BorderRadius.circular(8),
                    border:Border.all(color:Colors.white24,width:0.5)),
                child:Text(fmt(Duration(milliseconds:_seekDragMs.round())),
                    style:const TextStyle(fontSize:15,fontWeight:FontWeight.bold,color:Colors.white)),
              ),
            ])),
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
              decoration:BoxDecoration(
                color:Colors.black.withOpacity(0.7),
                borderRadius:BorderRadius.circular(26),
                border:_fastSeekLocked?Border.all(color:Colors.orange,width:1.5):null,
              ),
              padding:const EdgeInsets.symmetric(vertical:12,horizontal:6),
              child:Column(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[
                Icon(_fastSeekLocked?Icons.lock:(_fastSeekRight?Icons.fast_rewind:Icons.fast_forward),
                  color:Colors.orange,size:20),
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

        // ── badge ترجمه پس‌زمینه ──
        if(_translating && SrtTranslationService.isRunning)
          Positioned(
            top: _liveSubActive ? 108 : 80, left: 0, right: 0,
            child: ValueListenableBuilder<int>(
              valueListenable: SrtTranslationServiceStatus.notifier,
              builder: (_,__,___) => Center(child: GestureDetector(
                onTap: _showTranslationPanel,
                child: Container(
                  decoration: BoxDecoration(color: Colors.black.withOpacity(0.75), borderRadius: BorderRadius.circular(20)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Padding(padding: EdgeInsets.only(left: 10, top: 6, bottom: 6),
                      child: Icon(Icons.translate, color: Color(0xFF7C3AED), size: 12)),
                    const SizedBox(width: 5),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                        SrtTranslationServiceStatus.batchTotal > 0
                          ? '${SrtTranslationServiceStatus.batchDone}/${SrtTranslationServiceStatus.batchTotal}'
                          : L.translating,
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 4),
                    const Padding(padding: EdgeInsets.only(right: 6),
                      child: Icon(Icons.info_outline, color: Colors.white38, size: 12)),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        SrtTranslationService.cancel();
                        setState((){_translating=false; _translatingStatus='';});
                        showSnack(context, L.translationCancelled, color: Colors.orange);
                      },
                      child: const Padding(padding: EdgeInsets.fromLTRB(2,6,10,6),
                        child: Icon(Icons.close, color: Colors.white54, size: 13)),
                    ),
                  ]),
                ),
              )),
            ),
          ),

        // ── پیام وسط ──
        // ── نشانگر زیرنویس زنده ──
        if(_liveSubActive && _liveBadgeVisible)
          Positioned(
            top: 80, left: 0, right: 0,
            child: ValueListenableBuilder<int>(
              valueListenable: LiveSubState.notifier,
              builder: (_,__,___) => Center(child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.75),
                  borderRadius: BorderRadius.circular(20)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  GestureDetector(
                    onTap: _showLivePanel,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.fiber_smart_record, color: Colors.red, size: 12),
                        const SizedBox(width: 5),
                        Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(
                            LiveSubState.chunksTotal == 0 ? L.translationProgress : '${LiveSubState.chunksDone}/${LiveSubState.chunksTotal}  •  ${_liveStopwatch.elapsed.inSeconds}s',
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                          if(_liveTotalEstSec > 0)
                            Text('~${(_liveTotalEstSec/60).toStringAsFixed(1)} ${L.minutes}',
                              style: const TextStyle(color: Colors.white60, fontSize: 9)),
                        ]),
                      ]),
                    ),
                  ),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(()=>_liveBadgeVisible=false),
                    child: const Padding(
                      padding: EdgeInsets.fromLTRB(4, 6, 12, 6),
                      child: Icon(Icons.visibility, color: Colors.white54, size: 14)),
                  ),
                ]),
              )),
            ),
          ),

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
                Text('${_sleepAt!.difference(DateTime.now()).inMinutes}${L.minutes}',style:const TextStyle(color:Colors.orange,fontSize:12)),
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
                padding:const EdgeInsets.all(4),
                decoration:BoxDecoration(
                  color:_embeddedSubEnabled?const Color(0xFF7C3AED):const Color(0xFF7C3AED).withOpacity(0.15),
                  borderRadius:BorderRadius.circular(6),
                  border:Border.all(color:const Color(0xFF7C3AED).withOpacity(_embeddedSubEnabled?0:0.4)),
                ),
                child:Icon(Icons.subtitles_outlined,size:16,
                    color:_embeddedSubEnabled?Colors.white:const Color(0xFF7C3AED)),
              ),
            ),
          PopupMenuButton<String>(
            icon:const Icon(Icons.subtitles,color:Color(0xFF7C3AED)),
            tooltip:L.subtitle,
            onSelected:(v){
              switch(v){
                case 'ai':
                  AiSubtitleSheet.show(context,_curPath,(srt){
                    _loadSub(srt,secondary:false);
                    showSnack(context, L.aiSubtitleLoaded, color: Color(0xFF7C3AED));
                  },onPreview:(srt){
                    _loadSub(srt,secondary:false);
                  });
                  break;
                case 'online':
                  OpenSubtitlesSheet.show(context,_curPath,(srt){
                    _loadSub(srt,secondary:false);
                    showSnack(context, L.onlineSubtitleLoaded, color: Color(0xFF7C3AED));
                  });
                  break;
                case 'lyrics':
                  LyricsSheet.show(context, _curPath, (srtPath) {
                    _loadSub(srtPath, secondary: false);
                  }, query: p.basenameWithoutExtension(_curPath));
                  break;
                case 'translate':
                  if (_translating && SrtTranslationService.isRunning) {
                    // ترجمه در حال اجراست — پنل وضعیت رو نشون بده
                    _showTranslationPanel();
                  } else if (_sub1Path != null) {
                    SrtTranslateSheet.show(
                      context, _sub1Path!,
                      (translated) {
                        if(!mounted) return;
                        setState((){_translating=false; _translatingStatus='';});
                        _loadSub(translated, secondary: false);
                        showSnack(context,
                          'ترجمه ذخیره شد:\n$translated',
                          color: Color(0xFF7C3AED), seconds: 10);
                      },
                      onDoneSecondary: (translated) {
                        if(!mounted) return;
                        setState((){_translating=false; _translatingStatus='';});
                        _loadSub(translated, secondary: true);
                        showSnack(context, L.translationOnSub2, color: Color(0xFF7C3AED), seconds: 10);
                      },
                      onSrtUpdated: (partial) {
                        setState((){
                          _translating = true;
                          _translatingPartialPath = partial;
                          _translatingStatus = SrtTranslationServiceStatus.lastStatus;
                        });
                        _loadSub(partial, secondary: false);
                      },
                    );
                    setState((){_translating=true;});
                  } else {
                    showSnack(context, L.noSubtitleLoaded, color: Colors.orange);
                  }
                  break;
                case 'settings':
                  showModalBottomSheet(
                    context:context,isScrollControlled:true,backgroundColor:const Color(0xFF1C1C22),
                    shape:const RoundedRectangleBorder(borderRadius:BorderRadius.vertical(top:Radius.circular(20))),
                    builder:(ctx)=>PlayerSettings(
                      vs:_vs,onChanged:(vs){setState(()=>_vs=vs);},
                      vs2:_vs2,onChanged2:(vs){setState(()=>_vs2=vs);},
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
                      onEmbeddedSubEnabled:(v){setState((){_embeddedSubEnabled=v;if(!v)_embeddedSubText=null;});
                        if(v&&_subtitleTracks.isNotEmpty)player.setSubtitleTrack(_subtitleTracks.first);},
                      videoWidth:_videoWidth,videoHeight:_videoHeight,
                    ),
                  );
                  break;
                case 'live':
                  if (_liveSubActive) {
                    // نمایش مجدد badge اگه مخفی بود + باز کردن پنل وضعیت
                    setState(()=>_liveBadgeVisible=true);
                    _showLivePanel();
                  } else {
                    LiveSubSheet.show(context, _curPath, _startLiveSub);
                  }
                  break;
              }
            },
            itemBuilder:(_)=>[
              if (_liveSubActive)
                PopupMenuItem(value:'live',child:Row(children:[
                  const Icon(Icons.fiber_smart_record,size:18,color:Colors.red),
                  const SizedBox(width:10),
                  Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                    Text(L.liveRunning),
                    Text('${LiveSubState.chunksDone}/${LiveSubState.chunksTotal}',
                      style:const TextStyle(color:Colors.white54,fontSize:11)),
                  ]),
                ]))
              else
                PopupMenuItem(value:'live',child:Row(children:[
                  Icon(Icons.fiber_smart_record,size:18,color:Colors.red),SizedBox(width:10),Text(L.liveSubtitleSettings),
                ])),
              PopupMenuItem(value:'ai',child:Row(children:[
                Icon(Icons.auto_awesome,size:18,color:Color(0xFF7C3AED)),SizedBox(width:10),Text(L.aiSubtitleOffline),
              ])),
              PopupMenuItem(value:'online',child:Row(children:[
                Icon(Icons.cloud_download_outlined,size:18,color:Color(0xFF7C3AED)),SizedBox(width:10),Text(L.onlineSubtitleLabel),
              ])),
              if(_sub1Path!=null)
                PopupMenuItem(value:'translate',child:Row(children:[
                  Icon(Icons.translate,size:18,color:Color(0xFF7C3AED)),SizedBox(width:10),Text(L.translateSub),
                ])),
                PopupMenuItem(value:'lyrics',child:Row(children:[
                  Icon(Icons.music_note_rounded,size:18,color:Color(0xFFEC4899)),SizedBox(width:10),Text(L.musicSubtitle),
                ])),
              PopupMenuItem(value:'settings',child:Row(children:[
                Icon(Icons.tune,size:18,color:Colors.white70),SizedBox(width:10),Text(L.subtitleSettings),
              ])),
            ],
          ),
          IconButton(icon:const Icon(Icons.picture_in_picture_rounded),
              tooltip:'PiP',onPressed:_enterPip),
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
              PopupMenuItem(value:'fit',child:Text('${L.ratio}: ${_fit==BoxFit.contain?L.fit:_fit==BoxFit.cover?L.fill:L.stretch}')),
              PopupMenuItem(value:'rotate',child:Text('${L.rotate}: ${_rotationDeg.toInt()}°')),
              PopupMenuItem(value:'repeat',child:Text('${L.repeat}: ${_repeatMode==_Repeat.none?"off":_repeatMode==_Repeat.all?"all":"one"}')),
              PopupMenuItem(value:'night',child:Text(_vs.nightOpacity>0?L.disableNightMode:L.nightMode)),
              PopupMenuItem(value:'mute',child:Text(_muted?L.unmute:L.mute)),
              PopupMenuItem(value:'embsub',child:Text(L.embeddedSubtitle)),
              PopupMenuItem(value:'audio',child:Text(L.audioTracks)),
              PopupMenuItem(value:'sleep',child:Text(L.sleepTimer)),
              PopupMenuItem(value:'screenshot',child:Text(L.screenshot)),
              PopupMenuItem(value:'copy',child:Text(L.copySub)),
              PopupMenuItem(value:'info',child:Text(L.videoInfo)),
              PopupMenuItem(value:'lock',child:Text(L.lockScreen)),
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
              inactiveTrackColor:Colors.white.withOpacity(0.15),
              thumbColor:Colors.white,
              thumbShape:const RoundSliderThumbShape(enabledThumbRadius:6,elevation:0),
              overlayShape:SliderComponentShape.noOverlay,
              trackHeight:3.0,
            ),
            child:Slider(
              min:0,
              max:_duration.inMilliseconds<=0?1.0:_duration.inMilliseconds.toDouble(),
              value:(_seekDragging?_seekDragMs:_position.inMilliseconds.toDouble())
                  .clamp(0,_duration.inMilliseconds<=0?0:_duration.inMilliseconds.toDouble()),
              onChangeStart:(v){
                _hideTimer?.cancel(); // کنترل‌ها رو نگه دار
                _seekSession++;
                setState((){_seekDragging=true;_seekDragMs=v;_seekThumbData=null;_controlsVisible=true;});
                if(_vs.showSeekPreview)_fetchSeekThumb(v.round(),_seekSession);
              },
              onChanged:(v){
                setState(()=>_seekDragMs=v);
                if(_vs.showSeekPreview){_seekThumbTimer?.cancel();_seekThumbTimer=Timer(const Duration(milliseconds:100),(){final s=_seekSession;_fetchSeekThumb(v.round(),s);});}
              },
              onChangeEnd:(v){
                _seekThumbTimer?.cancel();
                _seekSession++;
                setState((){_seekDragging=false;_seekThumbData=null;});
                player.seek(Duration(milliseconds:v.round()));
                _startHideTimer();
              },
            ))),
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
      GestureDetector(onTap:(){setState((){_repeatA=null;_repeatB=null;_abActive=false;});_showOverlay(L.aToB);},
          child:Container(padding:const EdgeInsets.symmetric(horizontal:8,vertical:4),
              decoration:BoxDecoration(color:Colors.red.withOpacity(0.7),borderRadius:BorderRadius.circular(6)),
              child:const Icon(Icons.clear,size:16))),
    ],
    ...[
      const SizedBox(width:8),
      GestureDetector(
        onTap:()=>_toggleDeeepgram(),
        child:Container(
          padding:const EdgeInsets.symmetric(horizontal:8,vertical:4),
          decoration:BoxDecoration(
            color:_dgActive?Colors.green.withOpacity(0.8):Colors.white12,
            borderRadius:BorderRadius.circular(6),
            border:Border.all(color:_dgActive?Colors.green:Colors.white24)),
          child:Row(mainAxisSize:MainAxisSize.min,children:[
            Icon(Icons.record_voice_over_rounded,size:14,color:_dgActive?Colors.white:Colors.white54),
            const SizedBox(width:4),
            Text('AI',style:TextStyle(fontSize:11,color:_dgActive?Colors.white:Colors.white54,fontWeight:FontWeight.bold)),
          ]))),
    ],
    if(widget.isLive||widget.isOnlineUrl||_curPath.startsWith('http'))...[
      const SizedBox(width:8),
      GestureDetector(
        onTap:()=>_showAiLogDialog(),
        child:Container(
          padding:const EdgeInsets.symmetric(horizontal:8,vertical:4),
          decoration:BoxDecoration(
            color:const Color(0xFF7C3AED).withOpacity(0.3),
            borderRadius:BorderRadius.circular(6),
            border:Border.all(color:const Color(0xFF7C3AED))),
          child:const Row(mainAxisSize:MainAxisSize.min,children:[
            Icon(Icons.bug_report_rounded,size:14,color:Colors.white),
            SizedBox(width:4),
            Text('AI LOG',style:TextStyle(fontSize:11,color:Colors.white,fontWeight:FontWeight.bold)),
          ]))),
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

// ── پنل اطلاعات زیرنویس زنده (bottom sheet با آپدیت زنده) ──
class _LivePanelSheet extends StatefulWidget {
  final VoidCallback onStop, onSkipChunk, onToggleVideo;
  final Stopwatch stopwatch;
  const _LivePanelSheet({required this.onStop, required this.onSkipChunk, required this.onToggleVideo, required this.stopwatch});
  @override State<_LivePanelSheet> createState() => _LivePanelSheetState();
}

class _LivePanelSheetState extends State<_LivePanelSheet> {
  Timer? _t;
  @override void initState() { super.initState(); _t = Timer.periodic(const Duration(seconds:1),(_){ if(mounted) setState((){}); }); }
  @override void dispose() { _t?.cancel(); super.dispose(); }

  String _fmt(int s) => s < 60 ? '${s}s' : '${s~/60}m ${s%60}s';

  @override
  Widget build(BuildContext ctx) {
    final elapsed = widget.stopwatch.elapsed.inSeconds;

    return ValueListenableBuilder<int>(
      valueListenable: LiveSubState.notifier,
      builder: (_, __, ___) {
        final done        = LiveSubState.chunksDone;
        final total       = LiveSubState.chunksTotal;
        final transcribed = LiveSubState.transcribedMs ~/ 1000;
        final totalSec    = LiveSubState.totalMs ~/ 1000;
        final chunkSec    = total > 0 ? (totalSec / total).round() : 30;
        final remaining   = (total - done) * chunkSec;

    return SafeArea(child: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width:40,height:4,margin:const EdgeInsets.only(bottom:14),
          decoration:BoxDecoration(color:Colors.white24,borderRadius:BorderRadius.circular(2))),

        Row(children:[
          const Icon(Icons.fiber_smart_record,color:Colors.red,size:18),
          const SizedBox(width:8),
          Expanded(child:Text(L.liveRunning,style:TextStyle(color:Colors.white,fontSize:15,fontWeight:FontWeight.bold))),
          IconButton(icon:const Icon(Icons.close,color:Colors.white54,size:20),
            onPressed:()=>Navigator.pop(ctx),constraints:const BoxConstraints(),padding:const EdgeInsets.all(4)),
        ]),
        const SizedBox(height:12),
        const Divider(color:Colors.white12),
        const SizedBox(height:12),

        // ── زمان این تکه (ریست میشه) ──
        _row('⏱', '${_fmt(LiveSubState.chunkElapsedSec)}/~${_fmt(chunkSec)}'),
        const SizedBox(height:4),
        LinearProgressIndicator(
          value: chunkSec > 0 ? (LiveSubState.chunkElapsedSec / chunkSec).clamp(0.0,1.0) : 0,
          backgroundColor:Colors.white12, color:Colors.orange),
        const SizedBox(height:10),

        // ── کل زمان (ریست نمیشه) ──
        _row('⏰', _fmt(elapsed)),
        const SizedBox(height:4),
        LinearProgressIndicator(
          value: totalSec>0 ? (transcribed/totalSec).clamp(0.0,1.0) : 0,
          backgroundColor:Colors.white12, color:Colors.red),
        const SizedBox(height:12),

        _row('📊', '${done}/${total}'),
        const SizedBox(height:4),
        _row('🔊', '${_fmt(transcribed)}/${_fmt(totalSec)}'),
        const SizedBox(height:4),
        _row('⏳', '~${_fmt(remaining)}'),
        const SizedBox(height:4),
        _row('🧩', _fmt(LiveSubState.chunkMs ~/ 1000)),
        const SizedBox(height:4),
        _row('🌐', kLanguages[LiveSubState.language] ?? LiveSubState.language),
        const SizedBox(height:4),
        _row('🔗 Overlap', LiveSubState.useOverlap ? L.active : L.disabled),
        const SizedBox(height:16),

        const Divider(color:Colors.white12),
        const SizedBox(height:12),

        Row(children:[
          Expanded(child:OutlinedButton.icon(
            onPressed:widget.onToggleVideo,
            icon:const Icon(Icons.pause,size:16),
            label:Text(L.playPause,style:TextStyle(fontSize:12)),
            style:OutlinedButton.styleFrom(side:const BorderSide(color:Colors.white24)))),
          const SizedBox(width:8),
          Expanded(child:OutlinedButton.icon(
            onPressed:widget.onSkipChunk,
            icon:const Icon(Icons.skip_next,size:16),
            label:Text(L.skipChunk,style:TextStyle(fontSize:12)),
            style:OutlinedButton.styleFrom(side:const BorderSide(color:Colors.orange),foregroundColor:Colors.orange))),
        ]),
        const SizedBox(height:8),

        SizedBox(width:double.infinity,child:FilledButton.icon(
          onPressed:() async {
            final ok = await showDialog<bool>(context:ctx,builder:(_)=>AlertDialog(
              backgroundColor:const Color(0xFF1C1C22),
              title:Text(L.cancelLive,style:TextStyle(color:Colors.white,fontSize:15)),
              content:Text('${_fmt(transcribed)} saved',
                style:const TextStyle(color:Colors.white70,fontSize:12)),
              actions:[
                TextButton(onPressed:()=>Navigator.pop(ctx,false),child:Text(L.continue_)),
                FilledButton(onPressed:()=>Navigator.pop(ctx,true),
                  style:FilledButton.styleFrom(backgroundColor:Colors.red),child:Text(L.cancel)),
              ],
            ));
            if(ok==true) widget.onStop();
          },
          icon:const Icon(Icons.stop,size:16),
          label:Text(L.cancel),
          style:FilledButton.styleFrom(backgroundColor:Colors.red,padding:const EdgeInsets.symmetric(vertical:12)),
        )),
      ]),
    ));
      }, // end ValueListenableBuilder builder
    ); // end ValueListenableBuilder
  }

  Widget _row(String label, String value) => Row(children:[
    Text(label,style:const TextStyle(color:Colors.white60,fontSize:13)),
    const Spacer(),
    Text(value,style:const TextStyle(color:Colors.white,fontSize:13,fontWeight:FontWeight.bold)),
  ]);
}

// ── پنل اطلاعات ترجمه آنلاین (مثل live subtitle panel) ──
class _TranslationInfoPanel extends StatefulWidget {
  final VoidCallback onCancel;
  const _TranslationInfoPanel({required this.onCancel});
  @override State<_TranslationInfoPanel> createState() => _TranslationInfoPanelState();
}

class _TranslationInfoPanelState extends State<_TranslationInfoPanel> {
  Timer? _t;
  @override void initState() { super.initState(); _t = Timer.periodic(const Duration(seconds:1),(_){ if(mounted)setState((){}); }); }
  @override void dispose() { _t?.cancel(); super.dispose(); }

  String _fmt(int s) => s < 60 ? '${s}s' : '${s~/60}m ${s%60}s';

  @override
  Widget build(BuildContext ctx) {
    final done = SrtTranslationServiceStatus.batchDone;
    final total = SrtTranslationServiceStatus.batchTotal;
    final elapsed = SrtTranslationServiceStatus.sw.elapsed.inSeconds;
    final lang = kTranslateLangDisplay[SrtTranslationServiceStatus.targetLang]
      ?? SrtTranslationServiceStatus.targetLang;
    final remaining = total > 0 && done > 0
      ? ((elapsed / done) * (total - done)).round() : 0;

    return SafeArea(child: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width:40,height:4,margin:const EdgeInsets.only(bottom:14),
          decoration:BoxDecoration(color:Colors.white24,borderRadius:BorderRadius.circular(2))),
        Row(children:[
          const Icon(Icons.translate,color:Color(0xFF7C3AED),size:18),
          const SizedBox(width:8),
          Expanded(child:Text(L.translateOnline,style:TextStyle(color:Colors.white,fontSize:15,fontWeight:FontWeight.bold))),
          IconButton(icon:const Icon(Icons.close,color:Colors.white54,size:20),
            onPressed:()=>Navigator.pop(ctx),constraints:const BoxConstraints(),padding:const EdgeInsets.all(4)),
        ]),
        const SizedBox(height:12),
        const Divider(color:Colors.white12),
        const SizedBox(height:12),

        ValueListenableBuilder<int>(
          valueListenable: SrtTranslationServiceStatus.notifier,
          builder:(_,__,___) => Column(children:[
            Row(children:[
              const Icon(Icons.translate,color:Color(0xFF7C3AED),size:14),
              const SizedBox(width:6),
              Text(L.targetLang,style:TextStyle(color:Colors.white60,fontSize:13)),
              Text(lang,style:const TextStyle(color:Colors.white,fontSize:13,fontWeight:FontWeight.bold)),
            ]),
            const SizedBox(height:8),
            _row('⏱', _fmt(elapsed)),
            const SizedBox(height:4),
            _row('📊', '${done}/${total}'),
            const SizedBox(height:4),
            if(remaining>0) _row('⏳','~${_fmt(remaining)}'),
            const SizedBox(height:6),
            LinearProgressIndicator(
              value: total>0 ? (done/total).clamp(0.0,1.0) : null,
              backgroundColor:Colors.white12,color:const Color(0xFF7C3AED)),
            const SizedBox(height:4),
            Text(SrtTranslationServiceStatus.lastStatus,
              style:const TextStyle(color:Colors.white54,fontSize:11)),
          ]),
        ),
        const SizedBox(height:16),
        const Divider(color:Colors.white12),
        const SizedBox(height:12),
        SizedBox(width:double.infinity,child:FilledButton.icon(
          onPressed:widget.onCancel,
          icon:const Icon(Icons.stop,size:16),
          label:Text(L.cancelTranslation),
          style:FilledButton.styleFrom(backgroundColor:Colors.red,padding:const EdgeInsets.symmetric(vertical:12)),
        )),
      ]),
    ));
  }

  Widget _row(String label, String value) => Row(children:[
    Text(label,style:const TextStyle(color:Colors.white60,fontSize:13)),
    const Spacer(),
    Text(value,style:const TextStyle(color:Colors.white,fontSize:13,fontWeight:FontWeight.bold)),
  ]);
}


// ── دیالوگ تنظیمات Vosk ──
class _VoskSettingsDialog extends StatefulWidget {
  @override State<_VoskSettingsDialog> createState() => _VoskSettingsDialogState();
}

class _VoskSettingsDialogState extends State<_VoskSettingsDialog> {
  String _lang = 'fa';
  bool _translate = false;
  String _translateTo = 'fa';
  int _pollMs = 100;
  VoskModel? _selectedModel;
  String _engine = 'vosk'; // vosk, android

  static const _langs = {
    'auto': '🌐 تشخیص خودکار',
    'fa': '🇮🇷 فارسی',
    'en': '🇺🇸 English',
    'ar': '🇸🇦 العربية',
    'zh': '🇨🇳 中文',
    'ru': '🇷🇺 Русский',
    'es': '🇪🇸 Español',
    'fr': '🇫🇷 Français',
    'de': '🇩🇪 Deutsch',
    'tr': '🇹🇷 Türkçe',
    'hi': '🇮🇳 हिन्दी',
    'ja': '🇯🇵 日本語',
    'ko': '🇰🇷 한국어',
    'it': '🇮🇹 Italiano',
    'pt': '🇧🇷 Português',
    'uk': '🇺🇦 Українська',
  };

  static const _transLangs = {
    'fa': '🇮🇷 فارسی',
    'en': '🇺🇸 English',
    'ar': '🇸🇦 العربية',
    'zh-cn': '🇨🇳 中文 (ساده)',
    'zh-tw': '🇹🇼 中文 (سنتی)',
    'ru': '🇷🇺 Русский',
    'es': '🇪🇸 Español',
    'fr': '🇫🇷 Français',
    'de': '🇩🇪 Deutsch',
    'tr': '🇹🇷 Türkçe',
    'hi': '🇮🇳 हिन्दी',
    'ja': '🇯🇵 日本語',
    'ko': '🇰🇷 한국어',
    'it': '🇮🇹 Italiano',
    'pt': '🇧🇷 Português',
    'nl': '🇳🇱 Nederlands',
    'pl': '🇵🇱 Polski',
    'uk': '🇺🇦 Українська',
    'vi': '🇻🇳 Tiếng Việt',
    'id': '🇮🇩 Indonesia',
    'th': '🇹🇭 ภาษาไทย',
    'he': '🇮🇱 עברית',
    'sv': '🇸🇪 Svenska',
    'da': '🇩🇰 Dansk',
    'fi': '🇫🇮 Suomi',
    'no': '🇳🇴 Norsk',
    'cs': '🇨🇿 Čeština',
    'ro': '🇷🇴 Română',
    'hu': '🇭🇺 Magyar',
    'el': '🇬🇷 Ελληνικά',
    'bg': '🇧🇬 Български',
    'hr': '🇭🇷 Hrvatski',
    'sk': '🇸🇰 Slovenčina',
    'lt': '🇱🇹 Lietuvių',
    'lv': '🇱🇻 Latviešu',
    'et': '🇪🇪 Eesti',
    'sl': '🇸🇮 Slovenščina',
    'sr': '🇷🇸 Српски',
    'ca': '🏴 Català',
    'af': '🇿🇦 Afrikaans',
    'sq': '🇦🇱 Shqip',
    'am': '🇪🇹 አማርኛ',
    'az': '🇦🇿 Azərbaycan',
    'eu': '🏴 Euskara',
    'be': '🇧🇾 Беларуская',
    'bn': '🇧🇩 বাংলা',
    'bs': '🇧🇦 Bosanski',
    'ceb': '🇵🇭 Cebuano',
    'ny': '🇲🇼 Chichewa',
    'co': '🏴 Corsu',
    'cy': '🏴󠁧󠁢󠁷󠁬󠁳󠁿 Cymraeg',
    'eo': '🌍 Esperanto',
    'tl': '🇵🇭 Filipino',
    'fy': '🏴 Frysk',
    'gl': '🏴 Galego',
    'ka': '🇬🇪 ქართული',
    'gu': '🇮🇳 ગુજરાતી',
    'ht': '🇭🇹 Kreyòl ayisyen',
    'ha': '🌍 Hausa',
    'haw': '🌺 ʻŌlelo Hawaiʻi',
    'iw': '🇮🇱 עברית (alt)',
    'hmn': '🌏 Hmong',
    'is': '🇮🇸 Íslenska',
    'ig': '🌍 Igbo',
    'ga': '🇮🇪 Gaeilge',
    'jw': '🇮🇩 Jawa',
    'kn': '🇮🇳 ಕನ್ನಡ',
    'kk': '🇰🇿 Қазақ',
    'km': '🇰🇭 ភាសាខ្មែរ',
    'rw': '🇷🇼 Kinyarwanda',
    'ku': '🌍 Kurdî',
    'ky': '🇰🇬 Кыргызча',
    'lo': '🇱🇦 ລາວ',
    'la': '🌍 Latina',
    'lb': '🇱🇺 Lëtzebuergesch',
    'mk': '🇲🇰 Македонски',
    'mg': '🇲🇬 Malagasy',
    'ms': '🇲🇾 Melayu',
    'ml': '🇮🇳 മലയാളം',
    'mt': '🇲🇹 Malti',
    'mi': '🇳🇿 Māori',
    'mr': '🇮🇳 मराठी',
    'mn': '🇲🇳 Монгол',
    'my': '🇲🇲 မြန်မာ',
    'ne': '🇳🇵 नेपाली',
    'ps': '🇦🇫 پښتو',
    'pa': '🇮🇳 ਪੰਜਾਬੀ',
    'sm': '🇼🇸 Samoa',
    'gd': '🏴󠁧󠁢󠁳󠁣󠁴󠁿 Gàidhlig',
    'st': '🇿🇦 Sesotho',
    'sn': '🌍 Shona',
    'sd': '🇵🇰 سنڌي',
    'si': '🇱🇰 සිංහල',
    'so': '🇸🇴 Soomaali',
    'su': '🌏 Sunda',
    'sw': '🌍 Kiswahili',
    'tg': '🇹🇯 Тоҷикӣ',
    'ta': '🇮🇳 தமிழ்',
    'tt': '🇷🇺 Татар',
    'te': '🇮🇳 తెలుగు',
    'ur': '🇵🇰 اردو',
    'ug': '🌏 ئۇيغۇر',
    'uz': '🇺🇿 Ozbek',
    'xh': '🇿🇦 isiXhosa',
    'yi': '🌍 ייִדיש',
    'yo': '🌍 Yorùbá',
    'zu': '🇿🇦 isiZulu',
  };

  @override
  Widget build(BuildContext ctx) => AlertDialog(
    backgroundColor: const Color(0xFF12121C),
    title: const Text('تنظیمات زیرنویس زنده', style: TextStyle(color: Colors.white, fontSize: 15)),
    content: SizedBox(width: 300, child: Column(mainAxisSize: MainAxisSize.min, children: [
      // ── انتخاب موتور ──
      Row(children: [
        Expanded(child: GestureDetector(
          onTap: () => setState(() => _engine = 'vosk'),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: _engine == 'vosk' ? const Color(0xFF7C3AED) : const Color(0xFF1A1A2A),
              borderRadius: BorderRadius.circular(8)),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.memory_rounded, color: _engine=='vosk' ? Colors.white : Colors.white38, size: 16),
              const SizedBox(height: 4),
              Text('Vosk', style: TextStyle(color: _engine=='vosk' ? Colors.white : Colors.white38, fontSize: 11, fontWeight: FontWeight.bold)),
              Text('آفلاین', style: TextStyle(color: _engine=='vosk' ? Colors.white60 : Colors.white24, fontSize: 9)),
            ])))),
        const SizedBox(width: 8),
        Expanded(child: GestureDetector(
          onTap: () => setState(() => _engine = 'android'),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: _engine == 'android' ? const Color(0xFF7C3AED) : const Color(0xFF1A1A2A),
              borderRadius: BorderRadius.circular(8)),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.android_rounded, color: _engine=='android' ? Colors.white : Colors.white38, size: 16),
              const SizedBox(height: 4),
              Text('Android', style: TextStyle(color: _engine=='android' ? Colors.white : Colors.white38, fontSize: 11, fontWeight: FontWeight.bold)),
              Text('آنلاین - بیشتر زبان', style: TextStyle(color: _engine=='android' ? Colors.white60 : Colors.white24, fontSize: 9)),
            ])))),
      ]),
      const SizedBox(height: 14),

      // زبان مبدا
      const Align(alignment: Alignment.centerRight,
        child: Text('زبان صحبت', style: TextStyle(color: Colors.white60, fontSize: 12))),
      const SizedBox(height: 6),
StatefulBuilder(builder: (_, ss2) {
        if (_engine == 'android') {
          // Android STT — همه زبان‌های پشتیبانی شده
          return DropdownButtonFormField<String>(
            value: AndroidSttService.supportedLangs.containsKey(_lang) ? _lang : 'fa',
            dropdownColor: const Color(0xFF1A1A2A),
            decoration: InputDecoration(
              filled: true, fillColor: const Color(0xFF1A1A2A),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
            items: AndroidSttService.supportedLangs.entries.map((e) => DropdownMenuItem(
              value: e.key,
              child: Text(e.value, style: const TextStyle(color: Colors.white, fontSize: 13)))).toList(),
            onChanged: (v) => setState(() => _lang = v!),
          );
        }
        final downloaded = VoskService.downloadedModels
            .where((m) => m.langCode != 'spk').toList();
        final langCodes = downloaded.map((m) => m.langCode).toSet().toList();
        if (downloaded.isEmpty) {
          return Container(padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
            child: const Text('هیچ مدلی دانلود نشده\nبه Settings > Vosk Models برو',
              style: TextStyle(color: Colors.orange, fontSize: 12), textAlign: TextAlign.center));
        }
        // اگه زبان انتخابی دیگه موجود نیست، اولی رو انتخاب کن
        if (!langCodes.contains(_lang)) {
          WidgetsBinding.instance.addPostFrameCallback((_) => ss2(()=> _lang = langCodes.first));
        }
        final modelsForLang = downloaded.where((m) => m.langCode == _lang).toList();
        if (_selectedModel == null || _selectedModel!.langCode != _lang) {
          _selectedModel = modelsForLang.isNotEmpty ? modelsForLang.first : null;
        }
        return Column(children: [
          DropdownButtonFormField<String>(
            value: langCodes.contains(_lang) ? _lang : langCodes.first,
            dropdownColor: const Color(0xFF1A1A2A),
            decoration: InputDecoration(filled: true, fillColor: const Color(0xFF1A1A2A),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
            items: langCodes.map((code) {
              final models = downloaded.where((m) => m.langCode == code).toList();
              final name = models.first.name.split(' ').first;
              return DropdownMenuItem(value: code,
                child: Text('$name ($code)', style: const TextStyle(color: Colors.white, fontSize: 13)));
            }).toList(),
            onChanged: (v) => ss2(() { _lang = v!; _selectedModel = null; }),
          ),
          if (modelsForLang.length > 1) ...[
            const SizedBox(height: 8),
            const Align(alignment: Alignment.centerRight,
              child: Text('انتخاب مدل', style: TextStyle(color: Colors.white60, fontSize: 12))),
            const SizedBox(height: 6),
            DropdownButtonFormField<VoskModel>(
              value: _selectedModel,
              dropdownColor: const Color(0xFF1A1A2A),
              decoration: InputDecoration(filled: true, fillColor: const Color(0xFF1A1A2A),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
              items: modelsForLang.map((m) => DropdownMenuItem(value: m,
                child: Text('${m.isLarge ? "Large" : "Small"} — ${m.size}',
                  style: const TextStyle(color: Colors.white, fontSize: 13)))).toList(),
              onChanged: (v) => ss2(() => _selectedModel = v),
            ),
          ],
        ]);
      }),
      const SizedBox(height: 16),

      Row(children: [
        const Expanded(child: Text('ترجمه real-time', style: TextStyle(color: Colors.white, fontSize: 13))),
        Switch(value: _translate, onChanged: (v) => setState(() => _translate = v),
          activeColor: const Color(0xFF7C3AED)),
      ]),

      // سرعت polling
      const SizedBox(height: 12),
      const Align(alignment: Alignment.centerRight,
        child: Text('سرعت بروزرسانی', style: TextStyle(color: Colors.white60, fontSize: 12))),
      const SizedBox(height: 6),
      DropdownButtonFormField<int>(
        value: _pollMs,
        dropdownColor: const Color(0xFF1A1A2A),
        decoration: InputDecoration(
          filled: true, fillColor: const Color(0xFF1A1A2A),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
        items: const [
          DropdownMenuItem(value: 50,  child: Text('50ms — بیشترین سرعت',  style: TextStyle(color: Colors.white, fontSize: 13))),
          DropdownMenuItem(value: 100, child: Text('100ms — سریع (پیش‌فرض)', style: TextStyle(color: Colors.white, fontSize: 13))),
          DropdownMenuItem(value: 200, child: Text('200ms — متوسط',         style: TextStyle(color: Colors.white, fontSize: 13))),
          DropdownMenuItem(value: 300, child: Text('300ms — آرام',           style: TextStyle(color: Colors.white, fontSize: 13))),
          DropdownMenuItem(value: 500, child: Text('500ms — کمترین باری',   style: TextStyle(color: Colors.white, fontSize: 13))),
        ],
        onChanged: (v) => setState(() => _pollMs = v!),
      ),
      const SizedBox(height: 12),

      // ترجمه toggle
      Row(children: [
        const Expanded(child: Text('ترجمه real-time', style: TextStyle(color: Colors.white, fontSize: 13))),
        Switch(value: _translate, onChanged: (v) => setState(() => _translate = v),
          activeColor: const Color(0xFF7C3AED)),
      ]),

      if (_translate) ...[
        const SizedBox(height: 8),
        const Align(alignment: Alignment.centerRight,
          child: Text('ترجمه به', style: TextStyle(color: Colors.white60, fontSize: 12))),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          value: _translateTo,
          dropdownColor: const Color(0xFF1A1A2A),
          decoration: InputDecoration(
            filled: true, fillColor: const Color(0xFF1A1A2A),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
          items: _transLangs.entries.map((e) => DropdownMenuItem(
            value: e.key,
            child: Text(e.value, style: const TextStyle(color: Colors.white, fontSize: 13)))).toList(),
          onChanged: (v) => setState(() => _translateTo = v!),
        ),
      ],
    ])),
    actions: [
      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('لغو')),
      FilledButton(
        style: FilledButton.styleFrom(backgroundColor: const Color(0xFF7C3AED)),
        onPressed: () => Navigator.pop(ctx, {
          'lang': _lang == 'auto' ? 'multi' : _lang,
          'translate': _translate,
          'translateTo': _translateTo,
          'pollMs': _pollMs,
          'modelId': _selectedModel?.id,
          'engine': _engine,
        }),
        child: const Text('شروع')),
    ],
  );
}

class _SrtEntry {
  final int idx;
  final Duration start, end;
  final String text;
  _SrtEntry(this.idx, this.start, this.end, this.text);

  String toSrt() {
    String _fmt(Duration d) {
      final h = d.inHours.toString().padLeft(2,'0');
      final m = (d.inMinutes % 60).toString().padLeft(2,'0');
      final s = (d.inSeconds % 60).toString().padLeft(2,'0');
      final ms = (d.inMilliseconds % 1000).toString().padLeft(3,'0');
      return '$h:$m:$s,$ms';
    }
    return '$idx\n${_fmt(start)} --> ${_fmt(end)}\n$text\n';
  }
}
