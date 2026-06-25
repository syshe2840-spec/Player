import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:path/path.dart' as p;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const MyApp());
}

// ─────────────────────────────────────────────────────────────────────────────
// ثابت‌ها و ابزارها
// ─────────────────────────────────────────────────────────────────────────────
const Set<String> kVideoExt = {
  '.mp4', '.mkv', '.avi', '.mov', '.webm', '.m4v',
  '.3gp', '.flv', '.ts', '.m2ts', '.wmv', '.mpg', '.mpeg',
};
const List<String> kSubExt = ['.srt', '.ass', '.ssa', '.vtt'];

String fmt(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  final h = d.inHours;
  return h > 0
      ? '$h:${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))}'
      : '${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))}';
}

String sizeStr(File f) {
  try {
    final b = f.lengthSync();
    if (b > 1073741824) return '${(b / 1073741824).toStringAsFixed(1)} گیگابایت';
    return '${(b / 1048576).toStringAsFixed(0)} مگابایت';
  } catch (_) { return ''; }
}

String? matchSubtitle(String videoPath) {
  final dir = p.dirname(videoPath);
  final base = p.basenameWithoutExtension(videoPath);
  for (final ext in kSubExt) {
    final c = p.join(dir, '$base$ext');
    if (File(c).existsSync()) return c;
  }
  return null;
}

// ─────────────────────────────────────────────────────────────────────────────
// زیرنویس: تجزیه SRT
// ─────────────────────────────────────────────────────────────────────────────
class SubEntry {
  final Duration start, end;
  final String text;
  const SubEntry(this.start, this.end, this.text);
}

Duration _parseSrtTime(String s) {
  final clean = s.trim().replaceAll(',', '.');
  final parts = clean.split(':');
  if (parts.length != 3) return Duration.zero;
  final sm = parts[2].split('.');
  return Duration(
    hours: int.tryParse(parts[0]) ?? 0,
    minutes: int.tryParse(parts[1]) ?? 0,
    seconds: int.tryParse(sm[0]) ?? 0,
    milliseconds: sm.length > 1
        ? int.tryParse(sm[1].padRight(3, '0').substring(0, 3)) ?? 0
        : 0,
  );
}

List<SubEntry> parseSrt(String raw) {
  final entries = <SubEntry>[];
  final blocks = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim()
      .split(RegExp(r'\n\n+'));
  for (final block in blocks) {
    final lines = block.trim().split('\n');
    if (lines.length < 2) continue;
    for (int i = 0; i < lines.length - 1; i++) {
      final m = RegExp(
              r'(\d+:\d+:\d+[,.]\d+)\s*-->\s*(\d+:\d+:\d+[,.]\d+)')
          .firstMatch(lines[i]);
      if (m != null) {
        final text = lines.sublist(i + 1).join('\n').trim();
        if (text.isNotEmpty) {
          entries.add(SubEntry(
              _parseSrtTime(m.group(1)!), _parseSrtTime(m.group(2)!), text));
        }
        break;
      }
    }
  }
  return entries;
}

