import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:path/path.dart' as p;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const MyApp());
}

const Set<String> kVideoExt = {
  '.mp4','.mkv','.avi','.mov','.webm','.m4v',
  '.3gp','.flv','.ts','.m2ts','.wmv','.mpg','.mpeg',
};
const List<String> kSubExt = ['.srt','.ass','.ssa','.vtt'];

enum _SortBy { name, date, size, type }

String fmt(Duration d) {
  String two(int n) => n.toString().padLeft(2,'0');
  final h = d.inHours;
  return h > 0
      ? '$h:${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))}'
      : '${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))}';
}

String sizeStr(File f) {
  try {
    final b = f.lengthSync();
    if (b > 1073741824) return '${(b/1073741824).toStringAsFixed(1)}GB';
    return '${(b/1048576).toStringAsFixed(0)}MB';
  } catch(_){return '';}
}

String? matchSubtitle(String videoPath) {
  final dir = p.dirname(videoPath);
  final base = p.basenameWithoutExtension(videoPath);
  for (final ext in kSubExt) {
    final c = p.join(dir,'$base$ext');
    if (File(c).existsSync()) return c;
  }
  return null;
}

// ── SRT parser ──
class SubEntry {
  final Duration start, end;
  final String text;
  const SubEntry(this.start, this.end, this.text);
}

Duration _parseSrtTime(String s) {
  final clean = s.trim().replaceAll(',','.');
  final parts = clean.split(':');
  if (parts.length != 3) return Duration.zero;
  final sm = parts[2].split('.');
  return Duration(
    hours: int.tryParse(parts[0])??0,
    minutes: int.tryParse(parts[1])??0,
    seconds: int.tryParse(sm[0])??0,
    milliseconds: sm.length>1 ? int.tryParse(sm[1].padRight(3,'0').substring(0,3))??0:0,
  );
}

List<SubEntry> parseSrt(String raw) {
  final entries = <SubEntry>[];
  for (final block in raw.replaceAll('\r\n','\n').replaceAll('\r','\n').trim().split(RegExp(r'\n\n+'))) {
    final lines = block.trim().split('\n');
    if (lines.length < 2) continue;
    for (int i = 0; i < lines.length-1; i++) {
      final m = RegExp(r'(\d+:\d+:\d+[,.]\d+)\s*-->\s*(\d+:\d+:\d+[,.]\d+)').firstMatch(lines[i]);
      if (m != null) {
        final text = lines.sublist(i+1).join('\n').trim();
        if (text.isNotEmpty) entries.add(SubEntry(_parseSrtTime(m.group(1)!),_parseSrtTime(m.group(2)!),text));
        break;
      }
    }
  }
  return entries;
}

// ── Store ──
class Store {
  static Set<String> watched = {};
  static Set<String> bookmarked = {};
  static Set<String> favorited = {};
  static List<String> savedFolders = [];
  static List<String> watchHistory = [];
  static final Map<String,int> _durCache = {};

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    watched = (p.getStringList('watched')??[]).toSet();
    bookmarked = (p.getStringList('bookmarks')??[]).toSet();
    favorited = (p.getStringList('favorites')??[]).toSet();
    savedFolders = p.getStringList('savedFolders')??[];
    watchHistory = p.getStringList('watchHistory')??[];
  }

  static Future<void> markWatched(String path) async {
    watched.add(path);
    (await SharedPreferences.getInstance()).setStringList('watched',watched.toList());
  }

  static Future<void> toggleBookmark(String path) async {
    bookmarked.contains(path)?bookmarked.remove(path):bookmarked.add(path);
    (await SharedPreferences.getInstance()).setStringList('bookmarks',bookmarked.toList());
  }

  static Future<void> toggleFavorite(String path) async {
    favorited.contains(path)?favorited.remove(path):favorited.add(path);
    (await SharedPreferences.getInstance()).setStringList('favorites',favorited.toList());
  }

  static Future<void> toggleSavedFolder(String path) async {
    savedFolders.contains(path)?savedFolders.remove(path):savedFolders.add(path);
    (await SharedPreferences.getInstance()).setStringList('savedFolders',savedFolders);
  }

  static Future<void> addToHistory(String path) async {
    watchHistory.remove(path);
    watchHistory.insert(0,path);
    if (watchHistory.length>100) watchHistory=watchHistory.sublist(0,100);
    (await SharedPreferences.getInstance()).setStringList('watchHistory',watchHistory);
  }

  static Future<void> savePos(String path, Duration pos) async =>
      (await SharedPreferences.getInstance()).setInt('pos:$path',pos.inSeconds);

  static Future<Duration> getPos(String path) async {
    final p = await SharedPreferences.getInstance();
    return Duration(seconds: p.getInt('pos:$path')??0);
  }

  static Future<void> saveDur(String path, int s) async {
    _durCache[path]=s;
    (await SharedPreferences.getInstance()).setInt('dur:$path',s);
  }

  static Future<int> getDur(String path) async {
    if (_durCache.containsKey(path)) return _durCache[path]!;
    final p = await SharedPreferences.getInstance();
    return _durCache[path] = p.getInt('dur:$path')??0;
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'پلیر زیرنویس',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3:true, brightness:Brightness.dark,
        colorSchemeSeed:const Color(0xFF6C63FF), scaffoldBackgroundColor:const Color(0xFF101014)),
    builder: (ctx,child) => Directionality(textDirection:TextDirection.rtl,child:child!),
    home: const BrowserScreen(),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// مرورگر فایل
