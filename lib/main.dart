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

const Set<String> kVideoExt = {
  '.mp4', '.mkv', '.avi', '.mov', '.webm', '.m4v',
  '.3gp', '.flv', '.ts', '.m2ts', '.wmv', '.mpg', '.mpeg',
};
const List<String> kSubExt = ['.srt', '.ass', '.ssa', '.vtt'];

String fmt(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}

String sizeStr(File f) {
  try {
    final b = f.lengthSync();
    if (b > 1073741824) return '${(b / 1073741824).toStringAsFixed(1)} GB';
    return '${(b / 1048576).toStringAsFixed(0)} MB';
  } catch (_) {
    return '';
  }
}

// پیدا کردن زیرنویس هم‌اسم (تابع عمومی، هم مرورگر هم پلیر استفاده می‌کنن)
String? matchSubtitle(String videoPath) {
  final dir = p.dirname(videoPath);
  final base = p.basenameWithoutExtension(videoPath);
  for (final ext in kSubExt) {
    final c = p.join(dir, '$base$ext');
    if (File(c).existsSync()) return c;
  }
  return null;
}

// ---------------------------------------------------------------------------
// ذخیره‌سازی: دیده‌شده، نشانه‌گذاری، موقعیت پخش
// ---------------------------------------------------------------------------
class Store {
  static Set<String> watched = {};
  static Set<String> bookmarked = {};

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    watched = (p.getStringList('watched') ?? []).toSet();
    bookmarked = (p.getStringList('bookmarks') ?? []).toSet();
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

  static Future<void> savePos(String path, Duration pos) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt('pos:$path', pos.inSeconds);
  }

  static Future<Duration> getPos(String path) async {
    final p = await SharedPreferences.getInstance();
    return Duration(seconds: p.getInt('pos:$path') ?? 0);
  }
}

// ---------------------------------------------------------------------------
class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'پلیر زیرنویس',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF6C63FF),
        scaffoldBackgroundColor: const Color(0xFF101014),
      ),
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      home: const BrowserScreen(),
    );
  }
}

// ---------------------------------------------------------------------------
// مرورگر فایل
// ---------------------------------------------------------------------------
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

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await Store.load();
    await _ensurePermission();
  }

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
      final dir = Directory(path);
      final items = dir.listSync(followLinks: false);
      final dirs = items.whereType<Directory>().toList();
      final vids = items.whereType<File>().where(
          (f) => kVideoExt.contains(p.extension(f.path).toLowerCase())).toList();
      int cmp(FileSystemEntity a, FileSystemEntity b) =>
          p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase());
      dirs.sort(cmp);
      vids.sort(cmp);
      setState(() { _path = path; _dirs = dirs; _videos = vids; });
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
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          subtitlePath: matchSubtitle(video.path),
          playlist: _videos,
          playlistIndex: _videos.indexOf(video),
        ),
      ),
    );
    await Store.load();
    if (mounted) setState(() {});
  }

  void _showFileInfo(File f) {
    final sub = matchSubtitle(f.path);
    String modified = '';
    try { modified = f.lastModifiedSync().toString().split('.').first; } catch (_) {}
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
            _iRow(Icons.calendar_today, 'تاریخ', modified),
            _iRow(Icons.visibility_outlined, 'وضعیت',
                Store.watched.contains(f.path) ? 'دیده شده ✓' : 'دیده نشده'),
            _iRow(Icons.bookmark_outline, 'نشانه',
                Store.bookmarked.contains(f.path) ? 'نشانه‌گذاری شده ★' : 'بدون نشانه'),
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
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: Colors.white38),
        const SizedBox(width: 6),
        Text('$label: ', style: const TextStyle(color: Colors.white54, fontSize: 12)),
        Expanded(child: Text(val, style: const TextStyle(fontSize: 12),
            overflow: TextOverflow.ellipsis, maxLines: 2)),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _path == root,
      onPopInvokedWithResult: (didPop, _) { if (!didPop) _goUp(); },
      child: Scaffold(
        appBar: AppBar(
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
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_checking) return const Center(child: CircularProgressIndicator());
    if (!_granted) {
      return Center(
        child: Padding(
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
        ),
      );
    }
    return Column(children: [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        color: const Color(0xFF1A1A22),
        child: Text(_path,
            style: const TextStyle(fontSize: 11, color: Colors.white38),
            overflow: TextOverflow.ellipsis),
      ),
      Expanded(child: _buildList()),
    ]);
  }

  Widget _buildList() {
    final total = _dirs.length + _videos.length;
    if (total == 0) return const Center(child: Text('این پوشه خالی است'));

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: total,
      separatorBuilder: (_, __) =>
          const Divider(height: 1, color: Color(0xFF222230)),
      itemBuilder: (ctx, i) {
        if (i < _dirs.length) {
          final d = _dirs[i];
          return ListTile(
            leading: Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                  color: const Color(0xFF2A2520),
                  borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.folder, color: Color(0xFFFFCB6B)),
            ),
            title: Text(p.basename(d.path), maxLines: 1,
                overflow: TextOverflow.ellipsis),
            trailing: const Icon(Icons.chevron_left, color: Colors.white38),
            onTap: () => _loadDir(d.path),
          );
        }
        final v = _videos[i - _dirs.length];
        final seen = Store.watched.contains(v.path);
        final bkm = Store.bookmarked.contains(v.path);
        final hasSub = matchSubtitle(v.path) != null;

        return ListTile(
          leading: Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
                color: const Color(0xFF1E2433),
                borderRadius: BorderRadius.circular(10)),
            child: Icon(
              seen ? Icons.check_circle : Icons.movie,
              color: seen ? Colors.greenAccent : const Color(0xFF82AAFF),
            ),
          ),
          title: Text(p.basename(v.path), maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: seen ? Colors.greenAccent : Colors.white,
                fontWeight: seen ? FontWeight.w500 : FontWeight.normal,
              )),
          subtitle: Row(children: [
            Text(sizeStr(v),
                style: const TextStyle(fontSize: 11, color: Colors.white38)),
            if (hasSub) ...[
              const SizedBox(width: 8),
              const Text('• زیرنویس ✓',
                  style: TextStyle(fontSize: 11, color: Colors.greenAccent)),
            ],
          ]),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: () async {
                  await Store.toggleBookmark(v.path);
                  if (mounted) setState(() {});
                },
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(
                    bkm ? Icons.bookmark : Icons.bookmark_border,
                    color: bkm ? Colors.amber : Colors.white38,
                    size: 22,
                  ),
                ),
              ),
              const Icon(Icons.play_circle_outline, size: 24),
            ],
          ),
          onTap: () => _openVideo(v),
          onLongPress: () => _showFileInfo(v),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// پلیر ویدیو
