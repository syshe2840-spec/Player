import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'opensubtitles_service.dart' show OpenSubtitlesService;

/// مدیریت مسیر زیرنویس
/// فایل محلی: کنار خود ویدیو (سازگار با قبل)
/// URL آنلاین: Documents/Vezoo Subtitles/[نام فایل]/
class SubtitleStorage {

  static bool _isUrl(String path) =>
    path.startsWith('http://') || path.startsWith('https://');

  /// پوشه ذخیره زیرنویس برای یه ویدیو
  static Future<String> subtitleDir(String videoPath) async {
    if (_isUrl(videoPath)) {
      // URL آنلاین: /storage/emulated/0/Download/Vezoo Subtitles/[نام]/
      const downloadPath = '/storage/emulated/0/Download';
      final uri = Uri.parse(videoPath);
      final name = p.basenameWithoutExtension(
        uri.pathSegments.lastWhere((s) => s.isNotEmpty, orElse: () => 'video'));
      final dir = p.join(downloadPath, 'Vezoo Subtitles', name);
      await Directory(dir).create(recursive: true);
      return dir;
    }
    // فایل محلی: همان پوشه ویدیو
    return p.dirname(videoPath);
  }

  static String _baseName(String videoPath) {
    if (_isUrl(videoPath)) {
      final uri = Uri.parse(videoPath);
      return p.basenameWithoutExtension(
        uri.pathSegments.lastWhere((s) => s.isNotEmpty, orElse: () => 'video'));
    }
    return p.basenameWithoutExtension(videoPath);
  }

  static Future<String> subtitlePath(String videoPath, {required String suffix, String ext = 'srt'}) async {
    final dir = await subtitleDir(videoPath);
    return p.join(dir, '${_baseName(videoPath)}$suffix.$ext');
  }

  static Future<String> aiSubtitlePath(String videoPath, String lang) =>
    subtitlePath(videoPath, suffix: '_ai_$lang');

  static Future<String> onlineSubtitlePath(String videoPath, String lang) =>
    subtitlePath(videoPath, suffix: '_os_$lang');

  static Future<String> liveSubtitlePath(String videoPath, String lang) =>
    subtitlePath(videoPath, suffix: '_live_$lang');

  static Future<String> liveTranslatedPath(String videoPath, String lang) =>
    subtitlePath(videoPath, suffix: '_live_translated_$lang');

  static Future<String> translatedPath(String videoPath, String lang) =>
    subtitlePath(videoPath, suffix: '_translated_$lang');

  /// لیست همه زیرنویس‌های این ویدیو
  static Future<List<File>> listSubtitles(String videoPath) async {
    try {
      final dir = await subtitleDir(videoPath);
      final base = _baseName(videoPath);
      return Directory(dir).listSync()
        .whereType<File>()
        .where((f) {
          final name = p.basename(f.path);
          final ext = p.extension(f.path).toLowerCase();
          return name.startsWith(base) && ['.srt','.ass','.vtt'].contains(ext);
        })
        .toList()
        ..sort((a,b) => b.statSync().modified.compareTo(a.statSync().modified));
    } catch (_) { return []; }
  }
}