// ─────────────────────────────────────────────────────────────────────────────
class BrowserScreen extends StatefulWidget {
  const BrowserScreen({super.key});
  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> {
  static const root = '/storage/emulated/0';
  bool _granted=false, _checking=true;
  String _path = root;
  List<Directory> _dirs = [];
  List<File> _videos = [];
  bool _selectMode=false;
  final Set<String> _selected={};

  // مرتب‌سازی و جستجو
  _SortBy _sortBy = _SortBy.name;
  bool _sortDesc = false;
  bool _searching = false;
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() { super.initState(); _init(); }
  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  Future<void> _init() async { await Store.load(); await _ensurePermission(); }

  Future<void> _ensurePermission() async {
    setState(()=>_checking=true);
    var ok = await Permission.manageExternalStorage.isGranted;
    if (!ok) ok=(await Permission.manageExternalStorage.request()).isGranted;
    if (!ok) ok=(await Permission.storage.request()).isGranted;
    setState((){_granted=ok;_checking=false;});
    if (ok) _loadDir(_path);
  }

  void _loadDir(String path) {
    try {
      final items = Directory(path).listSync(followLinks:false);
      final dirs = items.whereType<Directory>().toList();
      final vids = items.whereType<File>().where(
          (f)=>kVideoExt.contains(p.extension(f.path).toLowerCase())).toList();
      dirs.sort((a,b)=>p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase()));
      setState((){_path=path;_dirs=dirs;_videos=vids;_selectMode=false;_selected.clear();_searching=false;_searchQuery='';_searchCtrl.clear();});
    } catch(_){
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('دسترسی ندارید')));
    }
  }

  void _goUp() {
    final parent = p.dirname(_path);
    if (parent!=_path && parent.startsWith('/storage')) _loadDir(parent);
  }

  // ── مرتب‌سازی ──
  List<File> get _sortedVideos {
    final s = List<File>.from(_videos);
    switch (_sortBy) {
      case _SortBy.name:
        s.sort((a,b)=>_sd(p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase())));
        break;
      case _SortBy.date:
        s.sort((a,b){try{return _sd(a.lastModifiedSync().compareTo(b.lastModifiedSync()));}catch(_){return 0;}});
        break;
      case _SortBy.size:
        s.sort((a,b){try{return _sd(a.lengthSync().compareTo(b.lengthSync()));}catch(_){return 0;}});
        break;
      case _SortBy.type:
        s.sort((a,b)=>_sd(p.extension(a.path).compareTo(p.extension(b.path))));
        break;
    }
    return s;
  }
  int _sd(int v) => _sortDesc ? -v : v;

  List<File> get _filteredVideos {
    if (_searchQuery.isEmpty) return _sortedVideos;
    return _sortedVideos.where((f)=>p.basename(f.path).toLowerCase().contains(_searchQuery.toLowerCase())).toList();
  }

  List<Directory> get _filteredDirs {
    if (_searchQuery.isEmpty) return _dirs;
    return _dirs.where((d)=>p.basename(d.path).toLowerCase().contains(_searchQuery.toLowerCase())).toList();
  }

  Future<void> _openVideo(File video, [List<File>? playlist, int? idx]) async {
    final pl = playlist ?? _filteredVideos;
    final i = idx ?? pl.indexOf(video);
    await Navigator.push(context, MaterialPageRoute(
      builder:(_)=>PlayerScreen(subtitlePath:matchSubtitle(video.path),playlist:pl,playlistIndex:i<0?0:i),
    ));
    await Store.load();
    if (mounted) setState((){});
  }

  Future<void> _openVideoByPath(String path) async {
    final f = File(path);
    if (!f.existsSync()){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('فایل یافت نشد')));return;}
    await _openVideo(f,[f],0);
  }

  void _showVideoMenu(File f) {
    showModalBottomSheet(
      context:context,
      backgroundColor:const Color(0xFF1C1C22),
      shape:const RoundedRectangleBorder(borderRadius:BorderRadius.vertical(top:Radius.circular(16))),
      builder:(ctx)=>_VideoMenu(
        file:f,
        onDone:()async{Navigator.pop(ctx);await Store.load();_loadDir(_path);},
        onInfo:(){Navigator.pop(ctx);_showFileInfo(f);},
        onDelete:(){Navigator.pop(ctx);_confirmDelete([f]);},
        onRename:(){Navigator.pop(ctx);_renameFile(f);},
        onSelect:(){Navigator.pop(ctx);setState((){_selectMode=true;_selected.add(f.path);});},
        onCopy:(){Navigator.pop(ctx);_copyFile(f);},
      ),
    );
  }

  Future<void> _copyFile(File f) async {
    if (Store.savedFolders.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('ابتدا یک پوشه را ذخیره کنید')));
      return;
    }
    final dest = await showDialog<String>(
      context:context,
      builder:(ctx)=>AlertDialog(
        backgroundColor:const Color(0xFF1C1C22),
        title:const Text('کپی به پوشه'),
        content:Column(mainAxisSize:MainAxisSize.min,
          children:Store.savedFolders.map((folder)=>ListTile(
            leading:const Icon(Icons.folder,color:Color(0xFFFFCB6B)),
            title:Text(p.basename(folder)),
            onTap:()=>Navigator.pop(ctx,folder),
          )).toList()),
      ),
    );
    if (dest==null) return;
    try {
      await f.copy(p.join(dest,p.basename(f.path)));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('کپی شد به ${p.basename(dest)}')));
    } catch(e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('خطا در کپی')));
    }
  }

  Future<void> _confirmDelete(List<File> files) async {
    final ok = await showDialog<bool>(
      context:context,
      builder:(ctx)=>AlertDialog(
        backgroundColor:const Color(0xFF1C1C22),
        title:const Text('حذف فایل'),
        content:Text(files.length==1?'«${p.basename(files.first.path)}» حذف شود؟':'${files.length} فایل حذف شود؟'),
        actions:[
          TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('لغو')),
          FilledButton(style:FilledButton.styleFrom(backgroundColor:Colors.red),
              onPressed:()=>Navigator.pop(ctx,true),child:const Text('حذف')),
        ],
      ),
    );
    if (ok!=true) return;
    for (final f in files){try{await f.delete();}catch(_){}}
    _loadDir(_path);
  }

  Future<void> _renameFile(File f) async {
    final ctrl = TextEditingController(text:p.basenameWithoutExtension(f.path));
    final name = await showDialog<String>(
      context:context,
      builder:(ctx)=>AlertDialog(
        backgroundColor:const Color(0xFF1C1C22),
        title:const Text('تغییر نام'),
        content:TextField(controller:ctrl,autofocus:true,decoration:const InputDecoration(hintText:'نام جدید')),
        actions:[
          TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('لغو')),
          FilledButton(onPressed:()=>Navigator.pop(ctx,ctrl.text.trim()),child:const Text('تأیید')),
        ],
      ),
    );
    if (name==null||name.isEmpty) return;
    try{await f.rename(p.join(p.dirname(f.path),'$name${p.extension(f.path)}'));_loadDir(_path);}
    catch(_){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('خطا در تغییر نام')));}
  }

  Future<void> _showFileInfo(File f) async {
    final sub=matchSubtitle(f.path);
    String modified='';
    try{modified=f.lastModifiedSync().toString().split('.').first;}catch(_){}
    final dur=await Store.getDur(f.path);
    if (!mounted) return;
    showDialog(context:context,builder:(ctx)=>AlertDialog(
      backgroundColor:const Color(0xFF1C1C22),
      title:Text(p.basename(f.path),style:const TextStyle(fontSize:13)),
      content:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
        _iRow(Icons.folder_outlined,'مسیر',p.dirname(f.path)),
        _iRow(Icons.data_usage,'حجم',sizeStr(f)),
        if(dur>0)_iRow(Icons.timer_outlined,'مدت',fmt(Duration(seconds:dur))),
        _iRow(Icons.calendar_today,'تاریخ',modified),
        _iRow(Icons.visibility_outlined,'وضعیت',Store.watched.contains(f.path)?'دیده شده ✓':'دیده نشده'),
        _iRow(Icons.bookmark_outline,'نشانه',Store.bookmarked.contains(f.path)?'★ نشانه‌گذاری شده':'ندارد'),
        _iRow(Icons.favorite_outline,'علاقه‌مندی',Store.favorited.contains(f.path)?'❤ در علاقه‌مندی‌ها':'ندارد'),
        _iRow(Icons.subtitles_outlined,'زیرنویس',sub!=null?p.basename(sub):'یافت نشد'),
      ]),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('بستن'))],
    ));
  }

  Widget _iRow(IconData icon,String label,String val)=>Padding(
    padding:const EdgeInsets.symmetric(vertical:3),
    child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Icon(icon,size:15,color:Colors.white38),const SizedBox(width:6),
      Text('$label: ',style:const TextStyle(color:Colors.white54,fontSize:12)),
      Expanded(child:Text(val,style:const TextStyle(fontSize:12),overflow:TextOverflow.ellipsis,maxLines:2)),
    ]),
  );

  @override
  Widget build(BuildContext context) {
    final isSaved=Store.savedFolders.contains(_path);
    return PopScope(
      canPop: _path==root&&!_selectMode&&!_searching,
      onPopInvokedWithResult:(didPop,_){
        if(!didPop){
          if(_searching){setState((){_searching=false;_searchQuery='';_searchCtrl.clear();});}
          else if(_selectMode){setState((){_selectMode=false;_selected.clear();});}
          else{_goUp();}
        }
      },
      child:Scaffold(
        appBar:_selectMode?_selectAppBar():_normalAppBar(isSaved),
        body:_buildBody(),
        floatingActionButtonLocation:FloatingActionButtonLocation.centerFloat,
        floatingActionButton:_selectMode?null:_buildFABs(),
      ),
    );
  }

  Widget _buildFABs()=>Row(mainAxisSize:MainAxisSize.min,children:[
    _fabBtn(Icons.history,'تاریخچه',Colors.white70,()=>_openPanel(0)),
    const SizedBox(width:8),
    _fabBtn(Icons.bookmark,'نشانه‌ها',Colors.amber,()=>_openPanel(1)),
    const SizedBox(width:8),
    _fabBtn(Icons.favorite,'علاقه‌مندی',Colors.redAccent,()=>_openPanel(2)),
    const SizedBox(width:8),
    _fabBtn(Icons.push_pin,'پوشه‌ها',Colors.greenAccent,()=>_openPanel(3)),
    const SizedBox(width:8),
    _fabBtn(Icons.settings,'تنظیمات',Colors.white54,()=>_openPanel(4)),
  ]);

  Widget _fabBtn(IconData icon,String tip,Color color,VoidCallback fn)=>
      FloatingActionButton.small(heroTag:tip,tooltip:tip,
          backgroundColor:const Color(0xFF252530),onPressed:fn,
          child:Icon(icon,size:18,color:color));

  PreferredSizeWidget _normalAppBar(bool isSaved)=>AppBar(
    title:_searching
        ? TextField(controller:_searchCtrl,autofocus:true,
            decoration:const InputDecoration(hintText:'جستجو...',border:InputBorder.none),
            onChanged:(v)=>setState(()=>_searchQuery=v))
        : Text(_path==root?'حافظه داخلی':p.basename(_path),overflow:TextOverflow.ellipsis),
    leading:_path!=root
        ?IconButton(icon:const Icon(Icons.arrow_upward),onPressed:_goUp)
        :null,
    actions:[
      IconButton(icon:Icon(_searching?Icons.close:Icons.search),
          onPressed:(){setState((){_searching=!_searching;if(!_searching){_searchQuery='';_searchCtrl.clear();}});}),
      if(_path!=root)IconButton(
        icon:Icon(isSaved?Icons.push_pin:Icons.push_pin_outlined,color:isSaved?Colors.amber:null),
        onPressed:()async{await Store.toggleSavedFolder(_path);setState((){});},
      ),
      PopupMenuButton<_SortBy>(
        icon:const Icon(Icons.sort),
        onSelected:(v)=>setState((){if(_sortBy==v)_sortDesc=!_sortDesc;else{_sortBy=v;_sortDesc=false;}}),
        itemBuilder:(_)=>[
          PopupMenuItem(value:_SortBy.name,child:Text('نام${_sortBy==_SortBy.name?(_sortDesc?' ↑':' ↓'):''}')),
          PopupMenuItem(value:_SortBy.date,child:Text('تاریخ${_sortBy==_SortBy.date?(_sortDesc?' ↑':' ↓'):''}')),
          PopupMenuItem(value:_SortBy.size,child:Text('حجم${_sortBy==_SortBy.size?(_sortDesc?' ↑':' ↓'):''}')),
          PopupMenuItem(value:_SortBy.type,child:Text('نوع${_sortBy==_SortBy.type?(_sortDesc?' ↑':' ↓'):''}')),
        ],
      ),
    ],
  );

  PreferredSizeWidget _selectAppBar()=>AppBar(
    leading:IconButton(icon:const Icon(Icons.close),
        onPressed:()=>setState((){_selectMode=false;_selected.clear();})),
    title:Text('${_selected.length} انتخاب‌شده'),
    actions:[
      IconButton(icon:const Icon(Icons.select_all),
          onPressed:()=>setState(()=>_selected.addAll(_filteredVideos.map((v)=>v.path)))),
      IconButton(icon:const Icon(Icons.delete_outline,color:Colors.redAccent),
          onPressed:_selected.isEmpty?null:()=>_confirmDelete(_selected.map((s)=>File(s)).toList())),
    ],
  );

  Widget _buildBody(){
    if(_checking) return const Center(child:CircularProgressIndicator());
    if(!_granted) return Center(child:Padding(padding:const EdgeInsets.all(32),
      child:Column(mainAxisSize:MainAxisSize.min,children:[
        const Icon(Icons.folder_off,size:64,color:Colors.white38),const SizedBox(height:16),
        const Text('اپ به دسترسی فایل‌ها نیاز دارد.',textAlign:TextAlign.center),const SizedBox(height:20),
        FilledButton.icon(onPressed:_ensurePermission,icon:const Icon(Icons.lock_open),label:const Text('اجازه دسترسی')),
        TextButton(onPressed:openAppSettings,child:const Text('تنظیمات اپ')),
      ]),
    ));
    return Column(children:[
      Container(width:double.infinity,padding:const EdgeInsets.symmetric(horizontal:16,vertical:5),
          color:const Color(0xFF1A1A22),
          child:Text(_path,style:const TextStyle(fontSize:11,color:Colors.white38),overflow:TextOverflow.ellipsis)),
      Expanded(child:_buildList()),
    ]);
  }

  Widget _buildList(){
    final fDirs=_filteredDirs, fVids=_filteredVideos;
    final total=fDirs.length+fVids.length;
    if(total==0) return const Center(child:Text('این پوشه خالی است'));
    return ListView.separated(
      padding:const EdgeInsets.only(bottom:90,top:4),
      itemCount:total,
      separatorBuilder:(_,__)=>const Divider(height:1,color:Color(0xFF222230)),
      itemBuilder:(ctx,i){
        if(i<fDirs.length){
          final d=fDirs[i];
          return ListTile(
            leading:Container(width:44,height:44,
                decoration:BoxDecoration(color:const Color(0xFF2A2520),borderRadius:BorderRadius.circular(10)),
                child:const Icon(Icons.folder,color:Color(0xFFFFCB6B))),
            title:Text(p.basename(d.path),maxLines:1,overflow:TextOverflow.ellipsis),
            trailing:const Icon(Icons.chevron_left,color:Colors.white38),
            onTap:()=>_loadDir(d.path),
          );
        }
        final v=fVids[i-fDirs.length];
        final seen=Store.watched.contains(v.path), bkm=Store.bookmarked.contains(v.path);
        final fav=Store.favorited.contains(v.path), hasSub=matchSubtitle(v.path)!=null;
        final sel=_selected.contains(v.path);
        return ListTile(
          selected:sel, selectedTileColor:const Color(0xFF2A2A4A),
          leading:_selectMode
              ?Checkbox(value:sel,onChanged:(_)=>setState(()=>sel?_selected.remove(v.path):_selected.add(v.path)))
              :Container(width:44,height:44,
                  decoration:BoxDecoration(color:const Color(0xFF1E2433),borderRadius:BorderRadius.circular(10)),
                  child:Icon(seen?Icons.check_circle:Icons.movie,
                      color:seen?Colors.greenAccent:const Color(0xFF82AAFF))),
          title:Text(p.basename(v.path),maxLines:1,overflow:TextOverflow.ellipsis,
              style:TextStyle(color:seen?Colors.greenAccent:Colors.white,fontWeight:seen?FontWeight.w500:FontWeight.normal)),
          subtitle:Row(children:[
            Text(sizeStr(v),style:const TextStyle(fontSize:11,color:Colors.white38)),
            if(hasSub)const Text(' • sub ✓',style:TextStyle(fontSize:11,color:Colors.greenAccent)),
          ]),
          trailing:_selectMode?null:Row(mainAxisSize:MainAxisSize.min,children:[
            if(fav)const Icon(Icons.favorite,color:Colors.redAccent,size:17),
            if(bkm)const Icon(Icons.bookmark,color:Colors.amber,size:17),
            const SizedBox(width:4),const Icon(Icons.play_circle_outline,size:24),
          ]),
          onTap:_selectMode?()=>setState(()=>sel?_selected.remove(v.path):_selected.add(v.path)):()=>_openVideo(v,fVids,i-fDirs.length),
          onLongPress:_selectMode?null:()=>_showVideoMenu(v),
        );
      },
    );
  }

  void _openPanel(int page){
    showModalBottomSheet(
      context:context,isScrollControlled:true,backgroundColor:const Color(0xFF1C1C22),
      shape:const RoundedRectangleBorder(borderRadius:BorderRadius.vertical(top:Radius.circular(20))),
      builder:(ctx)=>SizedBox(
        height:MediaQuery.of(context).size.height*0.65,
        child:_BottomPanel(initialPage:page,
            onVideoTap:(path){Navigator.pop(ctx);_openVideoByPath(path);},
            onFolderTap:(folder){Navigator.pop(ctx);_loadDir(folder);}),
      ),
    );
  }
}