// ---------------------------------------------------------------------------
enum _GMode { none, seek, brightness, volume, zoom, pan, subtitlePos }

class PlayerScreen extends StatefulWidget {
  final String? subtitlePath;
  final List<File> playlist;
  final int playlistIndex;

  const PlayerScreen({
    super.key,
    this.subtitlePath,
    required this.playlist,
    required this.playlistIndex,
  });

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

  // زیرنویس
  String? _subContent;
  bool _subVisible = true;
  double _fontSize = 32;
  bool _bold = true;
  double _bgOpacity = 0.5;
  Color _color = Colors.white;
  TextAlign _subAlign = TextAlign.center;
  double _subBottomPadding = 50.0;
  double _subPaddingStart = 50.0;

  // پخش
  double _speed = 1.0;
  BoxFit _fit = BoxFit.contain;
  bool _landscape = false;

  // کنترل‌ها
  bool _controlsVisible = true;
  bool _locked = false;
  Timer? _hideTimer;

  // بزرگنمایی و جابجایی
  double _scale = 1.0;
  double _baseScale = 1.0;
  Offset _offset = Offset.zero;
  Offset _baseOffset = Offset.zero;

  // اشاره‌ها
  _GMode _mode = _GMode.none;
  Offset _startFocal = Offset.zero;
  Offset _doubleTapPos = Offset.zero;
  int _seekStartMs = 0;
  int _seekTargetMs = 0;
  double _startBrightness = 0.5;
  double _startVolume = 100;
  Size _size = Size.zero;

  // پیام روی صفحه
  String? _overlay;
  Timer? _overlayTimer;

  final List<Color> _colorChoices = const [
    Colors.white, Color(0xFFFFEB3B), Color(0xFF69F0AE),
    Color(0xFF40C4FF), Color(0xFFFF8A65), Color(0xFFFF80AB),
  ];

  String get _curPath => widget.playlist[_playIndex].path;
  bool get _hasPrev => _playIndex > 0;
  bool get _hasNext => _playIndex < widget.playlist.length - 1;

