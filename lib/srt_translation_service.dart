import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'api_service.dart';
import 'whisper_service.dart' show WhisperService;
import 'subtitle_storage.dart';
import 'l10n.dart';

// ── زبان‌های پشتیبانی‌شده برای ترجمه (نام کامل برای Llama) ──
const kTranslateLangs = {
  // ── پرکاربرد ──
  'fa': 'Persian (Farsi)', 'en': 'English', 'ar': 'Arabic', 'zh': 'Chinese (Simplified)',
  'zh-tw': 'Chinese (Traditional)', 'ru': 'Russian', 'es': 'Spanish', 'fr': 'French',
  'de': 'German', 'tr': 'Turkish', 'hi': 'Hindi', 'ja': 'Japanese', 'ko': 'Korean',
  'it': 'Italian', 'pt': 'Portuguese', 'nl': 'Dutch',
  // ── اروپایی ──
  'pl': 'Polish', 'uk': 'Ukrainian', 'sv': 'Swedish', 'da': 'Danish', 'fi': 'Finnish',
  'no': 'Norwegian', 'cs': 'Czech', 'ro': 'Romanian', 'hu': 'Hungarian', 'el': 'Greek',
  'bg': 'Bulgarian', 'hr': 'Croatian', 'sk': 'Slovak', 'lt': 'Lithuanian',
  'lv': 'Latvian', 'sl': 'Slovenian', 'et': 'Estonian', 'sr': 'Serbian',
  'be': 'Belarusian', 'mk': 'Macedonian', 'bs': 'Bosnian', 'sq': 'Albanian',
  'is': 'Icelandic', 'mt': 'Maltese', 'cy': 'Welsh', 'ga': 'Irish',
  'eu': 'Basque', 'ca': 'Catalan', 'gl': 'Galician', 'af': 'Afrikaans',
  // ── خاورمیانه و آسیای مرکزی ──
  'he': 'Hebrew', 'ur': 'Urdu', 'ps': 'Pashto', 'ku': 'Kurdish',
  'az': 'Azerbaijani', 'ka': 'Georgian', 'hy': 'Armenian', 'kk': 'Kazakh',
  'uz': 'Uzbek', 'tk': 'Turkmen', 'ky': 'Kyrgyz', 'tg': 'Tajik', 'mn': 'Mongolian',
  // ── آسیای جنوبی ──
  'bn': 'Bengali', 'pa': 'Punjabi', 'gu': 'Gujarati', 'mr': 'Marathi',
  'ta': 'Tamil', 'te': 'Telugu', 'kn': 'Kannada', 'ml': 'Malayalam',
  'si': 'Sinhala', 'ne': 'Nepali',
  // ── آسیای جنوب شرقی ──
  'th': 'Thai', 'vi': 'Vietnamese', 'id': 'Indonesian', 'ms': 'Malay',
  'tl': 'Filipino', 'km': 'Khmer', 'lo': 'Lao', 'my': 'Burmese',
  // ── آفریقا ──
  'sw': 'Swahili', 'am': 'Amharic', 'so': 'Somali', 'ha': 'Hausa',
  'yo': 'Yoruba', 'ig': 'Igbo', 'sn': 'Shona', 'st': 'Sesotho', 'rw': 'Kinyarwanda',
  // ── آمریکا و اقیانوسیه ──
  'ht': 'Haitian Creole', 'mi': 'Maori', 'haw': 'Hawaiian',
  // ── دیگر ──
  'yi': 'Yiddish', 'eo': 'Esperanto', 'la': 'Latin',
};