class _VideoMenu extends StatefulWidget {
  final File file;
  final VoidCallback onDone,onInfo,onDelete,onRename,onSelect,onCopy;
  const _VideoMenu({required this.file,required this.onDone,required this.onInfo,
      required this.onDelete,required this.onRename,required this.onSelect,required this.onCopy});
  @override State<_VideoMenu> createState()=>_VideoMenuState();
}
class _VideoMenuState extends State<_VideoMenu>{
  late bool _bkm=Store.bookmarked.contains(widget.file.path);
  late bool _fav=Store.favorited.contains(widget.file.path);
  @override Widget build(BuildContext context)=>Column(mainAxisSize:MainAxisSize.min,children:[
    const SizedBox(height:8),
    Center(child:Container(width:40,height:4,decoration:BoxDecoration(color:Colors.white24,borderRadius:BorderRadius.circular(2)))),
    const SizedBox(height:4),
    ListTile(leading:const Icon(Icons.info_outline),title:const Text('اطلاعات فایل'),onTap:widget.onInfo),
    ListTile(leading:Icon(_bkm?Icons.bookmark:Icons.bookmark_border,color:Colors.amber),title:Text(_bkm?'حذف نشانه':'نشانه‌گذاری'),
        onTap:()async{await Store.toggleBookmark(widget.file.path);setState(()=>_bkm=!_bkm);widget.onDone();}),
    ListTile(leading:Icon(_fav?Icons.favorite:Icons.favorite_border,color:Colors.redAccent),title:Text(_fav?'حذف از علاقه‌مندی':'افزودن به علاقه‌مندی'),
        onTap:()async{await Store.toggleFavorite(widget.file.path);setState(()=>_fav=!_fav);widget.onDone();}),
    ListTile(leading:const Icon(Icons.copy_outlined),title:const Text('کپی به پوشه ذخیره‌شده'),onTap:widget.onCopy),
    ListTile(leading:const Icon(Icons.edit_outlined),title:const Text('تغییر نام'),onTap:widget.onRename),
    ListTile(leading:const Icon(Icons.delete_outline,color:Colors.redAccent),title:const Text('حذف',style:TextStyle(color:Colors.redAccent)),onTap:widget.onDelete),
    ListTile(leading:const Icon(Icons.select_all),title:const Text('انتخاب گروهی'),onTap:widget.onSelect),
    const SizedBox(height:8),
  ]);
}

