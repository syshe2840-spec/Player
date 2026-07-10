
import 'package:extractor/extractor.dart';

/// سرویس پخش آنلاین — YouTube, Instagram, TikTok, 1000+ سایت
/// از extractor package استفاده میکنه که yt-dlp رو با Python داخلی اجرا میکنه
class YtDlpService {
  static final _dl = YoutubeDLFlutter.instance;
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    await _dl.initialize(enableFFmpeg: false, enableAria2c: false);
    _initialized = true;
  }

  // ── وضعیت ──
  static Future<bool> isYtDlpInstalled() async {
    try {
      await init();
      final v = await _dl.getVersion();
      return v.youtubeDlVersion != null && v.youtubeDlVersion!.isNotEmpty;
    } catch (_) { return false; }
  }

  static Future<bool> isDenoInstalled() async => false; // deno از طریق extractor نیاز نیست

  static Future<Map<String,String?>> getVersions() async {
    try {
      await init();
      final v = await _dl.getVersion();
      return {'ytdlp': v.youtubeDlVersion, 'deno': null};
    } catch (_) { return {}; }
  }

  // ── آپدیت ──
  static Future<void> downloadYtDlp() async {
    await init();
    await _dl.updateYoutubeDL();
  }

  static Future<void> downloadDeno() async {} // نیازی نیست

  static Future<void> updateYtDlp() async => downloadYtDlp();
  static Future<void> updateDeno() async {}

  // ── حذف (extractor خودش manage میکنه) ──
  static Future<void> deleteYtDlp() async {}
  static Future<void> deleteDeno() async {}

  // ── بکاپ ──
  static Future<List<String>> backup() async => [];

  // ── ایمپورت ──
  static Future<void> importBin(String path, String type) async {}

  // ── progress stream ──
  static Stream<Map> downloadProgress() => const Stream.empty();

  // ── stream URL — مهم‌ترین تابع ──
  static Future<String> getStreamUrl(String url) async {
    await init();
    final info = await _dl.getVideoInfo(url);
    // پیدا کردن بهترین format قابل پخش (mp4 یا stream url)
    if (info.formats != null && info.formats!.isNotEmpty) {
      // اول دنبال url مستقیم بگرد
      for (final f in info.formats!.reversed) {
        final fu = f['url'] as String?;
        if (fu != null && fu.startsWith('http')) {
          final ext = (f['ext'] as String? ?? '').toLowerCase();
          final vcodec = (f['vcodec'] as String? ?? '');
          // ترجیح: video+audio در یه stream
          if (vcodec != 'none' && (ext == 'mp4' || ext == 'm4v' || ext == 'webm')) {
            return fu;
          }
        }
      }
      // fallback: هر url که داریم
      for (final f in info.formats!.reversed) {
        final fu = f['url'] as String?;
        if (fu != null && fu.startsWith('http')) return fu;
      }
    }
    throw Exception('No stream URL found for this video');
  }
}
