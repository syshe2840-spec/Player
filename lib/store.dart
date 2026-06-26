// lib/store.dart — تمام داده‌های ذخیره‌شده + مدل‌ها + ابزارها
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;
import 'dart:io';

// ─── ثابت‌ها ───
const Set<String> kVideoExt = {
  '.mp4','.mkv','.avi','.mov','.webm','.m4v',
  '.3gp','.flv','.ts','.m2ts','.wmv','.mpg','.mpeg',
};
const List<String> kSubExt = ['.srt','.ass','.ssa','.vtt'];

// فونت‌های پیش‌فرض
const List<(String label, String family)> kDefaultFonts = [
  ('پیش‌فرض', ''),
  ('سریف', 'serif'),
  ('تک‌فاصله', 'monospace'),
  ('فشرده', 'sans-serif-condensed'),
  ('نازک', 'sans-serif-light'),
  ('ایتالیک', 'cursive'),
];

// ─── ابزارها ───
String fmt(Duration d) {
  String two(int n) => n.toString().padLeft(2,'0');
  final h = d.inHours;
  return h>0
      ? '$h:${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))}'
      : '${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))}';
}

String sizeStr(File f) {
  try {
    final b = f.lengthSync();
    if (b>1073741824) return '${(b/1073741824).toStringAsFixed(1)}GB';
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

// ─── تجزیه SRT ───
class SubEntry {
  final Duration start, end;
  final String text;
  const SubEntry(this.start, this.end, this.text);
}

Duration _parseSrtTime(String s) {
  final clean = s.trim().replaceAll(',','.');
  final parts = clean.split(':');
  if (parts.length!=3) return Duration.zero;
  final sm = parts[2].split('.');
  return Duration(
    hours:int.tryParse(parts[0])??0,
    minutes:int.tryParse(parts[1])??0,
    seconds:int.tryParse(sm[0])??0,
    milliseconds:sm.length>1?int.tryParse(sm[1].padRight(3,'0').substring(0,3))??0:0,
  );
}

List<SubEntry> parseSrt(String raw) {
  final entries = <SubEntry>[];
  for (final block in raw.replaceAll('\r\n','\n').replaceAll('\r','\n').trim().split(RegExp(r'\n\n+'))) {
    final lines = block.trim().split('\n');
    if (lines.length<2) continue;
    for (int i=0;i<lines.length-1;i++) {
      final m = RegExp(r'(\d+:\d+:\d+[,.]\d+)\s*-->\s*(\d+:\d+:\d+[,.]\d+)').firstMatch(lines[i]);
      if (m!=null) {
        final text = lines.sublist(i+1).join('\n').trim();
        if (text.isNotEmpty) entries.add(SubEntry(_parseSrtTime(m.group(1)!),_parseSrtTime(m.group(2)!),text));
        break;
      }
    }
  }
  return entries;
}

// ─── تنظیمات ویدیو (قابل ذخیره per-video) ───
class VideoSettings {
  double fontSize;
  bool bold;
  int textColor;
  int bgColor;
  double bgOpacity;
  int textAlign; // TextAlign.index
  double bottomPadding;
  String fontFamily;
  double speed;
  double nightOpacity;

  VideoSettings({
    this.fontSize=30,this.bold=true,this.textColor=0xFFFFFFFF,
    this.bgColor=0xFF000000,this.bgOpacity=0.5,this.textAlign=1,
    this.bottomPadding=50,this.fontFamily='',this.speed=1.0,this.nightOpacity=0,
  });

  Map<String,dynamic> toMap()=>{'fontSize':fontSize,'bold':bold,'textColor':textColor,
    'bgColor':bgColor,'bgOpacity':bgOpacity,'textAlign':textAlign,
    'bottomPadding':bottomPadding,'fontFamily':fontFamily,'speed':speed,'nightOpacity':nightOpacity};

  factory VideoSettings.fromMap(Map<String,dynamic> m)=>VideoSettings(
    fontSize:(m['fontSize']as num? ??30).toDouble(),
    bold:m['bold']as bool? ??true,
    textColor:m['textColor']as int? ??0xFFFFFFFF,
    bgColor:m['bgColor']as int? ??0xFF000000,
    bgOpacity:(m['bgOpacity']as num? ??0.5).toDouble(),
    textAlign:m['textAlign']as int? ??1,
    bottomPadding:(m['bottomPadding']as num? ??50).toDouble(),
    fontFamily:m['fontFamily']as String? ??'',
    speed:(m['speed']as num? ??1.0).toDouble(),
    nightOpacity:(m['nightOpacity']as num? ??0).toDouble(),
  );
}

// ─── Store ───
class Store {
  static Set<String> watched = {};
  static Set<String> bookmarked = {};
  static Set<String> favorited = {};
  static List<String> savedFolders = [];
  static List<String> watchHistory = [];
  static Map<String,int> ratings = {};
  static Map<String,String> notes = {};
  static Map<String,String> _vsMap = {};
  static final Map<String,int> _durCache = {};

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    watched = (prefs.getStringList('watched')??[]).toSet();
    bookmarked = (prefs.getStringList('bookmarks')??[]).toSet();
    favorited = (prefs.getStringList('favorites')??[]).toSet();
    savedFolders = prefs.getStringList('savedFolders')??[];
    watchHistory = prefs.getStringList('watchHistory')??[];
    final rJson = prefs.getString('ratings');
    if (rJson!=null) {
      final m = json.decode(rJson) as Map;
      ratings = m.map((k,v)=>MapEntry(k as String,v as int));
    }
    final nJson = prefs.getString('notes');
    if (nJson!=null) {
      final m = json.decode(nJson) as Map;
      notes = m.map((k,v)=>MapEntry(k as String,v as String));
    }
    final vsJson = prefs.getString('vsMap');
    if (vsJson!=null) {
      final m = json.decode(vsJson) as Map;
      _vsMap = m.map((k,v)=>MapEntry(k as String,v as String));
    }
  }

  static Future<void> _save(String key,dynamic val)async{
    final p=await SharedPreferences.getInstance();
    if (val is String) p.setString(key,val);
    else if (val is List<String>) p.setStringList(key,val);
  }

  static Future<void> markWatched(String path) async {
    watched.add(path); _save('watched',watched.toList());
  }
  static Future<void> toggleBookmark(String path) async {
    bookmarked.contains(path)?bookmarked.remove(path):bookmarked.add(path);
    _save('bookmarks',bookmarked.toList());
  }
  static Future<void> toggleFavorite(String path) async {
    favorited.contains(path)?favorited.remove(path):favorited.add(path);
    _save('favorites',favorited.toList());
  }
  static Future<void> toggleSavedFolder(String path) async {
    savedFolders.contains(path)?savedFolders.remove(path):savedFolders.add(path);
    _save('savedFolders',savedFolders);
  }
  static Future<void> addToHistory(String path) async {
    watchHistory.remove(path); watchHistory.insert(0,path);
    if (watchHistory.length>100) watchHistory=watchHistory.sublist(0,100);
    _save('watchHistory',watchHistory);
  }
  static Future<void> removeFromHistory(String path) async {
    watchHistory.remove(path); _save('watchHistory',watchHistory);
  }
  static Future<void> clearHistory() async {
    watchHistory.clear(); _save('watchHistory',[]);
  }
  static Future<void> saveRating(String path, int rating) async {
    rating==0?ratings.remove(path):ratings[path]=rating;
    _save('ratings',json.encode(ratings));
  }
  static Future<void> saveNote(String path, String note) async {
    note.isEmpty?notes.remove(path):notes[path]=note;
    _save('notes',json.encode(notes));
  }
  static Future<void> saveVideoSettings(String path, VideoSettings vs) async {
    _vsMap[path]=json.encode(vs.toMap());
    _save('vsMap',json.encode(_vsMap));
  }
  static VideoSettings? loadVideoSettings(String path) {
    final s=_vsMap[path];
    if (s==null) return null;
    try { return VideoSettings.fromMap(json.decode(s) as Map<String,dynamic>); }
    catch(_){ return null; }
  }
  static Future<void> savePos(String path, Duration pos) async =>
      (await SharedPreferences.getInstance()).setInt('pos:$path',pos.inSeconds);
  static Future<Duration> getPos(String path) async {
    final p=await SharedPreferences.getInstance();
    return Duration(seconds:p.getInt('pos:$path')??0);
  }
  static Future<void> saveDur(String path, int s) async {
    _durCache[path]=s;
    (await SharedPreferences.getInstance()).setInt('dur:$path',s);
  }
  static Future<int> getDur(String path) async {
    if (_durCache.containsKey(path)) return _durCache[path]!;
    final p=await SharedPreferences.getInstance();
    return _durCache[path]=p.getInt('dur:$path')??0;
  }
}