class _BottomPanel extends StatefulWidget {
  final int initialPage;
  final ValueChanged<String> onVideoTap,onFolderTap;
  const _BottomPanel({required this.initialPage,required this.onVideoTap,required this.onFolderTap});
  @override State<_BottomPanel> createState()=>_BottomPanelState();
}
class _BottomPanelState extends State<_BottomPanel> with SingleTickerProviderStateMixin{
  late TabController _tab;
  @override void initState(){super.initState();_tab=TabController(length:5,vsync:this,initialIndex:widget.initialPage);}
  @override void dispose(){_tab.dispose();super.dispose();}
  @override Widget build(BuildContext context)=>Column(children:[
    const SizedBox(height:10),
    Center(child:Container(width:40,height:4,decoration:BoxDecoration(color:Colors.white24,borderRadius:BorderRadius.circular(2)))),
    TabBar(controller:_tab,isScrollable:true,tabs:const[
      Tab(icon:Icon(Icons.history,size:17),text:'تاریخچه'),
      Tab(icon:Icon(Icons.bookmark,size:17),text:'نشانه‌ها'),
      Tab(icon:Icon(Icons.favorite,size:17),text:'علاقه‌مندی'),
      Tab(icon:Icon(Icons.push_pin,size:17),text:'پوشه‌ها'),
      Tab(icon:Icon(Icons.settings,size:17),text:'تنظیمات'),
    ]),
    Expanded(child:TabBarView(controller:_tab,children:[
      _vList(Store.watchHistory,Icons.history,Colors.white70),
      _vList(Store.bookmarked.toList().reversed.toList(),Icons.bookmark,Colors.amber),
      _vList(Store.favorited.toList().reversed.toList(),Icons.favorite,Colors.redAccent),
      _folderList(),_settingsTab(),
    ])),
  ]);

  Widget _vList(List<String> paths,IconData icon,Color color){
    if(paths.isEmpty) return Center(child:Column(mainAxisSize:MainAxisSize.min,children:[
      Icon(icon,size:48,color:color.withOpacity(0.3)),const SizedBox(height:12),
      const Text('هنوز چیزی نیست',style:TextStyle(color:Colors.white54)),
    ]));
    return ListView.builder(itemCount:paths.length,itemBuilder:(_,i){
      final path=paths[i];
      final exists=File(path).existsSync();
      return ListTile(
        leading:Icon(icon,color:exists?color:Colors.white24,size:20),
        title:Text(p.basename(path),maxLines:1,overflow:TextOverflow.ellipsis,
            style:TextStyle(color:exists?Colors.white:Colors.white38)),
        subtitle:Text(p.dirname(path),maxLines:1,overflow:TextOverflow.ellipsis,
            style:const TextStyle(fontSize:11,color:Colors.white38)),
        onTap:exists?()=>widget.onVideoTap(path):null,
      );
    });
  }

  Widget _folderList(){
    final folders=Store.savedFolders;
    if(folders.isEmpty) return const Center(child:Column(mainAxisSize:MainAxisSize.min,children:[
      Icon(Icons.push_pin_outlined,size:48,color:Colors.white24),SizedBox(height:12),
      Text('پوشه‌ای ذخیره نشده',style:TextStyle(color:Colors.white54)),
      SizedBox(height:6),Text('در مرورگر آیکون 📌 را بزنید',style:TextStyle(fontSize:12,color:Colors.white38)),
    ]));
    return ListView.builder(itemCount:folders.length,itemBuilder:(_,i){
      final folder=folders[i];
      final exists=Directory(folder).existsSync();
      return ListTile(
        leading:Icon(Icons.folder,color:exists?const Color(0xFFFFCB6B):Colors.white24),
        title:Text(p.basename(folder),maxLines:1,overflow:TextOverflow.ellipsis),
        subtitle:Text(folder,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:11,color:Colors.white38)),
        trailing:IconButton(icon:const Icon(Icons.push_pin,color:Colors.amber,size:18),
            onPressed:()async{await Store.toggleSavedFolder(folder);setState((){});}),
        onTap:exists?()=>widget.onFolderTap(folder):null,
      );
    });
  }

  Widget _settingsTab()=>ListView(padding:const EdgeInsets.all(16),children:[
    const ListTile(leading:Icon(Icons.info_outline),title:Text('اطلاعات توسعه‌دهنده'),subtitle:Text('نسخه ۱.۰.۰')),
    const Divider(),
    const ListTile(leading:Icon(Icons.code),title:Text('Flutter + media_kit'),subtitle:Text('Anthropic Claude')),
  ]);
}

// ─────────────────────────────────────────────────────────────────────────────
// پلیر ویدیو
// ─────────────────────────────────────────────────────────────────────────────
enum _GMode{none,seek,brightness,volume,zoom,pan,subtitlePos}
enum _Repeat{none,one,all}

