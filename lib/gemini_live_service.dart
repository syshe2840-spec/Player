import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// سرویس ترجمه زنده با Gemini Live API
/// مستقیم WebSocket بدون SDK — مثل رویکرد e2dub
class GeminiLiveService {
  static const _ch = MethodChannel('com.vezoo.player/gemini_live');
  static const _apiKeyPref = 'gemini_api_key';

  /// ذخیره API key
  static Future<void> saveApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_apiKeyPref, key.trim());
  }

  /// خواندن API key
  static Future<String?> getApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_apiKeyPref);
  }

  /// حذف API key
  static Future<void> clearApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_apiKeyPref);
  }

  /// شروع ترجمه زنده
  static Future<bool> start({required String targetLang}) async {
    final key = await getApiKey();
    if (key == null || key.isEmpty) return false;
    await _ch.invokeMethod('start', {'apiKey': key, 'lang': targetLang});
    return true;
  }

  /// ارسال صدا (PCM 16kHz mono)
  static Future<void> sendAudio(List<int> pcmBytes) async {
    await _ch.invokeMethod('sendAudio', {'data': Uint8List.fromList(pcmBytes)});
  }

  /// توقف
  static Future<void> stop() async {
    await _ch.invokeMethod('stop');
  }

  /// گرفتن event بعدی از queue
  static Future<Map?> getNextEvent() async {
    final e = await _ch.invokeMethod<Map>('getNextEvent');
    return e;
  }

  /// زبان‌های پشتیبانی شده توسط Gemini Live
  static const supportedLangs = {
    'fa': 'فارسی',
    'en': 'English',
    'ar': 'العربية',
    'fr': 'Français',
    'de': 'Deutsch',
    'es': 'Español',
    'ru': 'Русский',
    'tr': 'Türkçe',
    'zh': '中文',
    'ja': '日本語',
    'ko': '한국어',
    'hi': 'हिंदी',
    'pt': 'Português',
    'it': 'Italiano',
    'nl': 'Nederlands',
    'pl': 'Polski',
    'uk': 'Українська',
    'sv': 'Svenska',
  };
}