// ─────────────────────────────────────────────────────────────────────────────
// Store
// ─────────────────────────────────────────────────────────────────────────────
class Store {
  static Set<String> watched = {};
  static Set<String> bookmarked = {};
  static Set<String> favorited = {};
  static final Map<String, int> _durCache = {};

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    watched = (prefs.getStringList('watched') ?? []).toSet();
    bookmarked = (prefs.getStringList('bookmarks') ?? []).toSet();
    favorited = (prefs.getStringList('favorites') ?? []).toSet();
  }

  static Future<void> markWatched(String path) async {
    if (watched.contains(path)) return;
    watched.add(path);
    final p = await SharedPreferences.getInstance();
    await p.setStringList('watched', watched.toList());
  }

  static Future<void> toggleBookmark(String path) async {
    bookmarked.contains(path) ? bookmarked.remove(path) : bookmarked.add(path);
    final p = await SharedPreferences.getInstance();
    await p.setStringList('bookmarks', bookmarked.toList());
  }

  static Future<void> toggleFavorite(String path) async {
    favorited.contains(path) ? favorited.remove(path) : favorited.add(path);
    final p = await SharedPreferences.getInstance();
    await p.setStringList('favorites', favorited.toList());
  }

  static Future<void> savePos(String path, Duration pos) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt('pos:$path', pos.inSeconds);
  }

  static Future<Duration> getPos(String path) async {
    final p = await SharedPreferences.getInstance();
    return Duration(seconds: p.getInt('pos:$path') ?? 0);
  }

  static Future<void> saveDur(String path, int seconds) async {
    _durCache[path] = seconds;
    final p = await SharedPreferences.getInstance();
    await p.setInt('dur:$path', seconds);
  }

  static Future<int> getDur(String path) async {
    if (_durCache.containsKey(path)) return _durCache[path]!;
    final p = await SharedPreferences.getInstance();
    return _durCache[path] = p.getInt('dur:$path') ?? 0;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// App
// ─────────────────────────────────────────────────────────────────────────────
class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'پلیر زیرنویس',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          colorSchemeSeed: const Color(0xFF6C63FF),
          scaffoldBackgroundColor: const Color(0xFF101014),
        ),
        builder: (ctx, child) =>
            Directionality(textDirection: TextDirection.rtl, child: child!),
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
  static const String root = '/storage/emulated/0';
  bool _granted = false;
  bool _checking = true;
  String _path = root;
  List<Directory> _dirs = [];
  List<File> _videos = [];

  // حالت انتخاب چندگانه
  bool _selectMode = false;
  final Set<String> _selected = {};

  @override
  void initState() { super.initState(); _init(); }

  Future<void> _init() async { await Store.load(); await _ensurePermission(); }

  Future<void> _ensurePermission() async {
    setState(() => _checking = true);
    var ok = await Permission.manageExternalStorage.isGranted;
    if (!ok) ok = (await Permission.manageExternalStorage.request()).isGranted;
    if (!ok) ok = (await Permission.storage.request()).isGranted;
    setState(() { _granted = ok; _checking = false; });
    if (ok) _loadDir(_path);
  }

  void _loadDir(String path) {
    try {
      final items = Directory(path).listSync(followLinks: false);
      final dirs = items.whereType<Directory>().toList();
      final vids = items.whereType<File>().where(
          (f) => kVideoExt.contains(p.extension(f.path).toLowerCase())).toList();
      int cmp(FileSystemEntity a, FileSystemEntity b) =>
          p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase());
      dirs.sort(cmp); vids.sort(cmp);
      setState(() { _path = path; _dirs = dirs; _videos = vids; _selectMode = false; _selected.clear(); });
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('به این پوشه دسترسی نیست')));
    }
  }

  void _goUp() {
    final parent = p.dirname(_path);
    if (parent != _path && parent.startsWith('/storage')) _loadDir(parent);
  }

  Future<void> _openVideo(File video) async {
    await Navigator.push(context, MaterialPageRoute(
      builder: (_) => PlayerScreen(
        subtitlePath: matchSubtitle(video.path),
        playlist: _videos,
        playlistIndex: _videos.indexOf(video),
      ),
    ));
    await Store.load();
    if (mounted) setState(() {});
  }

  Future<void> _openVideoByPath(String path) async {
    final f = File(path);
    if (!f.existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('فایل یافت نشد')));
      return;
    }
    await Navigator.push(context, MaterialPageRoute(
      builder: (_) => PlayerScreen(
        subtitlePath: matchSubtitle(path),
        playlist: [f],
        playlistIndex: 0,
      ),
    ));
    await Store.load();
    if (mounted) setState(() {});
  }

  // ───── منوی ویدیو (نگه داشتن) ─────
  void _showVideoMenu(File f) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C22),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => _VideoMenu(
        file: f,
        onRefresh: () async {
          Navigator.pop(ctx);
          await Store.load();
          _loadDir(_path);
        },
        onInfo: () { Navigator.pop(ctx); _showFileInfo(f); },
        onDelete: () { Navigator.pop(ctx); _confirmDelete([f]); },
        onRename: () { Navigator.pop(ctx); _renameFile(f); },
        onSelect: () { Navigator.pop(ctx); setState(() { _selectMode = true; _selected.add(f.path); }); },
      ),
    );
  }

  Future<void> _confirmDelete(List<File> files) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C22),
        title: const Text('حذف فایل'),
        content: Text(files.length == 1
            ? '«${p.basename(files.first.path)}» حذف شود؟'
            : '${files.length} فایل حذف شود؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('لغو')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    for (final f in files) {
      try { await f.delete(); } catch (_) {}
    }
    _loadDir(_path);
  }

  Future<void> _renameFile(File f) async {
    final ctrl = TextEditingController(text: p.basenameWithoutExtension(f.path));
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C22),
        title: const Text('تغییر نام'),
        content: TextField(controller: ctrl, autofocus: true,
            decoration: const InputDecoration(hintText: 'نام جدید')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('لغو')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('تأیید')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    try {
      final ext = p.extension(f.path);
      await f.rename(p.join(p.dirname(f.path), '$name$ext'));
      _loadDir(_path);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('خطا در تغییر نام')));
    }
  }

  Future<void> _showFileInfo(File f) async {
    final sub = matchSubtitle(f.path);
    String modified = '';
    try { modified = f.lastModifiedSync().toString().split('.').first; } catch (_) {}
    final dur = await Store.getDur(f.path);
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C22),
        title: Text(p.basename(f.path), style: const TextStyle(fontSize: 13)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _iRow(Icons.folder_outlined, 'مسیر', p.dirname(f.path)),
            _iRow(Icons.data_usage, 'حجم', sizeStr(f)),
            if (dur > 0) _iRow(Icons.timer_outlined, 'مدت', fmt(Duration(seconds: dur))),
            _iRow(Icons.calendar_today, 'تاریخ تغییر', modified),
            _iRow(Icons.visibility_outlined, 'وضعیت',
                Store.watched.contains(f.path) ? 'دیده شده ✓' : 'دیده نشده'),
            _iRow(Icons.bookmark_outline, 'نشانه',
                Store.bookmarked.contains(f.path) ? 'نشانه‌گذاری شده ★' : 'بدون نشانه'),
            _iRow(Icons.favorite_outline, 'علاقه‌مندی',
                Store.favorited.contains(f.path) ? 'در علاقه‌مندی‌ها ❤' : 'ندارد'),
            _iRow(Icons.subtitles_outlined, 'زیرنویس',
                sub != null ? p.basename(sub) : 'یافت نشد'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('بستن')),
        ],
      ),
    );
  }

  Widget _iRow(IconData icon, String label, String val) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 15, color: Colors.white38),
      const SizedBox(width: 6),
      Text('$label: ', style: const TextStyle(color: Colors.white54, fontSize: 12)),
      Expanded(child: Text(val, style: const TextStyle(fontSize: 12),
          overflow: TextOverflow.ellipsis, maxLines: 2)),
    ]),
  );

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _path == root && !_selectMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          if (_selectMode) { setState(() { _selectMode = false; _selected.clear(); }); }
          else { _goUp(); }
        }
      },
      child: Scaffold(
        appBar: _selectMode ? _selectAppBar() : _normalAppBar(),
        body: _buildBody(),
        // ─── سه دکمه شناور پایین ───
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
        floatingActionButton: _selectMode ? null : Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _fabBtn(Icons.bookmark, 'نشانه‌ها', () => _openPanel(0)),
            const SizedBox(width: 12),
            _fabBtn(Icons.favorite, 'علاقه‌مندی‌ها', () => _openPanel(1)),
            const SizedBox(width: 12),
            _fabBtn(Icons.settings, 'تنظیمات', () => _openPanel(2)),
          ],
        ),
      ),
    );
  }

  Widget _fabBtn(IconData icon, String tooltip, VoidCallback onTap) =>
      FloatingActionButton.small(
        heroTag: tooltip,
        tooltip: tooltip,
        backgroundColor: const Color(0xFF2A2A3A),
        onPressed: onTap,
        child: Icon(icon, size: 20),
      );

  PreferredSizeWidget _normalAppBar() => AppBar(
    title: Text(_path == root ? 'حافظه داخلی' : p.basename(_path),
        overflow: TextOverflow.ellipsis),
    leading: _path != root
        ? IconButton(icon: const Icon(Icons.arrow_upward), onPressed: _goUp)
        : null,
    actions: [
      PopupMenuButton<String>(
        icon: const Icon(Icons.folder_special_outlined),
        onSelected: _loadDir,
        itemBuilder: (_) => const [
          PopupMenuItem(value: root, child: Text('حافظه داخلی')),
          PopupMenuItem(value: '$root/Download', child: Text('دانلودها')),
          PopupMenuItem(value: '$root/Movies', child: Text('فیلم‌ها')),
          PopupMenuItem(value: '$root/DCIM', child: Text('دوربین')),
        ],
      ),
    ],
  );

  PreferredSizeWidget _selectAppBar() => AppBar(
    leading: IconButton(
      icon: const Icon(Icons.close),
      onPressed: () => setState(() { _selectMode = false; _selected.clear(); }),
    ),
    title: Text('${_selected.length} انتخاب‌شده'),
    actions: [
      IconButton(
        icon: const Icon(Icons.select_all),
        onPressed: () => setState(() => _selected.addAll(_videos.map((v) => v.path))),
      ),
      IconButton(
        icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
        onPressed: _selected.isEmpty ? null : () =>
            _confirmDelete(_selected.map((p) => File(p)).toList()),
      ),
    ],
  );

  Widget _buildBody() {
    if (_checking) return const Center(child: CircularProgressIndicator());
    if (!_granted) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.folder_off, size: 64, color: Colors.white38),
          const SizedBox(height: 16),
          const Text('برای مرور فیلم‌ها، اپ به دسترسی فایل‌ها نیاز دارد.',
              textAlign: TextAlign.center),
          const SizedBox(height: 20),
          FilledButton.icon(onPressed: _ensurePermission,
              icon: const Icon(Icons.lock_open), label: const Text('اجازه دسترسی')),
          TextButton(onPressed: openAppSettings, child: const Text('تنظیمات اپ')),
        ]),
      ));
    }
    return Column(children: [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        color: const Color(0xFF1A1A22),
        child: Text(_path, style: const TextStyle(fontSize: 11, color: Colors.white38),
            overflow: TextOverflow.ellipsis),
      ),
      Expanded(child: _buildList()),
    ]);
  }

  Widget _buildList() {
    final total = _dirs.length + _videos.length;
    if (total == 0) return const Center(child: Text('این پوشه خالی است'));
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 80, top: 4),
      itemCount: total,
      separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFF222230)),
      itemBuilder: (ctx, i) {
        if (i < _dirs.length) {
          final d = _dirs[i];
          return ListTile(
            leading: Container(
              width: 44, height: 44,
              decoration: BoxDecoration(color: const Color(0xFF2A2520),
                  borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.folder, color: Color(0xFFFFCB6B)),
            ),
            title: Text(p.basename(d.path), maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: const Icon(Icons.chevron_left, color: Colors.white38),
            onTap: () => _loadDir(d.path),
          );
        }
        final v = _videos[i - _dirs.length];
        final seen = Store.watched.contains(v.path);
        final bkm = Store.bookmarked.contains(v.path);
        final fav = Store.favorited.contains(v.path);
        final hasSub = matchSubtitle(v.path) != null;
        final sel = _selected.contains(v.path);

        return ListTile(
          selected: sel,
          selectedTileColor: const Color(0xFF2A2A4A),
          leading: _selectMode
              ? Checkbox(
                  value: sel,
                  onChanged: (_) => setState(() {
                    sel ? _selected.remove(v.path) : _selected.add(v.path);
                  }),
                )
              : Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(color: const Color(0xFF1E2433),
                      borderRadius: BorderRadius.circular(10)),
                  child: Icon(seen ? Icons.check_circle : Icons.movie,
                      color: seen ? Colors.greenAccent : const Color(0xFF82AAFF)),
                ),
          title: Text(p.basename(v.path), maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: seen ? Colors.greenAccent : Colors.white,
                fontWeight: seen ? FontWeight.w500 : FontWeight.normal,
              )),
          subtitle: Row(children: [
            Text(sizeStr(v), style: const TextStyle(fontSize: 11, color: Colors.white38)),
            if (hasSub) const Text(' • زیرنویس ✓',
                style: TextStyle(fontSize: 11, color: Colors.greenAccent)),
          ]),
          trailing: _selectMode ? null : Row(mainAxisSize: MainAxisSize.min, children: [
            if (fav) const Icon(Icons.favorite, color: Colors.redAccent, size: 18),
            if (bkm) const Icon(Icons.bookmark, color: Colors.amber, size: 18),
            const SizedBox(width: 4),
            const Icon(Icons.play_circle_outline, size: 24),
          ]),
          onTap: _selectMode
              ? () => setState(() { sel ? _selected.remove(v.path) : _selected.add(v.path); })
              : () => _openVideo(v),
          onLongPress: _selectMode ? null : () => _showVideoMenu(v),
        );
      },
    );
  }

  // ───── پانل شناور پایین ─────
  void _openPanel(int initialPage) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1C1C22),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: _BottomPanel(
          initialPage: initialPage,
          onVideoTap: (path) { Navigator.pop(ctx); _openVideoByPath(path); },
        ),
      ),
    );
  }
}

