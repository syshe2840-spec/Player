import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whisper_ggml_plus/whisper_ggml_plus.dart';

class WhisperModelDef {
  final WhisperModel model;
  final String name;
  final String desc;
  final int sizeMb;
  final int speedStars;
  final int accStars;
  const WhisperModelDef({required this.model, required this.name,
    required this.desc, required this.sizeMb,
    required this.speedStars, required this.accStars});
  // همان URL که package استفاده می‌کند
  String get url => 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-${model.modelName}.bin';
  String get filename => 'ggml-${model.modelName}.bin';
}

const kWhisperModels = [
  WhisperModelDef(model:WhisperModel.tiny,  name:'Tiny',  desc:'گوشی‌های ضعیف',       sizeMb:75,  speedStars:5, accStars:3),
  WhisperModelDef(model:WhisperModel.base,  name:'Base',  desc:'اکثر کاربران (پیشنهاد)',sizeMb:142, speedStars:4, accStars:4),
  WhisperModelDef(model:WhisperModel.small, name:'Small', desc:'گوشی‌های قوی',          sizeMb:466, speedStars:3, accStars:5),
];

const kLanguages = {
  'fa':'فارسی','en':'English','ar':'عربی','tr':'ترکی',
  'fr':'فرانسه','de':'آلمانی','es':'اسپانیایی','zh':'چینی',
  'ja':'ژاپنی','ru':'روسی','ko':'کره‌ای',
};

class WhisperService {
  static final _ch = const MethodChannel('com.vezoo.player/whisper');
  static bool _dlCancelled = false;
  static bool _trCancelled = false;

  // ── مسیر مدل‌ها — همان مسیری که WhisperController استفاده می‌کند ──
  static Future<String> getModelsDir() async {
    final d = await getApplicationSupportDirectory();
    return d.path;
  }
  static Future<String> modelPath(WhisperModelDef m) async =>
      p.join(await getModelsDir(), m.filename);

  static Future<bool> isDownloaded(WhisperModelDef m) async {
    try {
      final f = File(await modelPath(m));
      return f.existsSync() && f.lengthSync() > m.sizeMb * 1024 * 1024 * 0.3;
    } catch (_) { return false; }
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

  // ── دانلود با progress ──
  static Stream<double> downloadModel(WhisperModelDef model) async* {
    _dlCancelled = false;
    final dest = await modelPath(model);
    final tmp = '$dest.tmp';

    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 30);

      final req = await client.getUrl(Uri.parse(model.url));
      req.headers.set('User-Agent', 'whisper_flutter_downloader/1.0');
      final res = await req.close();

      if (res.statusCode != 200) {
        client.close();
        throw Exception('HTTP ${res.statusCode} — دانلود ناموفق');
      }

      final total = res.contentLength;
      int recv = 0;
      final sink = File(tmp).openWrite();

      await for (final chunk in res) {
        if (_dlCancelled) { await sink.close(); break; }
        sink.add(chunk);
        recv += chunk.length;
        if (total > 0) yield recv / total;
        else yield -1; // نامشخص
      }
      await sink.close();
      client.close();

      if (_dlCancelled) {
        try { File(tmp).deleteSync(); } catch (_) {}
        throw Exception('دانلود لغو شد');
      }

      if (File(tmp).existsSync()) {
        File(tmp).renameSync(dest);
        await setActive(model);
        yield 1.0;
      } else {
        throw Exception('فایل دانلود نشد');
      }
    } catch (e) {
      try { if (File(tmp).existsSync()) File(tmp).deleteSync(); } catch (_) {}
      rethrow;
    }
  }

  static void cancelDownload() { _dlCancelled = true; }

  static Future<void> deleteModel(WhisperModelDef m) async {
    try { File(await modelPath(m)).deleteSync(); } catch (_) {}
    final active = await getActiveModel();
    if (active?.model.modelName == m.model.modelName) {
      (await SharedPreferences.getInstance()).remove('whisper_active');
    }
  }

  // ── استخراج صدا از ویدیو ──
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
      final active = await getActiveModel();
      if (active == null || !(await isDownloaded(active))) {
        throw Exception('مدل AI دانلود نشده\nاز دکمه ✨ → AI مدل دانلود کنید');
      }
      final mPath = await modelPath(active);

      onStatus('استخراج صدا...', 0.1);
      wav = await extractAudio(videoPath);
      if (_trCancelled) throw Exception('لغو شد');
      if (!File(wav).existsSync() || File(wav).lengthSync() == 0) {
        throw Exception('استخراج صدا ناموفق — ویدیو صدا ندارد؟');
      }

      onStatus('تبدیل گفتار به متن (${active.name})...', 0.35);
      final ctrl = WhisperController();
      // مسیر مدل را مستقیماً پاس می‌دهیم
      final whisper = Whisper(model: active.model);
      final result = await whisper.transcribe(
        transcribeRequest: TranscribeRequest(
          audio: wav,
          language: language,
          isTranslate: false,
          isNoTimestamps: false,
          threads: 4,
        ),
        modelPath: mPath,
      );
      if (_trCancelled) throw Exception('لغو شد');

      onStatus('ذخیره SRT...', 0.9);
      final segs = result.segments;
      final srt = (segs != null && segs.isNotEmpty)
          ? _segsToSrt(segs) : _textToSrt(result.text);

      final ext = p.extension(videoPath);
      final srtPath = videoPath.replaceFirst(RegExp('${RegExp.escape(ext)}\$'), '_ai.srt');
      File(srtPath).writeAsStringSync(srt, encoding: utf8);

      onStatus('✓ تمام شد', 1.0);
      return srtPath;
    } finally {
      if (wav != null) try { File(wav).deleteSync(); } catch (_) {}
    }
  }

  static String _segsToSrt(List<WhisperTranscribeSegment> segs) {
    final b = StringBuffer();
    for (int i = 0; i < segs.length; i++) {
      b.writeln('${i+1}');
      b.writeln('${_d(segs[i].fromTs)} --> ${_d(segs[i].toTs)}');
      b.writeln(segs[i].text.trim());
      b.writeln();
    }
    return b.toString();
  }
  static String _textToSrt(String text) {
    final parts = text.split(RegExp(r'(?<=[.!?،؟])\s+')).where((s)=>s.trim().isNotEmpty).toList();
    final b = StringBuffer();
    for (int i = 0; i < parts.length; i++) {
      b.writeln('${i+1}');
      b.writeln('${_d(Duration(seconds:i*5))} --> ${_d(Duration(seconds:(i+1)*5))}');
      b.writeln(parts[i].trim()); b.writeln();
    }
    return b.toString();
  }
  static String _d(Duration d) {
    final h=d.inHours.toString().padLeft(2,'0');
    final m=(d.inMinutes%60).toString().padLeft(2,'0');
    final s=(d.inSeconds%60).toString().padLeft(2,'0');
    final ms=(d.inMilliseconds%1000).toString().padLeft(3,'0');
    return '$h:$m:$s,$ms';
  }
}

