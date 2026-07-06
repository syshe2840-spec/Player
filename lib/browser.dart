// lib/browser.dart — مرورگر فایل حرفه‌ای
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path/path.dart' as p;
import 'store.dart';
import 'ai_models_screen.dart';
import 'api_service.dart';
import 'online_player_sheet.dart';
import 'ytdlp_service.dart';
import 'settings.dart' show ToolsTabBody;
import 'package:url_launcher/url_launcher.dart' as ul;
import 'player.dart';

const kBg      = Color(0xFF08080F);
const kSurface = Color(0xFF0D0D1E);
const kCard    = Color(0xFF12122A);
const kBorder  = Color(0xFF232350);
const kAccent  = Color(0xFF7C3AED);
const kCyan    = Color(0xFF0EA5E9);
const kGreen   = Color(0xFF10B981);
const kAmber   = Color(0xFFF59E0B);
const kRed     = Color(0xFFEF4444);
const kPink    = Color(0xFFEC4899);
const kTextSec = Color(0xFF94A3B8);
const kTextDim = Color(0xFF64748B);

enum _SortBy{name,date,size,type}

LinearGradient _extGrad(String ext){
  switch(ext){
    case 'mp4': return const LinearGradient(colors:[Color(0xFF7C3AED),Color(0xFF4F46E5)]);
    case 'mkv': return const LinearGradient(colors:[Color(0xFF0EA5E9),Color(0xFF0284C7)]);
    case 'avi': return const LinearGradient(colors:[Color(0xFF10B981),Color(0xFF059669)]);
    case 'mov': return const LinearGradient(colors:[Color(0xFFEC4899),Color(0xFFBE185D)]);
    case 'webm':return const LinearGradient(colors:[Color(0xFFF59E0B),Color(0xFFD97706)]);
    case 'flv': return const LinearGradient(colors:[Color(0xFFEF4444),Color(0xFFDC2626)]);
    default:    return const LinearGradient(colors:[Color(0xFF6366F1),Color(0xFF4338CA)]);
  }
}

Widget _badge(String text,Color color)=>Container(
  padding:const EdgeInsets.symmetric(horizontal:6,vertical:2),
  decoration:BoxDecoration(color:color.withOpacity(0.12),borderRadius:BorderRadius.circular(5),
      border:Border.all(color:color.withOpacity(0.35),width:0.7)),
  child:Text(text,style:TextStyle(fontSize:10,color:color,fontWeight:FontWeight.w600,height:1.2)),
);

// ── کش thumbnail با MethodChannel → MediaMetadataRetriever ──
final Map<String,Uint8List?> _thumbCache={};
const _thumbChannel=MethodChannel('ir.subteam.subtitle_player/thumbnail');
Future<Uint8List?> _loadThumb(String path)async{
  if(_thumbCache.containsKey(path))return _thumbCache[path];
  try{
    final data=await _thumbChannel.invokeMethod<Uint8List>('getThumbnail',{'path':path,'timeMs':2000,'width':160,'height':90});
    return _thumbCache[path]=data;
  }catch(_){return _thumbCache[path]=null;}
}

// ─────────────────────────────────────────────────────────────────────────────
class BrowserScreen extends StatefulWidget{
  const BrowserScreen({super.key});
  @override State<BrowserScreen> createState()=>_BrowserState();
}

class _BrowserState extends State<BrowserScreen> with TickerProviderStateMixin{
  static const root='/storage/emulated/0';
  bool _granted=false,_checking=true;
  String _path=root;
  List<Directory> _dirs=[];
  List<File> _videos=[];
  bool _selectMode=false;
  final Set<String> _selected={};
  _SortBy _sortBy=_SortBy.name;
  bool _sortDesc=false;
  bool _searching=false;
  // جستجو: false=عادی، true=بازگشتی در کل حافظه
  bool _globalSearch=false;
  String _searchQuery='';
  List<File> _searchResults=[];
  bool _searchRunning=false;
  final TextEditingController _searchCtrl=TextEditingController();

  @override void initState(){super.initState();_init();}
  @override void dispose(){_searchCtrl.dispose();super.dispose();}

  Future<void> _init()async{await Store.load();await _ensurePermission();}

  Future<void> _ensurePermission()async{
    setState(()=>_checking=true);
    var ok=await Permission.manageExternalStorage.isGranted;
    if(!ok)ok=(await Permission.manageExternalStorage.request()).isGranted;
    if(!ok)ok=(await Permission.storage.request()).isGranted;
    setState((){_granted=ok;_checking=false;});
    if(ok)_loadDir(_path);
  }