// ───── منوی ویدیو ─────
class _VideoMenu extends StatefulWidget {
  final File file;
  final VoidCallback onRefresh, onInfo, onDelete, onRename, onSelect;
  const _VideoMenu({required this.file, required this.onRefresh,
      required this.onInfo, required this.onDelete, required this.onRename,
      required this.onSelect});
  @override
  State<_VideoMenu> createState() => _VideoMenuState();
}
class _VideoMenuState extends State<_VideoMenu> {
  bool _bkm = false;
  bool _fav = false;
  @override
  void initState() {
    super.initState();
    _bkm = Store.bookmarked.contains(widget.file.path);
    _fav = Store.favorited.contains(widget.file.path);
  }
  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      const SizedBox(height: 8),
      Center(child: Container(width: 40, height: 4,
          decoration: BoxDecoration(color: Colors.white24,
              borderRadius: BorderRadius.circular(2)))),
      const SizedBox(height: 8),
      ListTile(leading: const Icon(Icons.info_outline), title: const Text('اطلاعات فایل'), onTap: widget.onInfo),
      ListTile(
        leading: Icon(_bkm ? Icons.bookmark : Icons.bookmark_border, color: Colors.amber),
        title: Text(_bkm ? 'حذف نشانه' : 'نشانه‌گذاری'),
        onTap: () async {
          await Store.toggleBookmark(widget.file.path);
          setState(() => _bkm = !_bkm);
          widget.onRefresh();
        },
      ),
      ListTile(
        leading: Icon(_fav ? Icons.favorite : Icons.favorite_border, color: Colors.redAccent),
        title: Text(_fav ? 'حذف از علاقه‌مندی' : 'افزودن به علاقه‌مندی'),
        onTap: () async {
          await Store.toggleFavorite(widget.file.path);
          setState(() => _fav = !_fav);
          widget.onRefresh();
        },
      ),
      ListTile(leading: const Icon(Icons.edit_outlined), title: const Text('تغییر نام'), onTap: widget.onRename),
      ListTile(
        leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
        title: const Text('حذف', style: TextStyle(color: Colors.redAccent)),
        onTap: widget.onDelete,
      ),
      ListTile(leading: const Icon(Icons.select_all), title: const Text('انتخاب'), onTap: widget.onSelect),
      const SizedBox(height: 8),
    ]);
  }
}

