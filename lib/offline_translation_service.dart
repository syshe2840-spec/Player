import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:dart_sentencepiece_tokenizer/dart_sentencepiece_tokenizer.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// ── مدل‌های ترجمه آفلاین ──
class OfflineTransModel {
  final String id, name, desc;
  final int sizeMb, langCount;
  final List<String> langCodes;
  final Map<String, String> files;

  const OfflineTransModel({
    required this.id, required this.name, required this.desc,
    required this.sizeMb, required this.langCount,
    required this.langCodes, required this.files,
  });
}

const _gh = 'https://github.com/niedev/RTranslator/releases/download/2.0.0';
const _xen = 'https://huggingface.co/Xenova/nllb-200-distilled-600M/resolve/main/onnx';

final kOfflineModels = [
  OfflineTransModel(
    id: 'nllb_rtranslator',
    name: 'NLLB-600M (RTranslator)',
    desc: '200 زبان • int8 • بهینه شده • توصیه شده',
    sizeMb: 400, langCount: 200,
    langCodes: _nllbLangs,
    files: {
      'encoder.onnx':            'https://github.com/niedev/RTranslator/releases/download/2.0.0/NLLB_encoder.onnx',
      'decoder.onnx':            'https://github.com/niedev/RTranslator/releases/download/2.0.0/NLLB_decoder.onnx',
      'cache_init.onnx':         'https://github.com/niedev/RTranslator/releases/download/2.0.0/NLLB_cache_initializer.onnx',
      'embed_lm_head.onnx':      'https://github.com/niedev/RTranslator/releases/download/2.0.0/NLLB_embed_and_lm_head.onnx',
      'tokenizer.spm':           'https://github.com/niedev/RTranslator/releases/download/2.0.0/flores200_sacrebleu_tokenizer.spm',
    },
  ),
  OfflineTransModel(
    id: 'nllb_600m_xenova_q8',
    name: 'NLLB-600M Xenova Q8',
    desc: '200 زبان • int8 • نسخه آلترناتیو',
    sizeMb: 350, langCount: 200,
    langCodes: _nllbLangs,
    files: {
      'encoder.onnx':   'https://huggingface.co/Xenova/nllb-200-distilled-600M/resolve/main/onnx/encoder_model_quantized.onnx',
      'decoder.onnx':   'https://huggingface.co/Xenova/nllb-200-distilled-600M/resolve/main/onnx/decoder_model_quantized.onnx',
      'tokenizer.spm':  'https://github.com/niedev/RTranslator/releases/download/2.0.0/flores200_sacrebleu_tokenizer.spm',
    },
  ),
  OfflineTransModel(
    id: 'nllb_600m_xenova',
    name: 'NLLB-600M Xenova FP32',
    desc: '200 زبان • float32 • بالاترین دقت',
    sizeMb: 1200, langCount: 200,
    langCodes: _nllbLangs,
    files: {
      'encoder.onnx':   'https://huggingface.co/Xenova/nllb-200-distilled-600M/resolve/main/onnx/encoder_model.onnx',
      'decoder.onnx':   'https://huggingface.co/Xenova/nllb-200-distilled-600M/resolve/main/onnx/decoder_model.onnx',
      'tokenizer.spm':  'https://github.com/niedev/RTranslator/releases/download/2.0.0/flores200_sacrebleu_tokenizer.spm',
    },
  ),
];

// زبان‌های NLLB Flores-200
const _floresMap = {
  'fa':'fas_Arab','en':'eng_Latn','ar':'arb_Arab','zh':'zho_Hans',
  'ru':'rus_Cyrl','es':'spa_Latn','fr':'fra_Latn','de':'deu_Latn',
  'tr':'tur_Latn','hi':'hin_Deva','ja':'jpn_Jpan','ko':'kor_Hang',
  'it':'ita_Latn','pt':'por_Latn','nl':'nld_Latn','pl':'pol_Latn',
  'uk':'ukr_Cyrl','id':'ind_Latn','sv':'swe_Latn','no':'nob_Latn',
  'da':'dan_Latn','fi':'fin_Latn','el':'ell_Grek','he':'heb_Hebr',
  'hu':'hun_Latn','ro':'ron_Latn','cs':'ces_Latn','bg':'bul_Cyrl',
  'th':'tha_Thai','vi':'vie_Latn','ms':'zsm_Latn','bn':'ben_Beng',
  'ur':'urd_Arab','sw':'swh_Latn','ka':'kat_Geor',
};

const _nllbLangs = ['fa','en','ar','zh','ru','es','fr','de','tr','hi',
  'ja','ko','it','pt','nl','pl','uk','id','sv','no','da','fi','el',
  'he','hu','ro','cs','bg','th','vi','ms','bn','ur','sw','ka'];

