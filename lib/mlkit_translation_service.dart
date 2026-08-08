import 'package:google_mlkit_translation/google_mlkit_translation.dart';

/// سرویس ترجمه آفلاین با ML Kit — زیر 50ms، بدون نیاز به اینترنت
class MlKitTranslationService {
  static final Map<String, OnDeviceTranslator> _translators = {};
  static final _modelManager = OnDeviceTranslatorModelManager();

  /// نگاشت کد زبان ما به ML Kit tag
  static const _langMap = {
    'af': TranslateLanguage.afrikaans,
    'ar': TranslateLanguage.arabic,
    'be': TranslateLanguage.belarusian,
    'bg': TranslateLanguage.bulgarian,
    'bn': TranslateLanguage.bengali,
    'ca': TranslateLanguage.catalan,
    'cs': TranslateLanguage.czech,
    'cy': TranslateLanguage.welsh,
    'da': TranslateLanguage.danish,
    'de': TranslateLanguage.german,
    'el': TranslateLanguage.greek,
    'en': TranslateLanguage.english,
    'eo': TranslateLanguage.esperanto,
    'es': TranslateLanguage.spanish,
    'et': TranslateLanguage.estonian,
    'fa': TranslateLanguage.persian,
    'fi': TranslateLanguage.finnish,
    'fr': TranslateLanguage.french,
    'ga': TranslateLanguage.irish,
    'gl': TranslateLanguage.galician,
    'gu': TranslateLanguage.gujarati,
    'he': TranslateLanguage.hebrew,
    'hi': TranslateLanguage.hindi,
    'hr': TranslateLanguage.croatian,
    'hu': TranslateLanguage.hungarian,
    'id': TranslateLanguage.indonesian,
    'it': TranslateLanguage.italian,
    'ja': TranslateLanguage.japanese,
    'ka': TranslateLanguage.georgian,
    'kn': TranslateLanguage.kannada,
    'ko': TranslateLanguage.korean,
    'lt': TranslateLanguage.lithuanian,
    'lv': TranslateLanguage.latvian,
    'mk': TranslateLanguage.macedonian,
    'mr': TranslateLanguage.marathi,
    'ms': TranslateLanguage.malay,
    'mt': TranslateLanguage.maltese,
    'nl': TranslateLanguage.dutch,
    'no': TranslateLanguage.norwegian,
    'pl': TranslateLanguage.polish,
    'pt': TranslateLanguage.portuguese,
    'ro': TranslateLanguage.romanian,
    'ru': TranslateLanguage.russian,
    'sk': TranslateLanguage.slovak,
    'sl': TranslateLanguage.slovenian,
    'sq': TranslateLanguage.albanian,
    'sv': TranslateLanguage.swedish,
    'sw': TranslateLanguage.swahili,
    'ta': TranslateLanguage.tamil,
    'te': TranslateLanguage.telugu,
    'th': TranslateLanguage.thai,
    'tl': TranslateLanguage.tagalog,
    'tr': TranslateLanguage.turkish,
    'uk': TranslateLanguage.ukrainian,
    'ur': TranslateLanguage.urdu,
    'vi': TranslateLanguage.vietnamese,
    'zh': TranslateLanguage.chinese,
    'zh-cn': TranslateLanguage.chinese,
  };

  static bool isSupported(String langCode) =>
      _langMap.containsKey(langCode.toLowerCase());

  static Future<bool> isModelDownloaded(String langCode) async {
    final lang = _langMap[langCode.toLowerCase()];
    if (lang == null) return false;
    return _modelManager.isModelDownloaded(lang.toLanguageTag());
  }

  static Future<void> downloadModels(String sourceLang, String targetLang) async {
    final src = _langMap[sourceLang.toLowerCase()];
    final tgt = _langMap[targetLang.toLowerCase()];
    if (src != null) await _modelManager.downloadModel(src.toLanguageTag());
    if (tgt != null) await _modelManager.downloadModel(tgt.toLanguageTag());
  }

  static Future<String> translate(String text, {required String from, required String to}) async {
    if (text.trim().isEmpty) return text;
    final srcLang = _langMap[from.toLowerCase()];
    final tgtLang = _langMap[to.toLowerCase()];
    if (srcLang == null || tgtLang == null) return text;
    if (srcLang == tgtLang) return text;

    final key = '${from}_$to';
    if (!_translators.containsKey(key)) {
      _translators[key] = OnDeviceTranslator(
        sourceLanguage: srcLang,
        targetLanguage: tgtLang,
      );
    }
    try {
      return await _translators[key]!.translateText(text);
    } catch (_) { return text; }
  }

  static Future<void> dispose() async {
    for (final t in _translators.values) { await t.close(); }
    _translators.clear();
  }

  static Future<void> deleteModel(String langCode) async {
    final lang = _langMap[langCode.toLowerCase()];
    if (lang != null) await _modelManager.deleteModel(lang.toLanguageTag());
  }
}
