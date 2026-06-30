import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whisper_ggml_plus/whisper_ggml_plus.dart';

// ══════════════════════════════════════════════════════════
//  تعریف مدل‌ها
// ══════════════════════════════════════════════════════════
class WhisperModelDef {
  final String id;           // شناسه یکتا: 'tiny-q5_1'
  final WhisperModel base;   // WhisperModel enum
  final String name;         // نام نمایشی
  final String variant;      // '' | 'q5_1' | 'q8_0' | 'q5_0' | 'q6_k'
  final int sizeMb;
  final int speedStars;
  final int accStars;
  final String desc;

  const WhisperModelDef({required this.id, required this.base, required this.name,
    required this.variant, required this.sizeMb,
    required this.speedStars, required this.accStars, required this.desc});

  // URL دانلود — همان URL که package خودش استفاده می‌کند
  String get url =>
    'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-$id.bin';

  // نام فایل: ggml-{base.modelName}.bin (بدون variant suffix)
  String get filename => 'ggml-${base.modelName}.bin';

  // پوشه مخصوص این variant: {modelsRoot}/{id}/
  String dirPath(String root) => p.join(root, id);
  String filePath(String root) => p.join(dirPath(root), filename);

  bool isQuantized => variant.isNotEmpty;
}

const kWhisperModels = [
  // ── Tiny ──
  WhisperModelDef(id:'tiny',      base:WhisperModel.tiny,  name:'Tiny',     variant:'',     sizeMb:75,   speedStars:5, accStars:3, desc:'گوشی‌های ضعیف — سریع‌ترین'),
  WhisperModelDef(id:'tiny-q5_1', base:WhisperModel.tiny,  name:'Tiny Q5',  variant:'q5_1', sizeMb:31,   speedStars:5, accStars:3, desc:'فشرده‌شده — حجم کم'),

  // ── Base ──
  WhisperModelDef(id:'base',      base:WhisperModel.base,  name:'Base',     variant:'',     sizeMb:142,  speedStars:4, accStars:4, desc:'پیشنهاد برای اکثر کاربران'),
  WhisperModelDef(id:'base-q5_1', base:WhisperModel.base,  name:'Base Q5',  variant:'q5_1', sizeMb:57,   speedStars:4, accStars:4, desc:'فشرده — پیشنهاد ویژه'),

  // ── Small ──
  WhisperModelDef(id:'small',      base:WhisperModel.small, name:'Small',    variant:'',     sizeMb:466,  speedStars:3, accStars:4, desc:'دقت خوب'),
  WhisperModelDef(id:'small-q5_1', base:WhisperModel.small, name:'Small Q5', variant:'q5_1', sizeMb:181,  speedStars:3, accStars:4, desc:'فشرده'),

  // ── Medium ──
  WhisperModelDef(id:'medium',      base:WhisperModel.medium, name:'Medium',    variant:'',     sizeMb:1500, speedStars:2, accStars:5, desc:'دقت بالا — مخصوصاً فارسی'),
  WhisperModelDef(id:'medium-q5_0', base:WhisperModel.medium, name:'Medium Q5', variant:'q5_0', sizeMb:514,  speedStars:2, accStars:5, desc:'فشرده — کیفیت high'),

  // ── Large ──
  WhisperModelDef(id:'large-v3',              base:WhisperModel.large,        name:'Large V3',       variant:'',     sizeMb:3000, speedStars:1, accStars:5, desc:'بهترین دقت'),
  WhisperModelDef(id:'large-v3-turbo',        base:WhisperModel.largeV3Turbo, name:'Large Turbo',    variant:'',     sizeMb:798,  speedStars:2, accStars:5, desc:'سریع‌تر از Large'),
  WhisperModelDef(id:'large-v3-turbo-q5_0',   base:WhisperModel.largeV3Turbo, name:'Turbo Q5',       variant:'q5_0', sizeMb:531,  speedStars:2, accStars:5, desc:'فشرده — بهترین تعادل'),
];

const kLanguages = {
  'fa':'فارسی','en':'English','ar':'عربی','tr':'ترکی','fr':'فرانسه',
  'de':'آلمانی','es':'اسپانیایی','zh':'چینی','ja':'ژاپنی','ru':'روسی','ko':'کره‌ای',
};