// ───── پانل شناور: نشانه‌ها / علاقه‌مندی‌ها / تنظیمات ─────
class _BottomPanel extends StatefulWidget {
  final int initialPage;
  final ValueChanged<String> onVideoTap;
  const _BottomPanel({required this.initialPage, required this.onVideoTap});
  @override
  State<_BottomPanel> createState() => _BottomPanelState();
}
class _BottomPanelState extends State<_BottomPanel>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this, initialIndex: widget.initialPage);
  }
  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      const SizedBox(height: 12),
      Center(child: Container(width: 40, height: 4,
          decoration: BoxDecoration(color: Colors.white24,
              borderRadius: BorderRadius.circular(2)))),
      TabBar(
        controller: _tab,
        tabs: const [
          Tab(icon: Icon(Icons.bookmark), text: 'نشانه‌ها'),
          Tab(icon: Icon(Icons.favorite), text: 'علاقه‌مندی‌ها'),
          Tab(icon: Icon(Icons.settings), text: 'تنظیمات'),
        ],
      ),
      Expanded(
        child: TabBarView(
          controller: _tab,
          children: [
            _videoList(Store.bookmarked, Icons.bookmark, Colors.amber),
            _videoList(Store.favorited, Icons.favorite, Colors.redAccent),
            _settingsTab(),
          ],
        ),
      ),
    ]);
  }

  Widget _videoList(Set<String> paths, IconData icon, Color color) {
    final list = paths.toList().reversed.toList();
    if (list.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 48, color: color.withOpacity(0.3)),
        const SizedBox(height: 12),
        const Text('هنوز چیزی اضافه نشده', style: TextStyle(color: Colors.white54)),
      ]));
    }
    return ListView.builder(
      itemCount: list.length,
      itemBuilder: (ctx, i) {
        final path = list[i];
        final name = p.basename(path);
        final exists = File(path).existsSync();
        return ListTile(
          leading: Icon(icon, color: exists ? color : Colors.white24, size: 22),
          title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: exists ? Colors.white : Colors.white38)),
          subtitle: Text(p.dirname(path),
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: Colors.white38)),
          onTap: exists ? () => widget.onVideoTap(path) : null,
        );
      },
    );
  }

  Widget _settingsTab() => ListView(padding: const EdgeInsets.all(16), children: [
    const ListTile(
      leading: Icon(Icons.info_outline),
      title: Text('اطلاعات توسعه‌دهنده'),
      subtitle: Text('نسخه ۱.۰.۰ — به‌زودی تکمیل می‌شود'),
    ),
    const Divider(),
    const ListTile(
      leading: Icon(Icons.code),
      title: Text('ساخته‌شده با Flutter'),
      subtitle: Text('media_kit + Anthropic Claude'),
    ),
  ]);
}

