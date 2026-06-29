import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whisper_ggml_plus/whisper_ggml_plus.dart';

// ── تعریف مدل‌ها ──
class WhisperModelDef {
  final WhisperModel model;
  final String name;
  final String desc;
  final int sizeMb;
  final int speedStars;
  final int accStars;
  final String url;

  const WhisperModelDef({
    required this.model, required this.name, required this.desc,
    required this.sizeMb, required this.speedStars, required this.accStars,
    required this.url,
  });

  String get filename => 'ggml-${model.modelName}.bin';
}

const kWhisperModels = [
  WhisperModelDef(
    model: WhisperModel.tiny, name: 'Tiny', desc: 'گوشی‌های ضعیف',
    sizeMb: 31, speedStars: 5, accStars: 3,
    url: 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny-q5_1.bin',
  ),
  WhisperModelDef(
    model: WhisperModel.base, name: 'Base', desc: 'اکثر کاربران (پیشنهادی)',
    sizeMb: 57, speedStars: 4, accStars: 4,
    url: 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base-q5_1.bin',
  ),
  WhisperModelDef(
    model: WhisperModel.small, name: 'Small', desc: 'گوشی‌های قوی',
    sizeMb: 181, speedStars: 3, accStars: 5,
    url: 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small-q5_1.bin',
  ),
];

const kLanguages = {
  'fa': 'فارسی', 'en': 'English', 'ar': 'عربی',
  'tr': 'ترکی', 'fr': 'فرانسه', 'de': 'آلمانی',
  'es': 'اسپانیایی', 'zh': 'چینی', 'ja': 'ژاپنی', 'ru': 'روسی',
};

class WhisperService {
  static const _ch = MethodChannel('com.vezoo.player/whisper');
  static bool _dlCancelled = false;
  static bool _trCancelled = false;

  // ── پوشه مدل‌ها ──
  static Future<String> getModelsDir() async {
    final d = await getApplicationSupportDirectory();
    return d.path; // WhisperController هم از همین path استفاده می‌کنه
  }

  static Future<String> _modelPath(WhisperModelDef m) async =>
      p.join(await getModelsDir(), m.filename);

  static Future<bool> isDownloaded(WhisperModelDef m) async {
    final f = File(await _modelPath(m));
    if (!f.existsSync()) return false;
    return f.lengthSync() > m.sizeMb * 1024 * 1024 * 0.4;
  }

