import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whisper_ggml_plus/whisper_ggml_plus.dart';
import 'subtitle_storage.dart';
import 'l10n.dart';

// ══════════════════════════════════════════════════════════
//  تعریف مدل‌ها
// ══════════════════════════════════════════════════════════
class WhisperModelDef {
  final String id;
  final WhisperModel base;
  final String name;
  final String variant;
  final int sizeMb;
  final int speedStars;
  final int accStars;
  final String desc;
  final String? customPath; // برای مدل‌های ایمپورتی

  WhisperModelDef({required this.id, required this.base, required this.name,
    required this.variant, required this.sizeMb,
    required this.speedStars, required this.accStars, required this.desc,
    this.customPath});

  String get url =>
    'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-$id.bin';

  String get filename => 'ggml-${base.modelName}.bin';

  String dirPath(String root) => p.join(root, id);
  String filePath(String root) => customPath ?? p.join(dirPath(root), filename);

  bool get isQuantized => variant.isNotEmpty;
  bool get isCustom => customPath != null;
}

final List<WhisperModelDef> kWhisperModels = [
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

// ── موتور تشخیص گفتار — کاربر انتخاب می‌کند، هر دو همیشه در دسترس‌اند ──
enum WhisperEngine { v1, v2 }

/// تشخیص رم گوشی و پیشنهاد بهترین مدل بر اساس آن
Future<int> _getDeviceRamMb() async {
  const ch = MethodChannel('com.vezoo.player/whisper');
  final v = await ch.invokeMethod<int>('getDeviceInfo');
  return v ?? 3072; // پیش‌فرض محافظه‌کارانه اگر گرفتن RAM ممکن نبود
}

/// پیشنهاد مدل بر اساس رم گوشی (مگابایت)
WhisperModelDef _recommendModelByRam(int ramMb) {
  if (ramMb < 2500) return kWhisperModels.firstWhere((m) => m.id == 'tiny-q5_1');
  if (ramMb < 4000) return kWhisperModels.firstWhere((m) => m.id == 'base-q5_1');
  if (ramMb < 6000) return kWhisperModels.firstWhere((m) => m.id == 'small-q5_1');
  if (ramMb < 8000) return kWhisperModels.firstWhere((m) => m.id == 'medium-q5_0');
  return kWhisperModels.firstWhere((m) => m.id == 'large-v3-turbo-q5_0');
}

const kLanguages = {
  'auto':'auto',
  'fa':'فارسی','en':'English','ar':'عربی','tr':'ترکی','fr':'فرانسه',
  'de':'آلمانی','es':'اسپانیایی','zh':'چینی','ja':'ژاپنی','ru':'روسی','ko':'کره‌ای',
};

/// سطح پشتیبانی هر زبان در whisper (بر اساس داده‌های منتشرشده OpenAI)
/// 2=بهترین (انگلیسی) 1=خوب 0=متوسط (زبان‌های با منابع آموزشی کمتر)
const _kLangSupport = {
  'en':2, 'es':1,'fr':1,'de':1,'ru':1,'ja':1,'ko':1,'zh':1,'auto':1,
  'fa':0,'ar':0,'tr':0,
};

/// تخمین کیفیت/دقت بر اساس مدل انتخابی + زبان — فقط یک راهنمای کلی است
String estimateAccuracy(WhisperModelDef model, String lang) {
  final langScore = _kLangSupport[lang] ?? 0;
  final score = model.accStars + langScore - 1; // ترکیب امتیاز مدل و زبان
  if (score >= 6) return 'excellent';
  if (score >= 5) return 'good';
  if (score >= 3) return 'medium';
  return 'weak — use bigger model';
}

// ══════════════════════════════════════════════════════════
//  سرویس اصلی
// ══════════════════════════════════════════════════════════
class WhisperService {
  static final _ch = const MethodChannel('com.vezoo.player/whisper');
  static bool _dlCancelled = false;
  static bool _trCancelled = false;

  // ── پوشه‌ها ──
  static Future<String> _modelsRoot() async {
    // مسیر رو مستقیم از Kotlin بگیر — مطمئن‌ترین روش
    try {
      final path = await const MethodChannel('com.vezoo.player/whisper')
        .invokeMethod<String>('getModelsDir');
      if (path != null && path.isNotEmpty) return path;
    } catch (_) {}
    // fallback به path_provider
    return p.join((await getApplicationSupportDirectory()).path, 'whisper_models');
  }

  /// مسیر عمومی برای استفاده خارج از class
  static Future<String> getModelsRoot() => _modelsRoot();

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

  /// همه مدل‌های دانلودشده + ایمپورتی (با نام خوانا)
  static Future<List<WhisperModelDef>> allDownloadedModels() async {
    final known = await downloadedModels();
    final root = await _modelsRoot();

    // همه مسیرهای احتمالی برای مدل‌های ایمپورتی
    final searchDirs = <String>{root};
    try {
      final docDir = (await getApplicationDocumentsDirectory()).path;
      searchDirs.add(p.join(docDir, 'whisper_models'));
    } catch (_) {}

    for (final rootPath in searchDirs) {
      final dir = Directory(rootPath);
      if (!dir.existsSync()) continue;
      // اسکن همه .bin در root (نه زیرپوشه‌ها که مدل‌های standard هستن)
      for (final file in dir.listSync().whereType<File>()) {
        final fname = p.basename(file.path);
        if (!fname.endsWith('.bin')) continue;
        final id = 'custom_${p.basenameWithoutExtension(fname)}';
        // اگه قبلاً اضافه شده skip کن
        if (known.any((m) => m.id == id || m.customPath == file.path)) continue;
        known.add(WhisperModelDef(
          id: id,
          base: WhisperModel.base,
          name: _fileToReadableName(fname),
          variant: 'custom',
          sizeMb: (file.lengthSync() / (1024 * 1024)).round(),
          speedStars: 3, accStars: 4,
          desc: 'import • \$fname',
          customPath: file.path,
        ));
      }
    }
    return known;
  }

  static String _fileToReadableName(String filename) {
    // ggml-base-q5_1.bin → Base Q5
    // ggml-large-v3-turbo.bin → Large V3 Turbo
    var name = filename
      .replaceAll('ggml-', '')
      .replaceAll('.bin', '')
      .replaceAll('-', ' ')
      .replaceAll('_', '.')
      .split(' ')
      .map((w) => w.isNotEmpty ? w[0].toUpperCase() + w.substring(1) : w)
      .join(' ');
    return name;
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

      if (_dlCancelled) throw Exception(L.cancelled);

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
    if (m.isCustom) {
      // مدل ایمپورتی — فقط فایل .bin حذف شه
      try {
        final file = File(m.customPath!);
        if (file.existsSync()) file.deleteSync();
      } catch (_) {}
    } else {
      // مدل standard — پوشه حذف شه
      final dir = Directory(m.dirPath(root));
      try { if (dir.existsSync()) dir.deleteSync(recursive: true); } catch (_) {}
    }
    if ((await getActiveModel())?.id == m.id) {
      (await SharedPreferences.getInstance()).remove('whisper_active');
    }
  }

  // ── کش زیرنویس — بر اساس زبان ──
  /// مسیر فایل SRT (async — از SubtitleStorage استفاده می‌کند)
  static Future<String> srtPathAsync(String videoPath, String language) =>
    SubtitleStorage.aiSubtitlePath(videoPath, language);

  /// مسیر همزمان (fallback — فقط برای سازگاری قدیم)
  static String srtPath(String videoPath, String language) {
    final ext = p.extension(videoPath);
    final base = videoPath.replaceFirst(RegExp('${RegExp.escape(ext)}\$'), '');
    return '${base}_ai_$language.srt';
  }
  static bool subtitleExists(String videoPath, String language) =>
      File(srtPath(videoPath, language)).existsSync();

  /// لیست زبان‌هایی که زیرنویس AI برایشان ساخته شده
  static List<String> existingLanguages(String videoPath) {
    final ext = p.extension(videoPath);
    final base = p.basenameWithoutExtension(videoPath);
    final dir = Directory(p.dirname(videoPath));
    if (!dir.existsSync()) return [];
    final found = <String>[];
    final pattern = RegExp('^${RegExp.escape(base)}_ai_([a-z]{2,5})(_improved)?\\.srt\$');
    for (final f in dir.listSync()) {
      if (f is! File) continue;
      final m = pattern.firstMatch(p.basename(f.path));
      if (m != null) {
        final lang = m.group(1)!;
        if (!found.contains(lang)) found.add(lang);
      }
    }
    return found;
  }

  /// آیا نسخه بهبودیافته برای این زبان وجود دارد؟
  static bool improvedExists(String videoPath, String language) {
    final ext = p.extension(videoPath);
    final base = p.basenameWithoutExtension(videoPath);
    return File(p.join(p.dirname(videoPath), '${base}_ai_${language}_improved.srt')).existsSync();
  }
  static String improvedPath(String videoPath, String language) {
    final base = p.basenameWithoutExtension(videoPath);
    return p.join(p.dirname(videoPath), '${base}_ai_${language}_improved.srt');
  }

  /// مسیر نهایی برای استفاده — بهبودیافته در اولویت
  static String bestSrtPath(String videoPath, String language) =>
      improvedExists(videoPath, language) ? improvedPath(videoPath, language) : srtPath(videoPath, language);

  /// حذف همه زیرنویس‌های AI ساخته‌شده برای این ویدیو
  static void deleteAllSubtitles(String videoPath) {
    final base = p.basenameWithoutExtension(videoPath);
    final dir = Directory(p.dirname(videoPath));
    if (!dir.existsSync()) return;
    final pattern = RegExp('^${RegExp.escape(base)}_ai_[a-z]{2,5}(_improved)?\\.srt\$');
    for (final f in dir.listSync()) {
      if (f is File && pattern.hasMatch(p.basename(f.path))) {
        try { f.deleteSync(); } catch (_) {}
      }
    }
  }

  /// حذف یک زبان خاص (هم نسخه عادی هم بهبودیافته)
  static void deleteLanguage(String videoPath, String language) {
    try { File(srtPath(videoPath, language)).deleteSync(); } catch (_) {}
    try { File(improvedPath(videoPath, language)).deleteSync(); } catch (_) {}
  }

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

  /// مسیر پوشه کش صدا
  static Future<String> _audioCacheDir() async => p.join(await _modelsRoot(), '_audio_cache');

  /// حجم کل کش صدا (مگابایت)
  static Future<double> getAudioCacheSizeMb() async {
    final dir = Directory(await _audioCacheDir());
    if (!dir.existsSync()) return 0;
    int total = 0;
    for (final f in dir.listSync()) {
      if (f is File) total += f.lengthSync();
    }
    return total / 1024 / 1024;
  }

  /// تعداد فایل‌های کش‌شده
  static Future<int> getAudioCacheCount() async {
    final dir = Directory(await _audioCacheDir());
    if (!dir.existsSync()) return 0;
    return dir.listSync().whereType<File>().length;
  }

  /// پاک کردن کامل کش صدا
  static Future<void> clearAudioCache() async {
    final dir = Directory(await _audioCacheDir());
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }

  static Future<void> cancelExtraction() async {
    _trCancelled = true;

    try { await _ch.invokeMethod('cancelExtraction'); } catch (_) {}
  }

  // ── انتخاب موتور (v1 / v2) — کاربر تعیین می‌کند ──
  static Future<WhisperEngine> getActiveEngine() async {
    final s = (await SharedPreferences.getInstance()).getString('whisper_engine');
    return s == 'v2' ? WhisperEngine.v2 : WhisperEngine.v1;
  }
  static Future<void> setActiveEngine(WhisperEngine e) async =>
      (await SharedPreferences.getInstance()).setString('whisper_engine', e == WhisperEngine.v2 ? 'v2' : 'v1');

  /// رم گوشی به مگابایت (برای پیشنهاد مدل مناسب)
  static Future<int> getDeviceRamMb() => _getDeviceRamMb();

  /// پیشنهاد مدل مناسب بر اساس رم گوشی
  static WhisperModelDef recommendedModel(int ramMb) => _recommendModelByRam(ramMb);

  // ── مدت زمان ویدیو (برای تخمین زمان پردازش) ──
  static Future<int> getVideoDurationMs(String videoPath) async {
    try {
      final v = await _ch.invokeMethod<int>('getVideoDuration', {'path': videoPath});
      return v ?? 0;
    } catch (_) { return 0; }
  }

  /// تخمین زمان پردازش بر اساس مدت ویدیو + مدل + موتور
  /// ضرایب تجربی‌اند، فقط یک راهنمای کلی‌اند نه عدد دقیق
  static String estimateProcessingTime(int videoDurationMs, WhisperModelDef model, WhisperEngine engine) {
    if (videoDurationMs <= 0) return 'unknown';
    final videoSec = videoDurationMs / 1000;
    // ضریب کندی نسبت به مدت واقعی صدا — هرچه مدل بزرگ‌تر، ضریب بالاتر
    final modelFactor = switch (model.speedStars) {
      5 => 0.4, 4 => 0.7, 3 => 1.2, 2 => 2.2, _ => 4.0,
    };
    final engineFactor = engine == WhisperEngine.v2 ? 0.85 : 1.0; // V2 معمولاً کمی سریع‌تر
    final estSec = (videoSec * modelFactor * engineFactor).round();
    if (estSec < 60) return 'حدود $estSec ثانیه';
    final mins = (estSec / 60).round();
    return 'حدود $mins دقیقه';
  }

  // ══════════════════════════════════════════════════════════
  //  تاریخچه AI — لیست ویدیوهایی که زیرنویس برایشان ساخته شده
  // ══════════════════════════════════════════════════════════
  static Future<List<String>> getHistoryVideos() async {
    final list = (await SharedPreferences.getInstance()).getStringList('ai_history_videos') ?? [];
    // فقط فایل‌هایی که هنوز وجود دارند و واقعاً زیرنویس دارند
    return list.where((p) => File(p).existsSync() && existingLanguages(p).isNotEmpty).toList();
  }

  static Future<void> _addToHistory(String videoPath) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('ai_history_videos') ?? [];
    if (!list.contains(videoPath)) {
      list.insert(0, videoPath);
      await prefs.setStringList('ai_history_videos', list);
    }
  }

  static Future<void> removeFromHistory(String videoPath) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('ai_history_videos') ?? [];
    list.remove(videoPath);
    await prefs.setStringList('ai_history_videos', list);
  }

  // ══════════════════════════════════════════════════════════
  //  Notification پیشرفت — برای دیدن وضعیت حتی اگر کاربر از اپ خارج شود
  //  توجه: بدون foreground service واقعی، اندروید همچنان می‌تواند در شرایط
  //  کمبود حافظه پردازش را متوقف کند — این فقط نمایش وضعیت است، نه تضمین کامل.
  // ══════════════════════════════════════════════════════════
  static bool _cancelHandlerAttached = false;
  /// callback اضافی هنگام دریافت cancel از notification — برای ترجمه آنلاین
  static void Function()? onExternalCancel;

  static void _ensureCancelHandler() {
    if (_cancelHandlerAttached) return;
    _cancelHandlerAttached = true;
    const _cancelCh = EventChannel('com.vezoo.player/ai_cancel');
    _cancelCh.receiveBroadcastStream().listen((_) async {
      await cancelExtraction();
      onExternalCancel?.call(); // ترجمه آنلاین رو هم لغو کن
    }, onError: (_) {});
  }

  static Future<void> showProgressNotification(String title) async {
    _ensureCancelHandler();
    try { await _ch.invokeMethod('showAiProgress', {'title': title}); } catch (_) {}
  }
  static Future<void> updateProgressNotification(String status, double progress) async {
    try { await _ch.invokeMethod('updateAiProgress', {'status': status, 'percent': (progress*100).round()}); } catch (_) {}
  }
  static Future<void> hideProgressNotification() async {
    try { await _ch.invokeMethod('hideAiProgress'); } catch (_) {}
  }

  // ── Transcribe — مسیریابی بر اساس engine انتخابی ──
  static Future<String> transcribe({
    required String videoPath,
    required String language,
    required WhisperModelDef model,
    required bool useVad,
    required WhisperEngine engine,
    bool isTranslate = false,
    required void Function(String, double) onStatus,
  }) async {
    return engine == WhisperEngine.v2
      ? _transcribeV2(videoPath: videoPath, language: language, model: model, isTranslate: isTranslate, onStatus: onStatus)
      : _transcribeV1(videoPath: videoPath, language: language, model: model, useVad: useVad, isTranslate: isTranslate, onStatus: onStatus);
  }

  // ── V1: whisper_ggml_plus (پایدار، پکیج Flutter) ──
  static Future<String> _transcribeV1({
    required String videoPath,
    required String language,
    required WhisperModelDef model,
    required bool useVad,
    bool isTranslate = false,
    required void Function(String, double) onStatus,
  }) async {
    _trCancelled = false;

    final root = await _modelsRoot();
    final mPath = model.filePath(root);

    if (!File(mPath).existsSync()) {
      throw Exception('\${model.name}: \${L.fileNotFound}');
    }

    final sw = Stopwatch()..start();
    void logStage(String stage) {
      debugPrint('[Whisper V1] $stage: ${sw.elapsedMilliseconds}ms');
      sw.reset();
    }

    // ۱. استخراج صدا (با کش)
    onStatus(L.processing, 0.05);
    final wav = await extractAudio(videoPath);
    logStage('Extract Audio');
    if (_trCancelled) throw Exception(L.cancelled);
    if (!File(wav).existsSync() || File(wav).lengthSync() == 0) {
      throw Exception('Audio extraction failed');
    }

    // ۲. Transcribe
    onStatus('V1: \${model.name}', 0.3);
    final whisper = Whisper(model: model.base);
    final result = await whisper.transcribe(
      transcribeRequest: TranscribeRequest(
        audio: wav,
        language: language,
        isTranslate: isTranslate,
        threads: Platform.numberOfProcessors.clamp(2, 8),
        isNoTimestamps: false,
        vadMode: useVad ? WhisperVadMode.enabled : WhisperVadMode.disabled,
      ),
      modelPath: mPath,
    );
    logStage('Transcribe (load+infer)');
    if (_trCancelled) throw Exception(L.cancelled);

    // ۳. SRT
    onStatus('Building SRT...', 0.9);
    final segs = result.segments;
    String srt;
    if (segs != null && segs.isNotEmpty) {
      srt = _segsToSrt(segs);
    } else {
      srt = _textToSrt(result.text, _wavDurationSeconds(wav));
    }

    final out = await srtPathAsync(videoPath, language);
    File(out).writeAsStringSync(srt, encoding: utf8);
    await _addToHistory(videoPath);

    onStatus(L.saved, 1.0);
    return out;
  }

  // ── V2: whisper.cpp بومی (سریع‌تر، آزمایشی) ──
  static Future<String> _transcribeV2({
    required String videoPath,
    required String language,
    required WhisperModelDef model,
    bool isTranslate = false,
    required void Function(String, double) onStatus,
  }) async {
    _trCancelled = false;

    final root = await _modelsRoot();
    final mPath = model.filePath(root);
    if (!File(mPath).existsSync()) {
      throw Exception('\${model.name}: \${L.fileNotFound}');
    }

    final sw = Stopwatch()..start();
    void logStage(String stage) {
      debugPrint('[Whisper V2] $stage: ${sw.elapsedMilliseconds}ms');
      sw.reset();
    }

    // ۱. استخراج صدا (همون مسیر/کش مشترک با V1)
    onStatus(L.processing, 0.05);
    final wav = await extractAudio(videoPath);
    logStage('Extract Audio');
    if (_trCancelled) throw Exception(L.cancelled);
    if (!File(wav).existsSync() || File(wav).lengthSync() == 0) {
      throw Exception('Audio extraction failed');
    }

    int? ctx;
    try {
      // ۲. بارگذاری مدل در whisper.cpp بومی
      onStatus('V2 load: \${model.name}', 0.25);
      final ctxResult = await _ch.invokeMethod<dynamic>('v2InitContext', {'modelPath': mPath});
      logStage('Load Model');
      if (ctxResult == null) throw Exception('Model loading failed');
      ctx = (ctxResult as num).toInt();
      if (ctx == 0) throw Exception('Model loading failed (ctx=0)');
      if (_trCancelled) throw Exception(L.cancelled);

      // ۳. Transcribe بومی
      onStatus('V2: transcribing...', 0.4);
      final threads = Platform.numberOfProcessors.clamp(2, 8);
      final raw = await _ch.invokeMethod<String>('v2Transcribe', {
        'ctx': ctx, 'wavPath': wav, 'lang': language, 'threads': threads, 'translate': isTranslate,
      });
      logStage('Transcribe (infer)');
      if (_trCancelled) throw Exception(L.cancelled);
      if (raw == null || raw.trim().isEmpty) throw Exception('Empty V2 output');

      // ۴. تبدیل خروجی خام (start_ms|end_ms|text) به SRT
      onStatus('Building SRT...', 0.9);
      final srt = _v2RawToSrt(raw);

      final out = await srtPathAsync(videoPath, language);
      File(out).writeAsStringSync(srt, encoding: utf8);
      await _addToHistory(videoPath);

      onStatus(L.saved, 1.0);
      return out;
    } finally {
      if (ctx != null && ctx != 0) {
        try { await _ch.invokeMethod('v2FreeContext', {'ctx': ctx}); } catch (_) {}
      }
    }
  }

  /// تبدیل خروجی خام موتور V2 (هر خط: start_ms|end_ms|text) به فرمت SRT
  static String _v2RawToSrt(String raw) {
    final lines = raw.split('\n').where((l) => l.trim().isNotEmpty).toList();
    final b = StringBuffer();
    int idx = 1;
    for (final line in lines) {
      final parts = line.split('|');
      if (parts.length < 3) continue;
      final fromMs = int.tryParse(parts[0]) ?? 0;
      final toMs = int.tryParse(parts[1]) ?? (fromMs + 2000);
      final text = parts.sublist(2).join('|').trim();
      if (text.isEmpty) continue;
      b.writeln('$idx');
      b.writeln('${_d(Duration(milliseconds: fromMs))} --> ${_d(Duration(milliseconds: toMs))}');
      b.writeln(text);
      b.writeln();
      idx++;
    }
    return b.toString();
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

    final out = srtPath.replaceFirst(RegExp(r'(_ai_[a-z]{2,5})\.srt$'), r'$1_improved.srt');
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
  /// مدت واقعی فایل WAV (16kHz mono 16-bit) بر اساس حجم فایل — برای زمان‌بندی دقیق fallback
  static double _wavDurationSeconds(String wavPath) {
    try {
      final bytes = File(wavPath).lengthSync();
      final dataBytes = (bytes - 44).clamp(0, bytes); // حذف هدر ۴۴ بایتی WAV
      return dataBytes / 2 / 16000; // 16-bit mono @ 16kHz
    } catch (_) { return 0; }
  }

  static String _textToSrt(String text, [double totalSeconds = 0]) {
    final parts = text.split(RegExp(r'(?<=[.!?،؟])\s+')).where((s)=>s.trim().isNotEmpty).toList();
    if (parts.isEmpty) return '';
    // اگر مدت واقعی صدا داریم، هر جمله متناسب با طول نسبی‌اش زمان می‌گیرد
    final useReal = totalSeconds > 0;
    final perPart = useReal ? totalSeconds / parts.length : 5.0;
    final b = StringBuffer();
    for (int i = 0; i < parts.length; i++) {
      final from = (i * perPart);
      final to = ((i + 1) * perPart);
      b.writeln('${i+1}');
      b.writeln('${_d(Duration(milliseconds:(from*1000).round()))} --> ${_d(Duration(milliseconds:(to*1000).round()))}');
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

// ══════════════════════════════════════════════════════════
//  ویرایشگر دستی SRT — خواندن/نوشتن عمومی
// ══════════════════════════════════════════════════════════

/// یک سطر زیرنویس — برای استفاده در ویرایشگر دستی
class SrtEntry {
  Duration from;
  Duration to;
  String text;
  SrtEntry({required this.from, required this.to, required this.text});
}

/// خواندن یک فایل SRT و برگرداندن لیست قابل‌ویرایش
List<SrtEntry> readSrtEntries(String path) {
  if (!File(path).existsSync()) return [];
  final segs = WhisperService._parseSrt(File(path).readAsStringSync());
  return segs.map((s) => SrtEntry(from: s.from, to: s.to, text: s.text)).toList();
}

/// نوشتن لیست ویرایش‌شده به فایل SRT
void writeSrtEntries(String path, List<SrtEntry> entries) {
  final b = StringBuffer();
  for (int i = 0; i < entries.length; i++) {
    final e = entries[i];
    b.writeln('${i + 1}');
    b.writeln('${_fmtSrtDur(e.from)} --> ${_fmtSrtDur(e.to)}');
    b.writeln(e.text.trim());
    b.writeln();
  }
  File(path).writeAsStringSync(b.toString(), encoding: utf8);
}

String _fmtSrtDur(Duration d) =>
    '${d.inHours.toString().padLeft(2, '0')}:'
    '${(d.inMinutes % 60).toString().padLeft(2, '0')}:'
    '${(d.inSeconds % 60).toString().padLeft(2, '0')},'
    '${(d.inMilliseconds % 1000).toString().padLeft(3, '0')}';

// ══════════════════════════════════════════════════════════

// ══════════════════════════════════════════════════════════
//  زیرنویس زنده — پردازش تکه‌تکه V2 در حین پخش
// ══════════════════════════════════════════════════════════

enum LiveBehindAction { pause, slowDown }

class LiveSubConfig {
  final int chunkMs;
  final int overlapMs;
  final String language;
  final WhisperModelDef model;
  final bool isTranslate;
  final LiveBehindAction behindAction;
  final double behindSpeed;
  final bool syncTranslate;      // همگام‌سازی ترجمه آنلاین
  final String syncTranslateLang;
  const LiveSubConfig({
    this.chunkMs = 30000,
    this.overlapMs = 5000,
    required this.language,
    required this.model,
    this.isTranslate = false,
    this.behindAction = LiveBehindAction.pause,
    this.behindSpeed = 0.75,
    this.syncTranslate = false,
    this.syncTranslateLang = 'fa',
  });
}

class LiveSubState {
  static bool cancelled = false;
  static int transcribedMs = 0;
  static int totalMs = 0;
  static int chunksDone = 0;
  static int chunksTotal = 0;
  static int chunkMs = 30000;
  static String language = '';
  static bool useOverlap = true;
  static int chunkStartMs = 0;

  // ValueNotifier — وقتی chunk عوض شد فوری UI رو notify کنه
  static final notifier = ValueNotifier<int>(0);

  static void reset(){
    cancelled=false; transcribedMs=0; totalMs=0; chunksDone=0; chunksTotal=0;
    chunkStartMs = DateTime.now().millisecondsSinceEpoch;
    notifier.value = 0;
  }

  static void notify() => notifier.value++;

  static int get chunkElapsedSec =>
    ((DateTime.now().millisecondsSinceEpoch - chunkStartMs) / 1000).round();
}

/// مسیر فایل SRT زنده (کنار فایل ویدیو ذخیره میشه)
Future<String> liveSrtPath(String videoPath, String language) =>
  SubtitleStorage.liveSubtitlePath(videoPath, language);

/// لغو زیرنویس زنده
Future<void> cancelLiveSub() async {
  LiveSubState.cancelled = true;
  await WhisperService.cancelExtraction();
  _stopLiveSubService();
}

Future<void> _startLiveSubService(String videoName) async {
  const ch = MethodChannel('com.vezoo.player/whisper');
  try {
    await ch.invokeMethod('startLiveSubService', {
      'title': L.liveSubtitle,
      'text': videoName,
    });
    // توجه: از setMethodCallHandler استفاده نمی‌کنیم چون channel رو کور می‌کنه
    // وقتی service kill شه، LiveSubState.cancelled در onDestroy از Kotlin ست میشه
  } catch (_) {}
}

Future<void> _stopLiveSubService() async {
  const ch = MethodChannel('com.vezoo.player/whisper');
  try { await ch.invokeMethod('stopLiveSubService'); } catch (_) {}
}

/// پردازش زنده — chunk به chunk، SRT روی دیسک بروز میشه
Future<String> transcribeLive({
  required String videoPath,
  required LiveSubConfig config,
  required void Function(int startMs, int totalMs, int done, int total) onChunk,
  required void Function() onSrtUpdated,
}) async {
  LiveSubState.reset();

  // شروع Foreground Service — اپ minimize شد؟ پردازش ادامه میده
  await _startLiveSubService(p.basenameWithoutExtension(videoPath));
  const ch = MethodChannel('com.vezoo.player/whisper');

  final isOnline = videoPath.startsWith('http://') || videoPath.startsWith('https://');
  // برای URL آنلاین، timeout ۸ ثانیه — اگه دیر شد با تخمین ادامه بده
  int durationMs;
  if (isOnline) {
    durationMs = await WhisperService.getVideoDurationMs(videoPath)
      .timeout(const Duration(seconds: 8), onTimeout: () => 0);
    if (durationMs <= 0) durationMs = 3600000; // فرض ۱ ساعت برای URL
  } else {
    durationMs = await WhisperService.getVideoDurationMs(videoPath);
    if (durationMs <= 0) throw Exception('Cannot detect video duration');
  }
  LiveSubState.totalMs = durationMs;
  LiveSubState.chunkMs = config.chunkMs;
  LiveSubState.language = config.language;
  LiveSubState.useOverlap = config.overlapMs > 0;

  final srtFile = await liveSrtPath(videoPath, config.language);
  File(srtFile).writeAsStringSync('', encoding: utf8);

  final mPath = await WhisperService.modelFilePath(config.model);
  if (!File(mPath).existsSync()) throw Exception('\${L.error}: model not found');

  final ctxResult = await ch.invokeMethod<dynamic>('v2InitContext', {'modelPath': mPath});
  if (ctxResult == null) throw Exception('Model loading failed');
  final ctx = (ctxResult as num).toInt();
  if (ctx == 0) throw Exception('Model loading failed (ctx=0)');

  // پوشه موقت chunk ها
  final cacheDir = Directory(p.join((await getApplicationSupportDirectory()).path, '_live_chunks'));
  if (!cacheDir.existsSync()) cacheDir.createSync(recursive: true);

  try {
    final chunksTotal = (durationMs / config.chunkMs).ceil().clamp(1, 9999);
    LiveSubState.chunksTotal = chunksTotal;
    LiveSubState.notify(); // بعد از ست شدن total، badge رو آپدیت کن
    final allSegs = <_Seg>[];

    for (int i = 0; i < chunksTotal; i++) {
      if (LiveSubState.cancelled) break;

      final chunkStart = i * config.chunkMs;
      final chunkEnd   = ((i + 1) * config.chunkMs).clamp(0, durationMs);

      // overlap: شروع از کمی قبل‌تر (نه chunk اول) تا whisper context داشته باشه
      final extractStart = (i == 0 || config.overlapMs == 0)
          ? chunkStart
          : (chunkStart - config.overlapMs).clamp(0, durationMs);
      final extractDur  = chunkEnd - extractStart;

      LiveSubState.chunksDone = i;
      LiveSubState.chunkStartMs = DateTime.now().millisecondsSinceEpoch;
      LiveSubState.notify(); // فوری UI رو آپدیت کنه
      onChunk(chunkStart, durationMs, i, chunksTotal);

      final tmpWav = p.join(cacheDir.path, '${videoPath.hashCode.abs()}_$i.wav');
      try {
        await ch.invokeMethod('extractAudioRange', {
          'input': videoPath, 'output': tmpWav,
          'startMs': extractStart, 'durationMs': extractDur,
        });
      } catch (e) {
        debugPrint('[LiveSub] chunk $i extract: $e');
        try { File(tmpWav).deleteSync(); } catch (_) {}
        continue;
      }
      if (LiveSubState.cancelled) { try { File(tmpWav).deleteSync(); } catch (_) {} break; }

      final raw = await ch.invokeMethod<String>('v2Transcribe', {
        'ctx': ctx, 'wavPath': tmpWav,
        'lang': config.language,
        'threads': Platform.numberOfProcessors.clamp(2, 8),
        'translate': config.isTranslate,
      });
      try { File(tmpWav).deleteSync(); } catch (_) {}

      if (raw != null && raw.trim().isNotEmpty) {
        for (final line in raw.split('\n').where((l) => l.contains('|'))) {
          final parts = line.split('|');
          if (parts.length < 3) continue;
          // timestamp واقعی = offset در WAV + شروع استخراج
          final fromMs = (int.tryParse(parts[0]) ?? 0) + extractStart;
          final toMs   = (int.tryParse(parts[1]) ?? 0) + extractStart;
          final text   = parts.sublist(2).join('|').trim();
          // فیلتر ناحیه overlap (قبل از chunkStart) تا تکرار نشه
          if (text.isNotEmpty && fromMs >= chunkStart) {
            allSegs.add(_Seg(Duration(milliseconds: fromMs), Duration(milliseconds: toMs), text));
          }
        }
        File(srtFile).writeAsStringSync(_liveSegsToSrt(allSegs), encoding: utf8);
        LiveSubState.transcribedMs = chunkEnd;
        LiveSubState.chunksDone = i + 1;
        LiveSubState.notify();
        onSrtUpdated();
      }
    }

    if (!LiveSubState.cancelled) LiveSubState.transcribedMs = durationMs;
    _stopLiveSubService(); // service دیگه نیازی نیست
    return srtFile;
  } finally {
    try { await ch.invokeMethod('v2FreeContext', {'ctx': ctx}); } catch (_) {}
  }
}

String _fmtSrtTime(Duration d) =>
    '${d.inHours.toString().padLeft(2,'0')}:'
    '${(d.inMinutes%60).toString().padLeft(2,'0')}:'
    '${(d.inSeconds%60).toString().padLeft(2,'0')},'
    '${(d.inMilliseconds%1000).toString().padLeft(3,'0')}';

String _liveSegsToSrt(List<_Seg> segs) {
  final b = StringBuffer();
  for (int i = 0; i < segs.length; i++) {
    b.writeln('${i + 1}');
    b.writeln('${_fmtSrtTime(segs[i].from)} --> ${_fmtSrtTime(segs[i].to)}');
    b.writeln(segs[i].text.trim());
    b.writeln();
  }
  return b.toString();
}