  void _loadDir(String path){
    try{
      final items=Directory(path).listSync(followLinks:false);
      final dirs=items.whereType<Directory>().toList();
      final vids=items.whereType<File>().where(
          (f)=>kVideoExt.contains(p.extension(f.path).toLowerCase())).toList();
      dirs.sort((a,b)=>p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase()));
      setState((){_path=path;_dirs=dirs;_videos=vids;_selectMode=false;
        _selected.clear();_searching=false;_searchQuery='';_searchCtrl.clear();
        _searchResults=[];_globalSearch=false;});
    }catch(_){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('دسترسی ندارید')));
    }
  }
  void _goUp(){final par=p.dirname(_path);if(par!=_path&&par.startsWith('/storage'))_loadDir(par);}

  int _sd(int v)=>_sortDesc?-v:v;
  List<File> get _sortedVideos{
    final s=List<File>.from(_videos);
    switch(_sortBy){
      case _SortBy.name:s.sort((a,b)=>_sd(p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase())));break;
      case _SortBy.date:s.sort((a,b){try{return _sd(a.lastModifiedSync().compareTo(b.lastModifiedSync()));}catch(_){return 0;}});break;
      case _SortBy.size:s.sort((a,b){try{return _sd(a.lengthSync().compareTo(b.lengthSync()));}catch(_){return 0;}});break;
      case _SortBy.type:s.sort((a,b)=>_sd(p.extension(a.path).compareTo(p.extension(b.path))));break;
    }
    return s;
  }
  List<File> get _filteredVideos{
    if(!_searching||_searchQuery.isEmpty)return _sortedVideos;
    if(_globalSearch)return _searchResults;
    return _sortedVideos.where((f)=>p.basename(f.path).toLowerCase().contains(_searchQuery.toLowerCase())).toList();
  }
  List<Directory> get _filteredDirs{
    if(!_searching||_searchQuery.isEmpty||_globalSearch)return _globalSearch?[]:_dirs;
    return _dirs.where((d)=>p.basename(d.path).toLowerCase().contains(_searchQuery.toLowerCase())).toList();
  }

  // جستجوی سراسری — recursion دستی تا پوشه‌های ممنوع skip بشن
  Future<void> _runGlobalSearch(String query)async{
    if(query.isEmpty){setState((){_searchResults=[];_searchRunning=false;});return;}
    setState((){_searchResults=[];_searchRunning=true;});
    final results=<File>[];
    final q=query.toLowerCase();
    // شروع از ریشه کل حافظه
    await _deepSearch(Directory(root),q,results);
    // اگه SD card داشت اونم بگرده
    for(final d in _getStorageDevices()){
      if(mounted&&_searchRunning)await _deepSearch(d,q,results);
    }
    if(mounted)setState(()=>_searchRunning=false);
  }

  Future<void> _deepSearch(Directory dir,String query,List<File> results)async{
    if(!mounted||!_searchRunning)return;
    List<FileSystemEntity> entities;
    try{entities=await dir.list(recursive:false).toList();}catch(_){return;}
    for(final e in entities){
      if(!mounted||!_searchRunning)return;
      if(e is File){
        if(kVideoExt.contains(p.extension(e.path).toLowerCase())&&
            p.basename(e.path).toLowerCase().contains(query)){
          results.add(e);
          if(mounted)setState(()=>_searchResults=List.from(results));
        }
      }else if(e is Directory){
        // skip پوشه‌های سیستمی
        final name=p.basename(e.path);
        if(!name.startsWith('.')&&name!='proc'&&name!='sys'&&name!='dev'){
          await _deepSearch(e,query,results);
        }
      }
    }
  }

  Future<void> _openVideo(File video,[List<File>?playlist,int?idx])async{
    final pl=playlist??_filteredVideos;
    final i=idx??pl.indexOf(video);
    await Navigator.push(context,MaterialPageRoute(
      builder:(_)=>PlayerScreen(subtitlePath:matchSubtitle(video.path),playlist:pl,playlistIndex:i<0?0:i),
    ));
    await Store.load();
    if(mounted)setState((){});
  }

  Future<void> _openVideoByPath(String path)async{
    final f=File(path);
    if(!f.existsSync()){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('فایل یافت نشد')));return;}
    await _openVideo(f,[f],0);
  }

  List<Directory> _getStorageDevices(){
    final r=<Directory>[];
    try{for(final e in Directory('/storage').listSync()){
      if(e is Directory&&p.basename(e.path)!='emulated'&&p.basename(e.path)!='self')r.add(e);
    }}catch(_){}
    return r;
  }

  void _showVideoMenu(File f){
    showModalBottomSheet(
      context:context,backgroundColor:kSurface,
      shape:const RoundedRectangleBorder(borderRadius:BorderRadius.vertical(top:Radius.circular(24))),
      builder:(ctx)=>VideoMenu(
        file:f,
        onDone:()async{Navigator.pop(ctx);await Store.load();_loadDir(_path);},
        onInfo:(){Navigator.pop(ctx);_showFileInfo(f);},
        onDelete:(){Navigator.pop(ctx);_confirmDelete([f]);},
        onRename:(){Navigator.pop(ctx);_renameFile(f);},
        onSelect:(){Navigator.pop(ctx);setState((){_selectMode=true;_selected.add(f.path);});},
        onCopy:(){Navigator.pop(ctx);_copyFile(f);},
        onMove:(){Navigator.pop(ctx);_moveFile(f);},
        onRate:(){Navigator.pop(ctx);_showRating(f);},
        onNote:(){Navigator.pop(ctx);_showNote(f);},
      ),
    );
  }

  Future<void> _copyFile(File f)async{
    if(Store.savedFolders.isEmpty){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('ابتدا یک پوشه را ذخیره کنید')));return;}
    final dest=await _pickFolder('کپی به');
    if(dest==null)return;
    try{await f.copy(p.join(dest,p.basename(f.path)));
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('کپی شد به ${p.basename(dest)}')));}
    catch(_){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('خطا')));}
  }

  Future<void> _moveFile(File f)async{
    final dest=await _pickFolder('انتقال به');if(dest==null)return;
    final newPath=p.join(dest,p.basename(f.path));
    try{await f.rename(newPath);}
    catch(_){try{await f.copy(newPath);await f.delete();}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('خطا')));return;}}
    _loadDir(_path);
  }

  Future<String?> _pickFolder(String title)async{
    final all=[...Store.savedFolders];
    if(all.isEmpty){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('ابتدا یک پوشه را ذخیره کنید')));return null;}
    return showDialog<String>(context:context,builder:(ctx)=>AlertDialog(
      title:Text(title),
      content:Column(mainAxisSize:MainAxisSize.min,children:all.map((folder)=>ListTile(
        leading:const Icon(Icons.folder,color:kAmber),title:Text(p.basename(folder)),
        onTap:()=>Navigator.pop(ctx,folder),
      )).toList()),
    ));
  }

  Future<void> _confirmDelete(List<File> files)async{
    final ok=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
      title:const Text('حذف فایل'),
      content:Text(files.length==1?'«${p.basename(files.first.path)}» حذف شود؟':'${files.length} فایل حذف شود؟'),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('لغو')),
        FilledButton(style:FilledButton.styleFrom(backgroundColor:kRed),onPressed:()=>Navigator.pop(ctx,true),child:const Text('حذف')),
      ],
    ));
    if(ok!=true)return;
    for(final f in files){try{await f.delete();}catch(_){}}
    _loadDir(_path);
  }

  Future<void> _renameFile(File f)async{
    final ctrl=TextEditingController(text:p.basenameWithoutExtension(f.path));
    final name=await showDialog<String>(context:context,builder:(ctx)=>AlertDialog(
      title:const Text('تغییر نام'),
      content:TextField(controller:ctrl,autofocus:true,
          decoration:const InputDecoration(hintText:'نام جدید',border:OutlineInputBorder(),contentPadding:EdgeInsets.symmetric(horizontal:12,vertical:8))),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('لغو')),
        FilledButton(onPressed:()=>Navigator.pop(ctx,ctrl.text.trim()),child:const Text('تأیید')),
      ],
    ));
    if(name==null||name.isEmpty)return;
    try{await f.rename(p.join(p.dirname(f.path),'$name${p.extension(f.path)}'));_loadDir(_path);}
    catch(_){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('خطا')));}
  }

  Future<void> _showRating(File f)async{
    int rating=Store.ratings[f.path]??0;
    await showDialog(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,ss)=>AlertDialog(
      title:Text(p.basename(f.path),style:const TextStyle(fontSize:13)),
      content:Column(mainAxisSize:MainAxisSize.min,children:[
        const Text('امتیاز شما:',style:TextStyle(color:kTextSec)),const SizedBox(height:12),
        Row(mainAxisAlignment:MainAxisAlignment.center,children:List.generate(5,(i)=>GestureDetector(
          onTap:()=>ss(()=>rating=i+1),
          child:Padding(padding:const EdgeInsets.all(4),
              child:Icon(i<rating?Icons.star_rounded:Icons.star_outline_rounded,color:kAmber,size:36)),
        ))),
      ]),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('لغو')),
        if(rating>0)TextButton(onPressed:()async{await Store.saveRating(f.path,0);Navigator.pop(ctx);setState((){});},child:const Text('حذف',style:TextStyle(color:kRed))),
        FilledButton(onPressed:()async{await Store.saveRating(f.path,rating);Navigator.pop(ctx);setState((){});},child:const Text('ذخیره')),
      ],
    )));
  }

  Future<void> _showNote(File f)async{
    final ctrl=TextEditingController(text:Store.notes[f.path]??'');
    await showDialog(context:context,builder:(ctx)=>AlertDialog(
      title:const Text('یادداشت'),
      content:TextField(controller:ctrl,maxLines:5,autofocus:true,
          decoration:const InputDecoration(hintText:'یادداشت خود را بنویسید...',border:OutlineInputBorder(),contentPadding:EdgeInsets.all(12))),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('لغو')),
        FilledButton(onPressed:()async{await Store.saveNote(f.path,ctrl.text.trim());Navigator.pop(ctx);setState((){});},child:const Text('ذخیره')),
      ],
    ));
  }

  Future<void> _showFileInfo(File f)async{
    final sub=matchSubtitle(f.path);
    final allSubs=findAllSubtitles(f.path);
    String modified='';
    try{modified=f.lastModifiedSync().toString().split('.').first;}catch(_){}
    final dur=await Store.getDur(f.path);
    final rating=Store.ratings[f.path]??0;
    final note=Store.notes[f.path]??'';
    int fileSize=0;try{fileSize=f.lengthSync();}catch(_){}
    final ext=p.extension(f.path).toLowerCase().replaceAll('.','');
    // اطلاعات فرمت از پسوند
    final String codecHint=_codecHint(ext);
    if(!mounted)return;
    showDialog(context:context,builder:(ctx)=>AlertDialog(
      contentPadding:const EdgeInsets.fromLTRB(16,16,16,8),
      title:Row(children:[
        Container(width:4,height:20,decoration:BoxDecoration(color:kAccent,borderRadius:BorderRadius.circular(2))),
        const SizedBox(width:8),
        Expanded(child:Text(p.basename(f.path),style:const TextStyle(fontSize:13,fontWeight:FontWeight.w600))),
      ]),
      content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
        _iRow(Icons.folder_outlined,kTextSec,'مسیر',p.dirname(f.path)),
        _iRow(Icons.video_file_rounded,kCyan,'فرمت',ext.toUpperCase()),
        _iRow(Icons.data_usage_outlined,kTextSec,'حجم',sizeStr(f)),
        if(fileSize>0)_iRow(Icons.straighten_rounded,kTextSec,'دقیق','${fileSize} bytes'),
        if(dur>0)_iRow(Icons.timer_outlined,kCyan,'مدت',fmt(Duration(seconds:dur))),
        _iRow(Icons.calendar_today_outlined,kTextSec,'تاریخ',modified),
        _iRow(Icons.info_outline_rounded,kAccent,'کدک احتمالی',codecHint),
        _iRow(Icons.visibility_outlined,Store.watched.contains(f.path)?kGreen:kTextSec,
            'وضعیت',Store.watched.contains(f.path)?'دیده شده ✓':'دیده نشده'),
        if(rating>0)_iRow(Icons.star_rounded,kAmber,'امتیاز','${'★'*rating}${'☆'*(5-rating)}'),
        if(note.isNotEmpty)_iRow(Icons.notes_rounded,kTextSec,'یادداشت',note),
        if(allSubs.isNotEmpty)...[
          _iRow(Icons.subtitles_rounded,kGreen,'زیرنویس‌ها','${allSubs.length} فایل'),
          ...allSubs.map((s)=>Padding(
            padding:const EdgeInsets.only(right:24,top:2),
            child:Row(children:[
              Icon(Icons.fiber_manual_record_rounded,size:8,color:kGreen.withOpacity(0.6)),
              const SizedBox(width:6),
              Expanded(child:Text(p.basename(s),style:const TextStyle(fontSize:11,color:kTextSec))),
            ]),
          )),
        ]else _iRow(Icons.subtitles_off_rounded,kTextDim,'زیرنویس','یافت نشد'),
      ])),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('بستن'))],
    ));
  }

  // کدک احتمالی بر اساس پسوند
  String _codecHint(String ext){
    switch(ext){
      case 'mp4': return 'H.264/H.265 (MPEG-4)';
      case 'mkv': return 'H.264/H.265/AV1 (Matroska)';
      case 'avi': return 'DivX/Xvid/MPEG-4';
      case 'mov': return 'H.264/ProRes (QuickTime)';
      case 'webm': return 'VP8/VP9/AV1';
      case 'flv': return 'H.263/H.264 (Flash)';
      case 'ts': return 'H.264/MPEG-2 (Transport Stream)';
      case 'wmv': return 'WMV/VC-1';
      case 'mpg': case 'mpeg': return 'MPEG-1/MPEG-2';
      case 'm4v': return 'H.264 (iTunes Video)';
      default: return ext.toUpperCase();
    }
  }

  Widget _iRow(IconData icon,Color iconColor,String label,String val)=>Padding(
    padding:const EdgeInsets.symmetric(vertical:4),
    child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Container(padding:const EdgeInsets.all(4),decoration:BoxDecoration(color:iconColor.withOpacity(0.1),borderRadius:BorderRadius.circular(5)),
          child:Icon(icon,size:12,color:iconColor)),
      const SizedBox(width:8),
      Text('$label: ',style:const TextStyle(color:kTextSec,fontSize:12)),
      Expanded(child:Text(val,style:const TextStyle(fontSize:12,height:1.4),overflow:TextOverflow.ellipsis,maxLines:2)),
    ]),
  );

  @override
  Widget build(BuildContext context){
    final isSaved=Store.savedFolders.contains(_path);
    return PopScope(
      canPop:_path==root&&!_selectMode&&!_searching,
      onPopInvokedWithResult:(didPop,_){
        if(!didPop){
          if(_searching){setState((){_searching=false;_searchQuery='';_searchCtrl.clear();_searchResults=[];_globalSearch=false;});}
          else if(_selectMode){setState((){_selectMode=false;_selected.clear();});}
          else{_goUp();}
        }
      },
      child:Scaffold(
        extendBody:true,
        appBar:_selectMode?_selectBar():_normalBar(isSaved),
        body:_buildBody(),
        floatingActionButtonLocation:FloatingActionButtonLocation.centerFloat,
        floatingActionButton:_selectMode?null:_buildFABs(),
      ),
    );
  }

  Widget _buildFABs()=>ClipRRect(
    borderRadius:BorderRadius.circular(28),
    child:BackdropFilter(
      filter:ImageFilter.blur(sigmaX:20,sigmaY:20),
      child:Container(
        padding:const EdgeInsets.symmetric(horizontal:12,vertical:8),
        decoration:BoxDecoration(color:kSurface.withOpacity(0.85),borderRadius:BorderRadius.circular(28),border:Border.all(color:kBorder.withOpacity(0.7))),
        child:Row(mainAxisSize:MainAxisSize.min,children:[
          _fabBtn(Icons.history_rounded,'تاریخچه',kTextSec,()=>_openPanel(0)),
          const SizedBox(width:4),_fabBtn(Icons.bookmark_rounded,'نشانه‌ها',kAmber,()=>_openPanel(1)),
          const SizedBox(width:4),_fabBtn(Icons.favorite_rounded,'علاقه‌مندی',kPink,()=>_openPanel(2)),
          const SizedBox(width:4),_fabBtn(Icons.push_pin_rounded,'پوشه‌ها',kGreen,()=>_openPanel(3)),
          const SizedBox(width:4),_fabBtn(Icons.tune_rounded,'تنظیمات',kTextSec,()=>_openPanel(4)),
        ]),
      ),
    ),
  );

  Widget _fabBtn(IconData icon,String tip,Color color,VoidCallback fn)=>Tooltip(
    message:tip,
    child:InkWell(onTap:fn,borderRadius:BorderRadius.circular(20),
        child:Padding(padding:const EdgeInsets.all(10),child:Icon(icon,size:22,color:color))),
  );

  PreferredSizeWidget _normalBar(bool isSaved)=>AppBar(
    automaticallyImplyLeading:false,
    leading:_path!=root?IconButton(icon:const Icon(Icons.arrow_back_ios_new_rounded,size:18),onPressed:_goUp):null,
    title:_searching
        ?Row(children:[
            Expanded(child:TextField(controller:_searchCtrl,autofocus:true,
                style:const TextStyle(fontSize:14),
                decoration:InputDecoration(
                  hintText:_globalSearch?'جستجو در کل حافظه...':'جستجو در این پوشه...',
                  border:InputBorder.none,hintStyle:const TextStyle(color:kTextDim,fontSize:13)),
                onChanged:(v){setState(()=>_searchQuery=v);if(_globalSearch)_runGlobalSearch(v);})),
            if(_searchRunning)const SizedBox(width:14,height:14,child:CircularProgressIndicator(strokeWidth:1.5,color:kAccent)),
          ])
        :Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisSize:MainAxisSize.min,children:[
            Text(_path==root?'حافظه داخلی':p.basename(_path),overflow:TextOverflow.ellipsis,
                style:const TextStyle(fontSize:16,fontWeight:FontWeight.w600)),
            if(_path!=root)Text(p.dirname(_path),overflow:TextOverflow.ellipsis,
                style:const TextStyle(fontSize:10,color:kTextDim,height:1.2)),
          ]),
    actions:[
      if(_searching)...[
        // toggle: جستجوی کامل کل حافظه
        GestureDetector(
          onTap:(){
            setState(()=>_globalSearch=!_globalSearch);
            if(_globalSearch&&_searchQuery.isNotEmpty)_runGlobalSearch(_searchQuery);
            else setState(()=>_searchResults=[]);
          },
          child:Container(
            margin:const EdgeInsets.symmetric(vertical:8,horizontal:4),
            padding:const EdgeInsets.symmetric(horizontal:10,vertical:4),
            decoration:BoxDecoration(
              color:_globalSearch?kAccent:kCard,
              borderRadius:BorderRadius.circular(16),
              border:Border.all(color:_globalSearch?kAccent:kBorder),
            ),
            child:Row(mainAxisSize:MainAxisSize.min,children:[
              Icon(Icons.public_rounded,size:13,color:_globalSearch?Colors.white:kTextSec),
              const SizedBox(width:4),
              Text('همه‌جا',style:TextStyle(fontSize:11,color:_globalSearch?Colors.white:kTextSec,fontWeight:FontWeight.w600)),
            ]),
          ),
        ),
      ],
      IconButton(icon:Icon(_searching?Icons.close_rounded:Icons.search_rounded,size:20),
          onPressed:(){setState((){_searching=!_searching;if(!_searching){_searchQuery='';_searchCtrl.clear();_searchResults=[];_globalSearch=false;}});}),
      // دکمه پخش آنلاین
      if(!_searching)IconButton(
        icon:const Icon(Icons.wifi_tethering_rounded,size:20),
        tooltip:'پخش آنلاین',
        onPressed:()=>OnlinePlayerSheet.show(context)),
      if(!_searching)...[
        if(_path!=root)IconButton(
          icon:Icon(isSaved?Icons.push_pin_rounded:Icons.push_pin_outlined,color:isSaved?kAmber:kTextSec,size:20),
          onPressed:()async{await Store.toggleSavedFolder(_path);setState((){});},
        ),
        PopupMenuButton<String>(
          icon:const Icon(Icons.storage_rounded,size:20),
          tooltip:'انتخاب حافظه',
          itemBuilder:(_){
            final items=<PopupMenuEntry<String>>[
              _pmStr(Icons.phone_android_rounded,'/storage/emulated/0','📱 حافظه داخلی'),
              _pmStr(Icons.download_rounded,'/storage/emulated/0/Download','⬇ دانلودها'),
              _pmStr(Icons.movie_rounded,'/storage/emulated/0/Movies','🎬 فیلم‌ها'),
            ];
            for(final d in _getStorageDevices()){items.add(_pmStr(Icons.sd_card_rounded,d.path,'💾 ${p.basename(d.path)}'));}
            items..add(const PopupMenuDivider())..add(_pmStr(Icons.edit_rounded,'__custom__','📂 مسیر دلخواه...'));
            return items;
          },
          onSelected:(v){
            if(v=='__custom__'){
              final ctrl=TextEditingController(text:_path);
              showDialog(context:context,builder:(ctx)=>AlertDialog(
                title:const Text('مسیر دلخواه'),
                content:TextField(controller:ctrl,autofocus:true,
                    decoration:const InputDecoration(hintText:'/storage/emulated/0/...',border:OutlineInputBorder())),
                actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('لغو')),
                  FilledButton(onPressed:(){final pt=ctrl.text.trim();Navigator.pop(ctx);if(pt.isNotEmpty)_loadDir(pt);},child:const Text('برو'))],
              ));
            }else{_loadDir(v);}
          },
        ),
        PopupMenuButton<_SortBy>(
          icon:const Icon(Icons.sort_rounded,size:20),
          onSelected:(v)=>setState((){if(_sortBy==v)_sortDesc=!_sortDesc;else{_sortBy=v;_sortDesc=false;}}),
          itemBuilder:(_)=>[
            _pmSort(_SortBy.name,'نام',Icons.sort_by_alpha_rounded),
            _pmSort(_SortBy.date,'تاریخ',Icons.access_time_rounded),
            _pmSort(_SortBy.size,'حجم',Icons.data_usage_rounded),
            _pmSort(_SortBy.type,'نوع',Icons.video_file_rounded),
          ],
        ),
      ],
    ],
  );

  PopupMenuItem<String> _pmStr(IconData icon,String v,String t)=>PopupMenuItem(value:v,height:40,
      child:Row(children:[Icon(icon,size:16,color:kTextSec),const SizedBox(width:10),Text(t,style:const TextStyle(fontSize:13))]));
  PopupMenuItem<_SortBy> _pmSort(_SortBy v,String t,IconData icon)=>PopupMenuItem(value:v,height:40,
      child:Row(children:[Icon(icon,size:16,color:_sortBy==v?kAccent:kTextSec),const SizedBox(width:10),
        Text('$t${_sortBy==v?(_sortDesc?' ↑':' ↓'):''}',style:TextStyle(fontSize:13,color:_sortBy==v?kAccent:Colors.white))]));

  PreferredSizeWidget _selectBar()=>AppBar(
    automaticallyImplyLeading:false,
    backgroundColor:kAccent.withOpacity(0.15),
    leading:IconButton(icon:const Icon(Icons.close_rounded,size:20),onPressed:()=>setState((){_selectMode=false;_selected.clear();})),
    title:Text('${_selected.length} فایل انتخاب شد',style:const TextStyle(fontSize:15)),
    actions:[
      TextButton.icon(icon:const Icon(Icons.select_all_rounded,size:18),label:const Text('همه',style:TextStyle(fontSize:13)),
          onPressed:()=>setState(()=>_selected.addAll(_filteredVideos.map((v)=>v.path)))),
      IconButton(icon:const Icon(Icons.delete_outline_rounded,color:kRed,size:22),
          onPressed:_selected.isEmpty?null:()=>_confirmDelete(_selected.map((s)=>File(s)).toList())),
    ],
  );

  Widget _buildBody(){
    if(_checking)return const Center(child:CircularProgressIndicator());
    if(!_granted)return Center(child:Padding(padding:const EdgeInsets.all(32),child:Column(mainAxisSize:MainAxisSize.min,children:[
      Container(padding:const EdgeInsets.all(20),decoration:BoxDecoration(color:kCard,borderRadius:BorderRadius.circular(20),border:Border.all(color:kBorder)),
          child:const Icon(Icons.folder_off_rounded,size:48,color:kTextSec)),
      const SizedBox(height:20),
      const Text('اپ به دسترسی فایل‌ها نیاز دارد.',textAlign:TextAlign.center,style:TextStyle(color:kTextSec)),
      const SizedBox(height:20),
      FilledButton.icon(onPressed:_ensurePermission,icon:const Icon(Icons.lock_open_rounded),label:const Text('اجازه دسترسی')),
      const SizedBox(height:8),TextButton(onPressed:openAppSettings,child:const Text('تنظیمات اپ')),
    ])));

    return Column(children:[
      Container(width:double.infinity,padding:const EdgeInsets.symmetric(horizontal:16,vertical:6),color:kSurface,
          child:Row(children:[
            Icon(Icons.folder_open_rounded,size:12,color:kAccent.withOpacity(0.7)),const SizedBox(width:6),
            Expanded(child:Text(_path,style:const TextStyle(fontSize:10,color:kTextDim),overflow:TextOverflow.ellipsis)),
            if(_searchRunning)const SizedBox(width:12,height:12,child:CircularProgressIndicator(strokeWidth:1.5,color:kAccent)),
            if(_globalSearch&&!_searchRunning&&_searchResults.isNotEmpty)
              Text('${_searchResults.length} نتیجه',style:const TextStyle(fontSize:10,color:kAccent)),
          ])),
      Expanded(child:_buildList()),
    ]);
  }

  Widget _buildList(){
    final fDirs=_filteredDirs,fVids=_filteredVideos;
    final total=fDirs.length+fVids.length;
    if(total==0&&_searchRunning)return const Center(child:Column(mainAxisSize:MainAxisSize.min,children:[
      CircularProgressIndicator(),SizedBox(height:16),Text('در حال جستجوی کل حافظه...',style:TextStyle(color:kTextSec)),
    ]));
    if(total==0)return Center(child:Column(mainAxisSize:MainAxisSize.min,children:[
      Icon(Icons.video_library_outlined,size:48,color:kTextDim),const SizedBox(height:12),
      const Text('فایلی یافت نشد',style:TextStyle(color:kTextSec)),
    ]));

    return RefreshIndicator(
      onRefresh:()async{if(!_globalSearch){_loadDir(_path);}else if(_searchQuery.isNotEmpty){_runGlobalSearch(_searchQuery);}},
      color:kAccent,
      backgroundColor:kCard,
      child:ListView.builder(
      physics:const AlwaysScrollableScrollPhysics(),
      padding:EdgeInsets.only(bottom:MediaQuery.of(context).viewPadding.bottom+90,top:8,left:12,right:12),
      itemCount:total,
      itemBuilder:(ctx,i){
        if(i<fDirs.length){
          final d=fDirs[i];
          return _DirTile(dir:d,onTap:()=>_loadDir(d.path));
        }
        final v=fVids[i-fDirs.length];
        return _VideoTile(
          file:v,selectMode:_selectMode,selected:_selected.contains(v.path),
          onTap:_selectMode?()=>setState(()=>_selected.contains(v.path)?_selected.remove(v.path):_selected.add(v.path)):()=>_openVideo(v,fVids,i-fDirs.length),
          onLongPress:_selectMode?null:()=>_showVideoMenu(v),
          showPath:_globalSearch,
        );
      },
    ),);
  }

  void _openPanel(int page){
    showModalBottomSheet(
      context:context,isScrollControlled:true,
      builder:(ctx)=>SizedBox(height:MediaQuery.of(context).size.height*0.65,
          child:BottomPanel(initialPage:page,
              onVideoTap:(path){Navigator.pop(ctx);_openVideoByPath(path);},
              onFolderTap:(folder){Navigator.pop(ctx);_loadDir(folder);})),
    );
  }
}

