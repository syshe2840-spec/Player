import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';

// ─── آدرس Worker خودت رو اینجا بذار ───
const kWorkerUrl = 'https://player.lastofanarchy.workers.dev/';

class ApiService {
  static String _uuid = '';
  static String _appVersion = '1.0.0';

  // ── init در شروع اپ ──
  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _uuid = prefs.getString('device_uuid') ?? _makeUUID();
    await prefs.setString('device_uuid', _uuid);
    try {
      final info = await PackageInfo.fromPlatform();
      _appVersion = info.version;
    } catch (_) {}
  }

  static String _makeUUID() {
    final r = Random.secure();
    final b = List.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    String h(int n) => n.toRadixString(16).padLeft(2, '0');
    return '${h(b[0])}${h(b[1])}${h(b[2])}${h(b[3])}-'
        '${h(b[4])}${h(b[5])}-${h(b[6])}${h(b[7])}-'
        '${h(b[8])}${h(b[9])}-'
        '${h(b[10])}${h(b[11])}${h(b[12])}${h(b[13])}${h(b[14])}${h(b[15])}';
  }

  // ── GET helper ──
  static Future<dynamic> _get(String path) async {
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
      final req = await client.getUrl(Uri.parse('$kWorkerUrl$path'));
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      client.close();
      return json.decode(body);
    } catch (_) {
      return null;
    }
  }

  // ── اسپانسرها ──
  static Future<List<Map<String, dynamic>>> getSponsors() async {
    final data = await _get('/sponsors');
    if (data is List) return data.cast<Map<String, dynamic>>();
    return [];
  }

  // ── تنظیمات (آپدیت) ──
  static Future<Map<String, dynamic>?> getConfig() async {
    final data = await _get('/config');
    if (data is Map) return data.cast<String, dynamic>();
    return null;
  }

  // ── اعلان ──
  static Future<Map<String, dynamic>?> getAnnouncement() async {
    final data = await _get('/announce');
    if (data is Map) return data.cast<String, dynamic>();
    return null;
  }

  // ── ارسال آمار ──
  static Future<void> sendStat(String event, {String value = ''}) async {
    try {
      final client = HttpClient();
      final req = await client.postUrl(Uri.parse('$kWorkerUrl/stats'));
      req.headers.set('Content-Type', 'application/json');
      req.write(json.encode({
        'uuid': _uuid,
        'app_version': _appVersion,
        'android_version': Platform.operatingSystemVersion,
        'event': event,
        'value': value,
      }));
      await req.close();
      client.close();
    } catch (_) {}
  }

  // ── مقایسه نسخه ──
  static bool isNewer(String remote, String local) {
    try {
      final r = remote.split('.').map(int.parse).toList();
      final l = local.split('.').map(int.parse).toList();
      for (int i = 0; i < max(r.length, l.length); i++) {
        final rv = i < r.length ? r[i] : 0;
        final lv = i < l.length ? l[i] : 0;
        if (rv > lv) return true;
        if (rv < lv) return false;
      }
    } catch (_) {}
    return false;
  }

  static String get appVersion => _appVersion;
}

