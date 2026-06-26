
// lib/browser.dart — مرورگر فایل، منوی ویدیو، پانل شناور
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path/path.dart' as p;
import 'store.dart';
import 'player.dart';

enum _SortBy { name, date, size, type }

// ─────────────────────────────────────────────────────────────────────────────
// BrowserScreen
// ─────────────────────────────────────────────────────────────────────────────
class BrowserScreen extends StatefulWidget {
  const BrowserScreen({super.key});
  @override State<BrowserScreen> createState()=>_BrowserState();
}

class _BrowserState extends State<BrowserScreen> {
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
  bool _recursiveSearch=false;
  String _searchQuery='';
  List<File> _searchResults=[];
  bool _searchRunning=false;
  final TextEditingController _searchCtrl=TextEditingController();

  @override void initState(){super.initState();_init();}
  @override void dispose(){_searchCtrl.dispose();super.dispose();}

  Future<void> _init()async{await Store.load();await _ensurePermission();}

  // شناسایی همه حافظه‌های موجود (داخلی + SD card + OTG)
  List<Directory> _getStorageDevices() {
    final result = <Directory>[];
    try {
      for (final entity in Directory('/storage').listSync()) {
        if (entity is Directory && p.basename(entity.path) != 'emulated' &&
            p.basename(entity.path) != 'self') {
          result.add(entity);
        }
      }
    } catch(_) {}
    return result;
  }

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
      setState((){_path=path;_dirs=dirs;_videos=vids;_selectMode=false;_selected.clear();
        _searching=false;_searchQuery='';_searchCtrl.clear();_searchResults=[];});
    }catch(_){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('دسترسی ندارید')));
    }
  }

  void _goUp(){
    final parent=p.dirname(_path);
    if(parent!=_path&&parent.startsWith('/storage'))_loadDir(parent);
  }

  // ─── مرتب‌سازی ───
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
    if(_recursiveSearch)return _searchResults;
    return _sortedVideos.where((f)=>p.basename(f.path).toLowerCase().contains(_searchQuery.toLowerCase())).toList();
  }
  List<Directory> get _filteredDirs{
    if(!_searching||_searchQuery.isEmpty)return _dirs;
    if(_recursiveSearch)return [];
    return _dirs.where((d)=>p.basename(d.path).toLowerCase().contains(_searchQuery.toLowerCase())).toList();
  }

  // جستجوی بازگشتی کامل
  Future<void> _runRecursiveSearch(String query)async{
    if(query.isEmpty){setState((){_searchResults=[];_searchRunning=false;});return;}
    setState((){_searchResults=[];_searchRunning=true;});
    final results=<File>[];
    try{
      await for(final entity in Directory(_path).list(recursive:true,followLinks:false)){
        if(entity is File&&kVideoExt.contains(p.extension(entity.path).toLowerCase())&&
            p.basename(entity.path).toLowerCase().contains(query.toLowerCase())){
          results.add(entity);
          if(mounted)setState(()=>_searchResults=List.from(results));
        }
      }
    }catch(_){}
    if(mounted)setState(()=>_searchRunning=false);
  }

  Future<void> _openVideo(File video,[List<File>? playlist,int? idx])async{
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

  // ─── منوی ویدیو ───
  void _showVideoMenu(File f){
    showModalBottomSheet(
      context:context,backgroundColor:const Color(0xFF1C1C22),
      shape:const RoundedRectangleBorder(borderRadius:BorderRadius.vertical(top:Radius.circular(16))),
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
    catch(_){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('خطا در کپی')));}
  }

  Future<void> _moveFile(File f)async{
    final dest=await _pickFolder('انتقال به');
    if(dest==null)return;
    final newPath=p.join(dest,p.basename(f.path));
    try{
      await f.rename(newPath);
    }catch(_){
      try{await f.copy(newPath);await f.delete();}
      catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('خطا در انتقال')));return;}
    }
    _loadDir(_path);
    if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('انتقال موفق')));
  }

  Future<String?> _pickFolder(String title)async{
    final all=[...Store.savedFolders];
    if(all.isEmpty){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('ابتدا یک پوشه را ذخیره کنید')));return null;}
    return showDialog<String>(context:context,builder:(ctx)=>AlertDialog(
      backgroundColor:const Color(0xFF1C1C22),title:Text(title),
      content:Column(mainAxisSize:MainAxisSize.min,children:all.map((folder)=>ListTile(
        leading:const Icon(Icons.folder,color:Color(0xFFFFCB6B)),
        title:Text(p.basename(folder)),
        onTap:()=>Navigator.pop(ctx,folder),
      )).toList()),
    ));
  }

  Future<void> _confirmDelete(List<File> files)async{
    final ok=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
      backgroundColor:const Color(0xFF1C1C22),title:const Text('حذف'),
      content:Text(files.length==1?'«${p.basename(files.first.path)}» حذف شود؟':'${files.length} فایل حذف شود؟'),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('لغو')),
        FilledButton(style:FilledButton.styleFrom(backgroundColor:Colors.red),
            onPressed:()=>Navigator.pop(ctx,true),child:const Text('حذف')),
      ],
    ));
    if(ok!=true)return;
    for(final f in files){try{await f.delete();}catch(_){}}
    _loadDir(_path);
  }

  Future<void> _renameFile(File f)async{
    final ctrl=TextEditingController(text:p.basenameWithoutExtension(f.path));
    final name=await showDialog<String>(context:context,builder:(ctx)=>AlertDialog(
      backgroundColor:const Color(0xFF1C1C22),title:const Text('تغییر نام'),
      content:TextField(controller:ctrl,autofocus:true,decoration:const InputDecoration(hintText:'نام جدید')),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('لغو')),
        FilledButton(onPressed:()=>Navigator.pop(ctx,ctrl.text.trim()),child:const Text('تأیید')),
      ],
    ));
    if(name==null||name.isEmpty)return;
    try{await f.rename(p.join(p.dirname(f.path),'$name${p.extension(f.path)}'));_loadDir(_path);}
    catch(_){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('خطا در تغییر نام')));}
  }

  Future<void> _showRating(File f)async{
    int rating=Store.ratings[f.path]??0;
    await showDialog(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,ss)=>AlertDialog(
      backgroundColor:const Color(0xFF1C1C22),
      title:Text(p.basename(f.path),style:const TextStyle(fontSize:13)),
      content:Column(mainAxisSize:MainAxisSize.min,children:[
        const Text('امتیاز شما'),const SizedBox(height:12),
        Row(mainAxisAlignment:MainAxisAlignment.center,children:List.generate(5,(i)=>IconButton(
          icon:Icon(i<rating?Icons.star:Icons.star_border,color:Colors.amber,size:36),
          onPressed:(){ss(()=>rating=i+1);},
        ))),
      ]),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('لغو')),
        if(rating>0)TextButton(onPressed:()async{await Store.saveRating(f.path,0);Navigator.pop(ctx);setState((){});},child:const Text('حذف')),
        FilledButton(onPressed:()async{await Store.saveRating(f.path,rating);Navigator.pop(ctx);setState((){});},child:const Text('ذخیره')),
      ],
    )));
  }

  Future<void> _showNote(File f)async{
    final ctrl=TextEditingController(text:Store.notes[f.path]??'');
    await showDialog(context:context,builder:(ctx)=>AlertDialog(
      backgroundColor:const Color(0xFF1C1C22),
      title:Text('یادداشت — ${p.basename(f.path)}',style:const TextStyle(fontSize:13)),
      content:TextField(controller:ctrl,maxLines:5,autofocus:true,
          decoration:const InputDecoration(hintText:'یادداشت خود را بنویسید...',border:OutlineInputBorder())),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('لغو')),
        FilledButton(onPressed:()async{await Store.saveNote(f.path,ctrl.text.trim());Navigator.pop(ctx);setState((){});},child:const Text('ذخیره')),
      ],
    ));
  }

  Future<void> _showFileInfo(File f)async{
    final sub=matchSubtitle(f.path);
    String modified='';
    try{modified=f.lastModifiedSync().toString().split('.').first;}catch(_){}
    final dur=await Store.getDur(f.path);
    final rating=Store.ratings[f.path]??0;
    final note=Store.notes[f.path]??'';
    if(!mounted)return;
    showDialog(context:context,builder:(ctx)=>AlertDialog(
      backgroundColor:const Color(0xFF1C1C22),
      title:Text(p.basename(f.path),style:const TextStyle(fontSize:13)),
      content:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
        _iRow(Icons.folder_outlined,'مسیر',p.dirname(f.path)),
        _iRow(Icons.data_usage,'حجم',sizeStr(f)),
        if(dur>0)_iRow(Icons.timer_outlined,'مدت',fmt(Duration(seconds:dur))),
        _iRow(Icons.calendar_today,'تاریخ',modified),
        _iRow(Icons.visibility_outlined,'وضعیت',Store.watched.contains(f.path)?'دیده شده ✓':'دیده نشده'),
        if(rating>0)Padding(padding:const EdgeInsets.symmetric(vertical:3),child:Row(children:[
          const Icon(Icons.star,size:15,color:Colors.amber),const SizedBox(width:6),
          Text('امتیاز: ${'★'*rating}',style:const TextStyle(fontSize:12)),
        ])),
        if(note.isNotEmpty)_iRow(Icons.notes,'یادداشت',note),
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
  Widget build(BuildContext context){
    final isSaved=Store.savedFolders.contains(_path);
    return PopScope(
      canPop:_path==root&&!_selectMode&&!_searching,
      onPopInvokedWithResult:(didPop,_){
        if(!didPop){
          if(_searching){setState((){_searching=false;_searchQuery='';_searchCtrl.clear();_searchResults=[];});}
          else if(_selectMode){setState((){_selectMode=false;_selected.clear();});}
          else{_goUp();}
        }
      },
      child:Scaffold(
        appBar:_selectMode?_selectBar():_normalBar(isSaved),
        body:_buildBody(),
        floatingActionButtonLocation:FloatingActionButtonLocation.centerFloat,
        floatingActionButton:_selectMode?null:_buildFABs(),
      ),
    );
  }

  Widget _buildFABs()=>Row(mainAxisSize:MainAxisSize.min,children:[
    _fab(Icons.history,'تاریخچه',Colors.white70,()=>_openPanel(0)),
    const SizedBox(width:8),
    _fab(Icons.bookmark,'نشانه‌ها',Colors.amber,()=>_openPanel(1)),
    const SizedBox(width:8),
    _fab(Icons.favorite,'علاقه‌مندی',Colors.redAccent,()=>_openPanel(2)),
    const SizedBox(width:8),
    _fab(Icons.push_pin,'پوشه‌ها',Colors.greenAccent,()=>_openPanel(3)),
    const SizedBox(width:8),
    _fab(Icons.settings,'تنظیمات',Colors.white54,()=>_openPanel(4)),
  ]);

  Widget _fab(IconData icon,String tip,Color color,VoidCallback fn)=>
      FloatingActionButton.small(heroTag:tip,tooltip:tip,backgroundColor:const Color(0xFF252530),
          onPressed:fn,child:Icon(icon,size:18,color:color));

  PreferredSizeWidget _normalBar(bool isSaved)=>AppBar(
    title:_searching
        ?Row(children:[
            Expanded(child:TextField(controller:_searchCtrl,autofocus:true,
                decoration:const InputDecoration(hintText:'جستجو...',border:InputBorder.none),
                onChanged:(v){
                  setState(()=>_searchQuery=v);
                  if(_recursiveSearch)_runRecursiveSearch(v);
                })),
            if(_searchRunning)const SizedBox(width:16,height:16,child:CircularProgressIndicator(strokeWidth:2)),
          ])
        :Text(_path==root?'حافظه داخلی':p.basename(_path),overflow:TextOverflow.ellipsis),
    leading:_path!=root?IconButton(icon:const Icon(Icons.arrow_upward),onPressed:_goUp):null,
    actions:[
      if(_searching)IconButton(
        icon:Icon(_recursiveSearch?Icons.manage_search:Icons.search,
            color:_recursiveSearch?Colors.amber:null),
        tooltip:'جستجوی بازگشتی در همه زیرپوشه‌ها',
        onPressed:(){
          setState(()=>_recursiveSearch=!_recursiveSearch);
          if(_recursiveSearch&&_searchQuery.isNotEmpty)_runRecursiveSearch(_searchQuery);
          else setState(()=>_searchResults=[]);
        },
      ),
      IconButton(icon:Icon(_searching?Icons.close:Icons.search),
          onPressed:(){setState((){_searching=!_searching;if(!_searching){_searchQuery='';_searchCtrl.clear();_searchResults=[];_recursiveSearch=false;}});}),
      // دکمه رفتن به حافظه‌های دیگه و مسیر دلخواه
      PopupMenuButton<String>(
        icon:const Icon(Icons.storage),
        tooltip:'انتخاب حافظه',
        onSelected:(path){
          if(path=='__custom__'){
            final ctrl=TextEditingController(text:_path);
            showDialog(context:context,builder:(ctx)=>AlertDialog(
              backgroundColor:const Color(0xFF1C1C22),title:const Text('مسیر دلخواه'),
              content:TextField(controller:ctrl,autofocus:true,
                  decoration:const InputDecoration(hintText:'/storage/emulated/0/...')),
              actions:[
                TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('لغو')),
                FilledButton(onPressed:(){final p=ctrl.text.trim();Navigator.pop(ctx);if(p.isNotEmpty)_loadDir(p);},child:const Text('برو')),
              ],
            ));
          } else {
            _loadDir(path);
          }
        },
        itemBuilder:(_){
          final items = <PopupMenuEntry<String>>[
            const PopupMenuItem(value:'/storage/emulated/0',child:Text('📱 حافظه داخلی')),
            const PopupMenuItem(value:'/storage/emulated/0/Download',child:Text('⬇ دانلودها')),
            const PopupMenuItem(value:'/storage/emulated/0/Movies',child:Text('🎬 فیلم‌ها')),
          ];
          for(final d in _getStorageDevices()){
            items.add(PopupMenuItem(value:d.path,child:Text('💾 کارت SD: \${p.basename(d.path)}')));
          }
          items.add(const PopupMenuDivider());
          items.add(const PopupMenuItem(value:'__custom__',child:Text('📂 مسیر دلخواه...')));
          return items;
        },
      ),
      if(_path!=root)IconButton(
        icon:Icon(isSaved?Icons.push_pin:Icons.push_pin_outlined,color:isSaved?Colors.amber:null),
        onPressed:()async{await Store.toggleSavedFolder(_path);setState((){});},
      ),
      PopupMenuButton<_SortBy>(
        icon:const Icon(Icons.sort),
        onSelected:(v)=>setState((){if(_sortBy==v)_sortDesc=!_sortDesc;else{_sortBy=v;_sortDesc=false;}}),
        itemBuilder:(_)=>[
          PopupMenuItem(value:_SortBy.name,child:Text('نام${_sortBy==_SortBy.name?(_sortDesc?' ↑':' ↓'):''}',)),
          PopupMenuItem(value:_SortBy.date,child:Text('تاریخ${_sortBy==_SortBy.date?(_sortDesc?' ↑':' ↓'):''}',)),
          PopupMenuItem(value:_SortBy.size,child:Text('حجم${_sortBy==_SortBy.size?(_sortDesc?' ↑':' ↓'):''}',)),
          PopupMenuItem(value:_SortBy.type,child:Text('نوع${_sortBy==_SortBy.type?(_sortDesc?' ↑':' ↓'):''}',)),
        ],
      ),
    ],
  );

  PreferredSizeWidget _selectBar()=>AppBar(
    leading:IconButton(icon:const Icon(Icons.close),onPressed:()=>setState((){_selectMode=false;_selected.clear();})),
    title:Text('${_selected.length} انتخاب‌شده'),
    actions:[
      IconButton(icon:const Icon(Icons.select_all),onPressed:()=>setState(()=>_selected.addAll(_filteredVideos.map((v)=>v.path)))),
      IconButton(icon:const Icon(Icons.delete_outline,color:Colors.redAccent),
          onPressed:_selected.isEmpty?null:()=>_confirmDelete(_selected.map((s)=>File(s)).toList())),
    ],
  );

  Widget _buildBody(){
    if(_checking)return const Center(child:CircularProgressIndicator());
    if(!_granted)return Center(child:Padding(padding:const EdgeInsets.all(32),child:Column(mainAxisSize:MainAxisSize.min,children:[
      const Icon(Icons.folder_off,size:64,color:Colors.white38),const SizedBox(height:16),
      const Text('اپ به دسترسی فایل‌ها نیاز دارد.',textAlign:TextAlign.center),const SizedBox(height:20),
      FilledButton.icon(onPressed:_ensurePermission,icon:const Icon(Icons.lock_open),label:const Text('اجازه دسترسی')),
      TextButton(onPressed:openAppSettings,child:const Text('تنظیمات اپ')),
    ])));
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
    if(total==0&&_searchRunning)return const Center(child:Column(mainAxisSize:MainAxisSize.min,children:[
      CircularProgressIndicator(),SizedBox(height:12),Text('جستجو...',style:TextStyle(color:Colors.white54)),
    ]));
    if(total==0)return const Center(child:Text('نتیجه‌ای یافت نشد'));
    return ListView.separated(
      padding:EdgeInsets.only(bottom:MediaQuery.of(context).viewPadding.bottom+90,top:4),itemCount:total,
      separatorBuilder:(_,__)=>const Divider(height:1,color:Color(0xFF222230)),
      itemBuilder:(ctx,i){
        if(i<fDirs.length){
          final d=fDirs[i];
          return ListTile(
            leading:Container(width:44,height:44,decoration:BoxDecoration(color:const Color(0xFF2A2520),borderRadius:BorderRadius.circular(10)),child:const Icon(Icons.folder,color:Color(0xFFFFCB6B))),
            title:Text(p.basename(d.path),maxLines:1,overflow:TextOverflow.ellipsis),
            subtitle:_recursiveSearch?Text(d.path,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:10,color:Colors.white38)):null,
            trailing:const Icon(Icons.chevron_left,color:Colors.white38),
            onTap:()=>_loadDir(d.path),
          );
        }
        final v=fVids[i-fDirs.length];
        final seen=Store.watched.contains(v.path),bkm=Store.bookmarked.contains(v.path);
        final fav=Store.favorited.contains(v.path),hasSub=matchSubtitle(v.path)!=null;
        final sel=_selected.contains(v.path);
        final rating=Store.ratings[v.path]??0;
        final hasNote=Store.notes.containsKey(v.path);
        return ListTile(
          selected:sel,selectedTileColor:const Color(0xFF2A2A4A),
          leading:_selectMode
              ?Checkbox(value:sel,onChanged:(_)=>setState(()=>sel?_selected.remove(v.path):_selected.add(v.path)))
              :Container(width:44,height:44,decoration:BoxDecoration(color:const Color(0xFF1E2433),borderRadius:BorderRadius.circular(10)),
                  child:Icon(seen?Icons.check_circle:Icons.movie,color:seen?Colors.greenAccent:const Color(0xFF82AAFF))),
          title:Text(p.basename(v.path),maxLines:1,overflow:TextOverflow.ellipsis,
              style:TextStyle(color:seen?Colors.greenAccent:Colors.white,fontWeight:seen?FontWeight.w500:FontWeight.normal)),
          subtitle:Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisSize:MainAxisSize.min,children:[
            Row(children:[
              Text(sizeStr(v),style:const TextStyle(fontSize:11,color:Colors.white38)),
              if(hasSub)const Text(' • sub ✓',style:TextStyle(fontSize:11,color:Colors.greenAccent)),
              if(rating>0)Text(' ${'★'*rating}',style:const TextStyle(fontSize:11,color:Colors.amber)),
            ]),
            if(_recursiveSearch)Text(p.dirname(v.path),maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:10,color:Colors.white38)),
          ]),
          trailing:_selectMode?null:Row(mainAxisSize:MainAxisSize.min,children:[
            if(hasNote)const Icon(Icons.notes,color:Colors.white54,size:16),
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
      builder:(ctx)=>SizedBox(height:MediaQuery.of(context).size.height*0.65,
          child:BottomPanel(initialPage:page,
              onVideoTap:(path){Navigator.pop(ctx);_openVideoByPath(path);},
              onFolderTap:(folder){Navigator.pop(ctx);_loadDir(folder);})),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// منوی ویدیو (long press)
// ─────────────────────────────────────────────────────────────────────────────
class VideoMenu extends StatefulWidget {
  final File file;
  final VoidCallback onDone,onInfo,onDelete,onRename,onSelect,onCopy,onMove,onRate,onNote;
  const VideoMenu({super.key,required this.file,required this.onDone,required this.onInfo,
      required this.onDelete,required this.onRename,required this.onSelect,
      required this.onCopy,required this.onMove,required this.onRate,required this.onNote});
  @override State<VideoMenu> createState()=>_VideoMenuState();
}
class _VideoMenuState extends State<VideoMenu>{
  late bool _bkm=Store.bookmarked.contains(widget.file.path);
  late bool _fav=Store.favorited.contains(widget.file.path);
  @override Widget build(BuildContext context)=>Column(mainAxisSize:MainAxisSize.min,children:[
    const SizedBox(height:8),
    Center(child:Container(width:40,height:4,decoration:BoxDecoration(color:Colors.white24,borderRadius:BorderRadius.circular(2)))),
    const SizedBox(height:4),
    ListTile(leading:const Icon(Icons.info_outline),title:const Text('اطلاعات فایل'),onTap:widget.onInfo),
    ListTile(leading:Icon(_bkm?Icons.bookmark:Icons.bookmark_border,color:Colors.amber),title:Text(_bkm?'حذف نشانه':'نشانه‌گذاری'),
        onTap:()async{await Store.toggleBookmark(widget.file.path);setState(()=>_bkm=!_bkm);widget.onDone();}),
    ListTile(leading:Icon(_fav?Icons.favorite:Icons.favorite_border,color:Colors.redAccent),title:Text(_fav?'حذف از علاقه‌مندی':'علاقه‌مندی'),
        onTap:()async{await Store.toggleFavorite(widget.file.path);setState(()=>_fav=!_fav);widget.onDone();}),
    ListTile(leading:const Icon(Icons.star_outline,color:Colors.amber),title:const Text('امتیازدهی'),onTap:widget.onRate),
    ListTile(leading:const Icon(Icons.notes),title:const Text('یادداشت'),onTap:widget.onNote),
    ListTile(leading:const Icon(Icons.copy_outlined),title:const Text('کپی به پوشه'),onTap:widget.onCopy),
    ListTile(leading:const Icon(Icons.drive_file_move_outline),title:const Text('انتقال به پوشه'),onTap:widget.onMove),
    ListTile(leading:const Icon(Icons.edit_outlined),title:const Text('تغییر نام'),onTap:widget.onRename),
    ListTile(leading:const Icon(Icons.delete_outline,color:Colors.redAccent),title:const Text('حذف',style:TextStyle(color:Colors.redAccent)),onTap:widget.onDelete),
    ListTile(leading:const Icon(Icons.select_all),title:const Text('انتخاب گروهی'),onTap:widget.onSelect),
    const SizedBox(height:8),
  ]);
}

// ─────────────────────────────────────────────────────────────────────────────
// پانل شناور
// ─────────────────────────────────────────────────────────────────────────────
class BottomPanel extends StatefulWidget {
  final int initialPage;
  final ValueChanged<String> onVideoTap,onFolderTap;
  const BottomPanel({super.key,required this.initialPage,required this.onVideoTap,required this.onFolderTap});
  @override State<BottomPanel> createState()=>_BottomPanelState();
}
class _BottomPanelState extends State<BottomPanel> with SingleTickerProviderStateMixin{
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
      _historyTab(),
      _vList(Store.bookmarked.toList().reversed.toList(),Icons.bookmark,Colors.amber),
      _vList(Store.favorited.toList().reversed.toList(),Icons.favorite,Colors.redAccent),
      _folderList(),
      _settingsTab(),
    ])),
  ]);

  Widget _historyTab(){
    return Column(children:[
      if(Store.watchHistory.isNotEmpty)Padding(
        padding:const EdgeInsets.symmetric(horizontal:12,vertical:6),
        child:Row(children:[
          const Expanded(child:Text('آخرین مشاهده‌ها',style:TextStyle(fontWeight:FontWeight.bold))),
          TextButton.icon(icon:const Icon(Icons.delete_sweep,size:16),label:const Text('حذف همه'),
            style:TextButton.styleFrom(foregroundColor:Colors.redAccent),
            onPressed:()async{
              final ok=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
                backgroundColor:const Color(0xFF1C1C22),title:const Text('حذف همه تاریخچه؟'),
                actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('لغو')),
                  FilledButton(style:FilledButton.styleFrom(backgroundColor:Colors.red),
                    onPressed:()=>Navigator.pop(ctx,true),child:const Text('حذف'))],
              ));
              if(ok==true){await Store.clearHistory();setState((){}); }
            }),
        ]),
      ),
      Expanded(child:_vList(Store.watchHistory,Icons.history,Colors.white70,
          onLongPress:(path)async{await Store.removeFromHistory(path);setState((){}); })),
    ]);
  }

  Widget _vList(List<String> paths,IconData icon,Color color,{Function(String)? onLongPress}){
    if(paths.isEmpty)return Center(child:Column(mainAxisSize:MainAxisSize.min,children:[
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
        onLongPress:onLongPress!=null?()=>onLongPress(path):null,
      );
    });
  }

  Widget _folderList(){
    final folders=Store.savedFolders;
    if(folders.isEmpty)return const Center(child:Column(mainAxisSize:MainAxisSize.min,children:[
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
            onPressed:()async{await Store.toggleSavedFolder(folder);setState((){}); }),
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
