import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'api_service.dart';

class VezService {
  static const _ch = MethodChannel('com.vezoo.player/vezoo');
  static const _magic = [0x56,0x45,0x5A,0x4F,0x4F,0x01];
  static String? _cacheDir;

  static bool isVez(String path) {
    return path.toLowerCase().endsWith('.vez');
  }

  static Future<String> getCacheDir() async {
    _cacheDir ??= await _ch.invokeMethod<String>('getCacheDir');
    return _cacheDir ?? '/data/data/com.vezoo.player/cache';
  }

  static Future<bool> ensureMasterKey() async {
    try {
      final has = await _ch.invokeMethod<bool>('hasMasterKey') ?? false;
      if (has) return true;

      // Server Half از Cloudflare
      final data = await ApiService.getRaw('/master-half');
      final serverHalf = (data as Map?)?['server_half'] as String?;
      if (serverHalf == null || serverHalf.isEmpty) {
        throw Exception('server_half not set in D1');
      }

      final ok = await _ch.invokeMethod<bool>('initMasterKey', {'server_half': serverHalf});
      if (ok != true) throw Exception('initMasterKey failed');
      return true;
    } catch (e) {
      throw Exception('خطا در راه‌اندازی کریپتو: $e');
    }
  }

  static Future<String> decryptToTemp(String vezPath) async {
    await ensureMasterKey();

    final cacheDir = await getCacheDir();
    final dir = Directory(cacheDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);

    final ts = DateTime.now().millisecondsSinceEpoch;
    final tempPath = p.join(cacheDir, 'vez_$ts.tmp');

    final result = await _ch.invokeMethod<String>('decryptVez', {
      'input': vezPath,
      'output': tempPath,
    });

    if (result == null) throw Exception('decryptVez returned null');

    // بررسی فایل output
    final outFile = File(tempPath);
    if (!outFile.existsSync() || outFile.lengthSync() == 0) {
      throw Exception('فایل رمزگشایی‌شده خالی یا وجود ندارد: $tempPath');
    }

    return tempPath;
  }

  static void cleanup(String? tempPath) {
    if (tempPath == null) return;
    try { File(tempPath).deleteSync(); } catch (_) {}
  }
}
