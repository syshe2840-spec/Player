// lib/browser.dart — مرورگر فایل فوق‌حرفه‌ای و مدرن
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
import 'iptv_screen.dart';
import 'api_service.dart';
import 'online_player_sheet.dart';
import 'settings.dart' show ToolsTabBody;
import 'package:url_launcher/url_launcher.dart' as ul;
import 'player.dart';
import 'main.dart' show showSnack;
import 'l10n.dart';

// ── ثابت‌های رنگی و استایل مدرن (Design Tokens) ──
const kBg       = Color(0xFF090A10);
const kSurface  = Color(0xFF10121E);
const kCard     = Color(0xFF16192B);
const kCardLight= Color(0xFF1F233C);
const kBorder   = Color(0xFF2A2E4B);
const kAccent   = Color(0xFF8B5CF6);
const kCyan     = Color(0xFF06B6D4);
const kGreen    = Color(0xFF10B981);
const kAmber    = Color(0xFFF59E0B);
const kRed      = Color(0xFFF43F5E);
const kPink     = Color(0xFFEC4899);
const kTextSec  = Color(0xFFA0AEC0);
const kTextDim  = Color(0xFF64748B);

enum _SortBy { name, date, size, type }

LinearGradient _extGrad(String ext) {
  switch (ext) {
    case 'mp4':  return const LinearGradient(colors: [Color(0xFF8B5CF6), Color(0xFF6366F1)]);
    case 'mkv':  return const LinearGradient(colors: [Color(0xFF06B6D4), Color(0xFF3B82F6)]);
    case 'avi':  return const LinearGradient(colors: [Color(0xFF10B981), Color(0xFF059669)]);
    case 'mov':  return const LinearGradient(colors: [Color(0xFFEC4899), Color(0xFFD946EF)]);
    case 'webm': return const LinearGradient(colors: [Color(0xFFF59E0B), Color(0xFFD97706)]);
    case 'flv':  return const LinearGradient(colors: [Color(0xFFF43F5E), Color(0xFFE11D48)]);
    default:     return const LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF4338CA)]);
  }
}

Widget _badge(String text, Color color, {IconData? icon}) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
  decoration: BoxDecoration(
    color: color.withOpacity(0.15),
    borderRadius: BorderRadius.circular(8),
    border: Border.all(color: color.withOpacity(0.35), width: 0.8),
  ),
  child: Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (icon != null) ...[Icon(icon, size: 10, color: color), const SizedBox(width: 3)],
      Text(text, style: TextStyle(fontSize: 9.5, color: color, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
    ],
  ),
);

// ── کش thumbnail با MethodChannel ──
final Map<String, Uint8List?> _thumbCache = {};
const _thumbChannel = MethodChannel('ir.subteam.subtitle_player/thumbnail');

