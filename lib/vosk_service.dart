import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';

class VoskModel {
  final String id, langCode, name, size, url;
  final bool isLarge;
  const VoskModel({required this.id, required this.langCode, required this.name, required this.size, required this.url, this.isLarge = false});
}

const _b = 'https://alphacephei.com/vosk/models';

const kVoskModels = [
  // ══ فارسی ══
  VoskModel(id:'fa-sm',    langCode:'fa', name:'فارسی Small 0.42',     size:'53MB',  url:'$_b/vosk-model-small-fa-0.42.zip'),
  VoskModel(id:'fa-lg',    langCode:'fa', name:'فارسی Large 0.42',     size:'1.6GB', url:'$_b/vosk-model-fa-0.42.zip',    isLarge:true),
  VoskModel(id:'fa-sm2',   langCode:'fa', name:'فارسی Small 0.5',      size:'60MB',  url:'$_b/vosk-model-small-fa-0.5.zip'),
  VoskModel(id:'fa-lg2',   langCode:'fa', name:'فارسی Large 0.5',      size:'1GB',   url:'$_b/vosk-model-fa-0.5.zip',     isLarge:true),
  // ══ انگلیسی ══
  VoskModel(id:'en-sm',    langCode:'en', name:'English Small',         size:'40MB',  url:'$_b/vosk-model-small-en-us-0.15.zip'),
  VoskModel(id:'en-lg',    langCode:'en', name:'English Large 0.22',   size:'1.8GB', url:'$_b/vosk-model-en-us-0.22.zip',  isLarge:true),
  VoskModel(id:'en-lgraph',langCode:'en', name:'English LGraph 0.22',  size:'128MB', url:'$_b/vosk-model-en-us-0.22-lgraph.zip', isLarge:true),
  VoskModel(id:'en-giga',  langCode:'en', name:'English Gigaspeech',   size:'2.3GB', url:'$_b/vosk-model-en-us-0.42-gigaspeech.zip', isLarge:true),
  // English Other
  VoskModel(id:'en-zamia', langCode:'en', name:'English Zamia Small',   size:'49MB',  url:'$_b/vosk-model-small-en-us-zamia-0.5.zip'),
  VoskModel(id:'en-0.21',  langCode:'en', name:'English Large 0.21',   size:'1.6GB', url:'$_b/vosk-model-en-us-0.21.zip', isLarge:true),
  VoskModel(id:'en-aspire',langCode:'en', name:'English ASPIRE',       size:'1.4GB', url:'$_b/vosk-model-en-us-aspire-0.2.zip', isLarge:true),
  VoskModel(id:'en-libre', langCode:'en', name:'English LibriSpeech',  size:'845MB', url:'$_b/vosk-model-en-us-librispeech-0.2.zip', isLarge:true),
  VoskModel(id:'en-daanzu',langCode:'en', name:'English Daanzu',       size:'1.0GB', url:'$_b/vosk-model-en-us-daanzu-20200905.zip', isLarge:true),
  VoskModel(id:'en-danzlg',langCode:'en', name:'English Daanzu LGraph',size:'129MB', url:'$_b/vosk-model-en-us-daanzu-20200905-lgraph.zip', isLarge:true),
  // ══ هندی انگلیسی ══
  VoskModel(id:'en-in-sm', langCode:'en', name:'English Indian Small', size:'36MB',  url:'$_b/vosk-model-small-en-in-0.4.zip'),
  VoskModel(id:'en-in-lg', langCode:'en', name:'English Indian Large', size:'1GB',   url:'$_b/vosk-model-en-in-0.5.zip',  isLarge:true),
  // ══ عربی ══
  VoskModel(id:'ar-sm',    langCode:'ar', name:'العربية MGB2',          size:'318MB', url:'$_b/vosk-model-ar-mgb2-0.4.zip'),
  VoskModel(id:'ar-lg',    langCode:'ar', name:'العربية Large LINTO',   size:'1.3GB', url:'$_b/vosk-model-ar-0.22-linto-1.1.0.zip', isLarge:true),
  VoskModel(id:'ar-tn-sm', langCode:'ar', name:'عربی تونسی Small',      size:'158MB', url:'$_b/vosk-model-small-ar-tn-0.1-linto.zip'),
  VoskModel(id:'ar-tn-lg', langCode:'ar', name:'عربی تونسی Large',      size:'517MB', url:'$_b/vosk-model-ar-tn-0.1-linto.zip', isLarge:true),
  // ══ چینی ══
  VoskModel(id:'zh-sm',    langCode:'zh', name:'中文 Small',             size:'42MB',  url:'$_b/vosk-model-small-cn-0.22.zip'),
  VoskModel(id:'zh-lg',    langCode:'zh', name:'中文 Large',             size:'1.3GB', url:'$_b/vosk-model-cn-0.22.zip',    isLarge:true),
  VoskModel(id:'zh-lg2',   langCode:'zh', name:'中文 Kaldi MultiCN',    size:'1.5GB', url:'$_b/vosk-model-cn-kaldi-multicn-0.15.zip', isLarge:true),
  // ══ روسی ══
  VoskModel(id:'ru-sm',    langCode:'ru', name:'Русский Small',         size:'45MB',  url:'$_b/vosk-model-small-ru-0.22.zip'),
  VoskModel(id:'ru-lg',    langCode:'ru', name:'Русский Large 0.42',   size:'1.8GB', url:'$_b/vosk-model-ru-0.42.zip',    isLarge:true),
  VoskModel(id:'ru-lg2',   langCode:'ru', name:'Русский Large 0.22',   size:'1.5GB', url:'$_b/vosk-model-ru-0.22.zip',    isLarge:true),
  // ══ فرانسوی ══
  VoskModel(id:'fr-sm',    langCode:'fr', name:'Français Small',        size:'41MB',  url:'$_b/vosk-model-small-fr-0.22.zip'),
  VoskModel(id:'fr-sm2',   langCode:'fr', name:'Français Small Pguyot', size:'39MB',  url:'$_b/vosk-model-small-fr-pguyot-0.3.zip'),
  VoskModel(id:'fr-lg',    langCode:'fr', name:'Français Large',        size:'1.4GB', url:'$_b/vosk-model-fr-0.22.zip',    isLarge:true),
  VoskModel(id:'fr-lg2',   langCode:'fr', name:'Français LINTO',        size:'1.5GB', url:'$_b/vosk-model-fr-0.6-linto-2.2.0.zip', isLarge:true),
  // ══ آلمانی ══
  VoskModel(id:'de-sm',    langCode:'de', name:'Deutsch Small 0.15',   size:'45MB',  url:'$_b/vosk-model-small-de-0.15.zip'),
  VoskModel(id:'de-zamia', langCode:'de', name:'Deutsch Zamia Small',  size:'49MB',  url:'$_b/vosk-model-small-de-zamia-0.3.zip'),
  VoskModel(id:'de-lg',    langCode:'de', name:'Deutsch Large 0.21',   size:'1.9GB', url:'$_b/vosk-model-de-0.21.zip',    isLarge:true),
  VoskModel(id:'de-lg2',   langCode:'de', name:'Deutsch Tuda 900k',    size:'4.4GB', url:'$_b/vosk-model-de-tuda-0.6-900k.zip', isLarge:true),
  // ══ اسپانیایی ══
  VoskModel(id:'es-sm',    langCode:'es', name:'Español Small',         size:'39MB',  url:'$_b/vosk-model-small-es-0.42.zip'),
  VoskModel(id:'es-lg',    langCode:'es', name:'Español Large',         size:'1.4GB', url:'$_b/vosk-model-es-0.42.zip',    isLarge:true),
  // ══ پرتغالی ══
  VoskModel(id:'pt-sm',    langCode:'pt', name:'Português Small',       size:'31MB',  url:'$_b/vosk-model-small-pt-0.3.zip'),
  VoskModel(id:'pt-lg',    langCode:'pt', name:'Português FalaBrazil',  size:'1.6GB', url:'$_b/vosk-model-pt-fb-v0.1.1-20220516_2113.zip', isLarge:true),
  // ══ یونانی ══
  VoskModel(id:'el-lg',    langCode:'el', name:'Ελληνικά Large',        size:'1.1GB', url:'$_b/vosk-model-el-gr-0.7.zip',  isLarge:true),
  // ══ ترکی ══
  VoskModel(id:'tr-sm',    langCode:'tr', name:'Türkçe Small',          size:'35MB',  url:'$_b/vosk-model-small-tr-0.3.zip'),
  // ══ ویتنامی ══
  VoskModel(id:'vi-sm',    langCode:'vi', name:'Tiếng Việt Small',      size:'32MB',  url:'$_b/vosk-model-small-vn-0.4.zip'),
  VoskModel(id:'vi-lg',    langCode:'vi', name:'Tiếng Việt Large',      size:'78MB',  url:'$_b/vosk-model-vn-0.4.zip',     isLarge:true),
  // ══ ایتالیایی ══
  VoskModel(id:'it-sm',    langCode:'it', name:'Italiano Small',        size:'48MB',  url:'$_b/vosk-model-small-it-0.22.zip'),
  VoskModel(id:'it-lg',    langCode:'it', name:'Italiano Large',        size:'1.2GB', url:'$_b/vosk-model-it-0.22.zip',    isLarge:true),
  // ══ هلندی ══
  VoskModel(id:'nl-sm',    langCode:'nl', name:'Nederlands Small',      size:'39MB',  url:'$_b/vosk-model-small-nl-0.22.zip'),
  VoskModel(id:'nl-md',    langCode:'nl', name:'Nederlands Medium',     size:'860MB', url:'$_b/vosk-model-nl-spraakherkenning-0.6.zip', isLarge:true),
  VoskModel(id:'nl-lg',    langCode:'nl', name:'Nederlands LGraph',     size:'100MB', url:'$_b/vosk-model-nl-spraakherkenning-0.6-lgraph.zip'),
  // ══ کاتالان ══
  VoskModel(id:'ca',       langCode:'ca', name:'Català Small',          size:'42MB',  url:'$_b/vosk-model-small-ca-0.4.zip'),
  // ══ فیلیپینی ══
  VoskModel(id:'tl',       langCode:'tl', name:'Filipino',              size:'320MB', url:'$_b/vosk-model-tl-ph-generic-0.6.zip'),
  // ══ اوکراینی ══
  VoskModel(id:'uk-nano',  langCode:'uk', name:'Українська Nano',       size:'73MB',  url:'$_b/vosk-model-small-uk-v3-nano.zip'),
  VoskModel(id:'uk-sm',    langCode:'uk', name:'Українська Small',      size:'133MB', url:'$_b/vosk-model-small-uk-v3-small.zip'),
  VoskModel(id:'uk-lg',    langCode:'uk', name:'Українська Large',      size:'343MB', url:'$_b/vosk-model-uk-v3.zip',      isLarge:true),
  VoskModel(id:'uk-lgraph',langCode:'uk', name:'Українська LGraph',     size:'325MB', url:'$_b/vosk-model-uk-v3-lgraph.zip', isLarge:true),
  // ══ قزاقی ══
  VoskModel(id:'kz-sm',    langCode:'kk', name:'Қазақ Small',           size:'58MB',  url:'$_b/vosk-model-small-kz-0.42.zip'),
  VoskModel(id:'kz-lg',    langCode:'kk', name:'Қазақ Large',           size:'1.3GB', url:'$_b/vosk-model-kz-0.42.zip',    isLarge:true),
  // ══ سوئدی ══
  VoskModel(id:'sv',       langCode:'sv', name:'Svenska',               size:'289MB', url:'$_b/vosk-model-small-sv-rhasspy-0.15.zip'),
  // ══ ژاپنی ══
  VoskModel(id:'ja-sm',    langCode:'ja', name:'日本語 Small',            size:'48MB',  url:'$_b/vosk-model-small-ja-0.22.zip'),
  VoskModel(id:'ja-lg',    langCode:'ja', name:'日本語 Large',            size:'1GB',   url:'$_b/vosk-model-ja-0.22.zip',    isLarge:true),
  // ══ اسپرانتو ══
  VoskModel(id:'eo',       langCode:'eo', name:'Esperanto',             size:'42MB',  url:'$_b/vosk-model-small-eo-0.42.zip'),
  // ══ هندی ══
  VoskModel(id:'hi-sm',    langCode:'hi', name:'हिन्दी Small',           size:'42MB',  url:'$_b/vosk-model-small-hi-0.22.zip'),
  VoskModel(id:'hi-lg',    langCode:'hi', name:'हिन्दी Large',           size:'1.5GB', url:'$_b/vosk-model-hi-0.22.zip',    isLarge:true),
  // ══ چک ══
  VoskModel(id:'cs',       langCode:'cs', name:'Čeština',               size:'44MB',  url:'$_b/vosk-model-small-cs-0.4-rhasspy.zip'),
  // ══ لهستانی ══
  VoskModel(id:'pl',       langCode:'pl', name:'Polski',                size:'50MB',  url:'$_b/vosk-model-small-pl-0.22.zip'),
  // ══ ازبکی ══
  VoskModel(id:'uz',       langCode:'uz', name:'Ozbek',                 size:'49MB',  url:'$_b/vosk-model-small-uz-0.22.zip'),
  // ══ کره‌ای ══
  VoskModel(id:'ko',       langCode:'ko', name:'한국어',                  size:'82MB',  url:'$_b/vosk-model-small-ko-0.22.zip'),
  // ══ برتون ══
  VoskModel(id:'br',       langCode:'br', name:'Brezhoneg',             size:'70MB',  url:'$_b/vosk-model-br-0.8.zip'),
  // ══ گجراتی ══
  VoskModel(id:'gu-sm',    langCode:'gu', name:'ગુજરાતી Small',          size:'100MB', url:'$_b/vosk-model-small-gu-0.42.zip'),
  VoskModel(id:'gu-lg',    langCode:'gu', name:'ગુજરાતી Large',          size:'700MB', url:'$_b/vosk-model-gu-0.42.zip',    isLarge:true),
  // ══ تاجیکی ══
  VoskModel(id:'tg-sm',    langCode:'tg', name:'Тоҷикӣ Small',          size:'50MB',  url:'$_b/vosk-model-small-tg-0.22.zip'),
  VoskModel(id:'tg-lg',    langCode:'tg', name:'Тоҷикӣ Large',          size:'327MB', url:'$_b/vosk-model-tg-0.22.zip',    isLarge:true),
  // ══ تلوگو ══
  VoskModel(id:'te',       langCode:'te', name:'తెలుగు',                 size:'58MB',  url:'$_b/vosk-model-small-te-0.42.zip'),
  // ══ قرقیزی ══
  VoskModel(id:'ky-sm',    langCode:'ky', name:'Кыргызча Small',        size:'49MB',  url:'$_b/vosk-model-small-ky-0.42.zip'),
  VoskModel(id:'ky-lg',    langCode:'ky', name:'Кыргызча Large',        size:'1.1GB', url:'$_b/vosk-model-ky-0.42.zip',    isLarge:true),
  // ══ گرجی ══
  VoskModel(id:'ka-sm',    langCode:'ka', name:'ქართული Small',         size:'45MB',  url:'$_b/vosk-model-small-ka-0.42.zip'),
  VoskModel(id:'ka-lg',    langCode:'ka', name:'ქართული Large',         size:'700MB', url:'$_b/vosk-model-ka-0.42.zip',    isLarge:true),
  // ══ اندونزیایی ══
  VoskModel(id:'id',       langCode:'id', name:'Indonesia',             size:'75MB',  url:'$_b/vosk-model-id-0.22.zip'),
  // ══ سواحیلی ══
  VoskModel(id:'sw',       langCode:'sw', name:'Kiswahili',             size:'49MB',  url:'$_b/vosk-model-small-swahili-0.15.zip'),
  // ══ ولزی ══
  VoskModel(id:'cy',       langCode:'cy', name:'Cymraeg',               size:'117MB', url:'$_b/vosk-model-small-cy-rhasspy-0.15.zip'),
  // ══ تشخیص گوینده (همه زبان‌ها) ══
  VoskModel(id:'spk',      langCode:'spk',name:'Speaker ID (همه زبان‌ها)', size:'13MB', url:'$_b/vosk-model-spk-0.4.zip'),
  // ══ استونیایی ══
  VoskModel(id:'et',       langCode:'et', name:'Eesti',                 size:'16MB',  url:'$_b/vosk-model-small-et-0.4.zip'),
];

const _kDir = '/storage/emulated/0/Download/Vezoo/VoskModels';

class VoskService {
  static const _ch       = MethodChannel('com.vezoo.player/vosk');
  static const _ech      = EventChannel('com.vezoo.player/vosk_events');
  static const _callback = MethodChannel('com.vezoo.player/vosk_callback');
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
    final folderName = m.url.split('/').last.replaceAll('.zip', '');
    return dir.listSync().any((e) =>
      e is Directory && e.path.split('/').last == folderName);
  }

  static List<VoskModel> get downloadedModels =>
    kVoskModels.where((m) => isDownloaded(m)).toList();

  static List<String> get downloadedLangCodes =>
    downloadedModels.map((m) => m.langCode).toSet().toList();

  static VoskModel? bestModelForLang(String langCode) {
    final models = downloadedModels.where((m) => m.langCode == langCode).toList();
    if (models.isEmpty) return null;
    models.sort((a, b) => b.isLarge ? 1 : -1);
    return models.first;
  }

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
    final folderName = m.url.split('/').last.replaceAll('.zip', '');
    final dir = Directory('$_kDir/$folderName');
    if (dir.existsSync()) await dir.delete(recursive: true);
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