// ── نمایش فارسی نام زبان‌ها برای منو ──
const kTranslateLangDisplay = {
  'fa':'فارسی','en':'English','ar':'العربية','zh':'中文 (ساده)','zh-tw':'中文 (سنتی)',
  'ru':'Русский','es':'Español','fr':'Français','de':'Deutsch','tr':'Türkçe',
  'hi':'हिन्दी','ja':'日本語','ko':'한국어','it':'Italiano','pt':'Português',
  'nl':'Nederlands','pl':'Polski','uk':'Українська','sv':'Svenska','da':'Dansk',
  'fi':'Suomi','no':'Norsk','cs':'Čeština','ro':'Română','hu':'Magyar',
  'el':'Ελληνικά','bg':'Български','hr':'Hrvatski','sk':'Slovenčina','lt':'Lietuvių',
  'lv':'Latviešu','sl':'Slovenščina','et':'Eesti','sr':'Srpski','be':'Беларуская',
  'mk':'Македонски','bs':'Bosanski','sq':'Shqip','is':'Íslenska','mt':'Malti',
  'cy':'Cymraeg','ga':'Gaeilge','eu':'Euskara','ca':'Català','gl':'Galego',
  'af':'Afrikaans','he':'עברית','ur':'اردو','ps':'پښتو','ku':'Kurdî',
  'az':'Azərbaycan','ka':'ქართული','hy':'Հայերեն','kk':'Қазақ','uz':'Ozbek',
  'tk':'Türkmen','ky':'Кыргызча','tg':'Тоҷикӣ','mn':'Монгол',
  'bn':'বাংলা','pa':'ਪੰਜਾਬੀ','gu':'ગુજરાતી','mr':'मराठी','ta':'தமிழ்',
  'te':'తెలుగు','kn':'ಕನ್ನಡ','ml':'മലയാളം','si':'සිංහල','ne':'नेपाली',
  'th':'ภาษาไทย','vi':'Tiếng Việt','id':'Indonesia','ms':'Melayu',
  'tl':'Filipino','km':'ភាសាខ្មែរ','lo':'ລາວ','my':'မြန်မာ',
  'sw':'Kiswahili','am':'አማርኛ','so':'Soomaali','ha':'Hausa',
  'yo':'Yorùbá','ig':'Igbo','sn':'Shona','st':'Sesotho','rw':'Kinyarwanda',
  'ht':'Kreyòl','mi':'Māori','haw':'ʻŌlelo Hawaiʻi',
  'yi':'ייִדיש','eo':'Esperanto','la':'Latina',
};

class SrtEntry2 {
  final int index;
  final String timestamp; // خط timestamp دست‌نخورده
  final List<String> textLines;
  SrtEntry2(this.index, this.timestamp, this.textLines);
}

/// وضعیت زنده برای badge پلیر
class SrtTranslationServiceStatus {
  static String lastStatus = '';
  static String targetLang = '';
  static int batchDone = 0;
  static int batchTotal = 0;
  static final sw = Stopwatch();
  static final notifier = ValueNotifier<int>(0);

  static void reset() {
    lastStatus=''; batchDone=0; batchTotal=0; sw.reset(); sw.start();
  }
  static void update(String s) { lastStatus = s; notifier.value++; }
  static void setBatch(int done, int total) { batchDone=done; batchTotal=total; notifier.value++; }
}

class SrtTranslationService {
  static const _workerBase = 'https://player.lastofanarchy.workers.dev';
  static bool _cancelled = false;
  static bool isRunning = false; // آیا ترجمه در پس‌زمینه در حال اجراست

  static void cancel() { _cancelled = true; }

  /// شروع ترجمه در پس‌زمینه — بلافاصله برمی‌گرده
  /// نتیجه از طریق onSrtUpdated و onDone دریافت می‌شه
  static void startBackground({
    required String srtPath,
    required String targetLangCode,
    required void Function(String srtPath) onDone,
    void Function(String partialPath)? onSrtUpdated,
    void Function(String error)? onError,
  }) {
    _cancelled = false;
    isRunning = true;
    SrtTranslationServiceStatus.reset();
    SrtTranslationServiceStatus.targetLang = targetLangCode;

    // cancel hook — notification لغو → ترجمه هم لغو
    WhisperService.onExternalCancel = () => cancel();

    // شروع notification (EventChannel cancel رو هم راه‌اندازی می‌کنه)
    WhisperService.showProgressNotification(L.translateSubtitle);

    translateSrtFile(
      srtPath: srtPath,
      targetLangCode: targetLangCode,
      onSrtUpdated: onSrtUpdated,
      onStatus: (s, p) {
        SrtTranslationServiceStatus.update(s);
        WhisperService.updateProgressNotification(s, p);
      },
    ).then((path) {
      isRunning = false;
      WhisperService.onExternalCancel = null;
      WhisperService.hideProgressNotification();
      onDone(path);
    }).catchError((e) {
      isRunning = false;
      WhisperService.onExternalCancel = null;
      if (!_cancelled) {
        // نشون دادن خطا در notification و بعد ۳ ثانیه بستن
        WhisperService.updateProgressNotification(L.errorMsg(e), 0);
        Future.delayed(const Duration(seconds: 3), () {
          WhisperService.hideProgressNotification();
        });
        onError?.call('$e');
      } else {
        WhisperService.hideProgressNotification();
      }
    });
  }