Future<Uint8List?> _loadThumb(String path) async {
  if (_thumbCache.containsKey(path)) return _thumbCache[path];
  try {
    final data = await _thumbChannel.invokeMethod<Uint8List>(
      'getThumbnail',
      {'path': path, 'timeMs': 2000, 'width': 220, 'height': 124},
    );
    return _thumbCache[path] = data;
  } catch (_) {
    return _thumbCache[path] = null;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
class BrowserScreen extends StatefulWidget {
  const BrowserScreen({super.key});
  @override State<BrowserScreen> createState() => _BrowserState();
}

class _BrowserState extends State<BrowserScreen> with TickerProviderStateMixin {
  static const root = '/storage/emulated/0';
  bool _granted = false, _checking = true;
  String _path = root;
  List<Directory> _dirs = [];
  List<File> _videos = [];
  bool _selectMode = false;
  final Set<String> _selected = {};
  _SortBy _sortBy = _SortBy.name;
  bool _sortDesc = false;
  bool _searching = false;
  bool _globalSearch = false;
  String _searchQuery = '';
  List<File> _searchResults = [];
  bool _searchRunning = false;
  final TextEditingController _searchCtrl = TextEditingController();

  @override void initState() { super.initState(); _init(); }
  @override void dispose() { _searchCtrl.dispose(); super.dispose(); }

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
      dirs.sort((a, b) => p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase()));
      setState(() {
        _path = path; _dirs = dirs; _videos = vids; _selectMode = false;
        _selected.clear(); _searching = false; _searchQuery = ''; _searchCtrl.clear();
        _searchResults = []; _globalSearch = false;
      });
    } catch (_) {
      if (mounted) showSnack(context, L.noAccess);
    }
  }

  void _goUp() { final par = p.dirname(_path); if (par != _path && par.startsWith('/storage')) _loadDir(par); }

  int _sd(int v) => _sortDesc ? -v : v;
  List<File> get _sortedVideos {
    final s = List<File>.from(_videos);
    switch (_sortBy) {
      case _SortBy.name: s.sort((a, b) => _sd(p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase()))); break;
      case _SortBy.date: s.sort((a, b) { try { return _sd(a.lastModifiedSync().compareTo(b.lastModifiedSync())); } catch (_) { return 0; } }); break;
      case _SortBy.size: s.sort((a, b) { try { return _sd(a.lengthSync().compareTo(b.lengthSync())); } catch (_) { return 0; } }); break;
      case _SortBy.type: s.sort((a, b) => _sd(p.extension(a.path).compareTo(p.extension(b.path)))); break;
    }
    return s;
  }

  List<File> get _filteredVideos {
    if (!_searching || _searchQuery.isEmpty) return _sortedVideos;
    if (_globalSearch) return _searchResults;
    return _sortedVideos.where((f) => p.basename(f.path).toLowerCase().contains(_searchQuery.toLowerCase())).toList();
  }

  List<Directory> get _filteredDirs {
    if (!_searching || _searchQuery.isEmpty || _globalSearch) return _globalSearch ? [] : _dirs;
    return _dirs.where((d) => p.basename(d.path).toLowerCase().contains(_searchQuery.toLowerCase())).toList();
  }

  Future<void> _runGlobalSearch(String query) async {
    if (query.isEmpty) { setState(() { _searchResults = []; _searchRunning = false; }); return; }
    setState(() { _searchResults = []; _searchRunning = true; });
    final results = <File>[];
    final q = query.toLowerCase();
    await _deepSearch(Directory(root), q, results);
    for (final d in _getStorageDevices()) {
      if (mounted && _searchRunning) await _deepSearch(d, q, results);
    }
    if (mounted) setState(() => _searchRunning = false);
  }

  Future<void> _deepSearch(Directory dir, String query, List<File> results) async {
    if (!mounted || !_searchRunning) return;
    List<FileSystemEntity> entities;
    try { entities = await dir.list(recursive: false).toList(); } catch (_) { return; }
    for (final e in entities) {
      if (!mounted || !_searchRunning) return;
      if (e is File) {
        if (kVideoExt.contains(p.extension(e.path).toLowerCase()) &&
            p.basename(e.path).toLowerCase().contains(query)) {
          results.add(e);
          if (mounted) setState(() => _searchResults = List.from(results));
        }
      } else if (e is Directory) {
        final name = p.basename(e.path);
        if (!name.startsWith('.') && name != 'proc' && name != 'sys' && name != 'dev') {
          await _deepSearch(e, query, results);
        }
      }
    }
  }

  Future<void> _openVideo(File video, [List<File>? playlist, int? idx]) async {
    final pl = playlist ?? _filteredVideos;
    final i = idx ?? pl.indexOf(video);
    await Navigator.push(context, MaterialPageRoute(
      builder: (_) => PlayerScreen(subtitlePath: matchSubtitle(video.path), playlist: pl, playlistIndex: i < 0 ? 0 : i),
    ));
    await Store.load();
    if (mounted) setState(() {});
  }

  Future<void> _openVideoByPath(String path) async {
    final f = File(path);
    if (!f.existsSync()) { showSnack(context, L.fileNotFound); return; }
    await _openVideo(f, [f], 0);
  }

  List<Directory> _getStorageDevices() {
    final r = <Directory>[];
    try {
      for (final e in Directory('/storage').listSync()) {
        if (e is Directory && p.basename(e.path) != 'emulated' && p.basename(e.path) != 'self') r.add(e);
      }
    } catch (_) {}
    return r;
  }

  void _showVideoMenu(File f) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => VideoMenu(
        file: f,
        onDone: () async { Navigator.pop(ctx); await Store.load(); _loadDir(_path); },
        onInfo: () { Navigator.pop(ctx); _showFileInfo(f); },
        onDelete: () { Navigator.pop(ctx); _confirmDelete([f]); },
        onRename: () { Navigator.pop(ctx); _renameFile(f); },
        onSelect: () { Navigator.pop(ctx); setState(() { _selectMode = true; _selected.add(f.path); }); },
        onCopy: () { Navigator.pop(ctx); _copyFile(f); },
        onMove: () { Navigator.pop(ctx); _moveFile(f); },
        onRate: () { Navigator.pop(ctx); _showRating(f); },
        onNote: () { Navigator.pop(ctx); _showNote(f); },
      ),
    );
  }

  Future<void> _copyFile(File f) async {
    if (Store.savedFolders.isEmpty) { showSnack(context, L.noFolderSaved); return; }
    final dest = await _pickFolder(L.copyTo);
    if (dest == null) return;
    try {
      await f.copy(p.join(dest, p.basename(f.path)));
      if (mounted) showSnack(context, L.copied);
    } catch (_) { if (mounted) showSnack(context, L.error); }
  }

  Future<void> _moveFile(File f) async {
    final dest = await _pickFolder(L.transferTo); if (dest == null) return;
    final newPath = p.join(dest, p.basename(f.path));
    try { await f.rename(newPath); }
    catch (_) { try { await f.copy(newPath); await f.delete(); } catch (e) { if (mounted) showSnack(context, L.error); return; } }
    _loadDir(_path);
  }

  Future<String?> _pickFolder(String title) async {
    final all = [...Store.savedFolders];
    if (all.isEmpty) { showSnack(context, L.noFolderSaved); return null; }
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: kBorder)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: all.map((folder) => ListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            leading: const Icon(Icons.folder_special_rounded, color: kAmber),
            title: Text(p.basename(folder)),
            onTap: () => Navigator.pop(ctx, folder),
          )).toList(),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(List<File> files) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: kBorder)),
        title: Text(L.deleteFile, style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Text(files.length == 1 ? '${L.delete} «${p.basename(files.first.path)}»?' : '${files.length} ${L.delete}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(L.cancel, style: const TextStyle(color: kTextSec))),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: kRed), onPressed: () => Navigator.pop(ctx, true), child: Text(L.delete)),
        ],
      ),
    );
    if (ok != true) return;
    for (final f in files) { try { await f.delete(); } catch (_) {} }
    _loadDir(_path);
  }

  Future<void> _renameFile(File f) async {
    final ctrl = TextEditingController(text: p.basenameWithoutExtension(f.path));
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: kBorder)),
        title: Text(L.rename_, style: const TextStyle(fontWeight: FontWeight.bold)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(
            hintText: L.newName,
            filled: true,
            fillColor: kCard,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kBorder)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(L.cancel, style: const TextStyle(color: kTextSec))),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: Text(L.confirm)),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    try { await f.rename(p.join(p.dirname(f.path), '$name${p.extension(f.path)}')); _loadDir(_path); }
    catch (_) { if (mounted) showSnack(context, L.error); }
  }

  Future<void> _showRating(File f) async {
    int rating = Store.ratings[f.path] ?? 0;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) => AlertDialog(
          backgroundColor: kSurface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: kBorder)),
          title: Text(p.basename(f.path), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(L.yourRatingLabel, style: const TextStyle(color: kTextSec)),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (i) => GestureDetector(
                  onTap: () => ss(() => rating = i + 1),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(i < rating ? Icons.star_rounded : Icons.star_border_rounded, color: kAmber, size: 36),
                  ),
                )),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(L.cancel, style: const TextStyle(color: kTextSec))),
            if (rating > 0) TextButton(onPressed: () async { await Store.saveRating(f.path, 0); Navigator.pop(ctx); setState(() {}); }, child: Text(L.delete, style: const TextStyle(color: kRed))),
            FilledButton(onPressed: () async { await Store.saveRating(f.path, rating); Navigator.pop(ctx); setState(() {}); }, child: Text(L.save)),
          ],
        ),
      ),
    );
  }

  Future<void> _showNote(File f) async {
    final ctrl = TextEditingController(text: Store.notes[f.path] ?? '');
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: kBorder)),
        title: Text(L.note, style: const TextStyle(fontWeight: FontWeight.bold)),
        content: TextField(
          controller: ctrl,
          maxLines: 4,
          autofocus: true,
          decoration: InputDecoration(
            hintText: L.writtenNote,
            filled: true,
            fillColor: kCard,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kBorder)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(L.cancel, style: const TextStyle(color: kTextSec))),
          FilledButton(onPressed: () async { await Store.saveNote(f.path, ctrl.text.trim()); Navigator.pop(ctx); setState(() {}); }, child: Text(L.save)),
        ],
      ),
    );
  }

  Future<void> _showFileInfo(File f) async {
    final allSubs = findAllSubtitles(f.path);
    String modified = '';
    try { modified = f.lastModifiedSync().toString().split('.').first; } catch (_) {}
    final dur = await Store.getDur(f.path);
    final rating = Store.ratings[f.path] ?? 0;
    final note = Store.notes[f.path] ?? '';
    int fileSize = 0; try { fileSize = f.lengthSync(); } catch (_) {}
    final ext = p.extension(f.path).toLowerCase().replaceAll('.', '');
    final String codecHint = _codecHint(ext);
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: const BorderSide(color: kBorder)),
        contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
        title: Row(
          children: [
            Container(width: 4, height: 22, decoration: BoxDecoration(color: kAccent, borderRadius: BorderRadius.circular(4))),
            const SizedBox(width: 10),
            Expanded(child: Text(p.basename(f.path), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold))),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _iRow(Icons.folder_special_outlined, kTextSec, L.path, p.dirname(f.path)),
              _iRow(Icons.video_collection_rounded, kCyan, L.format, ext.toUpperCase()),
              _iRow(Icons.sd_storage_rounded, kTextSec, L.sortSize, sizeStr(f)),
              if (fileSize > 0) _iRow(Icons.pin_outlined, kTextSec, L.precise, '$fileSize Bytes'),
              if (dur > 0) _iRow(Icons.timer_sharp, kCyan, L.duration, fmt(Duration(seconds: dur))),
              _iRow(Icons.calendar_month_rounded, kTextSec, L.sortDate, modified),
              _iRow(Icons.memory_rounded, kAccent, L.probableCodec, codecHint),
              _iRow(Icons.remove_red_eye_rounded, Store.watched.contains(f.path) ? kGreen : kTextSec, L.status, Store.watched.contains(f.path) ? L.watched : L.notWatched),
              if (rating > 0) _iRow(Icons.star_rounded, kAmber, L.rating, '${'★' * rating}${'☆' * (5 - rating)}'),
              if (note.isNotEmpty) _iRow(Icons.sticky_note_2_rounded, kTextSec, L.note, note),
              if (allSubs.isNotEmpty) ...[
                _iRow(Icons.subtitles_rounded, kGreen, L.subtitle, '${allSubs.length}'),
                ...allSubs.map((s) => Padding(
                  padding: const EdgeInsets.only(right: 28, top: 4),
                  child: Row(
                    children: [
                      Icon(Icons.circle, size: 6, color: kGreen.withOpacity(0.8)),
                      const SizedBox(width: 8),
                      Expanded(child: Text(p.basename(s), style: const TextStyle(fontSize: 11, color: kTextSec))),
                    ],
                  ),
                )),
              ] else _iRow(Icons.subtitles_off_rounded, kTextDim, L.subtitle, L.notFound),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(L.close, style: const TextStyle(color: kAccent))),
        ],
      ),
    );
  }

  String _codecHint(String ext) {
    switch (ext) {
      case 'mp4':  return 'H.264 / H.265 (MPEG-4)';
      case 'mkv':  return 'H.264 / H.265 / AV1 (Matroska)';
      case 'avi':  return 'DivX / Xvid / MPEG-4';
      case 'mov':  return 'H.264 / ProRes (QuickTime)';
      case 'webm': return 'VP8 / VP9 / AV1';
      case 'flv':  return 'H.263 / H.264 (Flash)';
      case 'ts':   return 'H.264 / MPEG-2 (Transport Stream)';
      case 'wmv':  return 'WMV / VC-1';
      case 'mpg': case 'mpeg': return 'MPEG-1 / MPEG-2';
      case 'm4v':  return 'H.264 (iTunes Video)';
      default:     return ext.toUpperCase();
    }
  }

  Widget _iRow(IconData icon, Color iconColor, String label, String val) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(color: iconColor.withOpacity(0.12), borderRadius: BorderRadius.circular(7)),
          child: Icon(icon, size: 14, color: iconColor),
        ),
        const SizedBox(width: 10),
        Text('$label: ', style: const TextStyle(color: kTextSec, fontSize: 12, fontWeight: FontWeight.w500)),
        Expanded(child: Text(val, style: const TextStyle(fontSize: 12, height: 1.3), overflow: TextOverflow.ellipsis, maxLines: 2)),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final isSaved = Store.savedFolders.contains(_path);
    return PopScope(
      canPop: _path == root && !_selectMode && !_searching,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          if (_searching) { setState(() { _searching = false; _searchQuery = ''; _searchCtrl.clear(); _searchResults = []; _globalSearch = false; }); }
          else if (_selectMode) { setState(() { _selectMode = false; _selected.clear(); }); }
          else { _goUp(); }
        }
      },
      child: Scaffold(
        backgroundColor: kBg,
        extendBody: true,
        appBar: _selectMode ? _selectBar() : _normalBar(isSaved),
        body: _buildBody(),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
        floatingActionButton: _selectMode ? null : _buildFABs(),
      ),
    );
  }

  Widget _buildFABs() => ClipRRect(
    borderRadius: BorderRadius.circular(32),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: kSurface.withOpacity(0.75),
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: Colors.white.withOpacity(0.12)),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 20, spreadRadius: 5),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _fabBtn(Icons.history_toggle_off_rounded, L.history, kTextSec, () => _openPanel(0)),
            const SizedBox(width: 6),
            _fabBtn(Icons.bookmark_added_rounded, L.bookmarks, kAmber, () => _openPanel(1)),
            const SizedBox(width: 6),
            _fabBtn(Icons.favorite_border_rounded, L.favorites, kPink, () => _openPanel(2)),
            const SizedBox(width: 6),
            _fabBtn(Icons.push_pin_outlined, L.folders, kGreen, () => _openPanel(3)),
            const SizedBox(width: 6),
            _fabBtn(Icons.tune_rounded, L.settings, kTextSec, () => _openPanel(4)),
          ],
        ),
      ),
    ),
  );

  Widget _fabBtn(IconData icon, String tip, Color color, VoidCallback fn) => Tooltip(
    message: tip,
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: fn,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, size: 22, color: color),
        ),
      ),
    ),
  );

  PreferredSizeWidget _normalBar(bool isSaved) => AppBar(
    backgroundColor: kBg,
    elevation: 0,
    automaticallyImplyLeading: false,
    leading: _path != root
        ? IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18), onPressed: _goUp)
        : null,
    title: _searching
        ? Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  autofocus: true,
                  style: const TextStyle(fontSize: 14, color: Colors.white),
                  decoration: InputDecoration(
                    hintText: _globalSearch ? L.searchingGlobal : L.searchHere,
                    border: InputBorder.none,
                    hintStyle: const TextStyle(color: kTextDim, fontSize: 13),
                  ),
                  onChanged: (v) {
                    setState(() => _searchQuery = v);
                    if (_globalSearch) _runGlobalSearch(v);
                  },
                ),
              ),
              if (_searchRunning) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: kAccent)),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_path == root ? L.internalStorage : p.basename(_path),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.2)),
              if (_path != root)
                Text(p.dirname(_path),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10, color: kTextDim, height: 1.2)),
            ],
          ),
    actions: [
      if (_searching) ...[
        GestureDetector(
          onTap: () {
            setState(() => _globalSearch = !_globalSearch);
            if (_globalSearch && _searchQuery.isNotEmpty) _runGlobalSearch(_searchQuery);
            else setState(() => _searchResults = []);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _globalSearch ? kAccent : kCard,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _globalSearch ? kAccent : kBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.travel_explore_rounded, size: 14, color: _globalSearch ? Colors.white : kTextSec),
                const SizedBox(width: 4),
                Text(L.searchAll, style: TextStyle(fontSize: 11, color: _globalSearch ? Colors.white : kTextSec, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
      ],
      IconButton(
        icon: Icon(_searching ? Icons.close_rounded : Icons.search_rounded, size: 22),
        onPressed: () {
          setState(() {
            _searching = !_searching;
            if (!_searching) { _searchQuery = ''; _searchCtrl.clear(); _searchResults = []; _globalSearch = false; }
          });
        },
      ),
      if (!_searching) ...[
        IconButton(
          icon: const Icon(Icons.wifi_channel_rounded, size: 22, color: kCyan),
          tooltip: L.onlineVideo,
          onPressed: () => showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => const OnlinePlayerSheet(),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.tv_rounded, size: 22, color: kGreen),
          tooltip: 'IPTV',
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const IptvScreen())),
        ),
        if (_path != root)
          IconButton(
            icon: Icon(isSaved ? Icons.push_pin_rounded : Icons.push_pin_outlined, color: isSaved ? kAmber : kTextSec, size: 20),
            onPressed: () async { await Store.toggleSavedFolder(_path); setState(() {}); },
          ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.sd_storage_rounded, size: 20, color: kTextSec),
          tooltip: L.selectStorage,
          color: kSurface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: kBorder)),
          itemBuilder: (_) {
            final items = <PopupMenuEntry<String>>[
              _pmStr(Icons.smartphone_rounded, '/storage/emulated/0', L.internalStorage),
              _pmStr(Icons.download_for_offline_rounded, '/storage/emulated/0/Download', L.downloads),
              _pmStr(Icons.movie_creation_rounded, '/storage/emulated/0/Movies', L.movies),
            ];
            for (final d in _getStorageDevices()) {
              items.add(_pmStr(Icons.sd_card_rounded, d.path, p.basename(d.path)));
            }
            items..add(const PopupMenuDivider(height: 1))..add(_pmStr(Icons.folder_open_rounded, '__custom__', L.customPath));
            return items;
          },
          onSelected: (v) {
            if (v == '__custom__') {
              final ctrl = TextEditingController(text: _path);
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: kSurface,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: kBorder)),
                  title: Text(L.customPath, style: const TextStyle(fontWeight: FontWeight.bold)),
                  content: TextField(
                    controller: ctrl,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: '/storage/emulated/0/...',
                      filled: true,
                      fillColor: kCard,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kBorder)),
                    ),
                  ),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: Text(L.cancel, style: const TextStyle(color: kTextSec))),
                    FilledButton(onPressed: () { final pt = ctrl.text.trim(); Navigator.pop(ctx); if (pt.isNotEmpty) _loadDir(pt); }, child: Text(L.start)),
                  ],
                ),
              );
            } else { _loadDir(v); }
          },
        ),
        PopupMenuButton<_SortBy>(
          icon: const Icon(Icons.swap_vert_rounded, size: 22, color: kTextSec),
          color: kSurface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: kBorder)),
          onSelected: (v) => setState(() { if (_sortBy == v) _sortDesc = !_sortDesc; else { _sortBy = v; _sortDesc = false; } }),
          itemBuilder: (_) => [
            _pmSort(_SortBy.name, L.sortName, Icons.sort_by_alpha_rounded),
            _pmSort(_SortBy.date, L.sortDate, Icons.access_time_filled_rounded),
            _pmSort(_SortBy.size, L.sortSize, Icons.pie_chart_outline_rounded),
            _pmSort(_SortBy.type, L.sortType, Icons.video_collection_rounded),
          ],
        ),
      ],
    ],
  );

  PopupMenuItem<String> _pmStr(IconData icon, String v, String t) => PopupMenuItem(
    value: v,
    height: 42,
    child: Row(
      children: [
        Icon(icon, size: 18, color: kAccent),
        const SizedBox(width: 12),
        Text(t, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
      ],
    ),
  );

  PopupMenuItem<_SortBy> _pmSort(_SortBy v, String t, IconData icon) => PopupMenuItem(
    value: v,
    height: 42,
    child: Row(
      children: [
        Icon(icon, size: 18, color: _sortBy == v ? kAccent : kTextSec),
        const SizedBox(width: 12),
        Text('$t${_sortBy == v ? (_sortDesc ? '  ↑' : '  ↓') : ''}',
            style: TextStyle(fontSize: 13, color: _sortBy == v ? kAccent : Colors.white, fontWeight: _sortBy == v ? FontWeight.bold : FontWeight.normal)),
      ],
    ),
  );

  PreferredSizeWidget _selectBar() => AppBar(
    backgroundColor: kAccent.withOpacity(0.2),
    elevation: 0,
    automaticallyImplyLeading: false,
    leading: IconButton(icon: const Icon(Icons.close_rounded, size: 22), onPressed: () => setState(() { _selectMode = false; _selected.clear(); })),
    title: Text('${_selected.length} ${L.select}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
    actions: [
      if (_selected.isNotEmpty)
        IconButton(
          icon: const Icon(Icons.play_circle_fill_rounded, color: kAccent, size: 28),
          tooltip: L.play,
          onPressed: () {
            final sorted = _filteredVideos.where((v) => _selected.contains(v.path)).toList();
            if (sorted.isEmpty) return;
            setState(() { _selectMode = false; _selected.clear(); });
            Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerScreen(
              playlist: sorted.map((v) => File(v.path)).toList(),
              playlistIndex: 0,
            )));
          },
        ),
      TextButton.icon(
        icon: const Icon(Icons.select_all_rounded, size: 18),
        label: Text(L.allItems, style: const TextStyle(fontSize: 13)),
        onPressed: () => setState(() => _selected.addAll(_filteredVideos.map((v) => v.path))),
      ),
      IconButton(
        icon: const Icon(Icons.delete_forever_rounded, color: kRed, size: 22),
        onPressed: _selected.isEmpty ? null : () => _confirmDelete(_selected.map((s) => File(s)).toList()),
      ),
    ],
  );

  Widget _buildBody() {
    if (_checking) return const Center(child: CircularProgressIndicator(color: kAccent));
    if (!_granted) return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(28), border: Border.all(color: kBorder)),
              child: const Icon(Icons.folder_off_rounded, size: 56, color: kTextSec),
            ),
            const SizedBox(height: 24),
            Text(L.permissionNeeded, textAlign: TextAlign.center, style: const TextStyle(color: kTextSec, fontSize: 14)),
            const SizedBox(height: 24),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: kAccent, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
              onPressed: _ensurePermission,
              icon: const Icon(Icons.lock_open_rounded, size: 18),
              label: Text(L.grantPermission, style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 12),
            TextButton(onPressed: openAppSettings, child: Text(L.appSettings, style: const TextStyle(color: kTextDim))),
          ],
        ),
      ),
    );

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: kSurface,
          child: Row(
            children: [
              Icon(Icons.folder_open_rounded, size: 14, color: kAccent.withOpacity(0.8)),
              const SizedBox(width: 8),
              Expanded(child: Text(_path, style: const TextStyle(fontSize: 11, color: kTextDim, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis)),
              if (_searchRunning) const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.5, color: kAccent)),
              if (_globalSearch && !_searchRunning && _searchResults.isNotEmpty)
                _badge('${_searchResults.length}', kAccent, icon: Icons.travel_explore_rounded),
            ],
          ),
        ),
        Expanded(child: _buildList()),
      ],
    );
  }

  Widget _buildList() {
    final fDirs = _filteredDirs, fVids = _filteredVideos;
    final total = fDirs.length + fVids.length;
    if (total == 0 && _searchRunning) return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: kAccent),
          const SizedBox(height: 16),
          Text(L.searchingGlobal, style: const TextStyle(color: kTextSec)),
        ],
      ),
    );
    if (total == 0) return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.video_library_outlined, size: 56, color: kTextDim),
          const SizedBox(height: 14),
          Text(L.noFilesFound, style: const TextStyle(color: kTextSec, fontSize: 14)),
        ],
      ),
    );

    return RefreshIndicator(
      onRefresh: () async { if (!_globalSearch) { _loadDir(_path); } else if (_searchQuery.isNotEmpty) { _runGlobalSearch(_searchQuery); } },
      color: kAccent,
      backgroundColor: kCard,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewPadding.bottom + 90, top: 10, left: 12, right: 12),
        itemCount: total,
        itemBuilder: (ctx, i) {
          if (i < fDirs.length) {
            final d = fDirs[i];
            return _DirTile(dir: d, onTap: () => _loadDir(d.path));
          }
          final v = fVids[i - fDirs.length];
          return _VideoTile(
            file: v,
            selectMode: _selectMode,
            selected: _selected.contains(v.path),
            onTap: _selectMode
                ? () => setState(() => _selected.contains(v.path) ? _selected.remove(v.path) : _selected.add(v.path))
                : () => _openVideo(v, fVids, i - fDirs.length),
            onLongPress: _selectMode ? null : () => _showVideoMenu(v),
            showPath: _globalSearch,
          );
        },
      ),
    );
  }

  void _openPanel(int page) {
    final ctrl = DraggableScrollableController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      enableDrag: false,
      builder: (ctx) => DraggableScrollableSheet(
        controller: ctrl,
        initialChildSize: 0.58,
        minChildSize: 0.35,
        maxChildSize: 0.96,
        expand: false,
        snap: true,
        snapSizes: const [0.35, 0.58, 0.96],
        shouldCloseOnMinExtent: false,
        builder: (bctx, sc) => Container(
          decoration: BoxDecoration(
            color: kSurface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: kBorder.withOpacity(0.8)),
          ),
          child: Column(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.translucent,
                onVerticalDragUpdate: (d) {
                  final size = MediaQuery.of(ctx).size.height;
                  final delta = -d.delta.dy / size;
                  final cur = ctrl.size;
                  ctrl.jumpTo((cur + delta).clamp(0.35, 0.96));
                },
                onVerticalDragEnd: (d) async {
                  final cur = ctrl.size;
                  final target = cur > 0.75 ? 0.96 : cur > 0.45 ? 0.58 : 0.35;
                  await ctrl.animateTo(target, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
                  if (target <= 0.35 && ctx.mounted) Navigator.pop(ctx);
                },
                child: SizedBox(
                  height: 24,
                  child: Center(
                    child: Container(
                      width: 44, height: 4,
                      decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: BottomPanel(
                  initialPage: page,
                  noHandle: true,
                  onVideoTap: (path) { Navigator.pop(ctx); _openVideoByPath(path); },
                  onFolderTap: (folder) { Navigator.pop(ctx); _loadDir(folder); },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── تایل پوشه ──
class _DirTile extends StatelessWidget {
  final Directory dir;
  final VoidCallback onTap;
  const _DirTile({required this.dir, required this.onTap});

  @override Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    child: Material(
      color: kCard,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: kBorder.withOpacity(0.5)),
          ),
          child: Row(
            children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFD97706), Color(0xFFB45309)],
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(color: kAmber.withOpacity(0.2), blurRadius: 8, offset: const Offset(0, 2)),
                  ],
                ),
                child: const Icon(Icons.folder_rounded, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  p.basename(dir.path),
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, letterSpacing: 0.2),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(Icons.chevron_left_rounded, color: kTextDim, size: 22),
            ],
          ),
        ),
      ),
    ),
  );
}

