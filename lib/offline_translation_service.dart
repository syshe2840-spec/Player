import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── مدل‌های ترجمه آفلاین ──
class OfflineTransModel {
  final String id, name, description;
  final int langCount;
  final String size;
  final List<TranslateLanguage> languages;

  const OfflineTransModel({
    required this.id,
    required this.name,
    required this.description,
    required this.langCount,
    required this.size,
    required this.languages,
  });
}

// ── ۵ مدل آفلاین ──
final kOfflineModels = [
  OfflineTransModel(
    id: 'mlkit_lite',
    name: 'Lite — ۱۰ زبان',
    description: 'سبک‌ترین مدل — زبان‌های پرکاربرد',
    langCount: 10,
    size: '~۳۰۰MB',
    languages: [
      TranslateLanguage.english,
      TranslateLanguage.persian,
      TranslateLanguage.arabic,
      TranslateLanguage.chinese,
      TranslateLanguage.russian,
      TranslateLanguage.spanish,
      TranslateLanguage.french,
      TranslateLanguage.german,
      TranslateLanguage.turkish,
      TranslateLanguage.hindi,
    ],
  ),
  OfflineTransModel(
    id: 'mlkit_standard',
    name: 'Standard — ۲۰ زبان',
    description: 'مناسب برای اکثر کاربران',
    langCount: 20,
    size: '~۶۰۰MB',
    languages: [
      TranslateLanguage.english,
      TranslateLanguage.persian,
      TranslateLanguage.arabic,
      TranslateLanguage.chinese,
      TranslateLanguage.russian,
      TranslateLanguage.spanish,
      TranslateLanguage.french,
      TranslateLanguage.german,
      TranslateLanguage.turkish,
      TranslateLanguage.hindi,
      TranslateLanguage.japanese,
      TranslateLanguage.korean,
      TranslateLanguage.italian,
      TranslateLanguage.portuguese,
      TranslateLanguage.dutch,
      TranslateLanguage.polish,
      TranslateLanguage.ukrainian,
      TranslateLanguage.indonesian,
      TranslateLanguage.swedish,
      TranslateLanguage.norwegian,
    ],
  ),
  OfflineTransModel(
    id: 'mlkit_pro',
    name: 'Pro — ۳۵ زبان',
    description: 'پوشش زبان‌های بیشتر',
    langCount: 35,
    size: '~۱GB',
    languages: [
      TranslateLanguage.english,
      TranslateLanguage.persian,
      TranslateLanguage.arabic,
      TranslateLanguage.chinese,
      TranslateLanguage.russian,
      TranslateLanguage.spanish,
      TranslateLanguage.french,
      TranslateLanguage.german,
      TranslateLanguage.turkish,
      TranslateLanguage.hindi,
      TranslateLanguage.japanese,
      TranslateLanguage.korean,
      TranslateLanguage.italian,
      TranslateLanguage.portuguese,
      TranslateLanguage.dutch,
      TranslateLanguage.polish,
      TranslateLanguage.ukrainian,
      TranslateLanguage.indonesian,
      TranslateLanguage.swedish,
      TranslateLanguage.norwegian,
      TranslateLanguage.danish,
      TranslateLanguage.finnish,
      TranslateLanguage.greek,
      TranslateLanguage.hebrew,
      TranslateLanguage.hungarian,
      TranslateLanguage.romanian,
      TranslateLanguage.czech,
      TranslateLanguage.bulgarian,
      TranslateLanguage.croatian,
      TranslateLanguage.slovak,
      TranslateLanguage.slovenian,
      TranslateLanguage.thai,
      TranslateLanguage.vietnamese,
      TranslateLanguage.malay,
      TranslateLanguage.tagalog,
    ],
  ),
  OfflineTransModel(
    id: 'mlkit_max',
    name: 'Max — ۵۰ زبان',
    description: 'پوشش گسترده — کیفیت بالا',
    langCount: 50,
    size: '~۱.۵GB',
    languages: [
      TranslateLanguage.english,
      TranslateLanguage.persian,
      TranslateLanguage.arabic,
      TranslateLanguage.chinese,
      TranslateLanguage.russian,
      TranslateLanguage.spanish,
      TranslateLanguage.french,
      TranslateLanguage.german,
      TranslateLanguage.turkish,
      TranslateLanguage.hindi,
      TranslateLanguage.japanese,
      TranslateLanguage.korean,
      TranslateLanguage.italian,
      TranslateLanguage.portuguese,
      TranslateLanguage.dutch,
      TranslateLanguage.polish,
      TranslateLanguage.ukrainian,
      TranslateLanguage.indonesian,
      TranslateLanguage.swedish,
      TranslateLanguage.norwegian,
      TranslateLanguage.danish,
      TranslateLanguage.finnish,
      TranslateLanguage.greek,
      TranslateLanguage.hebrew,
      TranslateLanguage.hungarian,
      TranslateLanguage.romanian,
      TranslateLanguage.czech,
      TranslateLanguage.bulgarian,
      TranslateLanguage.croatian,
      TranslateLanguage.slovak,
      TranslateLanguage.slovenian,
      TranslateLanguage.thai,
      TranslateLanguage.vietnamese,
      TranslateLanguage.malay,
      TranslateLanguage.tagalog,
      TranslateLanguage.bengali,
      TranslateLanguage.urdu,
      TranslateLanguage.swahili,
      TranslateLanguage.catalan,
      TranslateLanguage.latvian,
      TranslateLanguage.lithuanian,
      TranslateLanguage.estonian,
      TranslateLanguage.galician,
    ],
  ),
  OfflineTransModel(
    id: 'mlkit_ultra',
    name: 'Ultra — ۵۸ زبان',
    description: 'کامل‌ترین مدل آفلاین — تمام زبان‌های ML Kit',
    langCount: 58,
    size: '~۱.۷GB',
    languages: TranslateLanguage.values,
  ),
];