  /// پارس SRT و جدا کردن متن از timestamp/index
  static List<SrtEntry2> parseSrt(String content) {
    final entries = <SrtEntry2>[];
    final blocks = content.trim().split(RegExp(r'\n\s*\n'));
    for (final block in blocks) {
      final lines = block.trim().split('\n');
      if (lines.length < 2) continue;
      int? idx;
      String? ts;
      final texts = <String>[];
      for (final line in lines) {
        if (idx == null && int.tryParse(line.trim()) != null) {
          idx = int.tryParse(line.trim());
        } else if (ts == null && line.contains('-->')) {
          ts = line.trim();
        } else if (ts != null) {
          texts.add(line);
        }
      }
      if (idx != null && ts != null && texts.isNotEmpty) {
        entries.add(SrtEntry2(idx, ts, texts));
      }
    }
    return entries;
  }

  /// بازسازی SRT از entries (با متن ترجمه‌شده)
  static String buildSrt(List<SrtEntry2> entries) {
    final b = StringBuffer();
    for (int i = 0; i < entries.length; i++) {
      final e = entries[i];
      b.writeln(e.index);
      b.writeln(e.timestamp);
      for (final t in e.textLines) b.writeln(t);
      b.writeln();
    }
    return b.toString();
  }

  /// ترجمه فایل SRT — آپلود متن‌ها به Cloudflare، دریافت ترجمه، ذخیره
  static Future<String> translateSrtFile({
    required String srtPath,
    required String targetLangCode,
    String? sourceLangCode,
    void Function(String status, double progress)? onStatus,
    void Function(String partialPath)? onSrtUpdated, // بعد از هر batch فراخوانی میشه
  }) async {
    _cancelled = false;
    onStatus?.call(L.loading, 0.05);

    // ── محدودیت حجم — بیشتر از ۳۰۰۰ خط قابل پردازش نیست ──
    // دلیل: سهمیه رایگان Cloudflare Workers AI روزانه محدوده
    final content = await File(srtPath).readAsString(encoding: utf8);
    final entries = parseSrt(content);
    if (entries.isEmpty) throw Exception('Empty SRT file');

    // چک حجم — حداکثر ۳۰۰۰ خط (معادل ~۳ ساعت فیلم)
    final totalTextLines = entries.fold(0, (s, e) => s + e.textLines.length);
    if (totalTextLines > 3000) {
      throw Exception(
        'File too large ($totalTextLines lines). Max 3000 lines.'
      );
    }

    // جمع‌آوری همه خطوط متن (بدون timestamp و index)
    final allTextLines = <String>[];
    final lineMap = <int>[]; // index in allTextLines → entry index + line index
    for (int i = 0; i < entries.length; i++) {
      for (int j = 0; j < entries[i].textLines.length; j++) {
        allTextLines.add(entries[i].textLines[j]);
        lineMap.add(i * 1000 + j); // pack entry+line index
      }
    }

    onStatus?.call(L.processing, 0.15);
    debugPrint('[SrtTranslate] ${allTextLines.length} lines → ${kTranslateLangs[targetLangCode]}');

    // ── Client-side batching: هر request فقط ۳۰ خط ──
    // این از timeout شدن Worker جلوگیری می‌کنه
    const batchSize = 50; // بزرگتر = کمتر رفت و برگشت
    final translatedLines = <String>[];
    final totalBatches = (allTextLines.length / batchSize).ceil();

    for (int b = 0; b < totalBatches; b++) {
      if (_cancelled) throw Exception(L.cancelled);

      final start = b * batchSize;
      final end = (start + batchSize).clamp(0, allTextLines.length);
      final batchLines = allTextLines.sublist(start, end);

      final progress = 0.2 + (b / totalBatches) * 0.65;
      onStatus?.call('Translating ${b+1}/$totalBatches...', progress);
      SrtTranslationServiceStatus.setBatch(b + 1, totalBatches);

      final body = jsonEncode({
        'lines': batchLines,
        'target_lang': kTranslateLangs[targetLangCode] ?? targetLangCode,
        if (sourceLangCode != null) 'source_lang': kTranslateLangs[sourceLangCode] ?? sourceLangCode,
      });

      final client = HttpClient();
      String responseBody;
      try {
        final req = await client.postUrl(Uri.parse('$_workerBase/translate-srt'));
        final bodyBytes = utf8.encode(body);
        req.headers.set('Content-Type', 'application/json; charset=utf-8');
        req.headers.contentLength = bodyBytes.length;
        req.add(bodyBytes);
        final res = await req.close();
        responseBody = await res.transform(utf8.decoder).join();
        if (res.statusCode != 200) {
          // چک محدودیت روزانه Cloudflare
          if (res.statusCode == 429 || responseBody.contains('Too Many Requests') ||
              responseBody.contains('rate limit') || responseBody.contains('quota')) {
            throw Exception(
              'Daily translation limit reached. Try again tomorrow.'
            );
          }
          throw Exception('Server error (${res.statusCode}): $responseBody');
        }
      } finally {
        client.close();
      }

      final data = jsonDecode(responseBody) as Map<String, dynamic>;
      final batchResult = (data['lines'] as List).map((e) => e.toString()).toList();
      if (batchResult.length != batchLines.length) {
        translatedLines.addAll(batchLines);
      } else {
        translatedLines.addAll(batchResult);
      }

      // ── ذخیره تدریجی بعد از هر batch ──
      final partialPath = await SubtitleStorage.translatedPath(srtPath, targetLangCode);

      // بازسازی entries تا اینجا با ترجمه + بقیه با متن اصلی
      int lineIdx2 = 0;
      final partialEntries = entries.map((e) {
        final newTexts = e.textLines.map((orig) {
          if (lineIdx2 < translatedLines.length) return translatedLines[lineIdx2++];
          lineIdx2++;
          return orig;
        }).toList();
        return SrtEntry2(e.index, e.timestamp, newTexts);
      }).toList();
      await File(partialPath).writeAsString(buildSrt(partialEntries), encoding: utf8);
      onSrtUpdated?.call(partialPath);
    }

    if (translatedLines.length != allTextLines.length) {
      throw Exception('Translation line count mismatch');
    }

    // ── ذخیره نهایی کامل ──
    final outPath = await SubtitleStorage.translatedPath(srtPath, targetLangCode);
    int lineIdx = 0;
    final newEntries = entries.map((e) {
      final newTexts = e.textLines.map((_) => translatedLines[lineIdx++]).toList();
      return SrtEntry2(e.index, e.timestamp, newTexts);
    }).toList();
    await File(outPath).writeAsString(buildSrt(newEntries), encoding: utf8);

    onStatus?.call(L.saved, 1.0);
    return outPath;
  }

  /// ترجمه مستقیم از محتوای SRT (بدون فایل)
  static Future<String> translateSrtContent({
    required String content,
    required String targetLangCode,
    String? sourceLangCode,
    void Function(String status, double progress)? onStatus,
  }) async {
    // یه فایل موقت بساز و برگشت بده
    final tmp = File('${Directory.systemTemp.path}/tmp_translate.srt');
    await tmp.writeAsString(content, encoding: utf8);
    return translateSrtFile(
      srtPath: tmp.path,
      targetLangCode: targetLangCode,
      sourceLangCode: sourceLangCode,
      onStatus: onStatus,
    );
  }
}