// ── تایل ویدیو با Thumbnail ──
class _VideoTile extends StatelessWidget {
  final File file;
  final bool selectMode, selected, showPath;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  const _VideoTile({
    required this.file,
    required this.selectMode,
    required this.selected,
    required this.onTap,
    this.onLongPress,
    this.showPath = false,
  });

  @override Widget build(BuildContext context) {
    final name = p.basename(file.path);
    final ext = p.extension(file.path).toLowerCase().replaceAll('.', '');
    final seen = Store.watched.contains(file.path);
    final bkm = Store.bookmarked.contains(file.path);
    final fav = Store.favorited.contains(file.path);
    final hasSub = matchSubtitle(file.path) != null;
    final rating = Store.ratings[file.path] ?? 0;
    final hasNote = Store.notes.containsKey(file.path);
    final grad = _extGrad(ext);
    final dur = Store.getCachedDur(file.path);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? kAccent.withOpacity(0.18) : kCard,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: selected ? kAccent : kBorder.withOpacity(0.6)),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: selectMode
                      ? AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: 52, height: 52,
                          decoration: BoxDecoration(color: selected ? kAccent : kBorder, borderRadius: BorderRadius.circular(12)),
                          child: Icon(selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, color: Colors.white, size: 22),
                        )
                      : SizedBox(
                          width: 80, height: 52,
                          child: FutureBuilder<Uint8List?>(
                            future: _loadThumb(file.path),
                            builder: (ctx, snap) {
                              if (snap.hasData && snap.data != null) {
                                return Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    Image.memory(snap.data!, fit: BoxFit.cover),
                                    if (seen)
                                      Container(
                                        color: kGreen.withOpacity(0.35),
                                        alignment: Alignment.center,
                                        child: const Icon(Icons.check_circle_rounded, color: Colors.white, size: 22),
                                      ),
                                  ],
                                );
                              }
                              return Container(
                                decoration: BoxDecoration(gradient: grad),
                                alignment: Alignment.center,
                                child: snap.connectionState == ConnectionState.waiting
                                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white70))
                                    : Text(ext.length > 3 ? ext.substring(0, 3).toUpperCase() : ext.toUpperCase(),
                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.black, color: Colors.white)),
                              );
                            },
                          ),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: seen ? kGreen : Colors.white, height: 1.25),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (showPath)
                        Text(p.dirname(file.path), style: const TextStyle(fontSize: 10, color: kTextDim), maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 6),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            Text(sizeStr(file), style: const TextStyle(fontSize: 10.5, color: kTextDim, fontWeight: FontWeight.w500)),
                            if (dur != null && dur > 0) ...[
                              const Text(' • ', style: TextStyle(fontSize: 10.5, color: kTextDim)),
                              Text(fmt(Duration(seconds: dur)), style: const TextStyle(fontSize: 10.5, color: kTextDim, fontWeight: FontWeight.w500)),
                            ],
                            if (hasSub) ...[const SizedBox(width: 6), _badge('SUB', kGreen, icon: Icons.subtitles_rounded)],
                            if (bkm) ...[const SizedBox(width: 4), _badge('BOOKMARK', kAmber, icon: Icons.bookmark_rounded)],
                            if (fav) ...[const SizedBox(width: 4), _badge('FAV', kPink, icon: Icons.favorite_rounded)],
                            if (hasNote) ...[const SizedBox(width: 4), _badge('NOTE', kCyan, icon: Icons.edit_note_rounded)],
                            if (rating > 0) ...[
                              const SizedBox(width: 6),
                              Text('${'★' * rating}', style: const TextStyle(fontSize: 10, color: kAmber)),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (!selectMode) ...[
                  const SizedBox(width: 8),
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: seen ? kGreen.withOpacity(0.12) : kAccent.withOpacity(0.12),
                      shape: BoxShape.circle,
                      border: Border.all(color: seen ? kGreen.withOpacity(0.3) : kAccent.withOpacity(0.3)),
                    ),
                    child: Icon(Icons.play_arrow_rounded, color: seen ? kGreen : kAccent, size: 22),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── منوی شناور و جدید ویدیو ──
class VideoMenu extends StatefulWidget {
  final File file;
  final VoidCallback onDone, onInfo, onDelete, onRename, onSelect, onCopy, onMove, onRate, onNote;
  const VideoMenu({super.key, required this.file, required this.onDone, required this.onInfo, required this.onDelete, required this.onRename, required this.onSelect, required this.onCopy, required this.onMove, required this.onRate, required this.onNote});
  @override State<VideoMenu> createState() => _VideoMenuState();
}

class _VideoMenuState extends State<VideoMenu> {
  late bool _bkm = Store.bookmarked.contains(widget.file.path);
  late bool _fav = Store.favorited.contains(widget.file.path);

  @override Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      color: kSurface,
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    child: SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: kBorder, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(color: kCardLight, borderRadius: BorderRadius.circular(14), border: Border.all(color: kBorder)),
                    child: const Icon(Icons.video_file_rounded, color: kAccent, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(child: Text(p.basename(widget.file.path), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), maxLines: 2)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Divider(height: 1, color: kBorder),
            _mi(Icons.info_outline_rounded, kTextSec, L.fileInfo, widget.onInfo),
            _mi(Icons.bookmark_border_rounded, _bkm ? kAmber : kTextSec, _bkm ? L.removeBookmark : L.addBookmark, () async { await Store.toggleBookmark(widget.file.path); setState(() => _bkm = !_bkm); widget.onDone(); }),
            _mi(Icons.favorite_outline_rounded, _fav ? kPink : kTextSec, _fav ? L.removeFavorite : L.favorites, () async { await Store.toggleFavorite(widget.file.path); setState(() => _fav = !_fav); widget.onDone(); }),
            _mi(Icons.star_outline_rounded, kAmber, L.rating, widget.onRate),
            _mi(Icons.edit_note_rounded, kCyan, L.note, widget.onNote),
            const Divider(height: 1, color: kBorder),
            _mi(Icons.playlist_add_rounded, kCyan, L.addToPlaylist, () async {
              final playlists = Store.playlists.keys.toList();
              if (playlists.isEmpty) { showSnack(context, L.noPlaylist); return; }
              final name = await showDialog<String>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: kSurface,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: kBorder)),
                  title: Text(L.playlist, style: const TextStyle(fontWeight: FontWeight.bold)),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: playlists.map((pl) => ListTile(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      leading: const Icon(Icons.queue_music_rounded, color: kCyan, size: 20),
                      title: Text(pl, style: const TextStyle(fontSize: 13)),
                      onTap: () => Navigator.pop(ctx, pl),
                    )).toList(),
                  ),
                  actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(L.cancel, style: const TextStyle(color: kTextSec)))],
                ),
              );
              if (name != null) {
                await Store.addToPlaylist(name, widget.file.path);
                showSnack(context, '${L.addedTo} "$name"');
              }
            }),
            _mi(Icons.content_copy_rounded, kTextSec, L.copyTo, widget.onCopy),
            _mi(Icons.drive_file_move_outlined, kTextSec, L.moveTo, widget.onMove),
            _mi(Icons.drive_file_rename_outline_rounded, kTextSec, L.rename_, widget.onRename),
            _mi(Icons.checklist_rounded, kTextSec, L.selectGroup, widget.onSelect),
            _mi(Icons.delete_outline_rounded, kRed, L.delete, widget.onDelete),
            const SizedBox(height: 12),
          ],
        ),
      ),
    ),
  );

  Widget _mi(IconData icon, Color iconColor, String title, VoidCallback onTap) => ListTile(
    dense: true,
    leading: Container(
      width: 32, height: 32,
      decoration: BoxDecoration(color: iconColor.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
      child: Icon(icon, color: iconColor, size: 18),
    ),
    title: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
    onTap: onTap,
  );
}

