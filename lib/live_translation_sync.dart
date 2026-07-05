import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'subtitle_storage.dart';
import 'srt_translation_service.dart';

/// همگام‌سازی ترجمه با زیرنویس زنده — پردازش موازی
/// هر بار chunk جدیدی از live subtitle میاد، خطوط جدید موازی ترجمه میشن
class LiveTranslationSync {
  static const _maxConcurrent = 5; // ۵ request موازی // حداکثر درخواست موازی به Cloudflare
  static const _batchSize = 50; // ۵۰ خط در هر request    // خط در هر درخواست

  final String targetLangCode;
  bool _cancelled = false;

  // وضعیت داخلی
  final List<SrtEntry2> _origSegs = [];       // همه segment های اصلی
  final List<String?> _translated = [];        // نتیجه ترجمه (null = هنوز نشده)
  final Queue<int> _queue = Queue();           // batch های در انتظار (شروع index)
  int _running = 0;                            // batch های در حال اجرا
  String? _outputSrtPath;                      // مسیر SRT ترجمه‌شده
  void Function(String path)? onUpdated;       // callback پس از هر آپدیت

  LiveTranslationSync({required this.targetLangCode});

  void cancel() => _cancelled = true;

  /// هر بار که live subtitle آپدیت شد صدا زده میشه
  void onLiveSubUpdated(String liveSrtPath, String outputSrtPath) {
    if (_cancelled) return;
    _outputSrtPath = outputSrtPath;

    String content;
    try {
      content = File(liveSrtPath).readAsStringSync(encoding: utf8);
    } catch (_) { return; }

    final newSegs = SrtTranslationService.parseSrt(content);
    if (newSegs.isEmpty) return;

    // پیدا کردن segment های جدید (که قبلاً ندیده بودیم)
    final prevCount = _origSegs.length;
    if (newSegs.length <= prevCount) return;

    // اضافه کردن segment های جدید
    _origSegs.addAll(newSegs.sublist(prevCount));

    // پیدا کردن اندیس line های جدید
    int prevLineCount = 0;
    for (int i = 0; i < prevCount; i++) {
      prevLineCount += _origSegs[i].textLines.length;
    }
    int newLineCount = 0;
    for (int i = prevCount; i < _origSegs.length; i++) {
      newLineCount += _origSegs[i].textLines.length;
    }

    // اضافه کردن null به لیست نتایج
    _translated.addAll(List.filled(newLineCount, null));

    // اضافه کردن batch های جدید به صف
    // هر batch با اندیس seg شروع میشه
    for (int i = prevCount; i < _origSegs.length; i += _batchSize) {
      _queue.add(i);
    }

    // شروع worker های موازی
    _pump();
  }

  void _pump() {
    while (_running < _maxConcurrent && _queue.isNotEmpty && !_cancelled) {
      final startSegIdx = _queue.removeFirst();
      _processBatch(startSegIdx);
    }
  }

  Future<void> _processBatch(int startSegIdx) async {
    _running++;
    try {
      if (_cancelled) return;

      final endSegIdx = (startSegIdx + _batchSize).clamp(0, _origSegs.length);

      // جمع‌آوری متن‌های این batch
      final textLines = <String>[];
      final lineToTranslatedIdx = <int>[];
      int absLineIdx = _absLineIdx(startSegIdx);

      for (int i = startSegIdx; i < endSegIdx; i++) {
        for (final text in _origSegs[i].textLines) {
          textLines.add(text);
          lineToTranslatedIdx.add(absLineIdx++);
        }
      }

      if (textLines.isEmpty) return;

      // ارسال به Cloudflare
      final results = await _translateBatch(textLines);
      if (_cancelled) return;

      // ذخیره نتایج
      for (int j = 0; j < results.length && j < lineToTranslatedIdx.length; j++) {
        final idx = lineToTranslatedIdx[j];
        if (idx < _translated.length) _translated[idx] = results[j];
      }

      // ذخیره SRT ترجمه‌شده
      _saveCurrentState();

    } catch (e) {
      debugPrint('[LiveTransSync] batch error: $e');
    } finally {
      _running--;
      _pump(); // پردازش batch های بعدی از صف
    }
  }

  /// اندیس مطلق line در لیست _translated برای یه seg
  int _absLineIdx(int segIdx) {
    int idx = 0;
    for (int i = 0; i < segIdx && i < _origSegs.length; i++) {
      idx += _origSegs[i].textLines.length;
    }
    return idx;
  }

  /// ارسال یه batch به Cloudflare
  Future<List<String>> _translateBatch(List<String> lines) async {
    if (lines.isEmpty) return [];

    const workerBase = 'https://player.lastofanarchy.workers.dev';
    final body = jsonEncode({
      'lines': lines,
      'target_lang': kTranslateLangs[targetLangCode] ?? targetLangCode,
    });

    final client = HttpClient();
    try {
      final req = await client.postUrl(Uri.parse('$workerBase/translate-srt'));
      final bytes = utf8.encode(body);
      req.headers.set('Content-Type', 'application/json; charset=utf-8');
      req.headers.contentLength = bytes.length;
      req.add(bytes);
      final res = await req.close();
      final resBody = await res.transform(utf8.decoder).join();
      if (res.statusCode != 200) return lines; // fallback: اصل

      final data = jsonDecode(resBody) as Map<String, dynamic>;
      final result = (data['lines'] as List).map((e) => e.toString()).toList();
      return result.length == lines.length ? result : lines;
    } catch (_) {
      return lines; // در صورت خطا متن اصلی رو برگردون
    } finally {
      client.close();
    }
  }

  /// ذخیره وضعیت فعلی به SRT — ترجمه‌شده‌ها + اصل برای باقی
  void _saveCurrentState() {
    if (_outputSrtPath == null) return;
    try {
      final b = StringBuffer();
      int lineIdx = 0;
      int segNum = 1;

      for (final seg in _origSegs) {
        b.writeln(segNum++);
        b.writeln(seg.timestamp);
        for (final orig in seg.textLines) {
          final translated = lineIdx < _translated.length ? _translated[lineIdx] : null;
          b.writeln(translated ?? orig); // ترجمه اگه آماده‌ست، وگرنه اصل
          lineIdx++;
        }
        b.writeln();
      }

      if (_outputSrtPath == null) return;
      File(_outputSrtPath!).writeAsStringSync(b.toString(), encoding: utf8);
      onUpdated?.call(_outputSrtPath!);
    } catch (e) {
      debugPrint('[LiveTransSync] save error: $e');
    }
  }

  /// آیا همه ترجمه‌ها تموم شدن؟
  bool get isComplete => _translated.every((t) => t != null) && _queue.isEmpty && _running == 0;

  /// نام فایل خروجی برای یه SRT زنده
  static Future<String> outputPath(String videoPath, String targetLangCode) =>
    SubtitleStorage.liveTranslatedPath(videoPath, targetLangCode);
}