const langNames = {
  'fa':'فارسی','en':'English','ar':'العربية','zh':'中文','ru':'Русский',
  'es':'Español','fr':'Français','de':'Deutsch','tr':'Türkçe','hi':'हिन्दी',
  'ja':'日本語','ko':'한국어','it':'Italiano','pt':'Português','nl':'Nederlands',
  'pl':'Polski','uk':'Українська','id':'Indonesia','sv':'Svenska','no':'Norsk',
  'da':'Dansk','fi':'Suomi','el':'Ελληνικά','he':'עברית','hu':'Magyar',
  'ro':'Română','cs':'Čeština','bg':'Български','th':'ภาษาไทย','vi':'Tiếng Việt',
  'ms':'Melayu','bn':'বাংলা','ur':'اردو','sw':'Kiswahili','ka':'ქართული',
};

// ── سرویس ──
class OfflineTranslationService {
  static const _kModel = 'offline_trans_model_v3';
  static const _kSrc   = 'offline_trans_src_v3';
  static const _kTgt   = 'offline_trans_tgt_v3';
  static const _kDir   = '/storage/emulated/0/Download/Vezoo/OfflineModels';

  static OrtSession? _encoder, _decoder, _cacheInit, _embedLmHead;
  static SentencePieceTokenizer? _tokenizer;
  static String? _loadedModelId;
  static String? _lastError;
  static bool _isRTranslator = false;
  static final _ort = OnnxRuntime();

  static Future<String> getSelectedModel() async =>
    (await SharedPreferences.getInstance()).getString(_kModel) ?? 'nllb_600m_q8';
  static Future<void> setSelectedModel(String v) async =>
    (await SharedPreferences.getInstance()).setString(_kModel, v);
  static Future<String> getSrcLang() async =>
    (await SharedPreferences.getInstance()).getString(_kSrc) ?? 'en';
  static Future<String> getTgtLang() async =>
    (await SharedPreferences.getInstance()).getString(_kTgt) ?? 'fa';
  static Future<void> setSrcLang(String v) async =>
    (await SharedPreferences.getInstance()).setString(_kSrc, v);
  static Future<void> setTgtLang(String v) async =>
    (await SharedPreferences.getInstance()).setString(_kTgt, v);

  // ── بررسی دانلود ──
  static bool isDownloaded(OfflineTransModel m) {
    final dir = Directory('$_kDir/${m.id}');
    if (!dir.existsSync()) return false;
    return m.files.keys.every((f) => File('${dir.path}/$f').existsSync());
  }

