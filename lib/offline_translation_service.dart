import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// ── ۵ مدل ترجمه آفلاین ──
class OfflineTransModel {
  final String id, name, desc;
  final int sizeMb, langCount;
  final List<String> langCodes; // ISO-639-1
  final Map<String, String> files; // filename → URL

  const OfflineTransModel({
    required this.id, required this.name, required this.desc,
    required this.sizeMb, required this.langCount,
    required this.langCodes, required this.files,
  });
}

const _gh = 'https://github.com/niedev/RTranslator/releases/download/2.0.0';
const _xen = 'https://huggingface.co/Xenova/nllb-200-distilled-600M/resolve/main/onnx';
const _hfFb = 'https://huggingface.co/facebook';

final kOfflineModels = [
  OfflineTransModel(
    id: 'nllb_600m_q8',
    name: 'NLLB-600M Q8',
    desc: '200 زبان • int8 optimized • سریع و سبک',
    sizeMb: 300, langCount: 200,
    langCodes: _nllbLangs,
    files: {
      'encoder.onnx': '$_gh/nllb_encoder_q8.onnx',
      'decoder.onnx': '$_gh/nllb_decoder_q8.onnx',
      'tokenizer.spm': '$_gh/flores200_sacrebleu_tokenizer.spm',
    },
  ),
  OfflineTransModel(
    id: 'nllb_600m_xenova',
    name: 'NLLB-600M Standard',
    desc: '200 زبان • کیفیت بالا',
    sizeMb: 1200, langCount: 200,
    langCodes: _nllbLangs,
    files: {
      'encoder.onnx': '$_xen/encoder_model.onnx',
      'decoder.onnx': '$_xen/decoder_model.onnx',
      'tokenizer.spm': '$_gh/flores200_sacrebleu_tokenizer.spm',
    },
  ),
  OfflineTransModel(
    id: 'nllb_600m_q8_xenova',
    name: 'NLLB-600M Q8 Alt',
    desc: '200 زبان • int8 • نسخه آلترناتیو',
    sizeMb: 350, langCount: 200,
    langCodes: _nllbLangs,
    files: {
      'encoder.onnx': '$_xen/encoder_model_quantized.onnx',
      'decoder.onnx': '$_xen/decoder_model_quantized.onnx',
      'tokenizer.spm': '$_gh/flores200_sacrebleu_tokenizer.spm',
    },
  ),
  OfflineTransModel(
    id: 'nllb_600m_q4',
    name: 'NLLB-600M Q4',
    desc: '200 زبان • int4 • کمترین حجم',
    sizeMb: 200, langCount: 200,
    langCodes: _nllbLangs,
    files: {
      'encoder.onnx': '$_xen/encoder_model_uint8.onnx',
      'decoder.onnx': '$_xen/decoder_model_uint8.onnx',
      'tokenizer.spm': '$_gh/flores200_sacrebleu_tokenizer.spm',
    },
  ),
  OfflineTransModel(
    id: 'nllb_600m_fp16',
    name: 'NLLB-600M FP16',
    desc: '200 زبان • float16 • بالاترین کیفیت',
    sizeMb: 1100, langCount: 200,
    langCodes: _nllbLangs,
    files: {
      'encoder.onnx': '$_xen/encoder_model_fp16.onnx',
      'decoder.onnx': '$_xen/decoder_model_fp16.onnx',
      'tokenizer.spm': '$_gh/flores200_sacrebleu_tokenizer.spm',
    },
  ),
];

// ── لیست زبان‌ها ──
const _nllbLangs = [
  'fa','en','ar','zh','ru','es','fr','de','tr','hi','ja','ko','it',
  'pt','nl','pl','uk','id','sv','no','da','fi','el','he','hu','ro',
  'cs','bg','th','vi','ms','bn','ur','sw','ka','sq','hr','sk','sl',
  'lt','lv','et','is','af','az','be','bs','cy','eu','gl','hy','ka',
  'km','lo','mk','mn','my','ne','si','tg','tt','uz',
];

const _m2mLangs = [
  'fa','en','ar','zh','ru','es','fr','de','tr','hi','ja','ko','it',
  'pt','nl','pl','uk','id','sv','no','da','fi','el','he','hu','ro',
  'cs','bg','th','vi','ms','bn','ur','sw','af','az','be','bs','cy',
  'eu','gl','hy','ka','km','lo','mk','mn','my','ne','si','tg','uz',
];

// ── نام زبان‌ها ──
const langNames = {
  'fa':'فارسی','en':'English','ar':'العربية','zh':'中文','ru':'Русский',
  'es':'Español','fr':'Français','de':'Deutsch','tr':'Türkçe','hi':'हिन्दी',
  'ja':'日本語','ko':'한국어','it':'Italiano','pt':'Português','nl':'Nederlands',
  'pl':'Polski','uk':'Українська','id':'Indonesia','sv':'Svenska','no':'Norsk',
  'da':'Dansk','fi':'Suomi','el':'Ελληνικά','he':'עברית','hu':'Magyar',
  'ro':'Română','cs':'Čeština','bg':'Български','th':'ภาษาไทย','vi':'Tiếng Việt',
  'ms':'Melayu','bn':'বাংলা','ur':'اردو','sw':'Kiswahili','ka':'ქართული',
};