// ── تایل پوشه ──
class _DirTile extends StatelessWidget{
  final Directory dir;final VoidCallback onTap;
  const _DirTile({required this.dir,required this.onTap});
  @override Widget build(BuildContext context)=>GestureDetector(
    onTap:onTap,
    child:Container(margin:const EdgeInsets.only(bottom:6),padding:const EdgeInsets.symmetric(horizontal:14,vertical:12),
      decoration:BoxDecoration(color:kCard,borderRadius:BorderRadius.circular(12),border:Border.all(color:kBorder.withOpacity(0.6))),
      child:Row(children:[
        Container(width:44,height:44,decoration:BoxDecoration(
          gradient:const LinearGradient(colors:[Color(0xFF92400E),Color(0xFFB45309)],begin:Alignment.topLeft,end:Alignment.bottomRight),
          borderRadius:BorderRadius.circular(10)),
          child:const Icon(Icons.folder_rounded,color:Colors.white,size:22)),
        const SizedBox(width:12),
        Expanded(child:Text(p.basename(dir.path),style:const TextStyle(fontWeight:FontWeight.w500,fontSize:14),maxLines:1,overflow:TextOverflow.ellipsis)),
        const Icon(Icons.chevron_left_rounded,color:kTextDim,size:20),
      ]),
    ),
  );
}

