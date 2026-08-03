import 'dart:io';
import 'package:path/path.dart' as p;
import 'opensubtitles_service.dart' show OpenSubtitlesService, ParsedFileInfo;

/// مدیریت مسیر زیرنویس با ساختار پوشه‌بندی هوشمند
/// فیلم:   [dir]/[اسم فیلم]/subtitle.srt
/// سریال:  [dir]/[اسم سریال]/Season XX/EXX/subtitle.srt
/// ناشناس: [dir]/Other/subtitle.srt
/// URL:    /storage/emulated/0/Download/Vezoo Subtitles/[همان ساختار]
class SubtitleStorage {

  static bool _isUrl(String path) =>
    path.startsWith('http://') || path.startsWith('https://');

  /// ریشه پوشه‌بندی (پوشه ویدیو یا Download برای URL)
  static String _baseDir(String videoPath) {
    if (_isUrl(videoPath)) return _onlineSubDir;
    return p.dirname(videoPath);
  }

  // پوشه زیرنویس آنلاین — در Downloads/Vezoo/Subtitles
  static const _onlineSubDir = '/storage/emulated/0/Download/Vezoo/Subtitles';

  static String _baseName(String videoPath) {
    if (_isUrl(videoPath)) {
      final uri = Uri.parse(videoPath);
      // برای یوتوب و URL های بلند — از timestamp استفاده کن
      final seg = uri.pathSegments.lastWhere((s) => s.isNotEmpty, orElse: () => '');
      if (seg.isEmpty || seg == 'videoplayback' || seg.length > 60) {
        return 'video_${DateTime.now().millisecondsSinceEpoch}';
      }
      return p.basenameWithoutExtension(seg);
    }
    final base = p.basenameWithoutExtension(videoPath);
    // sanitize نام فایل
    return base.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_').substring(0, base.length.clamp(0, 80));
  }

  static String _clean(String s) =>
    s.replaceAll(RegExp(r'[<>:"/\\|?*]'), ' ').trim().replaceAll(RegExp(r'\s+'), ' ');

  /// ساخت مسیر پوشه بر اساس اطلاعات فایل
  static String _buildSubDir(String baseDir, ParsedFileInfo info, String originalName) {
    if (info.isSeries && info.title.isNotEmpty) {
      // سریال با اسم شناخته‌شده
      final s = info.season;
      final e = info.episode;
      if (s != null && e != null) {
        return p.join(baseDir, _clean(info.title),
          'Season ${s.toString().padLeft(2,'0')}',
          'E${e.toString().padLeft(2,'0')}');
      } else if (s != null) {
        return p.join(baseDir, _clean(info.title),
          'Season ${s.toString().padLeft(2,'0')}');
      }
      return p.join(baseDir, _clean(info.title));
    } else if (!info.isSeries && info.title.isNotEmpty) {
      // فیلم با اسم شناخته‌شده
      final year = info.year != null ? ' (${info.year})' : '';
      return p.join(baseDir, _clean('${info.title}$year'));
    } else {
      // نتونست تشخیص بده → Other
      return p.join(baseDir, 'Other');
    }
  }

  /// پوشه کامل برای ذخیره زیرنویس
  static Future<String> subtitleDir(String videoPath) async {
    final baseDir = _baseDir(videoPath);
    final name = _baseName(videoPath);
    ParsedFileInfo info;
    try {
      info = OpenSubtitlesService.parseFilename(name);
    } catch (_) {
      info = ParsedFileInfo(title: '', isSeries: false);
    }
    final dir = _buildSubDir(baseDir, info, name);
    try { await Directory(dir).create(recursive: true); } catch(_) {}
    return dir;
  }

  /// مسیر کامل فایل زیرنویس
  static Future<String> subtitlePath(String videoPath, {required String suffix, String ext = 'srt'}) async {
    final dir = await subtitleDir(videoPath);
    return p.join(dir, '${_baseName(videoPath)}$suffix.$ext');
  }

  static Future<String> aiSubtitlePath(String vp, String lang) => subtitlePath(vp, suffix: '_ai_$lang');
  static Future<String> onlineSubtitlePath(String vp, String lang) => subtitlePath(vp, suffix: '_os_$lang');
  static Future<String> liveSubtitlePath(String vp, String lang) => subtitlePath(vp, suffix: '_live_$lang');
  static Future<String> liveTranslatedPath(String vp, String lang) => subtitlePath(vp, suffix: '_live_translated_$lang');
  static Future<String> translatedPath(String vp, String lang) => subtitlePath(vp, suffix: '_translated_$lang');

  /// جستجوی زیرنویس در هر دو مکان (قدیمی کنار فایل + جدید در پوشه)
  static Future<List<File>> listSubtitles(String videoPath) async {
    final found = <File>{};
    final base = _baseName(videoPath);
    final exts = ['.srt','.ass','.vtt'];

    // مکان قدیمی (کنار فایل)
    try {
      final oldDir = Directory(p.dirname(videoPath));
      if (oldDir.existsSync()) {
        for (final f in oldDir.listSync().whereType<File>()) {
          final n = p.basename(f.path);
          if (n.startsWith(base) && exts.contains(p.extension(n).toLowerCase())) found.add(f);
        }
      }
    } catch (_) {}

    // مکان جدید (پوشه‌بندی)
    try {
      final newDir = Directory(await subtitleDir(videoPath));
      if (newDir.existsSync()) {
        for (final f in newDir.listSync().whereType<File>()) {
          if (exts.contains(p.extension(f.path).toLowerCase())) found.add(f);
        }
      }
    } catch (_) {}

    return found.toList()..sort((a,b) => b.statSync().modified.compareTo(a.statSync().modified));
  }
}