// ── پانل شناور و زبانه ها ──
class BottomPanel extends StatefulWidget {
  final int initialPage;
  final ValueChanged<String> onVideoTap, onFolderTap;
  final bool noHandle;
  const BottomPanel({super.key, required this.initialPage, required this.onVideoTap, required this.onFolderTap, this.noHandle = false});
  @override State<BottomPanel> createState() => _BottomPanelState();
}

class _BottomPanelState extends State<BottomPanel> with SingleTickerProviderStateMixin {
  late TabController _tab;
  @override void initState() { super.initState(); _tab = TabController(length: 8, vsync: this, initialIndex: widget.initialPage.clamp(0, 7)); }
  @override void dispose() { _tab.dispose(); super.dispose(); }

  @override Widget build(BuildContext context) => Column(
    children: [
      if (!widget.noHandle) ...[
        const SizedBox(height: 10),
        Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: kBorder, borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 6),
      ],
      TabBar(
        controller: _tab,
        isScrollable: true,
        indicatorColor: kAccent,
        indicatorWeight: 3,
        labelColor: kAccent,
        unselectedLabelColor: kTextSec,
        labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        unselectedLabelStyle: const TextStyle(fontSize: 12),
        tabs: [
          Tab(icon: const Icon(Icons.history_toggle_off_rounded, size: 18), text: L.history),
          Tab(icon: const Icon(Icons.bookmark_added_rounded, size: 18), text: L.bookmarks),
          Tab(icon: const Icon(Icons.favorite_rounded, size: 18), text: L.favorites),
          Tab(icon: const Icon(Icons.push_pin_rounded, size: 18), text: L.folders),
          Tab(icon: const Icon(Icons.queue_music_rounded, size: 18), text: L.playlist),
          Tab(icon: const Icon(Icons.stars_rounded, size: 18), text: L.sponsors),
          Tab(icon: const Icon(Icons.construction_rounded, size: 18), text: L.tools),
          Tab(icon: const Icon(Icons.settings_suggest_rounded, size: 18), text: L.app),
        ],
      ),
      Expanded(
        child: TabBarView(
          controller: _tab,
          children: [
            _histTab(),
            _vList(Store.bookmarked.toList().reversed.toList(), Icons.bookmark_rounded, kAmber,
                onRemove: (path) async { await Store.toggleBookmark(path); setState(() {}); }),
            _vList(Store.favorited.toList().reversed.toList(), Icons.favorite_rounded, kPink,
                onRemove: (path) async { await Store.toggleFavorite(path); setState(() {}); }),
            _folderList(),
            _playlistTab(),
            _sponsorTab(),
            const ToolsTabBody(),
            _settingsTab(),
          ],
        ),
      ),
      SizedBox(height: MediaQuery.of(context).viewPadding.bottom),
    ],
  );

  Widget _histTab() => Column(
    children: [
      if (Store.watchHistory.isNotEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(child: Text(L.recentViews, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
              TextButton.icon(
                icon: const Icon(Icons.delete_sweep_rounded, size: 16, color: kRed),
                label: Text(L.deleteAll, style: const TextStyle(fontSize: 12, color: kRed)),
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: kSurface,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: kBorder)),
                      title: Text(L.deleteAllHistory, style: const TextStyle(fontWeight: FontWeight.bold)),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(L.cancel, style: const TextStyle(color: kTextSec))),
                        FilledButton(style: FilledButton.styleFrom(backgroundColor: kRed), onPressed: () => Navigator.pop(ctx, true), child: Text(L.delete)),
                      ],
                    ),
                  );
                  if (ok == true) { await Store.clearHistory(); setState(() {}); }
                },
              ),
            ],
          ),
        ),
      Expanded(
        child: _vList(
          Store.watchHistory, Icons.history_rounded, kTextSec,
          onLongPress: (path) async { await Store.removeFromHistory(path); setState(() {}); },
        ),
      ),
    ],
  );

  Widget _vList(List<String> paths, IconData icon, Color color, {Function(String)? onLongPress, void Function(String)? onRemove}) {
    if (paths.isEmpty) return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(20), border: Border.all(color: kBorder)),
            child: Icon(icon, size: 36, color: color.withOpacity(0.4)),
          ),
          const SizedBox(height: 12),
          Text(L.nothingYet, style: const TextStyle(color: kTextSec)),
        ],
      ),
    );

    return ListView.builder(
      itemCount: paths.length,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemBuilder: (_, i) {
        final path = paths[i];
        final isUrl = path.startsWith('http://') || path.startsWith('https://');
        final exists = isUrl ? true : File(path).existsSync();
        final displayName = isUrl ? Uri.parse(path).pathSegments.lastWhere((s) => s.isNotEmpty, orElse: () => path) : p.basename(path);
        final displaySub = isUrl ? path : p.dirname(path);

        return ListTile(
          dense: true,
          leading: Container(
            width: 34, height: 34,
            decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
            child: Icon(isUrl ? Icons.link_rounded : icon, color: exists ? color : kTextDim, size: 18),
          ),
          title: Text(displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: exists ? Colors.white : kTextDim, fontWeight: FontWeight.w500)),
          subtitle: Text(displaySub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: kTextDim)),
          trailing: onRemove != null ? IconButton(icon: const Icon(Icons.close_rounded, size: 16, color: kRed), onPressed: () => onRemove(path)) : null,
          onTap: exists ? () => widget.onVideoTap(path) : null,
          onLongPress: () {
            if (isUrl) {
              Clipboard.setData(ClipboardData(text: path));
              showSnack(context, L.linkCopied, color: const Color(0xFF7C3AED), seconds: 2);
            } else if (onLongPress != null) onLongPress(path);
          },
        );
      },
    );
  }

  Widget _folderList() {
    final folders = Store.savedFolders;
    if (folders.isEmpty) return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(20), border: Border.all(color: kBorder)),
            child: const Icon(Icons.push_pin_outlined, size: 36, color: kTextDim),
          ),
          const SizedBox(height: 12),
          Text(L.noSavedFolders, style: const TextStyle(color: kTextSec)),
          const SizedBox(height: 6),
          Text(L.pinFolderHint, style: const TextStyle(fontSize: 11, color: kTextDim)),
        ],
      ),
    );

    return ListView.builder(
      itemCount: folders.length,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemBuilder: (_, i) {
        final folder = folders[i];
        final exists = Directory(folder).existsSync();
        return ListTile(
          dense: true,
          leading: Container(
            width: 34, height: 34,
            decoration: BoxDecoration(color: kAmber.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
            child: Icon(Icons.folder_special_rounded, color: exists ? kAmber : kTextDim, size: 18),
          ),
          title: Text(p.basename(folder), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          subtitle: Text(folder, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: kTextDim)),
          trailing: IconButton(icon: const Icon(Icons.push_pin_rounded, size: 16, color: kRed), onPressed: () async { await Store.toggleSavedFolder(folder); setState(() {}); }),
          onTap: exists ? () => widget.onFolderTap(folder) : null,
        );
      },
    );
  }

  Widget _playlistTab() {
    final playlists = Store.playlists;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(child: Text(L.playlist, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: kAccent,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  minimumSize: const Size(0, 34),
                ),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(L.newItem, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                onPressed: () async {
                  final ctrl = TextEditingController();
                  final name = await showDialog<String>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: kSurface,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: kBorder)),
                      title: Text(L.newPlaylist, style: const TextStyle(fontWeight: FontWeight.bold)),
                      content: TextField(
                        controller: ctrl,
                        autofocus: true,
                        decoration: InputDecoration(
                          hintText: L.playlistName,
                          filled: true,
                          fillColor: kCard,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kBorder)),
                        ),
                      ),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(L.cancel, style: const TextStyle(color: kTextSec))),
                        FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: Text(L.create)),
                      ],
                    ),
                  );
                  if (name != null && name.isNotEmpty) { await Store.createPlaylist(name); setState(() {}); }
                },
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: kBorder),
        if (playlists.isEmpty)
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(20), border: Border.all(color: kBorder)),
                    child: const Icon(Icons.queue_music_rounded, size: 36, color: kTextDim),
                  ),
                  const SizedBox(height: 12),
                  Text(L.noPlaylists, style: const TextStyle(color: kTextSec)),
                  const SizedBox(height: 4),
                  Text(L.createPlaylist, style: const TextStyle(fontSize: 11, color: kTextDim)),
                ],
              ),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              itemCount: playlists.keys.length,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemBuilder: (_, i) {
                final name = playlists.keys.elementAt(i);
                final paths = playlists[name]!;
                return ListTile(
                  dense: true,
                  leading: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(gradient: const LinearGradient(colors: [kAccent, kCyan]), borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.queue_music_rounded, size: 18, color: Colors.white),
                  ),
                  title: Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  subtitle: Text('${paths.length} ${L.video}', style: const TextStyle(fontSize: 11, color: kTextDim)),
                  trailing: PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert_rounded, size: 20, color: kTextSec),
                    color: kSurface,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: kBorder)),
                    itemBuilder: (_) => [
                      PopupMenuItem(value: 'play', child: Text(L.play, style: const TextStyle(fontSize: 13))),
                      PopupMenuItem(value: 'delete', child: Text(L.delete, style: const TextStyle(fontSize: 13, color: kRed))),
                    ],
                    onSelected: (v) async {
                      if (v == 'delete') {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            backgroundColor: kSurface,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: kBorder)),
                            title: Text('${L.delete} "$name"?', style: const TextStyle(fontWeight: FontWeight.bold)),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(L.cancel, style: const TextStyle(color: kTextSec))),
                              FilledButton(style: FilledButton.styleFrom(backgroundColor: kRed), onPressed: () => Navigator.pop(ctx, true), child: Text(L.delete)),
                            ],
                          ),
                        );
                        if (ok == true) { await Store.deletePlaylist(name); setState(() {}); }
                      } else if (v == 'play' && paths.isNotEmpty) {
                        final files = paths.map((p) => File(p)).where((f) => f.existsSync()).toList();
                        if (files.isNotEmpty) {
                          Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerScreen(
                            playlist: files, playlistIndex: 0,
                            subtitlePath: matchSubtitle(files.first.path),
                          )));
                        }
                      }
                    },
                  ),
                  onTap: paths.isEmpty ? null : () {
                    final files = paths.map((p) => File(p)).where((f) => f.existsSync()).toList();
                    if (files.isNotEmpty) {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerScreen(
                        playlist: files, playlistIndex: 0,
                        subtitlePath: matchSubtitle(files.first.path),
                      )));
                    }
                  },
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _sponsorTab() => FutureBuilder<List<Map<String, dynamic>>>(
    future: ApiService.getSponsors(),
    builder: (ctx, snap) {
      if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: kAccent));
      final list = snap.data ?? [];
      if (list.isEmpty) return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(20), border: Border.all(color: kBorder)),
              child: const Icon(Icons.stars_rounded, size: 36, color: kTextDim),
            ),
            const SizedBox(height: 12),
            Text(L.noSponsors, style: const TextStyle(color: kTextSec)),
          ],
        ),
      );

      return ListView.builder(
        padding: const EdgeInsets.all(14),
        itemCount: list.length,
        itemBuilder: (_, i) {
          final s = list[i];
          final isFemale = (s['gender'] ?? 'male') == 'female';
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: kCard,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: kBorder.withOpacity(0.8)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 54, height: 54,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: isFemale ? [const Color(0xFFEC4899), const Color(0xFFF43F5E)] : [const Color(0xFF8B5CF6), const Color(0xFF06B6D4)]),
                      shape: BoxShape.circle,
                    ),
                    child: (s['avatar_url'] ?? '').isNotEmpty
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(27),
                            child: Image.network(s['avatar_url'], width: 54, height: 54, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Icon(isFemale ? Icons.face_3_rounded : Icons.face_rounded, color: Colors.white, size: 28)),
                          )
                        : Icon(isFemale ? Icons.face_3_rounded : Icons.face_rounded, color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5)),
                        if ((s['description'] ?? '').isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(s['description'], style: const TextStyle(fontSize: 11.5, color: kTextSec, height: 1.25)),
                          ),
                      ],
                    ),
                  ),
                  if ((s['link'] ?? '').isNotEmpty) ...[
                    const SizedBox(width: 8),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: kAccent,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        minimumSize: const Size(0, 36),
                      ),
                      onPressed: () => ul.launchUrl(Uri.parse(s['link']), mode: ul.LaunchMode.externalApplication),
                      child: Text(L.view, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      );
    },
  );

  Widget _settingsTab() => FutureBuilder<Map<String, dynamic>?>(
    future: ApiService.getConfig(),
    builder: (ctx, snap) {
      final cfg = snap.data ?? {};
      final channel = cfg['telegram_channel'] ?? '';
      final admin = cfg['telegram_admin'] ?? '';
      final reportText = cfg['report_text'] ?? L.reportBug;
      final remoteVer = cfg['app_version'] ?? '';
      final hasUpdate = remoteVer.isNotEmpty && ApiService.isNewer(remoteVer, ApiService.appVersion);

      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [kAccent.withOpacity(0.2), kCyan.withOpacity(0.1)]),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: kAccent.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: kAccent.withOpacity(0.25), borderRadius: BorderRadius.circular(14)),
                  child: const Icon(Icons.play_circle_fill_rounded, color: kAccent, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Vezoo Player', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 0.3)),
                      const SizedBox(height: 2),
                      Text('v${ApiService.appVersion}', style: const TextStyle(fontSize: 11, color: kTextSec)),
                    ],
                  ),
                ),
                if (snap.connectionState == ConnectionState.waiting)
                  const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: kAccent)),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _appBtn(
            icon: hasUpdate ? Icons.system_update_rounded : Icons.check_circle_rounded,
            color: hasUpdate ? kAmber : kGreen,
            label: hasUpdate ? L.updateAvailable : L.upToDate,
            onTap: hasUpdate ? () async {
              final url = cfg['download_url'] ?? '';
              if (url.isNotEmpty) await ul.launchUrl(Uri.parse(url), mode: ul.LaunchMode.externalApplication);
            } : null,
          ),
          const SizedBox(height: 10),
          _appBtn(
            icon: Icons.psychology_rounded,
            color: kAccent,
            label: L.aiModels,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AiModelsScreen())),
          ),
          const SizedBox(height: 10),
          if (channel.isNotEmpty)
            _appBtn(
              icon: Icons.telegram_rounded,
              color: kCyan,
              label: L.telegramChannel,
              onTap: () => ul.launchUrl(Uri.parse(channel), mode: ul.LaunchMode.externalApplication),
            ),
          if (channel.isNotEmpty) const SizedBox(height: 10),
          if (admin.isNotEmpty)
            _appBtn(
              icon: Icons.bug_report_rounded,
              color: kPink,
              label: reportText,
              onTap: () => ul.launchUrl(Uri.parse(admin), mode: ul.LaunchMode.externalApplication),
            ),
          const SizedBox(height: 16),
          const _LangPicker(),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(18), border: Border.all(color: kBorder)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(L.features, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 8),
                const Text('• MP4 / MKV / AVI / MOV / WEBM\n• SRT / VTT / ASS / SSA Subtitles\n• HDR Playback & Audio Boost\n• Dual Subtitle Support & AI Engines',
                    style: TextStyle(fontSize: 12, color: kTextSec, height: 1.6)),
              ],
            ),
          ),
        ],
      );
    },
  );
}