// ══════════════════════════════════════════════════════════
//  سرویس اصلی
// ══════════════════════════════════════════════════════════
class WhisperService {
  static final _ch = const MethodChannel('com.vezoo.player/whisper');
  static bool _dlCancelled = false;
  static bool _trCancelled = false;

  // ── پوشه‌ها ──
  static Future<String> _modelsRoot() async =>
      p.join((await getApplicationSupportDirectory()).path, 'whisper_models');

  static Future<String> modelFilePath(WhisperModelDef m) async =>
      m.filePath(await _modelsRoot());

  static Future<bool> isDownloaded(WhisperModelDef m) async {
    try {
      final f = File(await modelFilePath(m));
      return f.existsSync() && f.lengthSync() > m.sizeMb * 1024 * 1024 * 0.3;
    } catch (_) { return false; }
  }

  static Future<List<WhisperModelDef>> downloadedModels() async {
    final result = <WhisperModelDef>[];
    for (final m in kWhisperModels) {
      if (await isDownloaded(m)) result.add(m);
    }
    return result;
  }

  // ── مدل فعال ──
  static Future<WhisperModelDef?> getActiveModel() async {
    final id = (await SharedPreferences.getInstance()).getString('whisper_active');
    if (id == null) return null;
    try { return kWhisperModels.firstWhere((m) => m.id == id); } catch (_) { return null; }
  }
  static Future<void> setActive(WhisperModelDef m) async =>
      (await SharedPreferences.getInstance()).setString('whisper_active', m.id);

  // ── دانلود با Resume ──
  static Stream<double> downloadModel(WhisperModelDef model) async* {
    _dlCancelled = false;
    final root = await _modelsRoot();
    final dir = Directory(model.dirPath(root));
    if (!dir.existsSync()) dir.createSync(recursive: true);

    final dest = model.filePath(root);
    final tmp = '$dest.tmp';
    final tmpFile = File(tmp);

    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 30);

      // Resume: چک کردن فایل موقت قبلی
      final existingBytes = tmpFile.existsSync() ? tmpFile.lengthSync() : 0;

      final req = await client.getUrl(Uri.parse(model.url));
      req.headers.set('User-Agent', 'whisper_vezoo_downloader/1.0');
      if (existingBytes > 0) req.headers.set('Range', 'bytes=$existingBytes-');

      final res = await req.close();

      // 416 = فایل از قبل کامل شده
      if (res.statusCode == 416) {
        await res.drain();
        client.close();
        if (tmpFile.existsSync()) tmpFile.renameSync(dest);
        await setActive(model);
        yield 1.0;
        return;
      }

      final isResume = res.statusCode == 206;
      final isNew = res.statusCode == 200;
      if (!isResume && !isNew) {
        await res.drain();
        client.close();
        throw Exception('HTTP ${res.statusCode}');
      }

      // اگه resume نشد از اول شروع کن
      if (!isResume && tmpFile.existsSync()) tmpFile.deleteSync();

      final total = isResume
          ? existingBytes + (res.contentLength > 0 ? res.contentLength : 0)
          : (res.contentLength > 0 ? res.contentLength : model.sizeMb * 1024 * 1024);

      int recv = isResume ? existingBytes : 0;
      final mode = isResume ? FileMode.append : FileMode.write;
      final sink = tmpFile.openWrite(mode: mode);

      await for (final chunk in res) {
        if (_dlCancelled) { await sink.close(); break; }
        sink.add(chunk);
        recv += chunk.length;
        yield recv / total;
      }
      await sink.close();
      client.close();

      if (_dlCancelled) throw Exception('دانلود لغو شد');