  @override
  void initState() {
    super.initState();
    _playIndex = widget.playlistIndex
        .clamp(0, (widget.playlist.length - 1).clamp(0, 99999));
    WakelockPlus.enable();
    _subs.add(player.stream.position.listen((pos) {
      _position = pos;
      _maybeWatched();
      if (mounted) setState(() {});
    }));
    _subs.add(player.stream.duration.listen((d) {
      _duration = d;
      if (mounted) setState(() {});
    }));
    _subs.add(player.stream.playing.listen((pl) {
      _playing = pl;
      if (mounted) setState(() {});
    }));
    _start();
    _startHideTimer();
  }

  Future<void> _start() async {
    await player.open(Media(_curPath));
    final saved = await Store.getPos(_curPath);
    if (saved.inSeconds > 5) {
      await player.seek(saved);
      _showOverlay('ادامه از ${fmt(saved)}');
    }
    final sub = widget.subtitlePath ?? matchSubtitle(_curPath);
    if (sub != null) await _loadSubtitle(sub);
  }

  Future<void> _switchVideo(int idx) async {
    await Store.savePos(_curPath, _position);
    _playIndex = idx;
    _position = Duration.zero;
    _duration = Duration.zero;
    _subContent = null;
    setState(() {});
    await player.open(Media(_curPath));
    final saved = await Store.getPos(_curPath);
    if (saved.inSeconds > 5) await player.seek(saved);
    final sub = matchSubtitle(_curPath);
    if (sub != null) {
      await _loadSubtitle(sub);
    } else {
      await player.setSubtitleTrack(SubtitleTrack.no());
    }
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
    try {
      content = utf8.decode(bytes);
    } catch (_) {
      content = utf8.decode(bytes, allowMalformed: true);
    }
    _subContent = content;
    await _applySubtitle();
  }

  Future<void> _applySubtitle() async {
    if (_subContent != null && _subVisible) {
      await player.setSubtitleTrack(SubtitleTrack.data(_subContent!));
    } else {
      await player.setSubtitleTrack(SubtitleTrack.no());
    }
  }

