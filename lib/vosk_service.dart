import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';

// ── مدل‌های Vosk ──
class VoskModel {
  final String id, langCode, name, size, url;
  final bool isLarge;
  const VoskModel({required this.id, required this.langCode, required this.name, required this.size, required this.url, this.isLarge = false});
}

const _b = 'https://alphacephei.com/vosk/models';

const kVoskModels = [
  // ── فارسی ──
  VoskModel(id:'fa',      langCode:'fa', name:'فارسی',            size:'52MB',  url:'$_b/vosk-model-small-fa-0.42.zip'),
  // ── انگلیسی ──
  VoskModel(id:'en-sm',   langCode:'en', name:'English Small',    size:'40MB',  url:'$_b/vosk-model-small-en-us-0.15.zip'),
  VoskModel(id:'en-lg',   langCode:'en', name:'English Large',    size:'1.8GB', url:'$_b/vosk-model-en-us-0.22.zip', isLarge:true),
  // ── عربی ──
  VoskModel(id:'ar',      langCode:'ar', name:'العربية',          size:'37MB',  url:'$_b/vosk-model-ar-mgb2-0.4.zip'),
  // ── چینی ──
  VoskModel(id:'zh-sm',   langCode:'zh', name:'中文 Small',        size:'42MB',  url:'$_b/vosk-model-small-cn-0.22.zip'),
  VoskModel(id:'zh-lg',   langCode:'zh', name:'中文 Large',        size:'1.3GB', url:'$_b/vosk-model-cn-0.22.zip', isLarge:true),
  // ── روسی ──
  VoskModel(id:'ru-sm',   langCode:'ru', name:'Русский Small',    size:'45MB',  url:'$_b/vosk-model-small-ru-0.22.zip'),
  VoskModel(id:'ru-lg',   langCode:'ru', name:'Русский Large',    size:'1.8GB', url:'$_b/vosk-model-ru-0.42.zip', isLarge:true),
  // ── اسپانیایی ──
  VoskModel(id:'es-sm',   langCode:'es', name:'Español Small',    size:'39MB',  url:'$_b/vosk-model-small-es-0.42.zip'),
  VoskModel(id:'es-lg',   langCode:'es', name:'Español Large',    size:'1.4GB', url:'$_b/vosk-model-es-0.42.zip', isLarge:true),
  // ── فرانسوی ──
  VoskModel(id:'fr-sm',   langCode:'fr', name:'Français Small',   size:'41MB',  url:'$_b/vosk-model-small-fr-0.22.zip'),
  VoskModel(id:'fr-lg',   langCode:'fr', name:'Français Large',   size:'1.4GB', url:'$_b/vosk-model-fr-0.22.zip', isLarge:true),
  // ── آلمانی ──
  VoskModel(id:'de-sm',   langCode:'de', name:'Deutsch Small',    size:'42MB',  url:'$_b/vosk-model-small-de-0.15.zip'),
  VoskModel(id:'de-lg',   langCode:'de', name:'Deutsch Large',    size:'1.9GB', url:'$_b/vosk-model-de-0.21.zip', isLarge:true),
  // ── ترکی ──
  VoskModel(id:'tr-sm',   langCode:'tr', name:'Türkçe Small',     size:'35MB',  url:'$_b/vosk-model-small-tr-0.3.zip'),
  VoskModel(id:'tr-lg',   langCode:'tr', name:'Türkçe Large',     size:'300MB', url:'$_b/vosk-model-tr-0.3.zip', isLarge:true),
  // ── هندی ──
  VoskModel(id:'hi-sm',   langCode:'hi', name:'हिन्दी Small',      size:'42MB',  url:'$_b/vosk-model-small-hi-0.22.zip'),
  VoskModel(id:'hi-lg',   langCode:'hi', name:'हिन्दी Large',      size:'1.5GB', url:'$_b/vosk-model-hi-0.22.zip', isLarge:true),
  // ── ژاپنی ──
  VoskModel(id:'ja-sm',   langCode:'ja', name:'日本語 Small',       size:'48MB',  url:'$_b/vosk-model-small-ja-0.22.zip'),
  VoskModel(id:'ja-lg',   langCode:'ja', name:'日本語 Large',       size:'1GB',   url:'$_b/vosk-model-ja-0.22.zip', isLarge:true),
  // ── کره‌ای ──
  VoskModel(id:'ko-sm',   langCode:'ko', name:'한국어 Small',       size:'82MB',  url:'$_b/vosk-model-small-ko-0.22.zip'),
  VoskModel(id:'ko-lg',   langCode:'ko', name:'한국어 Large',       size:'2GB',   url:'$_b/vosk-model-ko-0.22.zip', isLarge:true),
  // ── ایتالیایی ──
  VoskModel(id:'it-sm',   langCode:'it', name:'Italiano Small',   size:'48MB',  url:'$_b/vosk-model-small-it-0.22.zip'),
  VoskModel(id:'it-lg',   langCode:'it', name:'Italiano Large',   size:'1.2GB', url:'$_b/vosk-model-it-0.22.zip', isLarge:true),
  // ── پرتغالی ──
  VoskModel(id:'pt-sm',   langCode:'pt', name:'Português Small',  size:'31MB',  url:'$_b/vosk-model-small-pt-0.3.zip'),
  // ── هلندی ──
  VoskModel(id:'nl-sm',   langCode:'nl', name:'Nederlands Small', size:'39MB',  url:'$_b/vosk-model-small-nl-0.22.zip'),
  VoskModel(id:'nl-lg',   langCode:'nl', name:'Nederlands Large', size:'860MB', url:'$_b/vosk-model-nl-spraakherkenning-0.6.zip', isLarge:true),
  // ── اوکراینی ──
  VoskModel(id:'uk-sm',   langCode:'uk', name:'Українська Small', size:'133MB', url:'$_b/vosk-model-small-uk-v3-small.zip'),
  VoskModel(id:'uk-lg',   langCode:'uk', name:'Українська Large', size:'343MB', url:'$_b/vosk-model-uk-v3.zip', isLarge:true),
  // ── ویتنامی ──
  VoskModel(id:'vi-sm',   langCode:'vi', name:'Tiếng Việt Small', size:'32MB',  url:'$_b/vosk-model-small-vn-0.4.zip'),
  VoskModel(id:'vi-lg',   langCode:'vi', name:'Tiếng Việt Large', size:'76MB',  url:'$_b/vosk-model-vn-0.4.zip', isLarge:true),
  // ── لهستانی ──
  VoskModel(id:'pl-sm',   langCode:'pl', name:'Polski Small',     size:'50MB',  url:'$_b/vosk-model-small-pl-0.22.zip'),
  VoskModel(id:'pl-lg',   langCode:'pl', name:'Polski Large',     size:'1.3GB', url:'$_b/vosk-model-pl-0.22.zip', isLarge:true),
  // ── اندونزیایی ──
  VoskModel(id:'id',      langCode:'id', name:'Indonesia',        size:'75MB',  url:'$_b/vosk-model-id-0.22.zip'),
  // ── سوئدی ──
  VoskModel(id:'sv',      langCode:'sv', name:'Svenska',          size:'62MB',  url:'$_b/vosk-model-small-sv-rhasspy-0.15.zip'),
  // ── چک ──
  VoskModel(id:'cs',      langCode:'cs', name:'Čeština',          size:'44MB',  url:'$_b/vosk-model-small-cs-0.4-rhasspy.zip'),
  // ── کاتالان ──
  VoskModel(id:'ca',      langCode:'ca', name:'Català',           size:'42MB',  url:'$_b/vosk-model-small-ca-0.4.zip'),
  // ── قزاقی ──
  VoskModel(id:'kz',      langCode:'kk', name:'Қазақ',            size:'34MB',  url:'$_b/vosk-model-small-kz-0.42.zip'),
  // ── ازبکی ──
  VoskModel(id:'uz',      langCode:'uz', name:'Ozbek',            size:'49MB',  url:'$_b/vosk-model-small-uz-0.22.zip'),
  // ── سواحیلی ──
  VoskModel(id:'sw',      langCode:'sw', name:'Kiswahili',        size:'49MB',  url:'$_b/vosk-model-small-swahili-0.15.zip'),
  // ── گجراتی ──
  VoskModel(id:'gu',      langCode:'gu', name:'ગુજરાતી',           size:'24MB',  url:'$_b/vosk-model-small-gu-0.42.zip'),
  // ── تلوگو ──
  VoskModel(id:'te',      langCode:'te', name:'తెలుగు',            size:'44MB',  url:'$_b/vosk-model-small-te-0.42.zip'),
  // ── یونانی ──
  VoskModel(id:'el-lg',   langCode:'el', name:'Ελληνικά',         size:'1GB',   url:'$_b/vosk-model-el-gr-0.7.zip', isLarge:true),
  // ── فیلیپینی ──
  VoskModel(id:'tl',      langCode:'tl', name:'Filipino',         size:'49MB',  url:'$_b/vosk-model-tl-ph-generic-0.6.zip'),
  // ── استونیایی ──
  VoskModel(id:'et',      langCode:'et', name:'Eesti',            size:'16MB',  url:'$_b/vosk-model-small-et-0.4.zip'),
  // ── ولزی ──
  VoskModel(id:'cy',      langCode:'cy', name:'Cymraeg',          size:'117MB', url:'$_b/vosk-model-small-cy-rhasspy-0.15.zip'),
  // ── اسپرانتو ──
  VoskModel(id:'eo',      langCode:'eo', name:'Esperanto',        size:'42MB',  url:'$_b/vosk-model-small-eo-0.42.zip'),
  // ── هندی انگلیسی ──
  VoskModel(id:'en-in', langCode:'en', name:'English Indian',  size:'36MB',  url:'$_b/vosk-model-small-en-in-0.4.zip'),
  // ── گرجی ──
  VoskModel(id:'ka',    langCode:'ka', name:'ქართული',          size:'50MB',  url:'$_b/vosk-model-small-ka-0.42.zip'),
  // ── تاجیکی ──
  VoskModel(id:'tg',    langCode:'tg', name:'Тоҷикӣ',           size:'42MB',  url:'$_b/vosk-model-small-tg-0.22.zip'),
  // ── قرقیزی ──
  VoskModel(id:'ky',    langCode:'ky', name:'Кыргызча',         size:'19MB',  url:'$_b/vosk-model-small-ky-0.42.zip'),
  // ── برتون ──
  VoskModel(id:'br',    langCode:'br', name:'Brezhoneg',        size:'44MB',  url:'$_b/vosk-model-br-0.8.zip'),
];

