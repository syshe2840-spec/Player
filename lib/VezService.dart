import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'api_service.dart';

/// سرویس رمزگشایی فایل‌های .vez
class VezService {
  static const _ch = MethodChannel('com.vezoo.player/vezoo');
  static const _magic = [0x56,0x45,0x5A,0x4F,0x4F,0x01]; // VEZOO\x01

  /// آیا فایل .vez هست؟
  static bool isVez(String path) {
    final ext = p.extension(path).toLowerCase();
    if (ext != '.vez') return false;
    try {
      final f = File(path);
      if (!f.existsSync()) return false;
      final bytes = f.openSync()..setPositionSync(0);
      final header = bytes.readSync(6);
      bytes.closeSync();
      for (int i = 0; i < 6; i++) {
        if (header[i] != _magic[i]) return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// مطمئن شو Master Key ذخیره شده
  static Future<bool> ensureMasterKey() async {
    try {
      final has = await _ch.invokeMethod<bool>('hasMasterKey') ?? false;
      if (has) return true;

      // گرفتن Server Half از Cloudflare
      final cfg = await ApiService.getConfig();
      if (cfg == null) throw Exception('خطا در اتصال به سرور');

      // /master-half endpoint
      final dynamic data = await ApiService.getRaw('/master-half');
      final serverHalf = (data as Map?)?['server_half'];
      if (serverHalf == null) throw Exception('server_half در سرور تنظیم نشده');

      final ok = await _ch.invokeMethod<bool>('initMasterKey', {'server_half': serverHalf});
      return ok == true;
    } catch (e) {
      throw Exception('خطا در راه‌اندازی کریپتو: $e');
    }
  }

  /// گرفتن metadata فایل .vez
  static Future<Map<String, dynamic>> getMeta(String path) async {
    await ensureMasterKey();
    final result = await _ch.invokeMethod<Map>('getVezMeta', {'path': path});
    return (result ?? {}).cast<String, dynamic>();
  }

  /// رمزگشایی فایل .vez به temp
  /// برگشت: مسیر فایل موقت
  static Future<String> decryptToTemp(String vezPath, {
    void Function(String status)? onStatus,
  }) async {
    onStatus?.call('راه‌اندازی کریپتو...');
    await ensureMasterKey();

    onStatus?.call('خواندن اطلاعات فایل...');
    final meta = await getMeta(vezPath);
    final ext = meta['original_ext'] as String? ?? 'mkv';

    // مسیر temp در cache اپ
    final cacheDir = Directory(
      vezPath.contains('/cache/') 
        ? p.dirname(vezPath) 
        : '/data/data/com.vezoo.player/cache'
    );
    if (!cacheDir.existsSync()) cacheDir.createSync(recursive: true);
    
    final tempPath = p.join(
      cacheDir.path,
      'vez_${DateTime.now().millisecondsSinceEpoch}.$ext'
    );

    onStatus?.call('رمزگشایی در حال انجام است...');
    await _ch.invokeMethod('decryptVez', {
      'input': vezPath,
      'output': tempPath,
    });

    return tempPath;
  }

  /// حذف فایل temp بعد از پخش
  static void cleanup(String? tempPath) {
    if (tempPath == null) return;
    try { File(tempPath).deleteSync(); } catch (_) {}
  }
}