// ─────────────────────────────────────────────────────────────────────────────
// پلیر ویدیو
// ─────────────────────────────────────────────────────────────────────────────
enum _GMode { none, seek, brightness, volume, zoom, pan, subtitlePos }
enum _Repeat { none, one, all }

class PlayerScreen extends StatefulWidget {
  final String? subtitlePath;
  final List<File> playlist;
  final int playlistIndex;
  const PlayerScreen({super.key, this.subtitlePath,
      required this.playlist, required this.playlistIndex});
  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final Player player = Player();
  late final VideoController controller = VideoController(player);

  late int _playIndex;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = true;
  final List<StreamSubscription> _subs = [];

  // ─── زیرنویس (رندر اختصاصی) ───
  List<SubEntry> _subEntries = [];
  bool _subVisible = true;
  double _fontSize = 30;
  bool _bold = true;
  double _bgOpacity = 0.5;
  Color _color = Colors.white;
  Color _subBgColor = Colors.black;
  TextAlign _subAlign = TextAlign.center;
  double _subBottomPadding = 50.0;
  double _subPaddingStart = 50.0;

  // ─── پخش ───
  double _speed = 1.0;
  BoxFit _fit = BoxFit.contain;
  bool _landscape = false;
  _Repeat _repeatMode = _Repeat.none;
  bool _muted = false;
  double _lastVolume = 100;

  // ─── حالت شب ───
  double _nightOpacity = 0.0;

  // ─── کنترل‌ها ───
  bool _controlsVisible = true;
  bool _locked = false;
  Timer? _hideTimer;

  // ─── زوم ───
  double _scale = 1.0, _baseScale = 1.0;
  Offset _offset = Offset.zero, _baseOffset = Offset.zero;

  // ─── اشاره‌ها ───
  _GMode _mode = _GMode.none;
  Offset _startFocal = Offset.zero, _doubleTapPos = Offset.zero;
  int _seekStartMs = 0, _seekTargetMs = 0;
  double _startBrightness = 0.5, _startVolume = 100;
  Size _size = Size.zero;

  // ─── پیام روی صفحه ───
  String? _overlay;
  Timer? _overlayTimer;

  final List<Color> _colorChoices = const [
    Colors.white, Color(0xFFFFEB3B), Color(0xFF69F0AE),
    Color(0xFF40C4FF), Color(0xFFFF8A65), Color(0xFFFF80AB),
  ];
  final List<Color> _bgColorChoices = const [
    Colors.black, Color(0xFF0D1B2A), Color(0xFF1B2E1B),
    Color(0xFF2A1B1B), Color(0xFF1B1B2E), Colors.transparent,
  ];

  String get _curPath => widget.playlist[_playIndex].path;
  bool get _hasPrev => _playIndex > 0;
  bool get _hasNext => _playIndex < widget.playlist.length - 1;

