import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'opensubtitles_service.dart' show ParsedFileInfo, OpenSubtitlesService;

/// مدیریت یکپارچه مسیر ذخیره زیرنویس‌ها
/// ساختار پوشه:
///   فیلم: [parent]/Subtitles/[اسم فیلم]/
///   سریال: [parent]/Subtitles/[اسم سریال]/Season XX/Episode YY/
///   URL آنلاین: [documents]/Vezoo Subtitles/[اسم فایل]/
class SubtitleStorage {
  static const _subFolder = 'Subtitles';

  /// پوشه ریشه زیرنویس برای یه ویدیو
  static Future<String> subtitleDir(String videoPath) async {
    final isUrl = videoPath.startsWith('http://') || videoPath.startsWith('https://');
    final parsed = OpenSubtitlesService.parseFilename(videoPath);

    String base;
    if (isUrl) {
      final docs = await getApplicationDocumentsDirectory();
      base = p.join(docs.path, 'Vezoo Subtitles');
    } else {
      base = p.join(p.dirname(videoPath), _subFolder);
    }

    String dir;
    if (parsed.isSeries && parsed.season != null) {
      // سریال: [base]/[اسم]/Season XX/Episode YY
      final ep = parsed.episode;
      dir = p.join(base, _clean(parsed.title),
        'Season ${parsed.season!.toString().padLeft(2, '0')}',
        ep != null ? 'Episode ${ep.toString().padLeft(2, '0')}' : '',
      );
    } else {
      // فیلم: [base]/[اسم فیلم]
      dir = p.join(base, _clean(parsed.title.isNotEmpty
        ? parsed.title
        : p.basenameWithoutExtension(videoPath)));
    }

    await Directory(dir).create(recursive: true);
    return dir;
  }

  /// مسیر کامل فایل زیرنویس
  static Future<String> subtitlePath(
    String videoPath, {
    required String suffix, // مثلاً '_fa' یا '_os_en' یا '_live_fa'
    String ext = 'srt',
  }) async {
    final dir = await subtitleDir(videoPath);
    final base = _baseNameFor(videoPath);
    return p.join(dir, '$base$suffix.$ext');
  }

  /// اسم پایه فایل ویدیو (بدون پسوند)
  static String _baseNameFor(String videoPath) {
    if (videoPath.startsWith('http://') || videoPath.startsWith('https://')) {
      final uri = Uri.parse(videoPath);
      return p.basenameWithoutExtension(uri.pathSegments.last.isNotEmpty
        ? uri.pathSegments.last
        : 'video');
    }
    return p.basenameWithoutExtension(videoPath);
  }

  /// پاکسازی اسم برای استفاده در مسیر
  static String _clean(String s) =>
    s.replaceAll(RegExp(r'[<>:"/\\|?*]'), ' ').trim();

  // ─── متدهای کمکی برای هر نوع زیرنویس ───

  static Future<String> aiSubtitlePath(String videoPath, String langCode) =>
    subtitlePath(videoPath, suffix: '_ai_$langCode');

  static Future<String> onlineSubtitlePath(String videoPath, String langCode) =>
    subtitlePath(videoPath, suffix: '_os_$langCode');

  static Future<String> liveSubtitlePath(String videoPath, String langCode) =>
    subtitlePath(videoPath, suffix: '_live_$langCode');

  static Future<String> liveTranslatedPath(String videoPath, String targetLang) =>
    subtitlePath(videoPath, suffix: '_live_translated_$targetLang');

  static Future<String> translatedPath(String videoPath, String targetLang) =>
    subtitlePath(videoPath, suffix: '_translated_$targetLang');

  /// لیست همه زیرنویس‌های ذخیره‌شده برای یه ویدیو
  static Future<List<File>> listSubtitles(String videoPath) async {
    try {
      final dir = Directory(await subtitleDir(videoPath));
      if (!dir.existsSync()) return [];
      return dir.listSync()
        .whereType<File>()
        .where((f) => ['.srt', '.ass', '.vtt'].contains(p.extension(f.path).toLowerCase()))
        .toList()
        ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    } catch (_) { return []; }
  }
}

