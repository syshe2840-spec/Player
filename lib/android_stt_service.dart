import 'dart:async';
import 'package:flutter/services.dart';

class AndroidSttService {
  static const _ch       = MethodChannel('com.vezoo.player/android_stt');
  static const _callback = MethodChannel('com.vezoo.player/android_stt_callback');
  static void Function(Map<String,dynamic>)? _eventHandler;

  static void _initCallback() {
    _callback.setMethodCallHandler((call) async {
      if (call.method == 'onAndroidSttEvent' && _eventHandler != null) {
        final data = Map<String,dynamic>.from(call.arguments as Map);
        _eventHandler!(data);
      }
    });
  }

  // ۳۵+ زبان پشتیبانی شده
  static const supportedLangs = {
    'auto':'🌐 تشخیص خودکار',
    'fa':'🇮🇷 فارسی', 'en':'🇺🇸 English', 'ar':'🇸🇦 العربية',
    'zh':'🇨🇳 中文', 'ru':'🇷🇺 Русский', 'es':'🇪🇸 Español',
    'fr':'🇫🇷 Français', 'de':'🇩🇪 Deutsch', 'tr':'🇹🇷 Türkçe',
    'hi':'🇮🇳 हिन्दी', 'ja':'🇯🇵 日本語', 'ko':'🇰🇷 한국어',
    'it':'🇮🇹 Italiano', 'pt':'🇧🇷 Português', 'nl':'🇳🇱 Nederlands',
    'pl':'🇵🇱 Polski', 'uk':'🇺🇦 Українська', 'vi':'🇻🇳 Tiếng Việt',
    'th':'🇹🇭 ภาษาไทย', 'id':'🇮🇩 Indonesia', 'sv':'🇸🇪 Svenska',
    'da':'🇩🇰 Dansk', 'fi':'🇫🇮 Suomi', 'no':'🇳🇴 Norsk',
    'he':'🇮🇱 עברית', 'el':'🇬🇷 Ελληνικά', 'hu':'🇭🇺 Magyar',
    'ro':'🇷🇴 Română', 'cs':'🇨🇿 Čeština', 'bg':'🇧🇬 Български',
    'ms':'🇲🇾 Melayu', 'bn':'🇧🇩 বাংলা', 'ur':'🇵🇰 اردو',
    'tl':'🇵🇭 Filipino', 'hr':'🇭🇷 Hrvatski', 'sk':'🇸🇰 Slovenčina',
  };

  static Stream<Map<String, dynamic>> events() {
    _initCallback();
    final controller = StreamController<Map<String,dynamic>>.broadcast();
    _eventHandler = (data) { if (!controller.isClosed) controller.add(data); };
    return controller.stream;
  }

  static Future<void> start(String lang) async {
    await _ch.invokeMethod('startAndroidStt', {'lang': lang});
  }

  static Future<void> stop() async {
    await _ch.invokeMethod('stopAndroidStt');
  }

  static Future<Map<String,dynamic>?> getNextEvent() async {
    final r = await _ch.invokeMethod<Map>('getAndroidSttNextEvent');
    if (r == null) return null;
    return Map<String,dynamic>.from(r);
  }
}
