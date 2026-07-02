import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'api_service.dart';

// ── زبان‌های پشتیبانی‌شده برای ترجمه (نام کامل برای Llama) ──
const kTranslateLangs = {
  'fa': 'Persian (Farsi)',
  'en': 'English',
  'ar': 'Arabic',
  'tr': 'Turkish',
  'fr': 'French',
  'de': 'German',
  'es': 'Spanish',
  'zh': 'Chinese (Simplified)',
  'ja': 'Japanese',
  'ru': 'Russian',
  'ko': 'Korean',
  'it': 'Italian',
  'pt': 'Portuguese',
  'nl': 'Dutch',
  'pl': 'Polish',
  'uk': 'Ukrainian',
  'hi': 'Hindi',
  'ur': 'Urdu',
  'he': 'Hebrew',
  'sv': 'Swedish',
  'da': 'Danish',
  'fi': 'Finnish',
  'no': 'Norwegian',
};

// ── نمایش فارسی نام زبان‌ها برای منو ──
const kTranslateLangDisplay = {
  'fa': 'فارسی',
  'en': 'English',
  'ar': 'عربی',
  'tr': 'ترکی',
  'fr': 'فرانسه',
  'de': 'آلمانی',
  'es': 'اسپانیایی',
  'zh': 'چینی',
  'ja': 'ژاپنی',
  'ru': 'روسی',
  'ko': 'کره‌ای',
  'it': 'ایتالیایی',
  'pt': 'پرتغالی',
  'nl': 'هلندی',
  'pl': 'لهستانی',
  'uk': 'اوکراینی',
  'hi': 'هندی',
  'ur': 'اردو',
  'he': 'عبری',
  'sv': 'سوئدی',
  'da': 'دانمارکی',
  'fi': 'فنلاندی',
  'no': 'نروژی',
};

class SrtEntry2 {
  final int index;
  final String timestamp; // خط timestamp دست‌نخورده
  final List<String> textLines;
  SrtEntry2(this.index, this.timestamp, this.textLines);
}

class SrtTranslationService {
  static const _workerBase = 'https://player.lastofanarchy.workers.dev';
  static bool _cancelled = false;

  static void cancel() => _cancelled = true;

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
    onStatus?.call('خواندن فایل...', 0.05);

    // ── محدودیت حجم — بیشتر از ۳۰۰۰ خط قابل پردازش نیست ──
    // دلیل: سهمیه رایگان Cloudflare Workers AI روزانه محدوده
    final content = await File(srtPath).readAsString(encoding: utf8);
    final entries = parseSrt(content);
    if (entries.isEmpty) throw Exception('فایل SRT خالی یا نامعتبر است');

    // چک حجم — حداکثر ۳۰۰۰ خط (معادل ~۳ ساعت فیلم)
    final totalTextLines = entries.fold(0, (s, e) => s + e.textLines.length);
    if (totalTextLines > 3000) {
      throw Exception(
        'متأسفم، این فایل زیرنویس خیلی بزرگ است ($totalTextLines خط).\n\n'
        'سرویس ترجمه ما از پلن رایگان Cloudflare استفاده می‌کند که محدودیت روزانه دارد '
        'و از فایل‌های بیشتر از ۳۰۰۰ خط پشتیبانی نمی‌کند.\n\n'
        'پیشنهاد: از ابزارهای ترجمه دیگری مانند Google Translate، DeepL یا '
        'اپلیکیشن‌های ترجمه SRT آنلاین استفاده کنید.'
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

    onStatus?.call('ارسال به سرور...', 0.15);
    debugPrint('[SrtTranslate] ${allTextLines.length} lines → ${kTranslateLangs[targetLangCode]}');

    // ── Client-side batching: هر request فقط ۳۰ خط ──
    // این از timeout شدن Worker جلوگیری می‌کنه
    const batchSize = 30;
    final translatedLines = <String>[];
    final totalBatches = (allTextLines.length / batchSize).ceil();

    for (int b = 0; b < totalBatches; b++) {
      if (_cancelled) throw Exception('لغو شد');

      final start = b * batchSize;
      final end = (start + batchSize).clamp(0, allTextLines.length);
      final batchLines = allTextLines.sublist(start, end);

      final progress = 0.2 + (b / totalBatches) * 0.65;
      onStatus?.call('ترجمه تکه ${b + 1} از $totalBatches...', progress);

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
              'سرویس ترجمه امروز به محدودیت رسیده است.\n\n'
              'سرویس ما از پلن رایگان Cloudflare AI استفاده می‌کند که سهمیه روزانه دارد. '
              'فردا دوباره امتحان کنید.\n\n'
              'یا از ابزارهای جایگزین مانند Google Translate یا DeepL استفاده کنید.'
            );
          }
          throw Exception('خطای سرور (${res.statusCode}): $responseBody');
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
      // اگه لغو شد یا خطا بود، تا اینجا ذخیره شده
      final partialDir = p.dirname(srtPath);
      final partialBase = p.basenameWithoutExtension(srtPath);
      final partialPath = p.join(partialDir, '${partialBase}_$targetLangCode.srt');

      // بازسازی entries تا اینجا با ترجمه + بقیه با متن اصلی
      int lineIdx2 = 0;
      final partialEntries = entries.map((e) {
        final newTexts = e.textLines.map((orig) {
          if (lineIdx2 < translatedLines.length) return translatedLines[lineIdx2++];
          lineIdx2++;
          return orig; // هنوز ترجمه نشده → اصل
        }).toList();
        return SrtEntry2(e.index, e.timestamp, newTexts);
      }).toList();
      await File(partialPath).writeAsString(buildSrt(partialEntries), encoding: utf8);
      onSrtUpdated?.call(partialPath); // اپلای روی پلیر (اختیاری)
    }

    if (translatedLines.length != allTextLines.length) {
      throw Exception('تعداد خطوط ترجمه‌شده با اصل مطابقت ندارد');
    }

    // ── ذخیره نهایی کامل ──
    final dir = p.dirname(srtPath);
    final base = p.basenameWithoutExtension(srtPath);
    final outPath = p.join(dir, '${base}_$targetLangCode.srt');
    int lineIdx = 0;
    final newEntries = entries.map((e) {
      final newTexts = e.textLines.map((_) => translatedLines[lineIdx++]).toList();
      return SrtEntry2(e.index, e.timestamp, newTexts);
    }).toList();
    await File(outPath).writeAsString(buildSrt(newEntries), encoding: utf8);

    onStatus?.call('✓ ذخیره شد', 1.0);
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