  // پیدا کردن متن زیرنویس برای زمان فعلی
  String? get _subText {
    if (!_subVisible || _subEntries.isEmpty) return null;
    for (final e in _subEntries) {
      if (_position >= e.start && _position <= e.end) return e.text;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _playIndex = widget.playlistIndex.clamp(0, (widget.playlist.length - 1).clamp(0, 999999));
    WakelockPlus.enable();
    _subs.add(player.stream.position.listen((pos) {
      _position = pos;
      _maybeWatched();
      if (mounted) setState(() {});
    }));
    _subs.add(player.stream.duration.listen((d) {
      _duration = d;
      if (d.inSeconds > 0) Store.saveDur(_curPath, d.inSeconds);
      if (mounted) setState(() {});
    }));
    _subs.add(player.stream.playing.listen((pl) {
      _playing = pl;
      if (mounted) setState(() {});
    }));
    _subs.add(player.stream.completed.listen((done) {
      if (!done) return;
      switch (_repeatMode) {
        case _Repeat.one:
          player.seek(Duration.zero); player.play(); break;
        case _Repeat.all:
          _switchVideo((_playIndex + 1) % widget.playlist.length); break;
        case _Repeat.none:
          if (_hasNext) _switchVideo(_playIndex + 1); break;
      }
    }));
    _start();
    _startHideTimer();
  }

  Future<void> _start() async {
    await player.open(Media(_curPath));
    final saved = await Store.getPos(_curPath);
    if (saved.inSeconds > 5 && mounted) {
      final resume = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1C1C22),
          title: const Text('ادامه پخش'),
          content: Text('از ${fmt(saved)} ادامه دهیم؟'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
                child: const Text('از ابتدا')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true),
                child: const Text('ادامه')),
          ],
        ),
      );
      if (resume == true && mounted) await player.seek(saved);
    }
    final sub = widget.subtitlePath ?? matchSubtitle(_curPath);
    if (sub != null) await _loadSubtitle(sub);
  }

  Future<void> _switchVideo(int idx) async {
    await Store.savePos(_curPath, _position);
    _playIndex = idx;
    _position = Duration.zero;
    _duration = Duration.zero;
    _subEntries = [];
    setState(() {});
    await player.open(Media(_curPath));
    final saved = await Store.getPos(_curPath);
    if (saved.inSeconds > 5) await player.seek(saved);
    final sub = matchSubtitle(_curPath);
    if (sub != null) await _loadSubtitle(sub);
  }

  void _maybeWatched() {
    if (_duration.inSeconds > 0 &&
        _position.inSeconds > _duration.inSeconds * 0.9) {
      Store.markWatched(_curPath);
    }
  }

  Future<void> _loadSubtitle(String path) async {
    final bytes = await File(path).readAsBytes();
    String content;
    try { content = utf8.decode(bytes); }
    catch (_) { content = utf8.decode(bytes, allowMalformed: true); }
    final ext = p.extension(path).toLowerCase();
    if (ext == '.srt' || ext == '.vtt') {
      setState(() => _subEntries = parseSrt(content));
    }
    // برای فرمت‌های دیگر (ass/ssa) عجالتاً خالی می‌ماند
  }

  Future<void> _pickSubtitleManually() async {
    final res = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: ['srt', 'vtt', 'ass', 'ssa']);
    final path = res?.files.single.path;
    if (path != null) await _loadSubtitle(path);
  }

  @override
  void dispose() {
    Store.savePos(_curPath, _position);
    for (final s in _subs) { s.cancel(); }
    _hideTimer?.cancel();
    _overlayTimer?.cancel();
    WakelockPlus.disable();
    try { ScreenBrightness().resetApplicationScreenBrightness(); } catch (_) {}
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    player.dispose();
    super.dispose();
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  void _toggleControls() {
    if (_locked) return;
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _startHideTimer();
  }

  void _showOverlay(String text) {
    setState(() => _overlay = text);
    _overlayTimer?.cancel();
    _overlayTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _overlay = null);
    });
  }

  // دو‌ضربه: چپ = جلو / راست = عقب
  void _onDoubleTap() {
    if (_locked) return;
    final onRight = _doubleTapPos.dx > _size.width / 2;
    var target = _position + Duration(seconds: onRight ? -10 : 10);
    if (target < Duration.zero) target = Duration.zero;
    player.seek(target);
    _showOverlay(onRight ? '⏮ ۱۰ ثانیه' : '۱۰ ثانیه ⏭');
  }

  Future<double> _getBrightness() async {
    try { return await ScreenBrightness().application; } catch (_) { return 0.5; }
  }
  Future<void> _setBrightness(double v) async {
    try { await ScreenBrightness().setApplicationScreenBrightness(v); } catch (_) {}
  }

  void _onScaleStart(ScaleStartDetails d) {
    if (_locked) return;
    _mode = _GMode.none;
    _baseScale = _scale; _baseOffset = _offset;
    _startFocal = d.localFocalPoint;
    _seekStartMs = _position.inMilliseconds;
    _subPaddingStart = _subBottomPadding;
    _startVolume = player.state.volume;
    _getBrightness().then((b) => _startBrightness = b);
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (_locked) return;
    if (d.pointerCount >= 2) {
      _mode = _GMode.zoom;
      setState(() {
        _scale = (_baseScale * d.scale).clamp(1.0, 4.0);
        _offset = _offset + d.focalPointDelta;
      });
      return;
    }
    final dx = d.localFocalPoint.dx - _startFocal.dx;
    final dy = d.localFocalPoint.dy - _startFocal.dy;
    if (_mode == _GMode.none) {
      if (dx.abs() < 8 && dy.abs() < 8) return;
      if (_scale > 1.05) { _mode = _GMode.pan; }
      else if (dx.abs() > dy.abs()) { _mode = _GMode.seek; }
      else if (_subVisible && _startFocal.dy > _size.height * 0.6) {
        _mode = _GMode.subtitlePos;
      } else if (_startFocal.dx > _size.width / 2) { _mode = _GMode.brightness; }
      else { _mode = _GMode.volume; }
    }
    switch (_mode) {
      case _GMode.pan:
        setState(() => _offset = _baseOffset + (d.localFocalPoint - _startFocal));
        break;
      case _GMode.seek:
        final total = _duration.inMilliseconds;
        _seekTargetMs = (_seekStartMs + ((dx / _size.width) * 90000).round()).clamp(0, total);
        _showOverlay('${fmt(Duration(milliseconds: _seekTargetMs))} / ${fmt(_duration)}');
        break;
      case _GMode.brightness:
        final nb = (_startBrightness - dy / _size.height).clamp(0.0, 1.0);
        _setBrightness(nb);
        _showOverlay('☀ ${(nb * 100).round()}%');
        break;
      case _GMode.volume:
        final nv = (_startVolume - dy / _size.height * 100).clamp(0.0, 100.0);
        player.setVolume(nv);
        _showOverlay('🔊 ${nv.round()}%');
        break;
      case _GMode.subtitlePos:
        setState(() => _subBottomPadding = (_subPaddingStart - dy)
            .clamp(10.0, _size.height * 0.75));
        _showOverlay('↕ موقعیت زیرنویس');
        break;
      default: break;
    }
  }

  void _onScaleEnd(ScaleEndDetails d) {
    if (_mode == _GMode.seek) {
      player.seek(Duration(milliseconds: _seekTargetMs));
    }
    if (_scale <= 1.02) setState(() { _scale = 1.0; _offset = Offset.zero; });
    _mode = _GMode.none;
  }

  void _toggleOrientation() {
    setState(() => _landscape = !_landscape);
    if (_landscape) {
      SystemChrome.setPreferredOrientations(
          [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  void _cycleFit() {
    setState(() { _fit = _fit == BoxFit.contain ? BoxFit.cover : _fit == BoxFit.cover ? BoxFit.fill : BoxFit.contain; });
    _showOverlay(_fit == BoxFit.contain ? 'عادی' : _fit == BoxFit.cover ? 'پر کردن' : 'کشیده');
  }

  void _cycleRepeat() {
    setState(() { _repeatMode = _repeatMode == _Repeat.none ? _Repeat.all : _repeatMode == _Repeat.all ? _Repeat.one : _Repeat.none; });
    _showOverlay(_repeatMode == _Repeat.none ? 'تکرار: خاموش' : _repeatMode == _Repeat.all ? 'تکرار: همه' : 'تکرار: یک');
  }

  @override
  Widget build(BuildContext context) {
    _size = MediaQuery.of(context).size;
    final bkm = Store.bookmarked.contains(_curPath);
    final sub = _subText;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── ویدیو ──
          Positioned.fill(
            child: ClipRect(
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..translate(_offset.dx, _offset.dy)
                  ..scale(_scale, _scale),
                child: Video(
                  controller: controller,
                  controls: NoVideoControls,
                  fit: _fit,
                  // زیرنویس media_kit را پنهان می‌کنیم، خودمان رندر می‌کنیم
                  subtitleViewConfiguration: const SubtitleViewConfiguration(
                    style: TextStyle(fontSize: 0, color: Colors.transparent),
                    padding: EdgeInsets.zero,
                  ),
                ),
              ),
            ),
          ),

          // ── زیرنویس اختصاصی ──
          if (sub != null)
            Positioned(
              left: 16, right: 16,
              bottom: _subBottomPadding,
              child: Align(
                alignment: _subAlign == TextAlign.right
                    ? Alignment.bottomRight
                    : _subAlign == TextAlign.left
                        ? Alignment.bottomLeft
                        : Alignment.bottomCenter,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _subBgColor.withOpacity(_bgOpacity),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(sub,
                    textAlign: _subAlign,
                    style: TextStyle(
                      fontSize: _fontSize,
                      color: _color,
                      fontWeight: _bold ? FontWeight.bold : FontWeight.normal,
                      height: 1.4,
                    ),
                  ),
                ),
              ),
            ),

          // ── حالت شب ──
          if (_nightOpacity > 0)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  color: const Color(0xFFFF7700).withOpacity(_nightOpacity * 0.35),
                ),
              ),
            ),

          // ── لایه اشاره ──
          if (!_locked)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _toggleControls,
                onDoubleTapDown: (d) => _doubleTapPos = d.localPosition,
                onDoubleTap: _onDoubleTap,
                onScaleStart: _onScaleStart,
                onScaleUpdate: _onScaleUpdate,
                onScaleEnd: _onScaleEnd,
                child: const SizedBox.expand(),
              ),
            ),

          // ── پیام وسط صفحه ──
          if (_overlay != null)
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.65),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(_overlay!,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),

          // ── کنترل‌ها ──
          if (_controlsVisible && !_locked) _buildControls(bkm),

          // ── دکمه باز کردن قفل ──
          if (_locked)
            Positioned(
              top: 16, left: 16,
              child: SafeArea(
                child: FloatingActionButton.small(
                  backgroundColor: Colors.black54,
                  onPressed: () => setState(() => _locked = false),
                  child: const Icon(Icons.lock),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildControls(bool bkm) {
    return SafeArea(
      child: Column(
        children: [
          // ── نوار بالا ──
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [Colors.black54, Colors.transparent],
              ),
            ),
            child: Row(
              children: [
                IconButton(icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.pop(context)),
                Expanded(child: Text(p.basename(_curPath), maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13))),
                IconButton(
                  icon: Icon(bkm ? Icons.bookmark : Icons.bookmark_border,
                      color: bkm ? Colors.amber : Colors.white),
                  onPressed: () async {
                    await Store.toggleBookmark(_curPath); setState(() {});
                  },
                ),
                IconButton(
                  icon: Icon(Store.favorited.contains(_curPath)
                      ? Icons.favorite : Icons.favorite_border,
                      color: Store.favorited.contains(_curPath)
                          ? Colors.redAccent : Colors.white),
                  onPressed: () async {
                    await Store.toggleFavorite(_curPath); setState(() {});
                  },
                ),
                IconButton(icon: const Icon(Icons.subtitles), onPressed: _openSettings),
                IconButton(
                    icon: Icon(_landscape ? Icons.stay_current_portrait : Icons.screen_rotation),
                    onPressed: _toggleOrientation),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  onSelected: (v) {
                    switch (v) {
                      case 'fit': _cycleFit(); break;
                      case 'repeat': _cycleRepeat(); break;
                      case 'night': setState(() => _nightOpacity = _nightOpacity > 0 ? 0 : 0.6); break;
                      case 'lock': setState(() { _locked = true; _controlsVisible = false; }); break;
                      case 'mute':
                        if (_muted) {
                          player.setVolume(_lastVolume);
                          setState(() => _muted = false);
                        } else {
                          _lastVolume = player.state.volume;
                          player.setVolume(0);
                          setState(() => _muted = true);
                        }
                        break;
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'fit', child: Text(
                        'اندازه تصویر: ${_fit == BoxFit.contain ? "عادی" : _fit == BoxFit.cover ? "پر" : "کشیده"}')),
                    PopupMenuItem(value: 'repeat', child: Text(
                        'تکرار: ${_repeatMode == _Repeat.none ? "خاموش" : _repeatMode == _Repeat.all ? "همه" : "یک"}')),
                    PopupMenuItem(value: 'night', child: Text(
                        _nightOpacity > 0 ? 'خاموش کردن حالت شب' : 'حالت شب (محافظت چشم)')),
                    PopupMenuItem(value: 'mute', child: Text(_muted ? 'لغو بی‌صدا' : 'بی‌صدا')),
                    const PopupMenuItem(value: 'lock', child: Text('قفل صفحه')),
                  ],
                ),
              ],
            ),
          ),

          // ── وسط: قبلی / پخش / بعدی ──
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  iconSize: 44,
                  icon: Icon(Icons.skip_previous,
                      color: _hasPrev ? Colors.white : Colors.white24),
                  onPressed: _hasPrev ? () => _switchVideo(_playIndex - 1) : null,
                ),
                const SizedBox(width: 24),
                IconButton(
                  iconSize: 68,
                  icon: Icon(_playing ? Icons.pause_circle_filled : Icons.play_circle_filled),
                  onPressed: () { _playing ? player.pause() : player.play(); _startHideTimer(); },
                ),
                const SizedBox(width: 24),
                IconButton(
                  iconSize: 44,
                  icon: Icon(Icons.skip_next,
                      color: _hasNext ? Colors.white : Colors.white24),
                  onPressed: _hasNext ? () => _switchVideo(_playIndex + 1) : null,
                ),
              ],
            ),
          ),

          // ── نوار پایین ──
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter, end: Alignment.topCenter,
                colors: [Colors.black54, Colors.transparent],
              ),
            ),
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: Row(
              children: [
                Text(fmt(_position), style: const TextStyle(fontSize: 12)),
                Expanded(
                  child: Slider(
                    min: 0,
                    max: _duration.inMilliseconds <= 0
                        ? 1.0 : _duration.inMilliseconds.toDouble(),
                    value: _position.inMilliseconds
                        .clamp(0, _duration.inMilliseconds <= 0
                            ? 0 : _duration.inMilliseconds)
                        .toDouble(),
                    onChanged: (v) {
                      player.seek(Duration(milliseconds: v.round()));
                      _startHideTimer();
                    },
                  ),
                ),
                Text(fmt(_duration), style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openSettings() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1C1C22),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          void change(VoidCallback fn) { fn(); setSheet(() {}); setState(() {}); }
          return Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20,
                MediaQuery.of(ctx).viewInsets.bottom + 24),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(child: Container(width: 40, height: 4,
                      decoration: BoxDecoration(color: Colors.white24,
                          borderRadius: BorderRadius.circular(2)))),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('نمایش زیرنویس'),
                    value: _subVisible,
                    onChanged: (v) => change(() => _subVisible = v),
                  ),
                  Text('اندازه فونت: ${_fontSize.round()}'),
                  Slider(min: 14, max: 64, value: _fontSize,
                      onChanged: (v) => change(() => _fontSize = v)),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('پررنگ (Bold)'),
                    value: _bold,
                    onChanged: (v) => change(() => _bold = v),
                  ),
                  Text('موقعیت از پایین: ${_subBottomPadding.round()}  '
                      '(یا در ناحیه زیرنویس بکش)'),
                  Slider(min: 10, max: 400, value: _subBottomPadding,
                      onChanged: (v) => change(() => _subBottomPadding = v)),
                  const SizedBox(height: 8),
                  const Text('چینش زیرنویس'),
                  const SizedBox(height: 8),
                  SegmentedButton<TextAlign>(
                    segments: const [
                      ButtonSegment(value: TextAlign.right, label: Text('راست'), icon: Icon(Icons.format_align_right, size: 16)),
                      ButtonSegment(value: TextAlign.center, label: Text('وسط'), icon: Icon(Icons.format_align_center, size: 16)),
                      ButtonSegment(value: TextAlign.left, label: Text('چپ'), icon: Icon(Icons.format_align_left, size: 16)),
                    ],
                    selected: {_subAlign},
                    onSelectionChanged: (s) => change(() => _subAlign = s.first),
                  ),
                  const SizedBox(height: 14),
                  const Text('رنگ متن زیرنویس'),
                  const SizedBox(height: 8),
                  Wrap(spacing: 10, children: _colorChoices.map((c) {
                    final sel = c.value == _color.value;
                    return GestureDetector(
                      onTap: () => change(() => _color = c),
                      child: Container(width: 34, height: 34,
                          decoration: BoxDecoration(color: c, shape: BoxShape.circle,
                              border: Border.all(
                                  color: sel ? Colors.white : Colors.transparent, width: 3))),
                    );
                  }).toList()),
                  const SizedBox(height: 14),
                  const Text('رنگ پس‌زمینه زیرنویس'),
                  const SizedBox(height: 8),
                  Wrap(spacing: 10, children: _bgColorChoices.map((c) {
                    final sel = c.value == _subBgColor.value;
                    return GestureDetector(
                      onTap: () => change(() => _subBgColor = c),
                      child: Container(width: 34, height: 34,
                          decoration: BoxDecoration(
                            color: c == Colors.transparent ? null : c,
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: sel ? Colors.white : Colors.white24, width: sel ? 3 : 1),
                          ),
                          child: c == Colors.transparent
                              ? const Center(child: Icon(Icons.block, size: 18, color: Colors.white38))
                              : null),
                    );
                  }).toList()),
                  const SizedBox(height: 8),
                  Text('شفافیت پس‌زمینه: ${(_bgOpacity * 100).round()}%'),
                  Slider(min: 0, max: 1, value: _bgOpacity,
                      onChanged: (v) => change(() => _bgOpacity = v)),
                  const Divider(height: 28),
                  const Text('سرعت پخش'),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, children: [0.5, 0.75, 1.0, 1.25, 1.5, 2.0].map((s) =>
                    ChoiceChip(
                      label: Text('${s}x'),
                      selected: _speed == s,
                      onSelected: (_) => change(() { _speed = s; player.setRate(s); }),
                    ),
                  ).toList()),
                  const Divider(height: 28),
                  Text('حالت شب: ${(_nightOpacity * 100).round()}%  (۰ = خاموش)'),
                  Slider(min: 0, max: 1, value: _nightOpacity,
                      activeColor: Colors.orange,
                      onChanged: (v) => change(() => _nightOpacity = v)),
                  const Divider(height: 28),
                  OutlinedButton.icon(
                    onPressed: () { Navigator.pop(ctx); _pickSubtitleManually(); },
                    icon: const Icon(Icons.file_open),
                    label: const Text('انتخاب زیرنویس دستی'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

