
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';

// ── مدل‌های Vosk ──
class VoskModel {
  final String id, langCode, name, size, url;
  const VoskModel({required this.id, required this.langCode, required this.name, required this.size, required this.url});
}

const _base = 'https://alphacephei.com/vosk/models';
const kVoskModels = [
  VoskModel(id:'fa',    langCode:'fa', name:'فارسی',       size:'52MB',  url:'$_base/vosk-model-fa-0.5.zip'),
  VoskModel(id:'en',    langCode:'en', name:'English',      size:'40MB',  url:'$_base/vosk-model-small-en-us-0.15.zip'),
  VoskModel(id:'en-lg', langCode:'en', name:'English Large',size:'1.8GB', url:'$_base/vosk-model-en-us-0.22.zip'),
  VoskModel(id:'ar',    langCode:'ar', name:'العربية',      size:'37MB',  url:'$_base/vosk-model-ar-mgb2-0.4.zip'),
  VoskModel(id:'zh',    langCode:'zh', name:'中文',          size:'42MB',  url:'$_base/vosk-model-small-cn-0.22.zip'),
  VoskModel(id:'ru',    langCode:'ru', name:'Русский',      size:'45MB',  url:'$_base/vosk-model-small-ru-0.22.zip'),
  VoskModel(id:'es',    langCode:'es', name:'Español',      size:'39MB',  url:'$_base/vosk-model-small-es-0.42.zip'),
  VoskModel(id:'fr',    langCode:'fr', name:'Français',     size:'41MB',  url:'$_base/vosk-model-small-fr-0.22.zip'),
  VoskModel(id:'de',    langCode:'de', name:'Deutsch',      size:'42MB',  url:'$_base/vosk-model-small-de-0.15.zip'),
  VoskModel(id:'tr',    langCode:'tr', name:'Türkçe',       size:'35MB',  url:'$_base/vosk-model-small-tr-0.3.zip'),
  VoskModel(id:'hi',    langCode:'hi', name:'हिन्दी',        size:'42MB',  url:'$_base/vosk-model-small-hi-0.22.zip'),
  VoskModel(id:'ja',    langCode:'ja', name:'日本語',         size:'48MB',  url:'$_base/vosk-model-small-ja-0.22.zip'),
  VoskModel(id:'ko',    langCode:'ko', name:'한국어',         size:'82MB',  url:'$_base/vosk-model-small-ko-0.22.zip'),
  VoskModel(id:'it',    langCode:'it', name:'Italiano',     size:'48MB',  url:'$_base/vosk-model-small-it-0.22.zip'),
  VoskModel(id:'pt',    langCode:'pt', name:'Português',    size:'31MB',  url:'$_base/vosk-model-small-pt-0.3.zip'),
  VoskModel(id:'nl',    langCode:'nl', name:'Nederlands',   size:'39MB',  url:'$_base/vosk-model-small-nl-0.22.zip'),
  VoskModel(id:'vi',    langCode:'vi', name:'Tiếng Việt',   size:'32MB',  url:'$_base/vosk-model-small-vn-0.4.zip'),
  VoskModel(id:'uk',    langCode:'uk', name:'Українська',   size:'133MB', url:'$_base/vosk-model-small-uk-v3-small.zip'),
];

const _kDir = '/storage/emulated/0/Download/Vezoo/VoskModels';

class VoskService {
  static const _ch  = MethodChannel('com.vezoo.player/vosk');
  static const _ech = EventChannel('com.vezoo.player/vosk_events');
  static StreamSubscription? _sub;

  static bool isDownloaded(VoskModel m) {
    final dir = Directory(_kDir);
    if (!dir.existsSync()) return false;
    return dir.listSync().any((e) =>
      e is Directory && (e.path.contains('-${m.langCode}-') ||
        e.path.contains('-${m.langCode}.') ||
        e.path.endsWith('-${m.langCode}')));
  }

  // دانلود و extract مدل
  static Stream<double> downloadModel(VoskModel m) async* {
    final dir = Directory(_kDir);
    await dir.create(recursive: true);
    final zipFile = File('$_kDir/${m.id}.zip');

    // دانلود
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 30);
    try {
      final req = await client.getUrl(Uri.parse(m.url));
      req.headers.set('User-Agent', 'vezoo_downloader/1.0');
      final res = await req.close();
      final total = res.contentLength > 0 ? res.contentLength : 0;
      int received = 0;
      final sink = zipFile.openWrite();
      await for (final chunk in res.timeout(const Duration(seconds: 60))) {
        sink.add(chunk); received += chunk.length;
        if (total > 0) yield received / total * 0.8;
        else yield 0.1;
      }
      await sink.close();
    } finally { client.close(); }
    yield 0.85;

    // extract
    await _ch.invokeMethod('extractModel', {'zipPath': zipFile.path, 'destDir': _kDir});
    yield 0.95;
    zipFile.deleteSync();
    yield 1.0;
  }

  static Future<void> deleteModel(VoskModel m) async {
    final dir = Directory(_kDir);
    if (!dir.existsSync()) return;
    final modelDir = dir.listSync().whereType<Directory>().firstWhere(
      (d) => d.path.contains('-${m.langCode}-') || d.path.contains('-${m.langCode}.') || d.path.endsWith('-${m.langCode}'),
      orElse: () => Directory(''));
    if (modelDir.path.isNotEmpty && modelDir.existsSync()) {
      await modelDir.delete(recursive: true);
    }
  }

  // شروع Vosk
  static Future<void> start(String langCode) async {
    await _ch.invokeMethod('requestMediaProjection', {'lang': langCode});
  }

  static Future<void> stop() async {
    await _ch.invokeMethod('stop');
  }

  static Stream<Map<String, dynamic>> events() {
    return _ech.receiveBroadcastStream().map((e) => Map<String, dynamic>.from(e as Map));
  }
}