// ── تایل ویدیو با thumbnail ──
class _VideoTile extends StatelessWidget{
  final File file;
  final bool selectMode,selected,showPath;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  const _VideoTile({required this.file,required this.selectMode,required this.selected,required this.onTap,this.onLongPress,this.showPath=false});

  @override Widget build(BuildContext context){
    final name=p.basename(file.path);
    final ext=p.extension(file.path).toLowerCase().replaceAll('.','');
    final seen=Store.watched.contains(file.path);
    final bkm=Store.bookmarked.contains(file.path);
    final fav=Store.favorited.contains(file.path);
    final hasSub=matchSubtitle(file.path)!=null;
    final rating=Store.ratings[file.path]??0;
    final hasNote=Store.notes.containsKey(file.path);
    final grad=_extGrad(ext);
    final dur=Store.getCachedDur(file.path);

    return GestureDetector(
      onTap:onTap,onLongPress:onLongPress,
      child:AnimatedContainer(
        duration:const Duration(milliseconds:150),
        margin:const EdgeInsets.only(bottom:6),
        decoration:BoxDecoration(
          color:selected?kAccent.withOpacity(0.15):kCard,
          borderRadius:BorderRadius.circular(12),
          border:Border.all(color:selected?kAccent.withOpacity(0.5):kBorder.withOpacity(0.6)),
        ),
        child:Padding(
          padding:const EdgeInsets.all(12),
          child:Row(children:[
            // ── پوستر ویدیو (thumbnail) ──
            ClipRRect(
              borderRadius:BorderRadius.circular(10),
              child:selectMode
                  ?AnimatedContainer(duration:const Duration(milliseconds:150),width:48,height:48,
                      decoration:BoxDecoration(color:selected?kAccent:kBorder,borderRadius:BorderRadius.circular(10)),
                      child:Icon(selected?Icons.check_rounded:Icons.circle_outlined,color:Colors.white,size:20))
                  :SizedBox(width:64,height:48,child:FutureBuilder<Uint8List?>(
                      future:_loadThumb(file.path),
                      builder:(ctx,snap){
                        if(snap.hasData&&snap.data!=null){
                          return Stack(fit:StackFit.expand,children:[
                            Image.memory(snap.data!,fit:BoxFit.cover),
                            // overlay: اگه دیده شده
                            if(seen)Container(color:kGreen.withOpacity(0.25),alignment:Alignment.center,
                                child:const Icon(Icons.check_circle_rounded,color:kGreen,size:20)),
                          ]);
                        }
                        // در حال بارگذاری یا خطا: نمایش ext badge
                        return Container(
                          decoration:BoxDecoration(gradient:grad),
                          alignment:Alignment.center,
                          child:snap.connectionState==ConnectionState.waiting
                              ?const SizedBox(width:16,height:16,child:CircularProgressIndicator(strokeWidth:1.5,color:Colors.white38))
                              :Text(ext.length>3?ext.substring(0,3).toUpperCase():ext.toUpperCase(),
                                  style:const TextStyle(fontSize:11,fontWeight:FontWeight.w800,color:Colors.white)),
                        );
                      },
                    )),
            ),
            const SizedBox(width:12),
            // ── اطلاعات ──
            Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Text(name,style:TextStyle(fontSize:14,fontWeight:FontWeight.w500,
                  color:seen?kGreen:Colors.white,height:1.3),maxLines:1,overflow:TextOverflow.ellipsis),
              if(showPath)Text(p.dirname(file.path),style:const TextStyle(fontSize:10,color:kTextDim),maxLines:1,overflow:TextOverflow.ellipsis),
              const SizedBox(height:5),
              Row(children:[
                Text(sizeStr(file),style:const TextStyle(fontSize:11,color:kTextDim)),
                if(dur!=null&&dur>0)...[const Text(' · ',style:TextStyle(fontSize:11,color:kTextDim)),Text(fmt(Duration(seconds:dur)),style:const TextStyle(fontSize:11,color:kTextDim))],
                if(hasSub)...[const SizedBox(width:5),_badge('SUB',kGreen)],
                if(bkm)...[const SizedBox(width:4),_badge('★',kAmber)],
                if(fav)...[const SizedBox(width:4),_badge('❤',kPink)],
                if(hasNote)...[const SizedBox(width:4),_badge('📝',kTextSec)],
                if(rating>0)...[const SizedBox(width:4),Text('${'★'*rating}',style:const TextStyle(fontSize:10,color:kAmber))],
              ]),
            ])),
            // ── دکمه پخش ──
            if(!selectMode)Container(
              width:36,height:36,
              decoration:BoxDecoration(
                color:seen?kGreen.withOpacity(0.15):kAccent.withOpacity(0.1),
                borderRadius:BorderRadius.circular(18),
                border:Border.all(color:seen?kGreen.withOpacity(0.3):kAccent.withOpacity(0.2)),
              ),
              child:Icon(Icons.play_arrow_rounded,color:seen?kGreen:kAccent,size:20),
            ),
          ]),
        ),
      ),
    );
  }
}

