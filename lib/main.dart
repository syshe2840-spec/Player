import 'dart:io';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:file_picker/file_picker.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // راه‌اندازی موتور پخش media_kit (همان mpv)
  MediaKit.ensureInitialized();
  runApp(const MyApp());
}

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
        colorSchemeSeed: Colors.indigo,
      ),
      home: const PlayerPage(),
    );
  }
}

class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key});

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  // پلیر و کنترلر تصویر
  late final Player player = Player();
  late final VideoController controller = VideoController(player);

  String? videoName;
  String? subtitleName;

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  // انتخاب فایل ویدیو
  Future<void> _pickVideo() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.video);
    final path = result?.files.single.path;
    if (path == null) return;
    setState(() => videoName = result!.files.single.name);
    await player.open(Media(path));
  }

  // انتخاب فایل زیرنویس srt
  // نکته‌ی کلیدی: محتوای زیرنویس را به صورت "متن" می‌خوانیم و مستقیم
  // به پلیر می‌دهیم. در مرحله‌های بعد، همین متن را قبل از دادن به پلیر
  // رمزگشایی (decrypt) می‌کنیم. ساختار همین می‌ماند.
  Future<void> _pickSubtitle() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['srt'],
    );
    final path = result?.files.single.path;
    if (path == null) return;
    final content = await File(path).readAsString();
    setState(() => subtitleName = result!.files.single.name);
    await player.setSubtitleTrack(SubtitleTrack.data(content));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('پلیر زیرنویس')),
      body: Column(
        children: [
          // ناحیه‌ی نمایش ویدیو
          Expanded(
            child: Container(
              color: Colors.black,
              width: double.infinity,
              child: videoName == null
                  ? const Center(
                      child: Text(
                        'یک ویدیو انتخاب کنید',
                        style: TextStyle(color: Colors.white54),
                      ),
                    )
                  : Video(controller: controller),
            ),
          ),
          // ناحیه‌ی دکمه‌ها
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                if (videoName != null)
                  Text('ویدیو: $videoName',
                      style: const TextStyle(fontSize: 12)),
                if (subtitleName != null)
                  Text('زیرنویس: $subtitleName',
                      style: const TextStyle(fontSize: 12)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _pickVideo,
                        icon: const Icon(Icons.movie),
                        label: const Text('انتخاب ویدیو'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: _pickSubtitle,
                        icon: const Icon(Icons.subtitles),
                        label: const Text('انتخاب زیرنویس'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

