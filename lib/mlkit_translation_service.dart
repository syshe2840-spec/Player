import 'package:google_mlkit_translation/google_mlkit_translation.dart';

class MlKitTranslationService {
  static final Map<String, OnDeviceTranslator> _translators = {};
  static final _modelManager = OnDeviceTranslatorModelManager();

  // enum برای OnDeviceTranslator
  static const _enumMap = {
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

  // tag string برای ModelManager
  static const _tagMap = {
    'af':'af','ar':'ar','be':'be','bg':'bg','bn':'bn','ca':'ca',
    'cs':'cs','cy':'cy','da':'da','de':'de','el':'el','en':'en',
    'eo':'eo','es':'es','et':'et','fa':'fa','fi':'fi','fr':'fr',
    'ga':'ga','gl':'gl','gu':'gu','he':'iw','hi':'hi','hr':'hr',
    'hu':'hu','id':'id','it':'it','ja':'ja','ka':'ka','kn':'kn',
    'ko':'ko','lt':'lt','lv':'lv','mk':'mk','mr':'mr','ms':'ms',
    'mt':'mt','nl':'nl','no':'no','pl':'pl','pt':'pt','ro':'ro',
    'ru':'ru','sk':'sk','sl':'sl','sq':'sq','sv':'sv','sw':'sw',
    'ta':'ta','te':'te','th':'th','tl':'tl','tr':'tr','uk':'uk',
    'ur':'ur','vi':'vi','zh':'zh','zh-cn':'zh',
  };

  static bool isSupported(String code) =>
      _enumMap.containsKey(code.toLowerCase());

  static Future<bool> isModelDownloaded(String code) async {
    final tag = _tagMap[code.toLowerCase()];
    if (tag == null) return false;
    return _modelManager.isModelDownloaded(tag);
  }

  static Future<void> downloadModels(String src, String tgt) async {
    final s = _tagMap[src.toLowerCase()];
    final t = _tagMap[tgt.toLowerCase()];
    if (s != null) await _modelManager.downloadModel(s);
    if (t != null) await _modelManager.downloadModel(t);
  }

  static Future<String> translate(String text,
      {required String from, required String to}) async {
    if (text.trim().isEmpty) return text;
    final srcE = _enumMap[from.toLowerCase()];
    final tgtE = _enumMap[to.toLowerCase()];
    if (srcE == null || tgtE == null || srcE == tgtE) return text;

    final key = '${from}_$to';
    _translators[key] ??= OnDeviceTranslator(
        sourceLanguage: srcE, targetLanguage: tgtE);
    try {
      return await _translators[key]!.translateText(text);
    } catch (_) {
      return text;
    }
  }

  static Future<void> dispose() async {
    for (final t in _translators.values) await t.close();
    _translators.clear();
  }

  static Future<void> deleteModel(String code) async {
    final tag = _tagMap[code.toLowerCase()];
    if (tag != null) await _modelManager.deleteModel(tag);
  }
}