// ── منوی ویدیو ──
class VideoMenu extends StatefulWidget{
  final File file;
  final VoidCallback onDone,onInfo,onDelete,onRename,onSelect,onCopy,onMove,onRate,onNote;
  const VideoMenu({super.key,required this.file,required this.onDone,required this.onInfo,required this.onDelete,required this.onRename,required this.onSelect,required this.onCopy,required this.onMove,required this.onRate,required this.onNote});
  @override State<VideoMenu> createState()=>_VideoMenuState();
}
class _VideoMenuState extends State<VideoMenu>{
  late bool _bkm=Store.bookmarked.contains(widget.file.path);
  late bool _fav=Store.favorited.contains(widget.file.path);
  @override Widget build(BuildContext context)=>SafeArea(top:false,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
    const SizedBox(height:12),
    Center(child:Container(width:36,height:4,decoration:BoxDecoration(color:kBorder,borderRadius:BorderRadius.circular(2)))),
    const SizedBox(height:8),
    Padding(padding:const EdgeInsets.symmetric(horizontal:16),child:Row(children:[
      Container(width:40,height:40,decoration:BoxDecoration(color:kCard,borderRadius:BorderRadius.circular(10),border:Border.all(color:kBorder)),
          child:const Icon(Icons.video_file_rounded,color:kAccent,size:20)),
      const SizedBox(width:12),
      Expanded(child:Text(p.basename(widget.file.path),style:const TextStyle(fontWeight:FontWeight.w600,fontSize:13),maxLines:2)),
    ])),
    const SizedBox(height:8),const Divider(height:1),
    _mi(Icons.info_outline_rounded,kTextSec,'اطلاعات فایل',widget.onInfo),
    _mi2(Icons.bookmark_rounded,_bkm?kAmber:kTextSec,_bkm?'حذف نشانه':'نشانه‌گذاری',()async{await Store.toggleBookmark(widget.file.path);setState(()=>_bkm=!_bkm);widget.onDone();}),
    _mi2(Icons.favorite_rounded,_fav?kPink:kTextSec,_fav?'حذف از علاقه‌مندی':'علاقه‌مندی',()async{await Store.toggleFavorite(widget.file.path);setState(()=>_fav=!_fav);widget.onDone();}),
    _mi(Icons.star_outline_rounded,kAmber,'امتیازدهی',widget.onRate),
    _mi(Icons.notes_rounded,kTextSec,'یادداشت',widget.onNote),
    const Divider(height:1),
    _mi(Icons.queue_music_rounded,kCyan,'افزودن به پلی‌لیست',()async{
      final playlists=Store.playlists.keys.toList();
      if(playlists.isEmpty){
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('ابتدا یک پلی‌لیست بسازید')));
        return;
      }
      final name=await showDialog<String>(context:context,builder:(ctx)=>AlertDialog(
        title:const Text('انتخاب پلی‌لیست'),
        content:Column(mainAxisSize:MainAxisSize.min,children:playlists.map((pl)=>ListTile(
          dense:true,leading:const Icon(Icons.queue_music_rounded,color:kCyan,size:18),
          title:Text(pl,style:const TextStyle(fontSize:13)),
          onTap:()=>Navigator.pop(ctx,pl))).toList()),
        actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('لغو'))],
      ));
      if(name!=null){
        await Store.addToPlaylist(name,widget.file.path);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('اضافه شد به «$name»')));
      }
    }),
    _mi(Icons.copy_rounded,kTextSec,'کپی به پوشه',widget.onCopy),
    _mi(Icons.drive_file_move_outline,kTextSec,'انتقال',widget.onMove),
    _mi(Icons.edit_rounded,kTextSec,'تغییر نام',widget.onRename),
    _mi(Icons.select_all_rounded,kTextSec,'انتخاب گروهی',widget.onSelect),
    _mi(Icons.delete_outline_rounded,kRed,'حذف',widget.onDelete),
    const SizedBox(height:8),
  ])));
  Widget _mi(IconData icon,Color iconColor,String title,VoidCallback onTap)=>ListTile(dense:true,
    leading:Container(width:30,height:30,decoration:BoxDecoration(color:iconColor.withOpacity(0.1),borderRadius:BorderRadius.circular(7)),
        child:Icon(icon,color:iconColor,size:15)),
    title:Text(title,style:const TextStyle(fontSize:13)),onTap:onTap);
  Widget _mi2(IconData icon,Color iconColor,String title,VoidCallback onTap)=>_mi(icon,iconColor,title,onTap);
}

