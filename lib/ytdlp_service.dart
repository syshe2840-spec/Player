import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// سرویس yt-dlp — پشتیبانی از ۱۰۰۰+ سایت
/// برای YouTube از youtube_explode_dart استفاده میشه (پایدارتر)
/// برای بقیه سایت‌ها از yt-dlp binary
class YtDlpService {
  static const _ch = MethodChannel('com.vezoo.player/whisper');

  // ── وضعیت ──
  static bool? _installed;

  static void resetCache() => _installed = null;

  static Future<bool> isInstalled() async {
    _installed ??= await _ch.invokeMethod<bool>('ytdlpIsInstalled') ?? false;
    return _installed!;
  }

  static const _progressCh = EventChannel('com.vezoo.player/ytdlp_progress');

  static Stream<int> get progressStream =>
    _progressCh.receiveBroadcastStream().map((e) => (e as int?) ?? 0);

  static Future<String?> getVersion() async {
    try {
      final v = await _ch.invokeMethod<String>('ytdlpGetVersion');
      return v;
    } catch (_) { return null; }
  }

  /// دانلود binary — اولین بار (~15MB)
  static Future<void> download({void Function(String)? onStatus}) async {
    onStatus?.call('دانلود yt-dlp...');
    await _ch.invokeMethod('ytdlpDownload');
    _installed = true;
    onStatus?.call('✓ نصب شد');
  }

  /// گرفتن URL مستقیم stream از هر لینک
  /// YouTube → youtube_explode_dart (پایدار، بدون binary)
  /// بقیه → yt-dlp binary
  static Future<String> getStreamUrl(String url) async {
    if (_isYouTubeUrl(url)) {
      return _getYouTubeStreamUrl(url);
    }
    if (!await isInstalled()) {
      await download();
    }
    final streamUrl = await _ch.invokeMethod<String>('ytdlpGetUrl', {'url': url});
    if (streamUrl == null || streamUrl.isEmpty) throw Exception('لینک stream یافت نشد');
    return streamUrl;
  }

  static bool _isYouTubeUrl(String url) =>
    url.contains('youtube.com') || url.contains('youtu.be');

  static Future<String> _getYouTubeStreamUrl(String url) async {
    // اول youtube_explode_dart امتحان کن (سریع‌تر، بدون binary)
    try {
      final yt = YoutubeExplode();
      try {
        final videoId = VideoId(url);
        final manifest = await yt.videos.streamsClient.getManifest(videoId);
        final stream = manifest.muxed.sortByVideoQuality().first;
        return stream.url.toString();
      } finally {
        yt.close();
      }
    } catch (_) {
      // اگه youtube_explode fail کرد، به yt-dlp fallback بشه
      if (await isInstalled()) {
        final streamUrl = await _ch.invokeMethod<String>('ytdlpGetUrl', {'url': url});
        if (streamUrl != null && streamUrl.isNotEmpty) return streamUrl;
      }
      throw Exception('پخش YouTube ناموفق — لطفاً yt-dlp رو نصب کنید یا بعداً امتحان کنید');
    }
  }

  /// گرفتن اطلاعات ویدیو (عنوان، مدت، thumbnail)
  static Future<YtDlpVideoInfo?> getInfo(String url) async {
    if (!await isInstalled()) return null;
    try {
      final json = await _ch.invokeMethod<String>('ytdlpGetInfo', {'url': url});
      if (json == null || json.isEmpty) return null;
      final data = jsonDecode(json) as Map<String, dynamic>;
      return YtDlpVideoInfo(
        title: data['title'] ?? '',
        uploader: data['uploader'] ?? data['channel'] ?? '',
        duration: (data['duration'] as num?)?.toInt(),
        thumbnail: data['thumbnail'] ?? '',
        extractor: data['extractor'] ?? '',
      );
    } catch (_) { return null; }
  }

  /// چک کردن اینکه URL توسط این سرویس پشتیبانی میشه
  static bool isSupportedUrl(String url) {
    if (!url.startsWith('http')) return false;
    final directPlay = ['.mp4','.mkv','.avi','.m3u8','.mpd','.ts'];
    if (directPlay.any((e) => url.contains(e))) return false;
    // YouTube از youtube_explode_dart
    if (_isYouTubeUrl(url)) return true;
    // بقیه از yt-dlp
    final ytdlpSites = [
      'twitch.tv','vimeo.com','twitter.com','x.com',
      'instagram.com','tiktok.com','dailymotion.com',
      'reddit.com','facebook.com','bilibili.com',
      'nicovideo.jp','soundcloud.com',
    ];
    return ytdlpSites.any((s) => url.contains(s));
  }
}

class YtDlpVideoInfo {
  final String title;
  final String uploader;
  final int? duration;
  final String thumbnail;
  final String extractor;
  YtDlpVideoInfo({required this.title, required this.uploader,
    this.duration, required this.thumbnail, required this.extractor});
}

