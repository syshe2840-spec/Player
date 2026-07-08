import 'package:flutter/services.dart';

/// سرویس yt-dlp — فقط نصب، بکاپ، ایمپورت
/// پخش آنلاین: فقط لینک مستقیم MP4/M3U8 پشتیبانی میشه
class YtDlpService {
  static const _ch = MethodChannel('com.vezoo.player/whisper');
  static const _progressCh = EventChannel('com.vezoo.player/ytdlp_progress');

  static bool? _installed;

  static void resetCache() => _installed = null;

  static Stream<int> get progressStream =>
    _progressCh.receiveBroadcastStream().map((e) => (e as int?) ?? 0);

  static Future<bool> isInstalled() async {
    _installed ??= await _ch.invokeMethod<bool>('ytdlpIsInstalled') ?? false;
    return _installed!;
  }

  static Future<void> download({void Function(String)? onStatus}) async {
    onStatus?.call('دانلود yt-dlp...');
    await _ch.invokeMethod('ytdlpDownload');
    _installed = true;
    onStatus?.call('✓ نصب شد');
  }

  static Future<String?> getVersion() async {
    try {
      return await _ch.invokeMethod<String>('ytdlpGetVersion');
    } catch (_) { return null; }
  }
}