// ── پانل شناور ──
class BottomPanel extends StatefulWidget{
  final int initialPage;
  final ValueChanged<String> onVideoTap,onFolderTap;
  const BottomPanel({super.key,required this.initialPage,required this.onVideoTap,required this.onFolderTap});
  @override State<BottomPanel> createState()=>_BottomPanelState();
}
class _BottomPanelState extends State<BottomPanel> with SingleTickerProviderStateMixin{
  late TabController _tab;
  @override void initState(){super.initState();_tab=TabController(length:8,vsync:this,initialIndex:widget.initialPage.clamp(0,6));}
  @override void dispose(){_tab.dispose();super.dispose();}
  @override Widget build(BuildContext context)=>Column(children:[
    const SizedBox(height:10),
    Center(child:Container(width:36,height:4,decoration:BoxDecoration(color:kBorder,borderRadius:BorderRadius.circular(2)))),
    const SizedBox(height:4),
    TabBar(controller:_tab,isScrollable:true,indicatorColor:kAccent,labelColor:kAccent,unselectedLabelColor:kTextSec,
        labelStyle:const TextStyle(fontSize:12,fontWeight:FontWeight.w600),unselectedLabelStyle:const TextStyle(fontSize:12),
        tabs:const[Tab(icon:Icon(Icons.history_rounded,size:16),text:'تاریخچه'),
          Tab(icon:Icon(Icons.bookmark_rounded,size:16),text:'نشانه‌ها'),
          Tab(icon:Icon(Icons.favorite_rounded,size:16),text:'علاقه‌مندی'),
          Tab(icon:Icon(Icons.push_pin_rounded,size:16),text:'پوشه‌ها'),
          Tab(icon:Icon(Icons.queue_music_rounded,size:16),text:'پلی‌لیست'),
          Tab(icon:Icon(Icons.star_rounded,size:16),text:'اسپانسر'),
          Tab(icon:Icon(Icons.build_rounded,size:16),text:'ابزارها'),
          Tab(icon:Icon(Icons.settings_rounded,size:16),text:'اپ')]),
    Expanded(child:TabBarView(controller:_tab,children:[
      _histTab(),
      _vList(Store.bookmarked.toList().reversed.toList(),Icons.bookmark_rounded,kAmber,
        onRemove:(path)async{await Store.toggleBookmark(path);setState((){}); }),
      _vList(Store.favorited.toList().reversed.toList(),Icons.favorite_rounded,kPink,
        onRemove:(path)async{await Store.toggleFavorite(path);setState((){}); }),
      _folderList(),_playlistTab(),_sponsorTab(),ToolsTabBody(),_settingsTab(),
    ])),
    SizedBox(height:MediaQuery.of(context).viewPadding.bottom),
  ]);