Widget _appBtn({required IconData icon, required Color color, required String label, VoidCallback? onTap}) {
  return Material(
    color: kCard,
    borderRadius: BorderRadius.circular(16),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: onTap != null ? color.withOpacity(0.35) : kBorder),
        ),
        child: Row(
          children: [
            Icon(icon, color: onTap != null ? color : kTextDim, size: 22),
            const SizedBox(width: 14),
            Text(label, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: onTap != null ? Colors.white : kTextSec)),
            const Spacer(),
            if (onTap != null) Icon(Icons.arrow_forward_ios_rounded, size: 14, color: kTextDim),
          ],
        ),
      ),
    ),
  );
}

class _LangPicker extends StatefulWidget {
  const _LangPicker();
  @override State<_LangPicker> createState() => _LangPickerState();
}

class _LangPickerState extends State<_LangPicker> {
  @override Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(L.language, style: const TextStyle(color: kTextSec, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: kSupportedLangs.map((lang) => GestureDetector(
            onTap: () async { await L.set(lang); if (mounted) setState(() {}); },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: L.current == lang ? kAccent : kCard,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: L.current == lang ? kAccent : kBorder),
              ),
              child: Text(
                kLangNames[lang]!,
                style: TextStyle(
                  fontSize: 12,
                  color: L.current == lang ? Colors.white : kTextSec,
                  fontWeight: L.current == lang ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          )).toList(),
        ),
      ],
    );
  }
}