const _kDir = '/storage/emulated/0/Download/Vezoo/VoskModels';

class VoskService {
  static const _ch       = MethodChannel('com.vezoo.player/vosk');
  static const _ech      = EventChannel('com.vezoo.player/vosk_events');
  static const _callback = MethodChannel('com.vezoo.player/vosk_callback');
  static StreamSubscription? _sub;
  static void Function(Map<String,dynamic>)? _eventHandler;

  static void _initCallback() {
    _callback.setMethodCallHandler((call) async {
      if (call.method == 'onVoskEvent' && _eventHandler != null) {
        final data = Map<String,dynamic>.from(call.arguments as Map);
        _eventHandler!(data);
      }
    });
  }

  static bool isDownloaded(VoskModel m) {
    final dir = Directory(_kDir);
    if (!dir.existsSync()) return false;
    return dir.listSync().any((e) =>
      e is Directory && (e.path.contains('-${m.langCode}-') ||
        e.path.contains('-${m.langCode}.') ||
        e.path.endsWith('-${m.langCode}') ||
        (m.id == 'en-lg' && e.path.contains('en-us-0.22')) ||
        (m.id == 'en-sm' && e.path.contains('small-en')) ||
        (m.isLarge && e.path.contains(m.id.split('-').first))));
  }

  // دانلود و extract
  static Stream<double> downloadModel(VoskModel m) async* {
    final dir = Directory(_kDir);
    await dir.create(recursive: true);
    final zipFile = File('$_kDir/${m.id}.zip');

    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 30);
    try {
      final req = await client.getUrl(Uri.parse(m.url));
      req.headers.set('User-Agent', 'vezoo_downloader/1.0');
      final res = await req.close();
      final total = res.contentLength > 0 ? res.contentLength : 0;
      int received = 0;
      final sink = zipFile.openWrite();
      await for (final chunk in res.timeout(const Duration(seconds: 120))) {
        sink.add(chunk); received += chunk.length;
        if (total > 0) yield received / total * 0.85;
        else yield 0.1;
      }
      await sink.close();
    } finally { client.close(); }
    yield 0.88;