  // ── دانلود مدل ──
  static Stream<double> downloadModel(OfflineTransModel m) async* {
    final dir = Directory('$_kDir/${m.id}');
    await dir.create(recursive: true);
    final files = m.files.entries.toList();
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(minutes: 30),
      followRedirects: true,
      maxRedirects: 10,
      headers: {'User-Agent': 'Mozilla/5.0 Vezoo'},
    ));
    for (int fi = 0; fi < files.length; fi++) {
      final entry = files[fi];
      final dest = File('${dir.path}/${entry.key}');
      if (dest.existsSync() && dest.lengthSync() > 10 * 1024) {
        yield (fi + 1) / files.length;
        continue;
      }
      if (dest.existsSync()) await dest.delete();
      // نشون دادن progress تخمینی حین دانلود
      double p = 0;
      final completer = Completer<void>();
      dio.download(
        entry.value,
        dest.path,
        onReceiveProgress: (rec, tot) {
          p = tot > 0 ? rec / tot : 0;
        },
      ).then((_) => completer.complete()).catchError((e) => completer.completeError(e));
      while (!completer.isCompleted) {
        yield (fi + p) / files.length;
        await Future.delayed(const Duration(milliseconds: 500));
      }
      await completer.future;
      yield (fi + 1) / files.length;
    }
    dio.close();
  }

    static Future<bool> _loadModel(String modelId) async {
    if (_loadedModelId == modelId) return true;
    final dir = '$_kDir/$modelId';
    if (!Directory(dir).existsSync()) return false;
    try {
      await _encoder?.close(); await _decoder?.close();
      await _cacheInit?.close(); await _embedLmHead?.close();
      _encoder = await _ort.createSession('$dir/encoder.onnx');
      _decoder = await _ort.createSession('$dir/decoder.onnx');
      // معماری ۴ فایلی RTranslator
      final cacheFile = File('$dir/cache_init.onnx');
      final embedFile = File('$dir/embed_lm_head.onnx');
      _isRTranslator = cacheFile.existsSync() && embedFile.existsSync();
      if (_isRTranslator) {
        _cacheInit = await _ort.createSession('$dir/cache_init.onnx');
        _embedLmHead = await _ort.createSession('$dir/embed_lm_head.onnx');
      }
      _tokenizer = await SentencePieceTokenizer.fromModelFile('$dir/tokenizer.spm');
      _loadedModelId = modelId;
      return true;
    } catch (e) {
      _lastError = e.toString();
      return false;
    }
  }

  // ── ترجمه ──
  static Future<String> translate(String text,
      {String? src, String? tgt, String? modelId}) async {
    final m = modelId ?? await getSelectedModel();
    final s = src ?? await getSrcLang();
    final t = tgt ?? await getTgtLang();
    if (!await _loadModel(m)) return '[LOAD_FAIL: ${_lastError ?? "unknown"}]';

    final enc = _encoder!; final dec = _decoder!; final tok = _tokenizer!;
    final srcFlores = _floresMap[s] ?? 'eng_Latn';
    final tgtFlores = _floresMap[t] ?? 'fas_Arab';

    try {
      final encoded = tok.encode('__${srcFlores}__ $text');
      final inputIds = Int64List.fromList(encoded.ids.map((e) => e.toInt()).toList());
      final attMask  = Int64List.fromList(List.filled(inputIds.length, 1));

      // Encode
      final inputIdsList = inputIds.toList();
      final attMaskList  = attMask.toList();
      final encInputs = {
        'input_ids':      await OrtValue.fromList(inputIdsList, [1, inputIds.length]),
        'attention_mask': await OrtValue.fromList(attMaskList,  [1, attMask.length]),
      };
      final encOut = await enc.run(encInputs);
      for (final v in encInputs.values) v.dispose();
      final encHidden = encOut['last_hidden_state']!;
      debugPrint('STEP3: encoder done, keys=\${encOut.keys.toList()}');

      // Greedy decode
      final tgtLangTok = tok.encode('__${tgtFlores}__').ids.first;
      final generated = <int>[tgtLangTok];
      for (int step = 0; step < 256; step++) {
        final decIds = Int64List.fromList(generated);
        final decInputs = {
          'input_ids':              await OrtValue.fromList(decIds.toList(), [1, decIds.length]),
          'attention_mask':         await OrtValue.fromList(attMaskList, [1, attMask.length]),
          'encoder_hidden_states':  encHidden,
        };
        final decOut = await dec.run(decInputs);
        decInputs['input_ids']?.dispose();
        decInputs['attention_mask']?.dispose();
        final logitsList = await decOut['logits']!.asList() as List;
        final logits = (logitsList.last as List);
        final nextTok = logits.indexOf(logits.reduce((a, b) => a > b ? a : b));
        if (nextTok == tok.encode('</s>').ids.firstOrNull) break;
        generated.add(nextTok);
      }
      debugPrint('STEP5: generated=\${generated.take(10).toList()}');
      final decoded = tok.decode(generated.skip(1).toList());
      if (decoded.isEmpty) return "[EMPTY_DECODE] gen=\${generated.length}tok";
      return decoded;
    } catch (e) {
      return '[ERR:\${e.toString().substring(0, e.toString().length.clamp(0, 60))}]';
    }
  }

  // ── ترجمه SRT ──
  static Future<String> translateSrt(String srtContent,
      {String? src, String? tgt, String? modelId,
       void Function(double)? onProgress,
       void Function(String)? onChunk}) async {
    final lines = srtContent.split('\n');
    final result = List<String>.from(lines);
    final textIdx = <int>[];
    for (int i = 0; i < lines.length; i++) {
      final l = lines[i].trim();
      if (l.isNotEmpty && !RegExp(r'^\d+$').hasMatch(l) && !l.contains('-->'))
        textIdx.add(i);
    }
    for (int i = 0; i < textIdx.length; i++) {
      final idx = textIdx[i];
      result[idx] = await translate(lines[idx].trim(), src: src, tgt: tgt, modelId: modelId);
      onProgress?.call((i + 1) / textIdx.length);
      onChunk?.call(result.join('\n'));
    }
    return result.join('\n');
  }

  // ── بکاپ / ایمپورت ──
  static Future<Map<String, String>> exportSettings() async => {
    'model': await getSelectedModel(),
    'src': await getSrcLang(),
    'tgt': await getTgtLang(),
  };

  static Future<void> importSettings(Map<String, String> data) async {
    if (data['model'] != null) await setSelectedModel(data['model']!);
    if (data['src']   != null) await setSrcLang(data['src']!);
    if (data['tgt']   != null) await setTgtLang(data['tgt']!);
  }
}