  // ── مدل فعال ──
  static Future<WhisperModelDef?> getActiveModel() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('whisper_active');
    if (name == null) return null;
    try { return kWhisperModels.firstWhere((m) => m.model.modelName == name); }
    catch (_) { return null; }
  }

  static Future<void> setActive(WhisperModelDef m) async =>
      (await SharedPreferences.getInstance()).setString('whisper_active', m.model.modelName);

  // ── دانلود ──
  static Stream<double> downloadModel(WhisperModelDef model) async* {
    _dlCancelled = false;
    final path = await _modelPath(model);
    final tmp = '$path.tmp';

    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
      final req = await client.getUrl(Uri.parse(model.url));
      final res = await req.close();
      final total = res.contentLength;
      int recv = 0;
      final sink = File(tmp).openWrite();

      await for (final chunk in res) {
        if (_dlCancelled) { await sink.close(); break; }
        sink.add(chunk);
        recv += chunk.length;
        if (total > 0) yield recv / total;
      }
      await sink.close();
      client.close();

      if (_dlCancelled) {
        if (File(tmp).existsSync()) File(tmp).deleteSync();
        throw Exception('دانلود لغو شد');
      }

      File(tmp).renameSync(path);
      await setActive(model);
      yield 1.0;
    } catch (e) {
      if (File(tmp).existsSync()) File(tmp).deleteSync();
      rethrow;
    }
  }

  static void cancelDownload() => _dlCancelled = true;

  static Future<void> deleteModel(WhisperModelDef m) async {
    final f = File(await _modelPath(m));
    if (f.existsSync()) f.deleteSync();
    final active = await getActiveModel();
    if (active?.model.modelName == m.model.modelName) {
      (await SharedPreferences.getInstance()).remove('whisper_active');
    }
  }

  // ── استخراج صدا (Kotlin) ──
  static Future<String> extractAudio(String videoPath) async {
    final tmp = await getTemporaryDirectory();
    final wav = p.join(tmp.path, 'wzr_${DateTime.now().millisecondsSinceEpoch}.wav');
    await _ch.invokeMethod('extractAudio', {'input': videoPath, 'output': wav});
    return wav;
  }

  static Future<void> cancelExtraction() async {
    _trCancelled = true;
    try { await _ch.invokeMethod('cancelExtraction'); } catch (_) {}
  }

  // ── Transcribe ──
  static Future<String> transcribe({
    required String videoPath,
    required String language,
    required void Function(String, double) onStatus,
  }) async {
    _trCancelled = false;
    String? wav;

    try {
      // ۱. چک مدل
      final active = await getActiveModel();
      if (active == null || !(await isDownloaded(active))) {
        throw Exception('مدل AI دانلود نشده\nاز تب AI مدل انتخاب کنید');
      }

      // ۲. استخراج صدا
      onStatus('استخراج صدا از ویدیو...', 0.1);
      wav = await extractAudio(videoPath);
      if (_trCancelled) throw Exception('لغو شد');

      if (!File(wav).existsSync() || File(wav).lengthSync() == 0) {
        throw Exception('استخراج صدا ناموفق');
      }

      // ۳. Transcribe
      onStatus('تبدیل گفتار به متن (${active.name})...', 0.4);
      final ctrl = WhisperController();
      final result = await ctrl.transcribe(
        model: active.model,
        audioPath: wav,
        lang: language,
        withTimestamps: true,
        convert: false,
      );
      if (_trCancelled) throw Exception('لغو شد');
      if (result == null) throw Exception('نتیجه‌ای دریافت نشد');

      // ۴. SRT
      onStatus('ذخیره زیرنویس...', 0.9);
      final segs = result.transcription.segments;
      final srt = (segs != null && segs.isNotEmpty)
          ? _segsToSrt(segs)
          : _textToSrt(result.transcription.text);

      final ext = p.extension(videoPath);
      final srtPath = videoPath.replaceAll(RegExp('${RegExp.escape(ext)}\$'), '_ai.srt');
      File(srtPath).writeAsStringSync(srt, encoding: utf8);

      onStatus('✓ زیرنویس ذخیره شد', 1.0);
      return srtPath;
    } finally {
      if (wav != null) try { File(wav).deleteSync(); } catch (_) {}
    }
  }

  static String _segsToSrt(List<WhisperTranscribeSegment> segs) {
    final b = StringBuffer();
    for (int i = 0; i < segs.length; i++) {
      b.writeln('${i + 1}');
      b.writeln('${_fmtDur(segs[i].fromTs)} --> ${_fmtDur(segs[i].toTs)}');
      b.writeln(segs[i].text.trim());
      b.writeln();
    }
    return b.toString();
  }

  static String _textToSrt(String text) {
    final parts = text.split(RegExp(r'(?<=[.!?،؟])\s+')).where((s) => s.trim().isNotEmpty).toList();
    final b = StringBuffer();
    for (int i = 0; i < parts.length; i++) {
      final from = Duration(seconds: i * 5);
      final to = Duration(seconds: (i + 1) * 5);
      b.writeln('${i + 1}');
      b.writeln('${_fmtDur(from)} --> ${_fmtDur(to)}');
      b.writeln(parts[i].trim());
      b.writeln();
    }
    return b.toString();
  }

  static String _fmtDur(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    final ms = (d.inMilliseconds % 1000).toString().padLeft(3, '0');
    return '$h:$m:$s,$ms';
  }
}
