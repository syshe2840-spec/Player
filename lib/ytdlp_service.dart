import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:direct_link/direct_link.dart';

/// سرویس پخش آنلاین
/// YouTube → youtube_explode_dart
/// بقیه (Instagram, TikTok, Twitter, Facebook...) → direct_link package
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
  static Future<String> getStreamUrl(String url) async {
    if (_isYouTubeUrl(url)) {
      return _getYouTubeStreamUrl(url);
    }
    return _getDirectLink(url);
  }

  /// direct_link — Instagram, TikTok, Twitter, Facebook, Vimeo, Reddit...
  static Future<String> _getDirectLink(String url) async {
    try {
      final dl = DirectLink();
      final data = await dl.check(url);
      if (data == null || data.links == null || data.links!.isEmpty) {
        throw Exception('لینک stream یافت نشد');
      }
      // بهترین کیفیت رو برگردون
      final best = data.links!.reduce((a, b) {
        final aQ = int.tryParse(a.quality?.replaceAll(RegExp(r'[^0-9]'), '') ?? '0') ?? 0;
        final bQ = int.tryParse(b.quality?.replaceAll(RegExp(r'[^0-9]'), '') ?? '0') ?? 0;
        return aQ >= bQ ? a : b;
      });
      if (best.link == null || best.link!.isEmpty) throw Exception('لینک خالی');
      return best.link!;
    } catch (e) {
      throw Exception('پخش ناموفق: $e');
    }
  }

  static bool _isYouTubeUrl(String url) =>
    url.contains('youtube.com') || url.contains('youtu.be');

  static Future<String> _getYouTubeStreamUrl(String url) async {
    // اول youtube_explode_dart
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
    } catch (_) {}

    // fallback به yt-dlp اگه نصب باشه
    if (await isInstalled()) {
      try {
        final streamUrl = await _ch.invokeMethod<String>('ytdlpGetUrl', {'url': url});
        if (streamUrl != null && streamUrl.isNotEmpty) return streamUrl;
      } catch (_) {}
    }

    throw Exception('ویدیو در دسترس نیست یا محدود شده.\nلطفاً از مرورگر باز کنید.');
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

  static bool isSupportedUrl(String url) {
    if (!url.startsWith('http')) return false;
    final directPlay = ['.mp4','.mkv','.avi','.m3u8','.mpd','.ts'];
    if (directPlay.any((e) => url.contains(e))) return false;
    final supported = [
      'youtube.com','youtu.be', // youtube_explode_dart
      'instagram.com','twitter.com','x.com','tiktok.com',
      'vimeo.com','twitch.tv','reddit.com','facebook.com',
      'soundcloud.com','bilibili.com','dailymotion.com',
    ];
    return supported.any((s) => url.contains(s));
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

