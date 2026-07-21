import 'package:flutter/services.dart';

/// سرویس yt-dlp — پشتیبانی از ۱۰۰۰+ سایت
class YtDlpService {
  static const _ch = MethodChannel('com.vezoo.player/ytdlp');

  // ۱۰۰۰+ سایت پشتیبانی شده (نمونه‌ای از مهم‌ترین‌ها)
  static const supportedSites = [
    '🎬 YouTube', '📘 Facebook', '🐦 Twitter/X', '📸 Instagram',
    '🎵 TikTok', '🎮 Twitch', '📺 Dailymotion', '🎥 Vimeo',
    '📡 Bilibili', '🎵 SoundCloud', '📰 Reddit', '🎬 Rumble',
    '📺 Odysee/LBRY', '🎮 Kick', '📺 Niconico', '🎬 Veoh',
    '🎬 9GAG', '📺 VK', '🎵 Bandcamp', '📺 Twitch Clips',
    '🎬 Metacafe', '📺 Dailymotion', '🎬 Break', '📺 IMDb',
    '+ بیش از ۱۰۰۰ سایت دیگر...',
  ];

  /// گرفتن stream URL مستقیم
  static Future<Map<String, dynamic>> getStreamUrl(String url) async {
    try {
      final result = await _ch.invokeMethod<Map>('getStreamUrl', {'url': url});
      return Map<String, dynamic>.from(result ?? {});
    } on PlatformException catch (e) {
      throw Exception('yt-dlp error: ${e.message}');
    }
  }

  /// گرفتن لیست format ها
  static Future<Map<String, dynamic>> getFormats(String url) async {
    try {
      final result = await _ch.invokeMethod<Map>('getFormats', {'url': url});
      return Map<String, dynamic>.from(result ?? {});
    } on PlatformException catch (e) {
      throw Exception('yt-dlp error: ${e.message}');
    }
  }

  /// آپدیت yt-dlp
  static Future<String> update() async {
    try {
      final result = await _ch.invokeMethod<String>('updateYtDlp');
      return result ?? 'Updated';
    } catch (e) {
      return 'Update failed: $e';
    }
  }

  /// چک کردن اینکه URL پشتیبانی میشه (yt-dlp همه رو امتحان میکنه)
  static bool isLikelySupported(String url) {
    if (url.isEmpty) return false;
    return url.startsWith('http://') || url.startsWith('https://');
  }
}

