import 'dart:io';
import 'package:flutter/services.dart';

/// سرویس yt-dlp + deno — stream URL از هر سایت
class YtDlpService {
  static const _ch = MethodChannel('com.vezoo.player/ytdlp');

  // ── وضعیت ──
  static Future<Map<String,String?>> getVersions() async {
    final r = await _ch.invokeMapMethod<String,String>('getVersions');
    return r ?? {};
  }

  static Future<bool> isYtDlpInstalled() async =>
    await _ch.invokeMethod<bool>('isInstalled', 'ytdlp') ?? false;

  static Future<bool> isDenoInstalled() async =>
    await _ch.invokeMethod<bool>('isInstalled', 'deno') ?? false;

  // ── دانلود ──
  static Stream<Map> downloadProgress() =>
    const EventChannel('com.vezoo.player/ytdlp_progress')
      .receiveBroadcastStream()
      .map((e) => (e as Map).cast<String,dynamic>());

  static Future<void> downloadYtDlp() async =>
    await _ch.invokeMethod('download', 'ytdlp');

  static Future<void> downloadDeno() async =>
    await _ch.invokeMethod('download', 'deno');

  // ── آپدیت ──
  static Future<void> updateYtDlp() async =>
    await _ch.invokeMethod('update', 'ytdlp');

  static Future<void> updateDeno() async =>
    await _ch.invokeMethod('update', 'deno');

  // ── حذف ──
  static Future<void> deleteYtDlp() async =>
    await _ch.invokeMethod('delete', 'ytdlp');

  static Future<void> deleteDeno() async =>
    await _ch.invokeMethod('delete', 'deno');

  // ── بکاپ ──
  static Future<List<String>> backup() async {
    final r = await _ch.invokeListMethod<String>('backup');
    return r ?? [];
  }

  // ── ایمپورت ──
  static Future<void> importBin(String path, String type) async =>
    await _ch.invokeMethod('import', {'path': path, 'type': type});

  // ── stream URL ──
  static Future<String> getStreamUrl(String url) async {
    final result = await _ch.invokeMethod<String>('streamUrl', url);
    if (result == null || result.isEmpty) throw Exception('Stream URL not found');
    return result;
  }
}