// ── سرویس ترجمه آفلاین ──
class OfflineTranslationService {
  static const _kModel = 'offline_trans_model_v2';
  static const _kSrc = 'offline_trans_src_v2';
  static const _kTgt = 'offline_trans_tgt_v2';
  static const _kCh = MethodChannel('com.vezoo.player/offline_translator');
  static const _kModelsDir = '/storage/emulated/0/Download/Vezoo/OfflineModels';

  static Future<String> getSelectedModel() async =>
    (await SharedPreferences.getInstance()).getString(_kModel) ?? 'nllb_600m_q8';

  static Future<void> setSelectedModel(String id) async =>
    (await SharedPreferences.getInstance()).setString(_kModel, id);

  static Future<String> getSrcLang() async =>
    (await SharedPreferences.getInstance()).getString(_kSrc) ?? 'en';

  static Future<String> getTgtLang() async =>
    (await SharedPreferences.getInstance()).getString(_kTgt) ?? 'fa';

  static Future<void> setSrcLang(String l) async =>
    (await SharedPreferences.getInstance()).setString(_kSrc, l);

  static Future<void> setTgtLang(String l) async =>
    (await SharedPreferences.getInstance()).setString(_kTgt, l);

  // ── بررسی دانلود بودن مدل ──
  static bool isDownloaded(OfflineTransModel m) {
    final dir = Directory('$_kModelsDir/${m.id}');
    if (!dir.existsSync()) return false;
    for (final filename in m.files.keys) {
      if (!File('${dir.path}/$filename').existsSync()) return false;
    }
    return true;
  }

  // ── دانلود مدل ──
  static Stream<double> downloadModel(OfflineTransModel m) async* {
    final dir = Directory('$_kModelsDir/${m.id}');
    await dir.create(recursive: true);
    final files = m.files.entries.toList();
    for (int fi = 0; fi < files.length; fi++) {
      final entry = files[fi];
      final dest = File('${dir.path}/${entry.key}');
      if (dest.existsSync()) { yield (fi + 1) / files.length; continue; }
      // دانلود
      final req = await http.Client().send(http.Request('GET', Uri.parse(entry.value)));
      final total = req.contentLength ?? 0;
      int received = 0;
      final sink = dest.openWrite();
      await for (final chunk in req.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) yield (fi + received / total) / files.length;
      }
      await sink.close();
      yield (fi + 1) / files.length;
    }
  }

  // ── حذف مدل ──
  static Future<void> deleteModel(OfflineTransModel m) async {
    final dir = Directory('$_kModelsDir/${m.id}');
    if (dir.existsSync()) await dir.delete(recursive: true);
  }

  // ── ترجمه ──
  static Future<String> translate(
    String text, {String? src, String? tgt, String? modelId}) async {
    final m = modelId ?? await getSelectedModel();
    final s = src ?? await getSrcLang();
    final t = tgt ?? await getTgtLang();
    return await _kCh.invokeMethod<String>('translate', {
      'modelId': m,
      'modelsDir': _kModelsDir,
      'text': text,
      'src': s,
      'tgt': t,
    }) ?? text;
  }

  // ── ترجمه SRT کامل ──
  static Future<String> translateSrt(
    String srtContent, {
    String? src, String? tgt, String? modelId,
    void Function(double)? onProgress,
    void Function(String)? onChunk,
  }) async {
    final lines = srtContent.split('\n');
    final result = List<String>.from(lines);
    final textIndices = <int>[];

    for (int i = 0; i < lines.length; i++) {
      final l = lines[i].trim();
      if (l.isNotEmpty && !RegExp(r'^\d+$').hasMatch(l) && !l.contains('-->')) {
        textIndices.add(i);
      }
    }

    for (int i = 0; i < textIndices.length; i++) {
      final idx = textIndices[i];
      result[idx] = await translate(lines[idx].trim(), src: src, tgt: tgt, modelId: modelId);
      onProgress?.call((i + 1) / textIndices.length);
      onChunk?.call(result.join('\n'));
    }
    return result.join('\n');
  }

  // ── بکاپ تنظیمات ──
  static Future<Map<String, String>> exportSettings() async {
    return {
      'model': await getSelectedModel(),
      'src': await getSrcLang(),
      'tgt': await getTgtLang(),
    };
  }

  static Future<void> importSettings(Map<String, String> data) async {
    if (data['model'] != null) await setSelectedModel(data['model']!);
    if (data['src'] != null) await setSrcLang(data['src']!);
    if (data['tgt'] != null) await setTgtLang(data['tgt']!);
  }
}

