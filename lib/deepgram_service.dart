import 'package:flutter/services.dart';
import 'api_service.dart';

/// سرویس Deepgram — real-time transcription با تأخیر ~۱۵۰ms
class DeepgramService {
  static const _ch = MethodChannel('com.vezoo.player/deepgram');
  static const _ev = EventChannel('com.vezoo.player/deepgram_events');

  static Stream<Map> events() =>
    _ev.receiveBroadcastStream().map((e) => (e as Map).cast<String, dynamic>());

  static Future<void> start({String language = 'multi', String streamUrl = ''}) async =>
    await _ch.invokeMethod('start', {'language': language, 'workerUrl': kWorkerUrl, 'streamUrl': streamUrl});

  static Future<void> stop() async =>
    await _ch.invokeMethod('stop');

  /// زبان‌های پشتیبانی‌شده Deepgram
  static const Map<String, String> languages = {
    'multi': 'Auto Detect',
    'en': 'English',
    'fa': 'فارسی',
    'ar': 'العربية',
    'ru': 'Русский',
    'zh': '中文',
    'ja': '日本語',
    'hi': 'हिन्दी',
    'id': 'Indonesia',
    'fr': 'Français',
    'de': 'Deutsch',
    'es': 'Español',
    'tr': 'Türkçe',
    'ko': '한국어',
    'pt': 'Português',
    'it': 'Italiano',
    'uk': 'Українська',
    'nl': 'Nederlands',
    'sv': 'Svenska',
  };
}
