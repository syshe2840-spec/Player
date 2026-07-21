import 'package:flutter/services.dart';
import 'dart:io' as dart;

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

  static const _cookiePath = '/storage/emulated/0/Download/Vezoo/cookies.txt';

  static bool hasCookies() => dart.io.File(_cookiePath).existsSync();

  static Future<void> deleteCookies() async {
    final f = dart.io.File(_cookiePath);
    if (f.existsSync()) await f.delete();
  }

  static Future<void> saveCookies(String content) async {
    final dir = dart.io.Directory('/storage/emulated/0/Download/Vezoo');
    await dir.create(recursive: true);
    await dart.io.File(_cookiePath).writeAsString(content);
  }

  /// گرفتن stream URL مستقیم
  static Future<Map<String, dynamic>> getStreamUrl(String url) async {
    try {
      final args = <String, dynamic>{'url': url};
      if (hasCookies()) args['cookiePath'] = _cookiePath;
      final result = await _ch.invokeMethod<Map>('getStreamUrl', args);
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

  /// گرفتن نسخه yt-dlp
  static Future<String> getVersion() async {
    try {
      final r = await _ch.invokeMethod<String>('getVersion');
      return r ?? 'نامشخص';
    } catch (_) { return 'نامشخص'; }
  }

  /// آپدیت با progress callback
  static Future<String> updateWithProgress(
      void Function(String status) onProgress) async {
    try {
      onProgress('⏳ در حال بررسی آپدیت...');
      final r = await _ch.invokeMethod<String>('updateYtDlp');
      onProgress('✅ ${r ?? "آپدیت انجام شد"}');
      return r ?? 'OK';
    } catch (e) {
      onProgress('❌ خطا: $e');
      return 'ERROR';
    }
  }
}

