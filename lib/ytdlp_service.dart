
import 'package:extractor/extractor.dart';

/// سرویس پخش آنلاین — YouTube, Instagram, TikTok, 1000+ سایت
class YtDlpService {
  static final _dl = YoutubeDLFlutter.instance;
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    try {
      final result = await _dl.initialize(enableFFmpeg: true, enableAria2c: false);
      if (result.success) {
        _initialized = true;
      } else {
        throw Exception('extractor init: success=${result.success} err=${result.errorMessage ?? "null"}');
      }
    } catch (e) {
      _initialized = false;
      rethrow;
    }
  }

  static Future<void> _ensureInit() async {
    if (!_initialized) await init();
  }

  // ── وضعیت ──
  static Future<bool> isYtDlpInstalled() async {
    try {
      await _ensureInit();
      final v = await _dl.getVersion();
      return v.youtubeDlVersion != null && v.youtubeDlVersion!.isNotEmpty;
    } catch (_) { return false; }
  }

  static Future<bool> isDenoInstalled() async => false;

  static Future<Map<String,String?>> getVersions() async {
    try {
      await _ensureInit();
      final v = await _dl.getVersion();
      return {'ytdlp': v.youtubeDlVersion, 'deno': null};
    } catch (_) { return {}; }
  }

  // ── آپدیت ──
  static Future<void> downloadYtDlp() async {
    await _ensureInit();
    await _dl.updateYoutubeDL(channel: UpdateChannel.stable);
  }

  static Future<void> downloadDeno() async {}
  static Future<void> updateYtDlp() async => downloadYtDlp();
  static Future<void> updateDeno() async {}
  static Future<void> deleteYtDlp() async {}
  static Future<void> deleteDeno() async {}
  static Future<List<String>> backup() async => [];
  static Future<void> importBin(String path, String type) async {}
  static Stream<Map> downloadProgress() => const Stream.empty();

  // ── stream URL ──
  static Future<String> getStreamUrl(String url) async {
    await _ensureInit();
    final info = await _dl.getVideoInfo(url);

    final formats = info.formats;
    if (formats != null && formats.isNotEmpty) {
      // اول: video+audio در یه stream (mp4/webm)
      for (final f in formats.reversed) {
        final fu = f?.url;
        if (fu == null || !fu.startsWith('http')) continue;
        final ext = f?.ext?.toLowerCase() ?? '';
        final vcodec = f?.vcodec ?? '';
        final acodec = f?.acodec ?? '';
        if (vcodec != 'none' && acodec != 'none' &&
            (ext == 'mp4' || ext == 'webm' || ext == 'm4v')) {
          return fu;
        }
      }
      // fallback: هر url با video
      for (final f in formats.reversed) {
        final fu = f?.url;
        if (fu != null && fu.startsWith('http') && (f?.vcodec ?? '') != 'none') {
          return fu;
        }
      }
      // آخرین fallback: هر url
      for (final f in formats.reversed) {
        final fu = f?.url;
        if (fu != null && fu.startsWith('http')) return fu;
      }
    }

    // اگه formats نبود، از url مستقیم info استفاده کن
    if (info.url != null && info.url!.startsWith('http')) return info.url!;
    throw Exception('No stream URL found');
  }
}