class PlayerScreen extends StatefulWidget {
  final String? subtitlePath;
  final List<File> playlist;
  final int playlistIndex;
  const PlayerScreen({super.key,this.subtitlePath,required this.playlist,required this.playlistIndex});
  @override State<PlayerScreen> createState()=>_PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen>{
  late final Player player=Player();
  late final VideoController controller=VideoController(player);
  late int _playIndex;

  Duration _position=Duration.zero,_duration=Duration.zero;
  bool _playing=true;
  final List<StreamSubscription> _subs=[];

  // زیرنویس ۱
  List<SubEntry> _subEntries=[];
  bool _subVisible=true;
  double _fontSize=30;
  bool _bold=true;
  double _bgOpacity=0.5;
  Color _color=Colors.white;
  Color _subBgColor=Colors.black;
  TextAlign _subAlign=TextAlign.center;
  double _subBottomPadding=50.0,_subPaddingStart=50.0;
  String _fontFamily='';
  int _subDelayMs=0;

  // زیرنویس ۲ (همزمان)
  List<SubEntry> _subEntries2=[];
  bool _sub2Visible=false;
  Color _color2=const Color(0xFFFFEB3B);
  int _subDelay2Ms=0;
  int _audioDelayMs=0;
  String? _sub2Path;

  // audio tracks
  List<AudioTrack> _audioTracks=[];

  // پخش
  double _speed=1.0;
  double _ampVolume=100; // تقویت صدا (۱۰۰-۳۰۰%)
  BoxFit _fit=BoxFit.contain;
  bool _landscape=false;
  _Repeat _repeatMode=_Repeat.none;
  bool _muted=false;
  double _savedPlayerVolume=100;
  double _rotationDeg=0;

  // A-B تکرار
  Duration? _repeatA,_repeatB;
  bool _abActive=false;

  // Sleep Timer
  Timer? _sleepTimer;
  DateTime? _sleepAt;

  // حالت شب
  double _nightOpacity=0.0;

  // کنترل‌ها
  bool _controlsVisible=true,_locked=false;
  Timer? _hideTimer;

  // زوم
  double _scale=1.0,_baseScale=1.0;
  Offset _offset=Offset.zero,_baseOffset=Offset.zero;

  // اشاره‌ها
  _GMode _mode=_GMode.none;
  Offset _startFocal=Offset.zero,_doubleTapPos=Offset.zero;
  int _seekStartMs=0,_seekTargetMs=0;
  double _startBrightness=0.5,_startSysVolume=0.5;
  Size _size=Size.zero;

  String? _overlay;
  Timer? _overlayTimer;

  // screenshot
  final GlobalKey _videoKey=GlobalKey();

  final List<Color> _colorChoices=const[Colors.white,Color(0xFFFFEB3B),Color(0xFF69F0AE),Color(0xFF40C4FF),Color(0xFFFF8A65),Color(0xFFFF80AB)];
  final List<Color> _bgColorChoices=const[Colors.black,Color(0xFF0D1B2A),Color(0xFF1B2E1B),Color(0xFF2A1B1B),Color(0xFF1B1B2E),Colors.transparent];

  String get _curPath=>widget.playlist[_playIndex].path;
  bool get _hasPrev=>_playIndex>0;
  bool get _hasNext=>_playIndex<widget.playlist.length-1;

  String? get _subText{
    if(!_subVisible||_subEntries.isEmpty) return null;
    final adj=_position-Duration(milliseconds:_subDelayMs);
    for(final e in _subEntries){if(adj>=e.start&&adj<=e.end)return e.text;}
    return null;
  }
  String? get _sub2Text{
    if(!_sub2Visible||_subEntries2.isEmpty) return null;
    final adj=_position-Duration(milliseconds:_subDelay2Ms);
    for(final e in _subEntries2){if(adj>=e.start&&adj<=e.end)return e.text;}
    return null;
  }

  @override
  void initState(){
    super.initState();
    _playIndex=widget.playlistIndex.clamp(0,(widget.playlist.length-1).clamp(0,999999));
    WakelockPlus.enable();
    VolumeController.instance.showSystemUI=false;
    _subs.add(player.stream.position.listen((pos){
      _position=pos;
      _maybeWatched();
      // A-B repeat
      if(_abActive&&_repeatA!=null&&_repeatB!=null&&_position>=_repeatB!){
        player.seek(_repeatA!);
      }
      if(mounted)setState((){});
    }));
    _subs.add(player.stream.duration.listen((d){
      _duration=d;
      if(d.inSeconds>0)Store.saveDur(_curPath,d.inSeconds);
      if(mounted)setState((){});
    }));
    _subs.add(player.stream.playing.listen((pl){_playing=pl;if(mounted)setState((){});}));
    _subs.add(player.stream.tracks.listen((t){if(mounted)setState(()=>_audioTracks=t.audio);}));
    _subs.add(player.stream.completed.listen((done){
      if(!done) return;
      switch(_repeatMode){
        case _Repeat.one:player.seek(Duration.zero);player.play();break;
        case _Repeat.all:_switchVideo((_playIndex+1)%widget.playlist.length);break;
        case _Repeat.none:if(_hasNext)_switchVideo(_playIndex+1);break;
      }
    }));
    _start();
    _startHideTimer();
  }

  Future<void> _start() async {
    await player.open(Media(_curPath));
    await Store.addToHistory(_curPath);
    final saved=await Store.getPos(_curPath);
    if(saved.inSeconds>5&&mounted){
      final resume=await showDialog<bool>(
        context:context,barrierDismissible:false,
        builder:(ctx)=>AlertDialog(
          backgroundColor:const Color(0xFF1C1C22),title:const Text('ادامه پخش'),
          content:Text('از ${fmt(saved)} ادامه دهیم؟'),
          actions:[
            TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('از ابتدا')),
            FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('ادامه')),
          ],
        ),
      );
      if(resume==true&&mounted)await player.seek(saved);
    }
    final sub=widget.subtitlePath??matchSubtitle(_curPath);
    if(sub!=null)await _loadSubtitle(sub,secondary:false);
  }

  Future<void> _switchVideo(int idx)async{
    await Store.savePos(_curPath,_position);
    _playIndex=idx;_position=Duration.zero;_duration=Duration.zero;_subEntries=[];_subEntries2=[];
    _repeatA=null;_repeatB=null;_abActive=false;
    setState((){});
    await player.open(Media(_curPath));
    await Store.addToHistory(_curPath);
    final saved=await Store.getPos(_curPath);
    if(saved.inSeconds>5)await player.seek(saved);
    final sub=matchSubtitle(_curPath);
    if(sub!=null)await _loadSubtitle(sub,secondary:false);
  }

  void _maybeWatched(){
    if(_duration.inSeconds>0&&_position.inSeconds>_duration.inSeconds*0.9)
      Store.markWatched(_curPath);
  }

  Future<void> _loadSubtitle(String path,{required bool secondary})async{
    final bytes=await File(path).readAsBytes();
    String content;
    try{content=utf8.decode(bytes);}catch(_){content=utf8.decode(bytes,allowMalformed:true);}
    if(['.srt','.vtt'].contains(p.extension(path).toLowerCase())){
      if(secondary){setState(()=>{_subEntries2=parseSrt(content),_sub2Path=path,_sub2Visible=true});}
      else{setState(()=>_subEntries=parseSrt(content));}
    }
  }

  Future<void> _pickSubtitle({required bool secondary})async{
    final res=await FilePicker.platform.pickFiles(type:FileType.custom,allowedExtensions:['srt','vtt','ass','ssa']);
    final path=res?.files.single.path;
    if(path!=null)await _loadSubtitle(path,secondary:secondary);
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
      setState(()=>_fontFamily=name);
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('فونت بارگذاری شد')));
    }catch(e){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('خطا در بارگذاری فونت')));
    }
  }

  void _copySubText(){
    final text=_subText??_sub2Text;
    if(text!=null){
      Clipboard.setData(ClipboardData(text:text));
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('متن زیرنویس کپی شد')));
    }
  }

  Future<void> _takeScreenshot()async{
    try{
      final boundary=_videoKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if(boundary==null)return;
      final image=await boundary.toImage(pixelRatio:2.0);
      final byteData=await image.toByteData(format:ui.ImageByteFormat.png);
      if(byteData==null)return;
      final bytes=byteData.buffer.asUint8List();
      final ts=DateTime.now().millisecondsSinceEpoch;
      final path='/storage/emulated/0/Pictures/screenshot_$ts.png';
      await File(path).writeAsBytes(bytes);
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('اسکرین‌شات: Pictures/screenshot_$ts.png')));
    }catch(e){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('خطا در اسکرین‌شات')));
    }
  }

  void _showSleepTimerDialog(){
    int minutes=30;
    showDialog(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,ss)=>AlertDialog(
      backgroundColor:const Color(0xFF1C1C22),
      title:const Text('تایمر خواب'),
      content:Column(mainAxisSize:MainAxisSize.min,children:[
        Text('$minutes دقیقه',style:const TextStyle(fontSize:24,fontWeight:FontWeight.bold)),
        Slider(min:1,max:180,divisions:179,value:minutes.toDouble(),onChanged:(v)=>ss(()=>minutes=v.round())),
        if(_sleepAt!=null)Text('باقی‌مانده: ${_sleepAt!.difference(DateTime.now()).inMinutes} دقیقه',
            style:const TextStyle(color:Colors.orange)),
      ]),
      actions:[
        if(_sleepAt!=null)TextButton(
          onPressed:(){_sleepTimer?.cancel();setState(()=>_sleepAt=null);Navigator.pop(ctx);},
          child:const Text('لغو تایمر',style:TextStyle(color:Colors.red))),
        TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('بستن')),
        FilledButton(onPressed:(){
          _sleepTimer?.cancel();
          final at=DateTime.now().add(Duration(minutes:minutes));
          setState(()=>_sleepAt=at);
          _sleepTimer=Timer(Duration(minutes:minutes),(){player.pause();setState(()=>_sleepAt=null);});
          Navigator.pop(ctx);
        },child:const Text('شروع')),
      ],
    )));
  }

  void _showAudioTrackPicker(){
    if(_audioTracks.isEmpty){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('تراک صوتی پیدا نشد')));return;}
    showDialog(context:context,builder:(ctx)=>AlertDialog(
      backgroundColor:const Color(0xFF1C1C22),
      title:const Text('انتخاب تراک صوتی'),
      content:Column(mainAxisSize:MainAxisSize.min,
        children:_audioTracks.map((t)=>ListTile(
          title:Text(t.title??t.language??'Track ${t.id}'),
          subtitle:t.language!=null?Text(t.language!):null,
          leading:const Icon(Icons.music_note),
          onTap:(){player.setAudioTrack(t);Navigator.pop(ctx);},
        )).toList()),
    ));
  }

  @override
  void dispose(){
    Store.savePos(_curPath,_position);
    for(final s in _subs){s.cancel();}
    _hideTimer?.cancel();_overlayTimer?.cancel();_sleepTimer?.cancel();
    WakelockPlus.disable();
    try{ScreenBrightness().resetApplicationScreenBrightness();}catch(_){}
    try{VolumeController.instance.showSystemUI=true;}catch(_){}
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    player.dispose();
    super.dispose();
  }

  void _startHideTimer(){
    _hideTimer?.cancel();
    _hideTimer=Timer(const Duration(seconds:4),(){if(mounted)setState(()=>_controlsVisible=false);});
  }

  void _toggleControls(){if(!_locked){setState(()=>_controlsVisible=!_controlsVisible);if(_controlsVisible)_startHideTimer();}}

  void _showOverlay(String text){
    setState(()=>_overlay=text);
    _overlayTimer?.cancel();
    _overlayTimer=Timer(const Duration(milliseconds:900),(){if(mounted)setState(()=>_overlay=null);});
  }

  // دابل‌تپ: چپ = -10s، راست = +10s، مرکز = play/pause
  void _onDoubleTap(){
    if(_locked) return;
    final third=_size.width/3;
    if(_doubleTapPos.dx<third){
      // چپ = عقب
      var t=_position-const Duration(seconds:10);
      if(t<Duration.zero)t=Duration.zero;
      player.seek(t);_showOverlay('⏮ ۱۰ ثانیه');
    } else if(_doubleTapPos.dx>third*2){
      // راست = جلو
      player.seek(_position+const Duration(seconds:10));_showOverlay('۱۰ ثانیه ⏭');
    } else {
      // وسط = play/pause
      _playing?player.pause():player.play();
      _showOverlay(_playing?'⏸':'▶');
      _startHideTimer();
    }
  }

  Future<double> _getBrightness()async{try{return await ScreenBrightness().application;}catch(_){return 0.5;}}
  Future<void> _setBrightness(double v)async{try{await ScreenBrightness().setApplicationScreenBrightness(v.clamp(0.0,1.0));}catch(_){}}

  void _onScaleStart(ScaleStartDetails d){
    if(_locked)return;
    _mode=_GMode.none;_baseScale=_scale;_baseOffset=_offset;
    _startFocal=d.localFocalPoint;_seekStartMs=_position.inMilliseconds;_subPaddingStart=_subBottomPadding;
    _getBrightness().then((b)=>_startBrightness=b);
    VolumeController.instance.getVolume().then((v)=>_startSysVolume=v);
  }

  void _onScaleUpdate(ScaleUpdateDetails d){
    if(_locked)return;
    if(d.pointerCount>=2){
      _mode=_GMode.zoom;
      setState((){_scale=(_baseScale*d.scale).clamp(0.05,8.0);_offset=_offset+d.focalPointDelta;});
      return;
    }
    final dx=d.localFocalPoint.dx-_startFocal.dx,dy=d.localFocalPoint.dy-_startFocal.dy;
    if(_mode==_GMode.none){
      if(dx.abs()<8&&dy.abs()<8)return;
      if(_scale>1.05&&dx.abs()<dy.abs()*2){_mode=_GMode.pan;}
      else if(dx.abs()>dy.abs()){_mode=_GMode.seek;}
      else if(_subVisible&&_startFocal.dy>_size.height*0.6){_mode=_GMode.subtitlePos;}
      else if(_startFocal.dx>_size.width/2){_mode=_GMode.brightness;}
      else{_mode=_GMode.volume;}
    }
    switch(_mode){
      case _GMode.pan:setState(()=>_offset=_baseOffset+(d.localFocalPoint-_startFocal));break;
      case _GMode.seek:
        _seekTargetMs=(_seekStartMs+((dx/_size.width)*90000).round()).clamp(0,_duration.inMilliseconds);
        _showOverlay('${fmt(Duration(milliseconds:_seekTargetMs))} / ${fmt(_duration)}');break;
      case _GMode.brightness:
        final nb=(_startBrightness-dy/_size.height).clamp(0.0,1.0);
        _setBrightness(nb);_showOverlay('☀ ${(nb*100).round()}%');break;
      case _GMode.volume:
        final nv=(_startSysVolume-dy/_size.height).clamp(0.0,1.0);
        VolumeController.instance.setVolume(nv);_showOverlay('🔊 ${(nv*100).round()}%');break;
      case _GMode.subtitlePos:
        setState(()=>_subBottomPadding=(_subPaddingStart-dy).clamp(0.0,_size.height*0.92));
        _showOverlay('↕ موقعیت زیرنویس');break;
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

  void _cycleFit(){
    setState(()=>_fit=_fit==BoxFit.contain?BoxFit.cover:_fit==BoxFit.cover?BoxFit.fill:BoxFit.contain);
    _showOverlay(_fit==BoxFit.contain?'عادی':_fit==BoxFit.cover?'پر':' کشیده');
  }

  void _cycleRepeat(){
    setState(()=>_repeatMode=_repeatMode==_Repeat.none?_Repeat.all:_repeatMode==_Repeat.all?_Repeat.one:_Repeat.none);
    _showOverlay(_repeatMode==_Repeat.none?'تکرار: خاموش':_repeatMode==_Repeat.all?'تکرار: همه':'تکرار: یک');
  }

  void _cycleRotation(){
    setState(()=>_rotationDeg=(_rotationDeg+90)%360);
    _showOverlay('چرخش: ${_rotationDeg.toInt()}°');
  }

  @override
  Widget build(BuildContext context){
    _size=MediaQuery.of(context).size;
    final bkm=Store.bookmarked.contains(_curPath);
    final sub=_subText,sub2=_sub2Text;

    return Scaffold(
      backgroundColor:Colors.black,
      body:Stack(children:[
        // ── ویدیو با RepaintBoundary برای screenshot ──
        Positioned.fill(child:ClipRect(child:Transform(
          alignment:Alignment.center,
          transform:Matrix4.identity()..translate(_offset.dx,_offset.dy)..scale(_scale,_scale)..rotateZ(_rotationDeg*3.14159/180),
          child:RepaintBoundary(key:_videoKey,child:Video(
            controller:controller,controls:NoVideoControls,fit:_fit,
            subtitleViewConfiguration:const SubtitleViewConfiguration(
                style:TextStyle(fontSize:0,color:Colors.transparent),padding:EdgeInsets.zero),
          )),
        ))),

        // ── زیرنویس ۱ ──
        if(sub!=null)Positioned(left:12,right:12,bottom:_subBottomPadding,child:Align(
          alignment:_subAlign==TextAlign.right?Alignment.bottomRight:_subAlign==TextAlign.left?Alignment.bottomLeft:Alignment.bottomCenter,
          child:Container(
            padding:const EdgeInsets.symmetric(horizontal:10,vertical:5),
            decoration:BoxDecoration(color:_subBgColor.withOpacity(_bgOpacity),borderRadius:BorderRadius.circular(5)),
            child:Text(sub,textAlign:_subAlign,style:TextStyle(
              fontFamily:_fontFamily.isEmpty?null:_fontFamily,
              fontSize:_fontSize,color:_color,fontWeight:_bold?FontWeight.bold:FontWeight.normal,height:1.4,
            )),
          ),
        )),

        // ── زیرنویس ۲ (بالاتر از اول) ──
        if(sub2!=null)Positioned(left:12,right:12,bottom:_subBottomPadding+_fontSize*1.8+16,child:Align(
          alignment:Alignment.bottomCenter,
          child:Container(
            padding:const EdgeInsets.symmetric(horizontal:10,vertical:5),
            decoration:BoxDecoration(color:Colors.black.withOpacity(0.55),borderRadius:BorderRadius.circular(5)),
            child:Text(sub2,textAlign:TextAlign.center,style:TextStyle(
              fontFamily:_fontFamily.isEmpty?null:_fontFamily,
              fontSize:_fontSize*0.9,color:_color2,fontWeight:FontWeight.bold,height:1.4,
            )),
          ),
        )),

        // ── A-B markers روی صفحه ──
        if(_repeatA!=null||_repeatB!=null)
          Positioned(top:0,left:0,right:0,child:LinearProgressIndicator(
            value:(_duration.inMilliseconds>0&&_repeatA!=null&&_repeatB!=null)
                ?(_repeatB!.inMilliseconds-_repeatA!.inMilliseconds)/_duration.inMilliseconds:0,
            backgroundColor:Colors.white12,color:Colors.orangeAccent.withOpacity(0.6),
          )),

        // ── حالت شب ──
        if(_nightOpacity>0)Positioned.fill(child:IgnorePointer(
            child:Container(color:const Color(0xFFFF7700).withOpacity(_nightOpacity*0.35)))),

        // ── لایه اشاره ──
        if(!_locked)Positioned.fill(child:GestureDetector(
          behavior:HitTestBehavior.opaque,
          onTap:_toggleControls,
          onDoubleTapDown:(d)=>_doubleTapPos=d.localPosition,
          onDoubleTap:_onDoubleTap,
          onLongPress:()=>_playing?player.pause():player.play(),
          onScaleStart:_onScaleStart,
          onScaleUpdate:_onScaleUpdate,
          onScaleEnd:_onScaleEnd,
          child:const SizedBox.expand(),
        )),

        // ── پیام وسط ──
        if(_overlay!=null)Center(child:Container(
          padding:const EdgeInsets.symmetric(horizontal:20,vertical:10),
          decoration:BoxDecoration(color:Colors.black.withOpacity(0.65),borderRadius:BorderRadius.circular(10)),
          child:Text(_overlay!,style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
        )),

        // ── کنترل‌ها ──
        if(_controlsVisible&&!_locked)_buildControls(bkm),

        // ── قفل ──
        if(_locked)Positioned(top:16,left:16,child:SafeArea(child:FloatingActionButton.small(
          backgroundColor:Colors.black54,
          onPressed:()=>setState(()=>_locked=false),
          child:const Icon(Icons.lock),
        ))),
      ]),
    );
  }

  Widget _buildControls(bool bkm){
    return SafeArea(child:Column(children:[
      // ── نوار بالا ──
      Container(
        decoration:const BoxDecoration(gradient:LinearGradient(
          begin:Alignment.topCenter,end:Alignment.bottomCenter,colors:[Colors.black54,Colors.transparent])),
        child:Row(children:[
          IconButton(icon:const Icon(Icons.arrow_back),onPressed:()=>Navigator.pop(context)),
          Expanded(child:Text(p.basename(_curPath),maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:13))),
          // sleep timer indicator
          if(_sleepAt!=null)
            GestureDetector(onTap:_showSleepTimerDialog,child:Padding(padding:const EdgeInsets.symmetric(horizontal:4),
                child:Row(mainAxisSize:MainAxisSize.min,children:[
                  const Icon(Icons.bedtime,size:16,color:Colors.orange),const SizedBox(width:2),
                  Text('${_sleepAt!.difference(DateTime.now()).inMinutes}م',style:const TextStyle(color:Colors.orange,fontSize:12)),
                ]))),
          IconButton(icon:Icon(bkm?Icons.bookmark:Icons.bookmark_border,color:bkm?Colors.amber:Colors.white),
              onPressed:()async{await Store.toggleBookmark(_curPath);setState((){});}),
          IconButton(icon:Icon(Store.favorited.contains(_curPath)?Icons.favorite:Icons.favorite_border,
              color:Store.favorited.contains(_curPath)?Colors.redAccent:Colors.white),
              onPressed:()async{await Store.toggleFavorite(_curPath);setState((){});}),
          IconButton(icon:const Icon(Icons.subtitles),onPressed:_openSettings),
          IconButton(icon:Icon(_landscape?Icons.stay_current_portrait:Icons.screen_rotation),onPressed:_toggleOrientation),
          PopupMenuButton<String>(
            icon:const Icon(Icons.more_vert),
            onSelected:(v){
              switch(v){
                case 'fit':_cycleFit();break;
                case 'rotate':_cycleRotation();break;
                case 'repeat':_cycleRepeat();break;
                case 'night':setState(()=>_nightOpacity=_nightOpacity>0?0:0.6);break;
                case 'lock':setState((){_locked=true;_controlsVisible=false;});break;
                case 'mute':if(_muted){player.setVolume(_savedPlayerVolume);setState(()=>_muted=false);}
                    else{_savedPlayerVolume=player.state.volume;player.setVolume(0);setState(()=>_muted=true);}break;
                case 'audio':_showAudioTrackPicker();break;
                case 'sleep':_showSleepTimerDialog();break;
                case 'screenshot':_takeScreenshot();break;
                case 'copy':_copySubText();break;
              }
            },
            itemBuilder:(_)=>[
              PopupMenuItem(value:'fit',child:Text('اندازه: ${_fit==BoxFit.contain?"عادی":_fit==BoxFit.cover?"پر":"کشیده"}')),
              PopupMenuItem(value:'rotate',child:Text('چرخش: ${_rotationDeg.toInt()}°')),
              PopupMenuItem(value:'repeat',child:Text('تکرار: ${_repeatMode==_Repeat.none?"خاموش":_repeatMode==_Repeat.all?"همه":"یک"}')),
              PopupMenuItem(value:'night',child:Text(_nightOpacity>0?'خاموش حالت شب':'حالت شب')),
              PopupMenuItem(value:'mute',child:Text(_muted?'لغو بی‌صدا':'بی‌صدا')),
              const PopupMenuItem(value:'audio',child:Text('انتخاب تراک صوتی')),
              const PopupMenuItem(value:'sleep',child:Text('تایمر خواب')),
              const PopupMenuItem(value:'screenshot',child:Text('اسکرین‌شات')),
              const PopupMenuItem(value:'copy',child:Text('کپی متن زیرنویس')),
              const PopupMenuItem(value:'lock',child:Text('قفل صفحه')),
            ],
          ),
        ]),
      ),

      // ── وسط: A-B + قبلی/پخش/بعدی ──
      Expanded(child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[
        // A-B buttons
        Row(mainAxisAlignment:MainAxisAlignment.center,children:[
          _abBtn(),
        ]),
        const SizedBox(height:8),
        Row(mainAxisAlignment:MainAxisAlignment.center,children:[
          IconButton(iconSize:44,icon:Icon(Icons.skip_previous,color:_hasPrev?Colors.white:Colors.white24),
              onPressed:_hasPrev?()=>_switchVideo(_playIndex-1):null),
          const SizedBox(width:24),
          IconButton(iconSize:68,icon:Icon(_playing?Icons.pause_circle_filled:Icons.play_circle_filled),
              onPressed:(){_playing?player.pause():player.play();_startHideTimer();}),
          const SizedBox(width:24),
          IconButton(iconSize:44,icon:Icon(Icons.skip_next,color:_hasNext?Colors.white:Colors.white24),
              onPressed:_hasNext?()=>_switchVideo(_playIndex+1):null),
        ]),
      ])),

      // ── نوار پایین ──
      Container(
        decoration:const BoxDecoration(gradient:LinearGradient(
          begin:Alignment.bottomCenter,end:Alignment.topCenter,colors:[Colors.black54,Colors.transparent])),
        padding:const EdgeInsets.fromLTRB(12,0,12,4),
        child:Row(children:[
          Text(fmt(_position),style:const TextStyle(fontSize:12)),
          Expanded(child:Slider(
            min:0,
            max:_duration.inMilliseconds<=0?1.0:_duration.inMilliseconds.toDouble(),
            value:_position.inMilliseconds.clamp(0,_duration.inMilliseconds<=0?0:_duration.inMilliseconds).toDouble(),
            onChanged:(v){player.seek(Duration(milliseconds:v.round()));_startHideTimer();},
          )),
          Text(fmt(_duration),style:const TextStyle(fontSize:12)),
        ]),
      ),
    ]));
  }

  Widget _abBtn()=>Row(mainAxisSize:MainAxisSize.min,children:[
    GestureDetector(
      onTap:(){setState((){_repeatA=_position;});_showOverlay('A: ${fmt(_position)}');},
      child:Container(padding:const EdgeInsets.symmetric(horizontal:10,vertical:4),
        decoration:BoxDecoration(
          color:_repeatA!=null?Colors.orangeAccent:Colors.white24,borderRadius:BorderRadius.circular(6)),
        child:Text(_repeatA!=null?'A: ${fmt(_repeatA!)}':'A',style:const TextStyle(fontSize:12,fontWeight:FontWeight.bold)),
      ),
    ),
    const SizedBox(width:8),
    GestureDetector(
      onTap:(){
        if(_repeatA==null)return;
        setState((){_repeatB=_position;_abActive=true;});
        _showOverlay('B: ${fmt(_position)} — تکرار فعال');
      },
      child:Container(padding:const EdgeInsets.symmetric(horizontal:10,vertical:4),
        decoration:BoxDecoration(
          color:_repeatB!=null?Colors.orangeAccent:Colors.white24,borderRadius:BorderRadius.circular(6)),
        child:Text(_repeatB!=null?'B: ${fmt(_repeatB!)}':'B',style:const TextStyle(fontSize:12,fontWeight:FontWeight.bold)),
      ),
    ),
    if(_repeatA!=null||_repeatB!=null)...[
      const SizedBox(width:8),
      GestureDetector(
        onTap:(){setState((){_repeatA=null;_repeatB=null;_abActive=false;});_showOverlay('A-B پاک شد');},
        child:Container(padding:const EdgeInsets.symmetric(horizontal:8,vertical:4),
          decoration:BoxDecoration(color:Colors.red.withOpacity(0.7),borderRadius:BorderRadius.circular(6)),
          child:const Icon(Icons.clear,size:16)),
      ),
    ],
  ]);

  void _openSettings(){
    showModalBottomSheet(
      context:context,isScrollControlled:true,backgroundColor:const Color(0xFF1C1C22),
      shape:const RoundedRectangleBorder(borderRadius:BorderRadius.vertical(top:Radius.circular(20))),
      builder:(ctx)=>StatefulBuilder(builder:(ctx,setSheet){
        void ch(VoidCallback fn){fn();setSheet((){});setState((){}); }
        return Padding(
          padding:EdgeInsets.fromLTRB(20,16,20,MediaQuery.of(ctx).viewInsets.bottom+24),
          child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
            Center(child:Container(width:40,height:4,decoration:BoxDecoration(color:Colors.white24,borderRadius:BorderRadius.circular(2)))),
            const SizedBox(height:14),

            // نمایش زیرنویس
            SwitchListTile(contentPadding:EdgeInsets.zero,title:const Text('نمایش زیرنویس ۱'),value:_subVisible,
                onChanged:(v)=>ch(()=>_subVisible=v)),

            // اندازه و استایل
            Text('اندازه فونت: ${_fontSize.round()}'),
            Slider(min:8,max:100,value:_fontSize,onChanged:(v)=>ch(()=>_fontSize=v)),
            SwitchListTile(contentPadding:EdgeInsets.zero,title:const Text('Bold (پررنگ)'),value:_bold,
                onChanged:(v)=>ch(()=>_bold=v)),

            // دیلی زیرنویس ۱
            Text('دیلی زیرنویس ۱: $_subDelayMs ms'),
            Row(children:[
              IconButton(icon:const Icon(Icons.remove),onPressed:()=>ch(()=>_subDelayMs-=100)),
              Expanded(child:Slider(min:-5000,max:5000,value:_subDelayMs.toDouble(),
                  onChanged:(v)=>ch(()=>_subDelayMs=v.round()))),
              IconButton(icon:const Icon(Icons.add),onPressed:()=>ch(()=>_subDelayMs+=100)),
            ]),

            // موقعیت زیرنویس
            Text('موقعیت از پایین: ${_subBottomPadding.round()}px  (یا بکش روی صفحه)'),
            Slider(min:0,max:900,value:_subBottomPadding.clamp(0,900),
                onChanged:(v)=>ch(()=>_subBottomPadding=v)),

            const SizedBox(height:8),
            const Text('چینش زیرنویس'),const SizedBox(height:8),
            SegmentedButton<TextAlign>(
              segments:const[
                ButtonSegment(value:TextAlign.right,label:Text('راست'),icon:Icon(Icons.format_align_right,size:16)),
                ButtonSegment(value:TextAlign.center,label:Text('وسط'),icon:Icon(Icons.format_align_center,size:16)),
                ButtonSegment(value:TextAlign.left,label:Text('چپ'),icon:Icon(Icons.format_align_left,size:16)),
              ],
              selected:{_subAlign},
              onSelectionChanged:(s)=>ch(()=>_subAlign=s.first),
            ),

            const SizedBox(height:12),const Text('رنگ متن'),const SizedBox(height:8),
            Wrap(spacing:10,children:_colorChoices.map((c)=>GestureDetector(onTap:()=>ch(()=>_color=c),
              child:Container(width:34,height:34,decoration:BoxDecoration(color:c,shape:BoxShape.circle,
                  border:Border.all(color:c.value==_color.value?Colors.white:Colors.transparent,width:3))))).toList()),

            const SizedBox(height:12),const Text('رنگ پس‌زمینه'),const SizedBox(height:8),
            Wrap(spacing:10,children:_bgColorChoices.map((c){
              final sel=c.value==_subBgColor.value;
              return GestureDetector(onTap:()=>ch(()=>_subBgColor=c),child:Container(width:34,height:34,
                decoration:BoxDecoration(color:c==Colors.transparent?null:c,shape:BoxShape.circle,
                    border:Border.all(color:sel?Colors.white:Colors.white24,width:sel?3:1)),
                child:c==Colors.transparent?const Center(child:Icon(Icons.block,size:18,color:Colors.white38)):null));
            }).toList()),
            const SizedBox(height:8),
            Text('شفافیت پس‌زمینه: ${(_bgOpacity*100).round()}%'),
            Slider(min:0,max:1,value:_bgOpacity,onChanged:(v)=>ch(()=>_bgOpacity=v)),

            const Divider(height:24),

            // زیرنویس ۲ همزمان
            Row(children:[
              Expanded(child:SwitchListTile(contentPadding:EdgeInsets.zero,
                  title:const Text('زیرنویس ۲ (همزمان)'),value:_sub2Visible,
                  onChanged:(v)=>ch(()=>_sub2Visible=v))),
            ]),
            OutlinedButton.icon(onPressed:()=>_pickSubtitle(secondary:true),
                icon:const Icon(Icons.file_open),label:const Text('بارگذاری زیرنویس ۲')),
            if(_sub2Path!=null)Text('فایل: ${p.basename(_sub2Path!)}',style:const TextStyle(fontSize:11,color:Colors.white54)),
            if(_sub2Visible&&_subEntries2.isNotEmpty)...[
              Text('دیلی زیرنویس ۲: $_subDelay2Ms ms'),
              Row(children:[
                IconButton(icon:const Icon(Icons.remove),onPressed:()=>ch(()=>_subDelay2Ms-=100)),
                Expanded(child:Slider(min:-5000,max:5000,value:_subDelay2Ms.toDouble(),
                    onChanged:(v)=>ch(()=>_subDelay2Ms=v.round()))),
                IconButton(icon:const Icon(Icons.add),onPressed:()=>ch(()=>_subDelay2Ms+=100)),
              ]),
              const Text('رنگ زیرنویس ۲'),const SizedBox(height:8),
              Wrap(spacing:10,children:_colorChoices.map((c)=>GestureDetector(onTap:()=>ch(()=>_color2=c),
                child:Container(width:30,height:30,decoration:BoxDecoration(color:c,shape:BoxShape.circle,
                    border:Border.all(color:c.value==_color2.value?Colors.white:Colors.transparent,width:3))))).toList()),
            ],

            const Divider(height:24),

            // فونت
            Row(children:[
              Expanded(child:OutlinedButton.icon(onPressed:()=>_pickFont(),icon:const Icon(Icons.font_download),
                  label:Text(_fontFamily.isEmpty?'انتخاب فونت دلخواه (TTF/OTF)':'فونت: بارگذاری شده'))),
              if(_fontFamily.isNotEmpty)IconButton(icon:const Icon(Icons.clear),onPressed:()=>ch(()=>_fontFamily='')),
            ]),

            const Divider(height:24),

            // تقویت صدا تا ۳۰۰%
            Text('تقویت صدا: ${_ampVolume.round()}%'),
            Slider(min:100,max:300,value:_ampVolume,
                onChanged:(v)=>ch((){_ampVolume=v;player.setVolume(v);})),

            // دیلی صدا
            Row(children:[
              const Text('دیلی صدا (ms): '),
              IconButton(icon:const Icon(Icons.remove),
                  onPressed:()=>ch(()=>_audioDelayMs=(_audioDelayMs-100).clamp(-5000,5000))),
              Expanded(child:Text('$_audioDelayMs ms',textAlign:TextAlign.center,
                  style:const TextStyle(fontWeight:FontWeight.bold))),
              IconButton(icon:const Icon(Icons.add),
                  onPressed:()=>ch(()=>_audioDelayMs=(_audioDelayMs+100).clamp(-5000,5000))),
            ]),

            const Divider(height:24),

            // سرعت تا ۱۰x
            Text('سرعت: ${_speed%1==0?_speed.toInt():_speed}x'),
            Slider(min:0.25,max:10,divisions:39,value:_speed,
                onChanged:(v)=>ch((){_speed=(v*4).round()/4;player.setRate(_speed);})),
            Wrap(spacing:6,children:[0.5,1.0,1.5,2.0,3.0,5.0,10.0].map((s)=>ChoiceChip(
                label:Text('${s%1==0?s.toInt():s}x'),selected:_speed==s,
                onSelected:(_)=>ch((){_speed=s;player.setRate(s);}))).toList()),

            const Divider(height:24),

            // حالت شب
            Text('حالت شب: ${(_nightOpacity*100).round()}%'),
            Slider(min:0,max:1,value:_nightOpacity,activeColor:Colors.orange,
                onChanged:(v)=>ch(()=>_nightOpacity=v)),

            const Divider(height:24),

            // زیرنویس ۱ دستی
            OutlinedButton.icon(onPressed:()=>_pickSubtitle(secondary:false),
                icon:const Icon(Icons.file_open),label:const Text('انتخاب زیرنویس ۱')),
          ])),
        );
      }),
    );
  }
}
