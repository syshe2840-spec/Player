import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'whisper_service.dart';

/// صفحه تست AI v2 — whisper.cpp بومی (native)
/// فقط برای اعتبارسنجی که libvezoo_whisper.so درست کار می‌کند.
/// بعد از تأیید، منطق نهایی به whisper_service جایگزین می‌شود.
class WhisperV2TestScreen extends StatefulWidget {
  const WhisperV2TestScreen({super.key});
  @override State<WhisperV2TestScreen> createState() => _State();
}

class _State extends State<WhisperV2TestScreen> {
  static const _ch = MethodChannel('com.vezoo.player/whisper');

  String _log = '';
  bool _running = false;
  String? _videoPath;
  String _lang = 'en';

  void _addLog(String s) {
    setState(() => _log = '$_log\n$s');
    debugPrint('[WhisperV2Test] $s');
  }

  Future<void> _pickVideo() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.video);
    if (res?.files.single.path != null) {
      setState(() => _videoPath = res!.files.single.path);
      _addLog('ویدیو انتخاب شد: ${_videoPath!.split('/').last}');
    }
  }

  Future<void> _runTest() async {
    if (_videoPath == null) { _addLog('⚠ اول یه ویدیو انتخاب کن'); return; }

    setState((){ _running = true; _log = ''; });
    int? ctx;
    String? wav;

    try {
      // ۱. چک مدل دانلودشده (از سیستم v1 استفاده می‌کنیم — همون فایل .bin)
      _addLog('① جستجوی مدل دانلودشده...');
      final active = await WhisperService.getActiveModel();
      if (active == null) throw Exception('هیچ مدلی فعال نیست — اول از تب AI یه مدل دانلود کن');
      final modelPath = await WhisperService.modelFilePath(active);
      if (!File(modelPath).existsSync()) throw Exception('فایل مدل پیدا نشد: $modelPath');
      _addLog('   مدل: ${active.name} ($modelPath)');

      // ۲. system info (تست لود شدن .so)
      _addLog('② تست لود کتابخانه native...');
      final sysInfo = await _ch.invokeMethod<String>('v2SystemInfo');
      _addLog('   ✓ libvezoo_whisper.so لود شد');
      _addLog('   CPU info: $sysInfo');

      // ۳. init context
      _addLog('③ بارگذاری مدل در whisper.cpp...');
      final stopwatch = Stopwatch()..start();
      final ctxResult = await _ch.invokeMethod<dynamic>('v2InitContext', {'modelPath': modelPath});
      ctx = (ctxResult as num).toInt();
      _addLog('   ✓ مدل بارگذاری شد در ${stopwatch.elapsedMilliseconds}ms (ctx=$ctx)');

      // ۴. استخراج صدا (با همون extractAudio v1)
      _addLog('④ استخراج صدا از ویدیو...');
      stopwatch.reset();
      wav = await WhisperService.extractAudio(_videoPath!);
      _addLog('   ✓ صدا استخراج شد در ${stopwatch.elapsedMilliseconds}ms');
      _addLog('   فایل: $wav (${(File(wav).lengthSync()/1024).toStringAsFixed(0)} KB)');

      // ۵. transcribe واقعی
      _addLog('⑤ اجرای transcribe بومی (whisper_full)...');
      stopwatch.reset();
      final text = await _ch.invokeMethod<String>('v2Transcribe', {
        'ctx': ctx, 'wavPath': wav, 'lang': _lang, 'threads': 4,
      });
      _addLog('   ✓ transcribe تمام شد در ${stopwatch.elapsedMilliseconds}ms');
      _addLog('');
      _addLog('━━━━━━━━━━━━━━━━━━━━━━━━━━');
      _addLog('نتیجه (start_ms|end_ms|text):');
      _addLog(text ?? '(خالی)');
      _addLog('━━━━━━━━━━━━━━━━━━━━━━━━━━');

    } catch (e) {
      _addLog('');
      _addLog('✗ خطا: $e');
    } finally {
      if (ctx != null) {
        try { await _ch.invokeMethod('v2FreeContext', {'ctx': ctx}); } catch (_) {}
      }
      // توجه: wav کش‌شده عمداً حذف نمی‌شود — برای استفاده بعدی نگه داشته می‌شود
      setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF0F0F14),
    appBar: AppBar(
      backgroundColor: const Color(0xFF1C1C22),
      title: const Text('تست AI v2 (native)', style: TextStyle(color: Colors.white, fontSize: 15)),
      leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.pop(context)),
    ),
    body: Column(children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Row(children: [
            Expanded(child: OutlinedButton.icon(
              onPressed: _pickVideo,
              icon: const Icon(Icons.video_file, size: 16),
              label: Text(_videoPath == null ? 'انتخاب ویدیو' : _videoPath!.split('/').last,
                overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFF7C3AED))),
            )),
            const SizedBox(width: 8),
            DropdownButton<String>(
              value: _lang, dropdownColor: const Color(0xFF2A2A35),
              style: const TextStyle(color: Colors.white, fontSize: 13),
              items: const [
                DropdownMenuItem(value: 'en', child: Text('English')),
                DropdownMenuItem(value: 'fa', child: Text('فارسی')),
              ],
              onChanged: (v) { if (v != null) setState(() => _lang = v); },
            ),
          ]),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, child: FilledButton.icon(
            onPressed: _running ? null : _runTest,
            icon: _running
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.play_arrow),
            label: Text(_running ? 'در حال اجرا...' : 'اجرای تست'),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF7C3AED), padding: const EdgeInsets.symmetric(vertical: 14)),
          )),
        ]),
      ),
      const Divider(color: Colors.white12, height: 1),
      Expanded(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          child: SingleChildScrollView(
            child: SelectableText(
              _log.isEmpty ? 'لاگ اینجا نمایش داده می‌شود...' : _log.trim(),
              style: const TextStyle(color: Colors.greenAccent, fontSize: 11, fontFamily: 'monospace', height: 1.5),
            ),
          ),
        ),
      ),
    ]),
  );
}