  Widget _histTab()=>Column(children:[
    if(Store.watchHistory.isNotEmpty)Padding(
      padding:const EdgeInsets.symmetric(horizontal:12,vertical:6),
      child:Row(children:[
        const Expanded(child:Text('آخرین مشاهده‌ها',style:TextStyle(fontWeight:FontWeight.w600,fontSize:13))),
        TextButton.icon(icon:const Icon(Icons.delete_sweep_rounded,size:15,color:kRed),label:const Text('حذف همه',style:TextStyle(fontSize:12,color:kRed)),
            onPressed:()async{final ok=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
              title:const Text('حذف همه تاریخچه؟'),
              actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('لغو')),
                FilledButton(style:FilledButton.styleFrom(backgroundColor:kRed),onPressed:()=>Navigator.pop(ctx,true),child:const Text('حذف'))],
            ));if(ok==true){await Store.clearHistory();setState((){});}})
      ])),
    Expanded(child:_vList(Store.watchHistory,Icons.history_rounded,kTextSec,
        onLongPress:(path)async{await Store.removeFromHistory(path);setState((){});})),
  ]);

  Widget _vList(List<String> paths,IconData icon,Color color,{Function(String)?onLongPress, void Function(String)?onRemove}){
    if(paths.isEmpty)return Center(child:Column(mainAxisSize:MainAxisSize.min,children:[
      Container(padding:const EdgeInsets.all(16),decoration:BoxDecoration(color:kCard,borderRadius:BorderRadius.circular(16),border:Border.all(color:kBorder)),
          child:Icon(icon,size:32,color:color.withOpacity(0.4))),
      const SizedBox(height:12),const Text('هنوز چیزی نیست',style:TextStyle(color:kTextSec)),
    ]));
    return ListView.builder(itemCount:paths.length,padding:const EdgeInsets.only(bottom:8),itemBuilder:(_,i){
      final path=paths[i];
      final isUrl = path.startsWith('http://') || path.startsWith('https://');
      final exists = isUrl ? true : File(path).existsSync();
      final displayName = isUrl ? Uri.parse(path).pathSegments.lastWhere((s)=>s.isNotEmpty,orElse:()=>path) : p.basename(path);
      final displaySub = isUrl ? path : p.dirname(path);
      return ListTile(dense:true,
        leading:Container(width:30,height:30,decoration:BoxDecoration(color:color.withOpacity(0.1),borderRadius:BorderRadius.circular(7)),
            child:Icon(isUrl ? Icons.link_rounded : icon,color:exists?color:kTextDim,size:15)),
        title:Text(displayName,maxLines:1,overflow:TextOverflow.ellipsis,
            style:TextStyle(fontSize:13,color:exists?Colors.white:kTextDim)),
        subtitle:Text(displaySub,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:10,color:kTextDim)),
        trailing:onRemove!=null?IconButton(
          icon:const Icon(Icons.close,size:14,color:kRed),
          onPressed:()=>onRemove(path)):null,
        onTap:exists?(){
          if(isUrl) widget.onVideoTap(path);
          else widget.onVideoTap(path);
        }:null,
        onLongPress:(){
          if(isUrl){
            Clipboard.setData(ClipboardData(text:path));
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content:Text('لینک کپی شد'),duration:Duration(seconds:2),backgroundColor:Color(0xFF7C3AED)));
          } else if(onLongPress!=null) onLongPress(path);
        });
    });
  }

  Widget _folderList(){
    final folders=Store.savedFolders;
    if(folders.isEmpty)return Center(child:Column(mainAxisSize:MainAxisSize.min,children:[
      Container(padding:const EdgeInsets.all(16),decoration:BoxDecoration(color:kCard,borderRadius:BorderRadius.circular(16),border:Border.all(color:kBorder)),
          child:const Icon(Icons.push_pin_outlined,size:32,color:kTextDim)),
      const SizedBox(height:12),const Text('پوشه‌ای ذخیره نشده',style:TextStyle(color:kTextSec)),
      const SizedBox(height:6),const Text('در مرورگر آیکون 📌 را بزنید',style:TextStyle(fontSize:11,color:kTextDim)),
    ]));
    return ListView.builder(itemCount:folders.length,itemBuilder:(_,i){
      final folder=folders[i];final exists=Directory(folder).existsSync();
      return ListTile(dense:true,
        leading:Container(width:30,height:30,decoration:BoxDecoration(color:kAmber.withOpacity(0.1),borderRadius:BorderRadius.circular(7)),
            child:Icon(Icons.folder_rounded,color:exists?kAmber:kTextDim,size:15)),
        title:Text(p.basename(folder),maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:13)),
        subtitle:Text(folder,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:10,color:kTextDim)),
        trailing:IconButton(icon:const Icon(Icons.push_pin_rounded,size:14,color:kRed),
            onPressed:()async{await Store.toggleSavedFolder(folder);setState((){});}),
        onTap:exists?()=>widget.onFolderTap(folder):null);
    });
  }

  Widget _playlistTab(){
    final playlists=Store.playlists;
    return Column(children:[
      Padding(padding:const EdgeInsets.symmetric(horizontal:12,vertical:8),
        child:Row(children:[
          const Expanded(child:Text('پلی‌لیست‌ها',style:TextStyle(fontWeight:FontWeight.w600,fontSize:13))),
          FilledButton.icon(
            style:FilledButton.styleFrom(padding:const EdgeInsets.symmetric(horizontal:10),minimumSize:const Size(0,32)),
            icon:const Icon(Icons.add_rounded,size:16),label:const Text('جدید',style:TextStyle(fontSize:12)),
            onPressed:()async{
              final ctrl=TextEditingController();
              final name=await showDialog<String>(context:context,builder:(ctx)=>AlertDialog(
                title:const Text('پلی‌لیست جدید'),
                content:TextField(controller:ctrl,autofocus:true,
                    decoration:const InputDecoration(hintText:'نام پلی‌لیست...',border:OutlineInputBorder())),
                actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('لغو')),
                  FilledButton(onPressed:()=>Navigator.pop(ctx,ctrl.text.trim()),child:const Text('ساخت'))],
              ));
              if(name!=null&&name.isNotEmpty){await Store.createPlaylist(name);setState((){});}
            }),
        ])),
      const Divider(height:1),
      if(playlists.isEmpty)Expanded(child:Center(child:Column(mainAxisSize:MainAxisSize.min,children:[
        Container(padding:const EdgeInsets.all(16),decoration:BoxDecoration(color:kCard,borderRadius:BorderRadius.circular(16),border:Border.all(color:kBorder)),
            child:const Icon(Icons.queue_music_rounded,size:32,color:kTextDim)),
        const SizedBox(height:12),const Text('پلی‌لیستی ندارید',style:TextStyle(color:kTextSec)),
        const SizedBox(height:4),const Text('با دکمه «جدید» بسازید',style:TextStyle(fontSize:11,color:kTextDim)),
      ])))
      else Expanded(child:ListView.builder(itemCount:playlists.keys.length,itemBuilder:(_,i){
        final name=playlists.keys.elementAt(i);
        final paths=playlists[name]!;
        return ListTile(dense:true,
          leading:Container(width:32,height:32,decoration:BoxDecoration(
              gradient:LinearGradient(colors:[kAccent,kCyan]),borderRadius:BorderRadius.circular(8)),
              child:const Icon(Icons.queue_music_rounded,size:16,color:Colors.white)),
          title:Text(name,style:const TextStyle(fontSize:13,fontWeight:FontWeight.w500)),
          subtitle:Text('${paths.length} ویدیو',style:const TextStyle(fontSize:11,color:kTextDim)),
          trailing:PopupMenuButton<String>(
            icon:const Icon(Icons.more_vert_rounded,size:18,color:kTextSec),
            itemBuilder:(_)=>[
              const PopupMenuItem(value:'play',child:Text('پخش',style:TextStyle(fontSize:13))),
              const PopupMenuItem(value:'delete',child:Text('حذف',style:TextStyle(fontSize:13,color:kRed))),
            ],
            onSelected:(v)async{
              if(v=='delete'){
                final ok=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
                  title:Text('حذف «$name»؟'),
                  actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('لغو')),
                    FilledButton(style:FilledButton.styleFrom(backgroundColor:kRed),
                        onPressed:()=>Navigator.pop(ctx,true),child:const Text('حذف'))],
                ));
                if(ok==true){await Store.deletePlaylist(name);setState((){});}
              }else if(v=='play'&&paths.isNotEmpty){
                final files=paths.map((p)=>File(p)).where((f)=>f.existsSync()).toList();
                if(files.isNotEmpty)widget.onVideoTap(files.first.path);
              }
            }),
          onTap:paths.isEmpty?null:(){widget.onVideoTap(paths.first);},
        );
      })),
    ]);
  }

  Widget _sponsorTab(){
    return FutureBuilder<List<Map<String,dynamic>>>(
      future:ApiService.getSponsors(),
      builder:(ctx,snap){
        if(snap.connectionState==ConnectionState.waiting)
          return const Center(child:CircularProgressIndicator());
        final list=snap.data??[];
        if(list.isEmpty)return Center(child:Column(mainAxisSize:MainAxisSize.min,children:[
          Container(padding:const EdgeInsets.all(16),
            decoration:BoxDecoration(color:kCard,borderRadius:BorderRadius.circular(16),border:Border.all(color:kBorder)),
            child:const Icon(Icons.star_rounded,size:32,color:kTextDim)),
          const SizedBox(height:12),
          const Text('هنوز اسپانسری نیست',style:TextStyle(color:kTextSec)),
        ]));
        return ListView.builder(
          padding:const EdgeInsets.all(12),
          itemCount:list.length,
          itemBuilder:(_,i){
            final s=list[i];
            final isFemale=(s['gender']??'male')=='female';
            return Card(
              color:kCard,
              margin:const EdgeInsets.only(bottom:12),
              shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(16),
                side:const BorderSide(color:kBorder,width:0.5)),
              child:Padding(padding:const EdgeInsets.all(16),child:Row(children:[
                // آواتار
                Container(width:56,height:56,
                  decoration:BoxDecoration(
                    gradient:LinearGradient(colors:isFemale?[const Color(0xFFEC4899),const Color(0xFFF43F5E)]:[const Color(0xFF7C3AED),const Color(0xFF0EA5E9)]),
                    borderRadius:BorderRadius.circular(28)),
                  child:(s['avatar_url']??'').isNotEmpty
                    ?ClipRRect(borderRadius:BorderRadius.circular(28),child:Image.network(s['avatar_url'],width:56,height:56,fit:BoxFit.cover,errorBuilder:(_,__,___)=>Icon(isFemale?Icons.face_3_rounded:Icons.face_rounded,color:Colors.white,size:28)))
                    :Icon(isFemale?Icons.face_3_rounded:Icons.face_rounded,color:Colors.white,size:28)),
                const SizedBox(width:14),
                // متن
                Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                  Text(s['name']??'',style:const TextStyle(fontWeight:FontWeight.bold,fontSize:15)),
                  if((s['description']??'').isNotEmpty)Padding(
                    padding:const EdgeInsets.only(top:4),
                    child:Text(s['description'],style:const TextStyle(fontSize:12,color:kTextSec))),
                ])),
                // دکمه
                if((s['link']??'').isNotEmpty)...[
                  const SizedBox(width:8),
                  FilledButton(
                    style:FilledButton.styleFrom(
                      padding:const EdgeInsets.symmetric(horizontal:12,vertical:8),
                      minimumSize:const Size(0,36)),
                    onPressed:()=>ul.launchUrl(Uri.parse(s['link']),mode:ul.LaunchMode.externalApplication),
                    child:const Text('مشاهده',style:TextStyle(fontSize:12))),
                ],
              ])),
            );
          });
      });
  }

  Widget _settingsTab()=>FutureBuilder<Map<String,dynamic>?>(
    future:ApiService.getConfig(),
    builder:(ctx,snap){
      final cfg=snap.data??{};
      final channel=cfg['telegram_channel']??'';
      final admin=cfg['telegram_admin']??'';
      final reportText=cfg['report_text']??'گزارش مشکل / پیشنهاد';
      final remoteVer=cfg['app_version']??'';
      final hasUpdate=remoteVer.isNotEmpty&&ApiService.isNewer(remoteVer,ApiService.appVersion);

      return ListView(padding:const EdgeInsets.all(16),children:[
        // هدر اپ
        Container(padding:const EdgeInsets.all(16),decoration:BoxDecoration(
          gradient:LinearGradient(colors:[kAccent.withOpacity(0.15),kCyan.withOpacity(0.08)]),
          borderRadius:BorderRadius.circular(12),border:Border.all(color:kAccent.withOpacity(0.2))),
          child:Row(children:[
            Container(padding:const EdgeInsets.all(8),decoration:BoxDecoration(color:kAccent.withOpacity(0.2),borderRadius:BorderRadius.circular(8)),
                child:const Icon(Icons.play_circle_rounded,color:kAccent,size:24)),
            const SizedBox(width:12),
            Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              const Text('پلیر زیرنویس',style:TextStyle(fontWeight:FontWeight.w700,fontSize:15)),
              Text('نسخه ${ApiService.appVersion}${remoteVer.isNotEmpty?" — سرور: $remoteVer":""}',
                  style:const TextStyle(fontSize:11,color:kTextSec)),
            ])),
            if(snap.connectionState==ConnectionState.waiting)
              const SizedBox(width:16,height:16,child:CircularProgressIndicator(strokeWidth:2)),
          ])),

        const SizedBox(height:12),

        // دکمه چک آپدیت
        _appBtn(
          icon:hasUpdate?Icons.system_update_rounded:Icons.check_circle_rounded,
          color:hasUpdate?kAmber:kGreen,
          label:hasUpdate?'نسخه جدید موجود است — دانلود':'اپ بروز است',
          onTap:hasUpdate?()async{
            final url=cfg['download_url']??'';
            if(url.isNotEmpty)await ul.launchUrl(Uri.parse(url),mode:ul.LaunchMode.externalApplication);
          }:null,
        ),

        const SizedBox(height:8),

        // زیرنویس AI
        _appBtn(
          icon:Icons.auto_awesome_rounded,color:const Color(0xFF7C3AED),
          label:'زیرنویس AI (آفلاین) — مدیریت مدل‌ها',
          onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const AiModelsScreen())),
        ),

        const SizedBox(height:8),

        // کانال تلگرام
        if(channel.isNotEmpty)_appBtn(
          icon:Icons.telegram_rounded,color:kCyan,
          label:'کانال تلگرام',
          onTap:()=>ul.launchUrl(Uri.parse(channel),mode:ul.LaunchMode.externalApplication)),

        const SizedBox(height:8),

        // گزارش مشکل / پیشنهاد
        if(admin.isNotEmpty)_appBtn(
          icon:Icons.bug_report_rounded,color:kPink,
          label:reportText,
          onTap:()=>ul.launchUrl(Uri.parse(admin),mode:ul.LaunchMode.externalApplication)),

        const SizedBox(height:16),
        Container(padding:const EdgeInsets.all(14),decoration:BoxDecoration(color:kCard,borderRadius:BorderRadius.circular(12),border:Border.all(color:kBorder)),
            child:const Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Text('ویژگی‌ها',style:TextStyle(fontWeight:FontWeight.w600,fontSize:13)),SizedBox(height:8),
              Text('• پخش تمام فرمت‌های ویدیو\n• زیرنویس SRT, VTT, ASS, SSA\n• HDR detection\n• زیرنویس دوگانه',
                  style:TextStyle(fontSize:12,color:kTextSec,height:1.7)),
            ])),
      ]);
    });
}

Widget _appBtn({required IconData icon,required Color color,required String label,VoidCallback? onTap}){
  return InkWell(
    onTap:onTap,
    borderRadius:BorderRadius.circular(12),
    child:Container(
      padding:const EdgeInsets.symmetric(horizontal:16,vertical:12),
      decoration:BoxDecoration(color:kCard,borderRadius:BorderRadius.circular(12),
          border:Border.all(color:onTap!=null?color.withOpacity(0.3):kBorder)),
      child:Row(children:[
        Icon(icon,color:onTap!=null?color:kTextDim,size:20),
        const SizedBox(width:12),
        Text(label,style:TextStyle(fontSize:13,color:onTap!=null?Colors.white:kTextSec)),
        const Spacer(),
        if(onTap!=null)Icon(Icons.arrow_forward_ios_rounded,size:12,color:kTextDim),
      ]),
    ),
  );
}