      tmpFile.renameSync(dest);
      await setActive(model);
      yield 1.0;
    } catch (e) {
      // فایل tmp رو نگه دار برای resume بعدی — فقط اگه کامل نشد
      if (File(dest).existsSync()) File(dest).deleteSync();
      rethrow;
    }
  }

  static void cancelDownload() => _dlCancelled = true;

  static Future<void> deleteModel(WhisperModelDef m) async {
    final root = await _modelsRoot();
    final dir = Directory(m.dirPath(root));
    try { if (dir.existsSync()) dir.deleteSync(recursive: true); } catch (_) {}
    if ((await getActiveModel())?.id == m.id) {
      (await SharedPreferences.getInstance()).remove('whisper_active');
    }
  }

  // ── کش زیرنویس ──
  static String srtPath(String videoPath) {
    final ext = p.extension(videoPath);
    return videoPath.replaceFirst(RegExp('${RegExp.escape(ext)}\$'), '_ai.srt');
  }
  static bool subtitleExists(String videoPath) => File(srtPath(videoPath)).existsSync();

  // ── کش صدا ──
  static Future<String> _audioCache(String videoPath) async {
    final root = await _modelsRoot();
    final audioDir = Directory(p.join(root, '_audio_cache'));
    if (!audioDir.existsSync()) audioDir.createSync(recursive: true);
    // نام فایل بر اساس مسیر + اندازه ویدیو
    final stat = File(videoPath).statSync();
    final key = videoPath.hashCode.abs().toString() + '_' + stat.size.toString();
    return p.join(audioDir.path, '$key.wav');
  }

  // ── استخراج صدا ──
  static Future<String> extractAudio(String videoPath) async {
    final cachedWav = await _audioCache(videoPath);
    if (File(cachedWav).existsSync() && File(cachedWav).lengthSync() > 1000) {
      return cachedWav; // استفاده از کش
    }
    await _ch.invokeMethod('extractAudio', {'input': videoPath, 'output': cachedWav});
    return cachedWav;
  }

  static Future<void> cancelExtraction() async {
    _trCancelled = true;
    try { await _ch.invokeMethod('cancelExtraction'); } catch (_) {}
  }

  // ── Transcribe ──
  static Future<String> transcribe({
    required String videoPath,
    required String language,
    required WhisperModelDef model,
    required bool useVad,
    required void Function(String, double) onStatus,
  }) async {
    _trCancelled = false;

    final root = await _modelsRoot();
    final mPath = model.filePath(root);

    if (!File(mPath).existsSync()) {
      throw Exception('مدل ${model.name} پیدا نشد\nدوباره دانلود کنید');
    }

    // ۱. استخراج صدا (با کش)
    onStatus('استخراج صدا...', 0.05);
    final wav = await extractAudio(videoPath);
    if (_trCancelled) throw Exception('لغو شد');
    if (!File(wav).existsSync() || File(wav).lengthSync() == 0) {
      throw Exception('استخراج صدا ناموفق');
    }

    // ۲. Transcribe
    onStatus('تبدیل گفتار به متن (${model.name})...', 0.3);
    final whisper = Whisper(model: model.base, modelDir: model.dirPath(root));
    final result = await whisper.transcribe(
      transcribeRequest: TranscribeRequest(
        audio: wav,
        language: language,
        isTranslate: false,
        threads: 4,
        isNoTimestamps: false,
        vadMode: useVad ? WhisperVadMode.enabled : WhisperVadMode.disabled,
      ),
    );
    if (_trCancelled) throw Exception('لغو شد');

    // ۳. SRT
    onStatus('ساخت فایل SRT...', 0.9);
    final segs = result.segments;
    String srt;
    if (segs != null && segs.isNotEmpty) {
      srt = _segsToSrt(segs);
    } else {
      srt = _textToSrt(result.text);
    }

    final out = srtPath(videoPath);
    File(out).writeAsStringSync(srt, encoding: utf8);

    onStatus('✓ ذخیره شد', 1.0);
    return out;
  }

  // ══════════════════════════════════════════════════════════
  //  ✨ بهبود زیرنویس — کاملاً آفلاین
  // ══════════════════════════════════════════════════════════
  static Future<String> improveSrt(String srtPath) async {
    final content = File(srtPath).readAsStringSync();
    final segs = _parseSrt(content);
    if (segs.isEmpty) return srtPath;

    var improved = segs.toList();
    improved = _removeRepetitions(improved);
    improved = _fixTiming(improved);
    improved = _fixPunctuation(improved);
    improved = _fixHalfSpaces(improved);

    final out = srtPath.replaceFirst(RegExp(r'_ai\.srt$'), '_ai_improved.srt');
    File(out).writeAsStringSync(_segsToSrtRaw(improved), encoding: utf8);
    return out;
  }

  // ── تبدیل‌کننده‌ها ──
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
    return '${d.inHours.toString().padLeft(2,'0')}:'
      '${(d.inMinutes%60).toString().padLeft(2,'0')}:'
      '${(d.inSeconds%60).toString().padLeft(2,'0')},'
      '${(d.inMilliseconds%1000).toString().padLeft(3,'0')}';
  }

  // ── Parser SRT ──
  static List<_Seg> _parseSrt(String content) {
    final segs = <_Seg>[];
    final blocks = content.trim().split(RegExp(r'\n\s*\n'));
    for (final block in blocks) {
      final lines = block.trim().split('\n');
      if (lines.length < 3) continue;
      final times = lines[1].split(' --> ');
      if (times.length < 2) continue;
      try {
        final from = _parseDur(times[0].trim());
        final to   = _parseDur(times[1].trim());
        final text = lines.sublist(2).join(' ').trim();
        segs.add(_Seg(from, to, text));
      } catch (_) {}
    }
    return segs;
  }
  static Duration _parseDur(String s) {
    final p = s.replaceAll(',', '.').split(RegExp(r'[:\.]'));
    if (p.length < 4) return Duration.zero;
    return Duration(hours:int.parse(p[0]), minutes:int.parse(p[1]),
      seconds:int.parse(p[2]), milliseconds:int.parse(p[3]));
  }
  static String _segsToSrtRaw(List<_Seg> segs) {
    final b = StringBuffer();
    for (int i = 0; i < segs.length; i++) {
      b.writeln('${i+1}');
      b.writeln('${_d(segs[i].from)} --> ${_d(segs[i].to)}');
      b.writeln(segs[i].text); b.writeln();
    }
    return b.toString();
  }

  // ── الگوریتم‌های بهبود ──
  static List<_Seg> _removeRepetitions(List<_Seg> s) {
    final r = <_Seg>[];
    for (int i = 0; i < s.length; i++) {
      final t = s[i].text.trim();
      if (i > 0 && t == r.last.text.trim()) continue;
      // تکرار whisper با کلمه قبلی
      if (i > 0 && t.split(' ').length < 4 && r.last.text.trim().endsWith(t)) continue;
      r.add(s[i]);
    }
    return r;
  }

  static List<_Seg> _fixTiming(List<_Seg> s) {
    final r = <_Seg>[];
    for (int i = 0; i < s.length; i++) {
      var seg = s[i];
      // حداقل ۸۰۰ms
      final dur = seg.to.inMilliseconds - seg.from.inMilliseconds;
      if (dur < 800) seg = _Seg(seg.from, seg.from + const Duration(milliseconds:800), seg.text);
      // فاصله بین زیرنویس‌ها: max 2.5s
      if (r.isNotEmpty) {
        final gap = seg.from.inMilliseconds - r.last.to.inMilliseconds;
        if (gap < 0) seg = _Seg(r.last.to + const Duration(milliseconds:50), seg.to, seg.text);
      }
      r.add(seg);
    }
    return r;
  }

  static List<_Seg> _fixPunctuation(List<_Seg> s) => s.map((seg) {
    var t = seg.text.trim();
    // اگه سوالی هست ؟ اضافه کن
    if (!t.endsWith('؟') && !t.endsWith('?') && !t.endsWith('.') &&
        !t.endsWith('!') && !t.endsWith('،')) {
      final lc = t.toLowerCase();
      final isQ = lc.startsWith('آیا') || lc.startsWith('چرا') ||
          lc.startsWith('چه ') || lc.startsWith('کی ') ||
          lc.startsWith('کجا') || lc.startsWith('چطور') ||
          lc.startsWith('why ') || lc.startsWith('what ') ||
          lc.startsWith('how ') || lc.startsWith('when ') ||
          lc.startsWith('where ') || lc.startsWith('who ');
      t = isQ ? '$t؟' : '$t.';
    }
    return _Seg(seg.from, seg.to, t);
  }).toList();

  static List<_Seg> _fixHalfSpaces(List<_Seg> s) => s.map((seg) {
    var t = seg.text;
    // می + فعل
    t = t.replaceAllMapped(
      RegExp(r'می ([^\s]{2,})'),
      (m) => 'می‌${m[1]}',
    );
    // ها + ی/را
    t = t.replaceAllMapped(
      RegExp(r'(\S+) ها(ی|یی|را|ی را|)'),
      (m) => '${m[1]}‌ها${m[2]}',
    );
    // تر / ترین
    t = t.replaceAllMapped(RegExp(r'(\S+) (تر|ترین)(\s|\.|,|؟|!)'), (m) => '${m[1]}‌${m[2]}${m[3]}');
    return _Seg(seg.from, seg.to, t);
  }).toList();
}

class _Seg {
  final Duration from, to;
  final String text;
  const _Seg(this.from, this.to, this.text);
}