    await _ch.invokeMethod('extractModel', {'zipPath': zipFile.path, 'destDir': _kDir});
    yield 0.97;
    try { zipFile.deleteSync(); } catch (_) {}
    yield 1.0;
  }

  static Future<void> deleteModel(VoskModel m) async {
    final dir = Directory(_kDir);
    if (!dir.existsSync()) return;
    for (final e in dir.listSync()) {
      if (e is Directory && (e.path.contains('-${m.langCode}-') ||
          e.path.contains('-${m.langCode}.') ||
          e.path.endsWith('-${m.langCode}'))) {
        await e.delete(recursive: true);
      }
    }
  }

  static Stream<Map<String, dynamic>> events() {
    _initCallback();
    final controller = StreamController<Map<String,dynamic>>.broadcast();
    _eventHandler = (data) { if (!controller.isClosed) controller.add(data); };
    try {
      _ech.receiveBroadcastStream().listen((e) {
        final data = Map<String,dynamic>.from(e as Map);
        if (!controller.isClosed) controller.add(data);
      });
    } catch (_) {}
    return controller.stream;
  }

  static Future<void> start(String langCode, {String? modelId}) async {
    await _ch.invokeMethod('requestMediaProjection', {'lang': langCode, 'modelId': modelId});
  }

  static Future<void> stop() async { await _ch.invokeMethod('stop'); }

  static Future<Map<String,dynamic>?> getNextEvent() async {
    final r = await _ch.invokeMethod<Map>('getNextEvent');
    if (r == null) return null;
    return Map<String,dynamic>.from(r);
  }
}

