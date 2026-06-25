import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const MyApp());
}

// پسوندهای ویدیویی و زیرنویس که می‌شناسیم
const Set<String> kVideoExt = {
  '.mp4', '.mkv', '.avi', '.mov', '.webm', '.m4v',
  '.3gp', '.flv', '.ts', '.m2ts', '.wmv', '.mpg', '.mpeg',
};
const List<String> kSubExt = ['.srt', '.ass', '.ssa', '.vtt'];

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
        scaffoldBackgroundColor: const Color(0xFF121218),
      ),
      // کل اپ راست‌به‌چپ
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      home: const BrowserScreen(),
    );
  }
}

// ---------------------------------------------------------------------------
//  صفحه مرور فایل‌ها (فایل‌منیجر داخل اپ)
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
    _ensurePermission();
  }

  Future<void> _ensurePermission() async {
    setState(() => _checking = true);
    // اندروید ۱۱ به بالا: دسترسی به همه فایل‌ها
    var ok = await Permission.manageExternalStorage.isGranted;
    if (!ok) ok = (await Permission.manageExternalStorage.request()).isGranted;
    // اندروید قدیمی‌تر
    if (!ok) ok = (await Permission.storage.request()).isGranted;
    setState(() {
      _granted = ok;
      _checking = false;
    });
    if (ok) _loadDir(_path);
  }

  void _loadDir(String path) {
    try {
      final dir = Directory(path);
      final items = dir.listSync(followLinks: false);
      final dirs = items.whereType<Directory>().toList();
      final vids = items.whereType<File>().where((f) {
        return kVideoExt.contains(p.extension(f.path).toLowerCase());
      }).toList();
      int byName(FileSystemEntity a, FileSystemEntity b) =>
          p.basename(a.path).toLowerCase().compareTo(
              p.basename(b.path).toLowerCase());
      dirs.sort(byName);
      vids.sort(byName);
      setState(() {
        _path = dir.path;
        _dirs = dirs;
        _videos = vids;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('به این پوشه دسترسی نیست')),
      );
    }
  }

  // پیدا کردن زیرنویس هم‌اسم در همان پوشه
  String? _matchSubtitle(String videoPath) {
    final dir = p.dirname(videoPath);
    final base = p.basenameWithoutExtension(videoPath);
    for (final ext in kSubExt) {
      final candidate = p.join(dir, '$base$ext');
      if (File(candidate).existsSync()) return candidate;
    }
    return null;
  }

  void _openVideo(File video) {
    final sub = _matchSubtitle(video.path);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          videoPath: video.path,
          subtitlePath: sub,
        ),
      ),
    );
  }

  void _goUp() {
    final parent = p.dirname(_path);
    if (parent != _path && parent.startsWith('/storage')) _loadDir(parent);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _path == root ? 'حافظه داخلی' : p.basename(_path),
          overflow: TextOverflow.ellipsis,
        ),
        leading: _path != root
            ? IconButton(icon: const Icon(Icons.arrow_upward), onPressed: _goUp)
            : null,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.bookmark_outline),
            onSelected: _loadDir,
            itemBuilder: (_) => const [
              PopupMenuItem(value: root, child: Text('حافظه داخلی')),
              PopupMenuItem(
                  value: '$root/Download', child: Text('دانلودها')),
              PopupMenuItem(value: '$root/Movies', child: Text('فیلم‌ها')),
              PopupMenuItem(value: '$root/DCIM', child: Text('دوربین')),
            ],
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_checking) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!_granted) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.folder_off, size: 64, color: Colors.white38),
              const SizedBox(height: 16),
              const Text(
                'برای مرور فیلم‌ها و زیرنویس‌ها، اپ به دسترسی فایل‌ها نیاز دارد.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _ensurePermission,
                icon: const Icon(Icons.lock_open),
                label: const Text('اجازه دسترسی'),
              ),
              TextButton(
                onPressed: openAppSettings,
                child: const Text('باز کردن تنظیمات اپ'),
              ),
            ],
          ),
        ),
      );
    }

    final total = _dirs.length + _videos.length;
    if (total == 0) {
      return const Center(child: Text('این پوشه خالی است'));
    }

    return ListView.builder(
      itemCount: total,
      itemBuilder: (context, i) {
        if (i < _dirs.length) {
          final d = _dirs[i];
          return ListTile(
            leading: const Icon(Icons.folder, color: Color(0xFFFFCB6B)),
            title: Text(p.basename(d.path)),
            onTap: () => _loadDir(d.path),
          );
        }
        final v = _videos[i - _dirs.length];
        final hasSub = _matchSubtitle(v.path) != null;
        return ListTile(
          leading: const Icon(Icons.movie, color: Color(0xFF82AAFF)),
          title: Text(p.basename(v.path)),
          subtitle: hasSub
              ? const Text('زیرنویس پیدا شد ✓',
                  style: TextStyle(color: Colors.greenAccent, fontSize: 12))
              : null,
          trailing: const Icon(Icons.play_circle_outline),
          onTap: () => _openVideo(v),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
//  صفحه پخش
// ---------------------------------------------------------------------------
class PlayerScreen extends StatefulWidget {
  final String videoPath;
  final String? subtitlePath;
  const PlayerScreen({super.key, required this.videoPath, this.subtitlePath});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final Player player = Player();
  late final VideoController controller = VideoController(player);

  // محتوای زیرنویس فعلی (متن خام). در آینده همین جا رمزگشایی می‌شود.
  String? _subContent;
  bool _subVisible = true;

  // تنظیمات ظاهری زیرنویس
  double _fontSize = 32;
  bool _bold = true;
  double _bgOpacity = 0.5;
  Color _color = Colors.white;
  double _speed = 1.0;

  final List<Color> _colorChoices = const [
    Colors.white,
    Color(0xFFFFEB3B),
    Color(0xFF69F0AE),
    Color(0xFF40C4FF),
    Color(0xFFFF8A65),
    Color(0xFFFF80AB),
  ];

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    await player.open(Media(widget.videoPath));
    if (widget.subtitlePath != null) {
      await _loadSubtitle(widget.subtitlePath!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'زیرنویس: ${p.basename(widget.subtitlePath!)}')),
        );
      }
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
      type: FileType.custom,
      allowedExtensions: ['srt', 'ass', 'ssa', 'vtt'],
    );
    final path = res?.files.single.path;
    if (path != null) await _loadSubtitle(path);
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  SubtitleViewConfiguration get _subConfig => SubtitleViewConfiguration(
        style: TextStyle(
          fontSize: _fontSize,
          color: _color,
          fontWeight: _bold ? FontWeight.bold : FontWeight.normal,
          backgroundColor: Colors.black.withOpacity(_bgOpacity),
          height: 1.3,
        ),
        textAlign: TextAlign.center,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(p.basename(widget.videoPath),
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15)),
        actions: [
          IconButton(
            icon: const Icon(Icons.subtitles),
            tooltip: 'تنظیمات زیرنویس',
            onPressed: _openSettings,
          ),
        ],
      ),
      body: Center(
        child: Video(
          controller: controller,
          subtitleViewConfiguration: _subConfig,
        ),
      ),
    );
  }

  void _openSettings() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1C1C22),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            // یک تغییر را هم در شیت و هم در پلیر اعمال می‌کند
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
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // روشن/خاموش زیرنویس
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('نمایش زیرنویس'),
                      value: _subVisible,
                      onChanged: (v) => change(() {
                        _subVisible = v;
                        _applySubtitle();
                      }),
                    ),

                    // اندازه فونت
                    Text('اندازه فونت: ${_fontSize.round()}'),
                    Slider(
                      min: 16,
                      max: 60,
                      value: _fontSize,
                      onChanged: (v) => change(() => _fontSize = v),
                    ),

                    // پررنگ
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('پررنگ (Bold)'),
                      value: _bold,
                      onChanged: (v) => change(() => _bold = v),
                    ),

                    // شفافیت پس‌زمینه
                    Text('پس‌زمینه: ${(_bgOpacity * 100).round()}%'),
                    Slider(
                      min: 0,
                      max: 1,
                      value: _bgOpacity,
                      onChanged: (v) => change(() => _bgOpacity = v),
                    ),

                    // رنگ
                    const SizedBox(height: 8),
                    const Text('رنگ نوشته'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      children: _colorChoices.map((c) {
                        final selected = c.value == _color.value;
                        return GestureDetector(
                          onTap: () => change(() => _color = c),
                          child: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: c,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: selected
                                    ? Colors.white
                                    : Colors.transparent,
                                width: 3,
                              ),
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

                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.pop(ctx);
                              _pickSubtitleManually();
                            },
                            icon: const Icon(Icons.file_open),
                            label: const Text('انتخاب زیرنویس'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

