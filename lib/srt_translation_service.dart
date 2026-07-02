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
  }) async {
    onStatus?.call('خواندن فایل...', 0.05);
    final content = await File(srtPath).readAsString(encoding: utf8);
    final entries = parseSrt(content);
    if (entries.isEmpty) throw Exception('فایل SRT خالی یا نامعتبر است');

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

    // ارسال به Worker
    final body = jsonEncode({
      'lines': allTextLines,
      'target_lang': kTranslateLangs[targetLangCode] ?? targetLangCode,
      if (sourceLangCode != null) 'source_lang': kTranslateLangs[sourceLangCode] ?? sourceLangCode,
    });

    onStatus?.call('در حال ترجمه...', 0.3);
    final client = HttpClient();
    String responseBody;
    try {
      final req = await client.postUrl(Uri.parse('$_workerBase/translate-srt'));
      req.headers.set('Content-Type', 'application/json');
      req.write(body);
      final res = await req.close();
      responseBody = await res.transform(utf8.decoder).join();
      if (res.statusCode != 200) throw Exception('خطای سرور (${res.statusCode}): $responseBody');
    } finally {
      client.close();
    }

    onStatus?.call('پردازش نتیجه...', 0.85);
    final data = jsonDecode(responseBody) as Map<String, dynamic>;
    final translatedLines = (data['lines'] as List).map((e) => e.toString()).toList();

    if (translatedLines.length != allTextLines.length) {
      throw Exception('تعداد خطوط ترجمه‌شده با اصل مطابقت ندارد');
    }

    // بازسازی entries با متن ترجمه‌شده
    int lineIdx = 0;
    final newEntries = entries.map((e) {
      final newTexts = e.textLines.map((_) => translatedLines[lineIdx++]).toList();
      return SrtEntry2(e.index, e.timestamp, newTexts);
    }).toList();

    // ذخیره کنار فایل اصلی
    final dir = p.dirname(srtPath);
    final base = p.basenameWithoutExtension(srtPath);
    final outPath = p.join(dir, '${base}_$targetLangCode.srt');
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