  Future<void> _pickSubtitleManually() async {
    final res = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: ['srt', 'ass', 'ssa', 'vtt']);
    final path = res?.files.single.path;
    if (path != null) await _loadSubtitle(path);
  }

  @override
  void dispose() {
    Store.savePos(_curPath, _position);
    for (final s in _subs) {
      s.cancel();
    }
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

  // دو‌ضربه: چپ صفحه = جلو، راست صفحه = عقب (مثل پلیرهای انگلیسی‌زبان)
  void _onDoubleTap() {
    if (_locked) return;
    final onRight = _doubleTapPos.dx > _size.width / 2;
    final delta = Duration(seconds: onRight ? -10 : 10);
    var target = _position + delta;
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
    _baseScale = _scale;
    _baseOffset = _offset;
    _startFocal = d.localFocalPoint;
    _seekStartMs = _position.inMilliseconds;
    _subPaddingStart = _subBottomPadding;
    _startVolume = player.state.volume;
    _getBrightness().then((b) => _startBrightness = b);
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (_locked) return;

    // دو انگشت = زوم و جابجایی
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
      if (_scale > 1.05) {
        _mode = _GMode.pan;
      } else if (dx.abs() > dy.abs()) {
        _mode = _GMode.seek;
      } else if (_subVisible && _startFocal.dy > _size.height * 0.65) {
        // کشیدن در ناحیه زیرنویس = جابجایی زیرنویس
        _mode = _GMode.subtitlePos;
      } else if (_startFocal.dx > _size.width / 2) {
        // نیمه راست = نور
        _mode = _GMode.brightness;
      } else {
        // نیمه چپ = صدا
        _mode = _GMode.volume;
      }
    }

    switch (_mode) {
      case _GMode.pan:
        setState(() => _offset = _baseOffset + (d.localFocalPoint - _startFocal));
        break;
      case _GMode.seek:
        final total = _duration.inMilliseconds;
        final delta = ((dx / _size.width) * 90000).round();
        _seekTargetMs = (_seekStartMs + delta).clamp(0, total);
        _showOverlay(
            '${fmt(Duration(milliseconds: _seekTargetMs))} / ${fmt(_duration)}');
        break;
      case _GMode.brightness:
        final nb = (_startBrightness - dy / _size.height).clamp(0.0, 1.0);
        _setBrightness(nb);
        _showOverlay('☀ ${(nb * 100).round()}%');
        break;
      case _GMode.volume:
        final nv =
            (_startVolume - dy / _size.height * 100).clamp(0.0, 100.0);
        player.setVolume(nv);
        _showOverlay('🔊 ${nv.round()}%');
        break;
      case _GMode.subtitlePos:
        // کشیدن بالا = عدد بزرگ‌تر = زیرنویس بالاتر
        final newPad = (_subPaddingStart - dy)
            .clamp(10.0, _size.height * 0.75);
        setState(() => _subBottomPadding = newPad);
        _showOverlay('موقعیت زیرنویس');
        break;
      default:
        break;
    }
  }

  void _onScaleEnd(ScaleEndDetails d) {
    if (_mode == _GMode.seek) {
      player.seek(Duration(milliseconds: _seekTargetMs));
    }
    if (_scale <= 1.02) {
      setState(() {
        _scale = 1.0;
        _offset = Offset.zero;
      });
    }
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
    setState(() {
      _fit = _fit == BoxFit.contain
          ? BoxFit.cover
          : _fit == BoxFit.cover
              ? BoxFit.fill
              : BoxFit.contain;
    });
    _showOverlay(_fit == BoxFit.contain
        ? 'عادی'
        : _fit == BoxFit.cover
            ? 'پر کردن صفحه'
            : 'کشیده');
  }

  SubtitleViewConfiguration get _subConfig => SubtitleViewConfiguration(
        style: TextStyle(
          fontSize: _fontSize,
          color: _color,
          fontWeight: _bold ? FontWeight.bold : FontWeight.normal,
          backgroundColor: Colors.black.withOpacity(_bgOpacity),
          height: 1.4,
        ),
        textAlign: _subAlign,
        padding: EdgeInsets.fromLTRB(20, 0, 20, _subBottomPadding),
      );

  @override
  Widget build(BuildContext context) {
    _size = MediaQuery.of(context).size;
    final bkm = Store.bookmarked.contains(_curPath);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ویدیو با زوم
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
                  subtitleViewConfiguration: _subConfig,
                ),
              ),
            ),
          ),

          // لایه اشاره (کل صفحه)
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

          // پیام وسط صفحه
          if (_overlay != null)
            Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.65),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(_overlay!,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),

          // کنترل‌های پلیر
          if (_controlsVisible && !_locked) _buildControls(bkm),

          // دکمه قفل (وقتی قفل است)
          if (_locked)
            Positioned(
              top: 16,
              left: 16,
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
          // ===== نوار بالا =====
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black54, Colors.transparent],
              ),
            ),
            child: Row(
              children: [
                IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.pop(context)),
                Expanded(
                  child: Text(p.basename(_curPath),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13)),
                ),
                // نشانه‌گذاری
                IconButton(
                  icon: Icon(
                    bkm ? Icons.bookmark : Icons.bookmark_border,
                    color: bkm ? Colors.amber : Colors.white,
                  ),
                  onPressed: () async {
                    await Store.toggleBookmark(_curPath);
                    setState(() {});
                  },
                ),
                IconButton(
                    icon: const Icon(Icons.subtitles),
                    onPressed: _openSettings),
                IconButton(
                  icon: Icon(_fit == BoxFit.contain
                      ? Icons.fit_screen
                      : Icons.aspect_ratio),
                  onPressed: _cycleFit,
                ),
                IconButton(
                  icon: Icon(_landscape
                      ? Icons.stay_current_portrait
                      : Icons.screen_rotation),
                  onPressed: _toggleOrientation,
                ),
                IconButton(
                  icon: const Icon(Icons.lock_open),
                  onPressed: () => setState(() {
                    _locked = true;
                    _controlsVisible = false;
                  }),
                ),
              ],
            ),
          ),

          // ===== وسط: قبلی / پخش / بعدی =====
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // در RTL: اولین آیتم = سمت راست = ویدیوی قبلی
                IconButton(
                  iconSize: 44,
                  icon: Icon(Icons.skip_previous,
                      color: _hasPrev ? Colors.white : Colors.white24),
                  onPressed: _hasPrev ? () => _switchVideo(_playIndex - 1) : null,
                ),
                const SizedBox(width: 24),
                IconButton(
                  iconSize: 68,
                  icon: Icon(_playing
                      ? Icons.pause_circle_filled
                      : Icons.play_circle_filled),
                  onPressed: () {
                    _playing ? player.pause() : player.play();
                    _startHideTimer();
                  },
                ),
                const SizedBox(width: 24),
                // در RTL: آخرین آیتم = سمت چپ = ویدیوی بعدی
                IconButton(
                  iconSize: 44,
                  icon: Icon(Icons.skip_next,
                      color: _hasNext ? Colors.white : Colors.white24),
                  onPressed: _hasNext ? () => _switchVideo(_playIndex + 1) : null,
                ),
              ],
            ),
          ),

          // ===== نوار پایین: زمان + اسلایدر =====
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Colors.black54, Colors.transparent],
              ),
            ),
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: Row(
              children: [
                Text(fmt(_position),
                    style: const TextStyle(fontSize: 12)),
                Expanded(
                  child: Slider(
                    min: 0,
                    max: _duration.inMilliseconds <= 0
                        ? 1.0
                        : _duration.inMilliseconds.toDouble(),
                    value: _position.inMilliseconds
                        .clamp(
                            0,
                            _duration.inMilliseconds <= 0
                                ? 0
                                : _duration.inMilliseconds)
                        .toDouble(),
                    onChanged: (v) {
                      player.seek(Duration(milliseconds: v.round()));
                      _startHideTimer();
                    },
                  ),
                ),
                Text(fmt(_duration),
                    style: const TextStyle(fontSize: 12)),
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
          void change(VoidCallback fn) {
            fn();
            setSheet(() {});
            setState(() {});
          }

          return Padding(
            padding: EdgeInsets.fromLTRB(
                20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // دستگیره
                  Center(
                      child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                              color: Colors.white24,
                              borderRadius: BorderRadius.circular(2)))),
                  const SizedBox(height: 16),

                  // نمایش / مخفی‌کردن زیرنویس
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('نمایش زیرنویس'),
                    value: _subVisible,
                    onChanged: (v) =>
                        change(() { _subVisible = v; _applySubtitle(); }),
                  ),

                  // اندازه فونت
                  Text('اندازه فونت: ${_fontSize.round()}'),
                  Slider(
                      min: 14,
                      max: 64,
                      value: _fontSize,
                      onChanged: (v) => change(() => _fontSize = v)),

                  // پررنگ
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('پررنگ (Bold)'),
                    value: _bold,
                    onChanged: (v) => change(() => _bold = v),
                  ),

                  // شفافیت پس‌زمینه
                  Text(
                      'پس‌زمینه: ${(_bgOpacity * 100).round()}% (۰ = بی‌رنگ)'),
                  Slider(
                      min: 0,
                      max: 1,
                      value: _bgOpacity,
                      onChanged: (v) => change(() => _bgOpacity = v)),

                  // موقعیت عمودی زیرنویس
                  Text(
                      'موقعیت از پایین: ${_subBottomPadding.round()} (یا با کشیدن روی صفحه)'),
                  Slider(
                      min: 10,
                      max: 400,
                      value: _subBottomPadding,
                      onChanged: (v) =>
                          change(() => _subBottomPadding = v)),

                  // چینش متن
                  const SizedBox(height: 8),
                  const Text('چینش زیرنویس'),
                  const SizedBox(height: 8),
                  SegmentedButton<TextAlign>(
                    segments: const [
                      ButtonSegment(
                          value: TextAlign.right,
                          label: Text('راست'),
                          icon: Icon(Icons.format_align_right, size: 16)),
                      ButtonSegment(
                          value: TextAlign.center,
                          label: Text('وسط'),
                          icon: Icon(Icons.format_align_center, size: 16)),
                      ButtonSegment(
                          value: TextAlign.left,
                          label: Text('چپ'),
                          icon: Icon(Icons.format_align_left, size: 16)),
                    ],
                    selected: {_subAlign},
                    onSelectionChanged: (s) =>
                        change(() => _subAlign = s.first),
                  ),

                  // رنگ متن
                  const SizedBox(height: 14),
                  const Text('رنگ زیرنویس'),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 12,
                    children: _colorChoices.map((c) {
                      final sel = c.value == _color.value;
                      return GestureDetector(
                        onTap: () => change(() => _color = c),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: sel ? Colors.white : Colors.transparent,
                                width: 3),
                          ),
                        ),
                      );
                    }).toList(),
                  ),

                  const Divider(height: 32),

                  // سرعت پخش
                  const Text('سرعت پخش'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [0.5, 0.75, 1.0, 1.25, 1.5, 2.0].map((s) {
                      return ChoiceChip(
                        label: Text('${s}x'),
                        selected: _speed == s,
                        onSelected: (_) => change(() {
                          _speed = s;
                          player.setRate(s);
                        }),
                      );
                    }).toList(),
                  ),

                  const Divider(height: 32),

                  // انتخاب زیرنویس دستی
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _pickSubtitleManually();
                    },
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