// ── سرویس ترجمه آفلاین ──
class OfflineTranslationService {
  static const _kModel = 'offline_trans_model';
  static const _kDownloaded = 'offline_trans_downloaded';
  static const _kSrcLang = 'offline_trans_src';
  static const _kTgtLang = 'offline_trans_tgt';

  static final _modelManager = OnDeviceTranslatorModelManager();
  static OnDeviceTranslator? _translator;

  // ── تنظیمات ذخیره شده ──
  static Future<String> getSelectedModel() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kModel) ?? 'mlkit_lite';
  }

  static Future<void> setSelectedModel(String id) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kModel, id);
  }

  static Future<TranslateLanguage> getSrcLang() async {
    final p = await SharedPreferences.getInstance();
    final name = p.getString(_kSrcLang) ?? 'en';
    return TranslateLanguage.values.firstWhere(
      (l) => l.bcpCode == name, orElse: () => TranslateLanguage.english);
  }

  static Future<TranslateLanguage> getTgtLang() async {
    final p = await SharedPreferences.getInstance();
    final name2 = p.getString(_kTgtLang) ?? 'fa';
    return TranslateLanguage.values.firstWhere(
      (l) => l.bcpCode == name2, orElse: () => TranslateLanguage.persian);
  }

  static Future<void> setSrcLang(TranslateLanguage l) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kSrcLang, l.bcpCode);
  }

  static Future<void> setTgtLang(TranslateLanguage l) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kTgtLang, l.bcpCode);
  }

  // ── دانلود مدل ──
  static Future<bool> isDownloaded(TranslateLanguage lang) async {
    return await _modelManager.isModelDownloaded(lang);
  }

  static Future<void> downloadModel(
    TranslateLanguage lang,
    void Function(double) onProgress,
  ) async {
    onProgress(0);
    await _modelManager.downloadModel(lang, isWifiRequired: false);
    onProgress(1);
  }

  static Future<void> deleteModel(TranslateLanguage lang) async {
    await _modelManager.deleteModel(lang);
  }

  // ── ترجمه ──
  static Future<String> translate(
    String text, {
    TranslateLanguage? src,
    TranslateLanguage? tgt,
  }) async {
    final s = src ?? await getSrcLang();
    final t = tgt ?? await getTgtLang();

    if (_translator == null ||
        _translator!.sourceLanguage != s ||
        _translator!.targetLanguage != t) {
      _translator?.close();
      _translator = OnDeviceTranslator(sourceLanguage: s, targetLanguage: t);
    }

    return await _translator!.translateText(text);
  }

  // ── ترجمه SRT کامل ──
  static Future<String> translateSrt(
    String srtContent, {
    TranslateLanguage? src,
    TranslateLanguage? tgt,
    void Function(double)? onProgress,
    void Function(String)? onChunk,
  }) async {
    final lines = srtContent.split('\n');
    final result = <String>[];
    final textLines = <int>[];

    // پیدا کردن خطوط متن
    for (int i = 0; i < lines.length; i++) {
      final l = lines[i].trim();
      if (l.isEmpty || RegExp(r'^\d+$').hasMatch(l) || l.contains('-->')) {
        result.add(lines[i]);
      } else {
        textLines.add(i);
        result.add('__TRANS__$i');
      }
    }

    // ترجمه
    for (int i = 0; i < textLines.length; i++) {
      final idx = textLines[i];
      final translated = await translate(lines[idx].trim(), src: src, tgt: tgt);
      result[idx] = translated;
      onProgress?.call((i + 1) / textLines.length);
      onChunk?.call(result.join('\n'));
    }

    return result.join('\n');
  }

  static void dispose() {
    _translator?.close();
    _translator = null;
  }
}

// نام زیبا برای زبان‌ها
extension TranslateLanguageExt on TranslateLanguage {
  String get displayName {
    const names = {
      'en': 'English', 'fa': 'فارسی', 'ar': 'العربية', 'zh': '中文',
      'ru': 'Русский', 'es': 'Español', 'fr': 'Français', 'de': 'Deutsch',
      'tr': 'Türkçe', 'hi': 'हिन्दी', 'ja': '日本語', 'ko': '한국어',
      'it': 'Italiano', 'pt': 'Português', 'nl': 'Nederlands', 'pl': 'Polski',
      'uk': 'Українська', 'id': 'Indonesia', 'sv': 'Svenska', 'no': 'Norsk',
      'da': 'Dansk', 'fi': 'Suomi', 'el': 'Ελληνικά', 'he': 'עברית',
      'hu': 'Magyar', 'ro': 'Română', 'cs': 'Čeština', 'bg': 'Български',
      'hr': 'Hrvatski', 'sk': 'Slovenčina', 'sl': 'Slovenščina',
      'th': 'ภาษาไทย', 'vi': 'Tiếng Việt', 'ms': 'Melayu', 'tl': 'Filipino',
      'bn': 'বাংলা', 'ur': 'اردو', 'sw': 'Kiswahili', 'ca': 'Català',
      'lv': 'Latviešu', 'lt': 'Lietuvių', 'et': 'Eesti', 'gl': 'Galego',
      'be': 'Беларуская', 'az': 'Azərbaycan', 'ka': 'ქართული',
      'hy': 'Հայերեն', 'sq': 'Shqip', 'mk': 'Македонски', 'sr': 'Српски',
    };
    return names[bcpCode] ?? bcpCode.toUpperCase();
  }
}

