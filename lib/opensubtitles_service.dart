import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
import 'subtitle_storage.dart';

// ── ثابت‌ها ──
const String _osBaseUrl = 'https://api.opensubtitles.com/api/v1';
const String _osUserAgent = 'Vezoo v1.0';

// ── مدل‌ها ──
class OsFeature {
  final int id;
  final String type; // movie | tvshow
  final String title;
  final String? year;
  final int? imdbId;
  final String? imgUrl;
  OsFeature({required this.id, required this.type, required this.title, this.year, this.imdbId, this.imgUrl});

  factory OsFeature.fromJson(Map<String, dynamic> j) {
    final a = (j['attributes'] as Map?)?.cast<String, dynamic>() ?? {};
    // نکته مهم: فیلد بیرونی j['type'] همیشه "feature" است (تأیید شده از تیم OpenSubtitles)
    // نوع واقعی (Movie/TvShow/Episode) داخل attributes.feature_type است
    return OsFeature(
      id: int.tryParse('${j['id']}') ?? 0,
      type: (a['feature_type'] ?? '').toString().toLowerCase(),
      title: (a['title'] ?? '').toString(),
      year: a['year']?.toString(),
      imdbId: int.tryParse('${a['imdb_id']}'),
      imgUrl: a['img_url']?.toString(),
    );
  }
}

class OsSubtitle {
  final int fileId;
  final String language;
  final String release;
  final int downloadCount;
  final bool hd;
  OsSubtitle({required this.fileId, required this.language, required this.release, required this.downloadCount, required this.hd});

  factory OsSubtitle.fromJson(Map<String, dynamic> j) {
    final a = (j['attributes'] as Map?)?.cast<String, dynamic>() ?? {};
    final files = (a['files'] as List?) ?? [];
    final fileId = files.isNotEmpty ? (int.tryParse('${files[0]['file_id']}') ?? 0) : 0;
    return OsSubtitle(
      fileId: fileId,
      language: (a['language'] ?? '').toString(),
      release: (a['release'] ?? '').toString(),
      downloadCount: int.tryParse('${a['download_count']}') ?? 0,
      hd: a['hd'] == true,
    );
  }
}

class ParsedFileInfo {
  final String title;
  final int? year;
  final int? season;
  final int? episode;
  final bool isSeries;
  ParsedFileInfo({required this.title, this.year, this.season, this.episode, required this.isSeries});
}

// ── سرویس — کاملاً بدون نیاز به یوزر/پسورد، فقط API Key ──
class OpenSubtitlesService {
  static String? _cachedKey;

  /// گرفتن کلید API از سرور Cloudflare — با کش محلی برای دفعات بعد
  static Future<String> _getApiKey() async {
    if (_cachedKey != null && _cachedKey!.isNotEmpty) return _cachedKey!;

    try {
      final data = await ApiService.getRaw('/opensubtitles-key');
      final key = (data as Map?)?['api_key'] as String?;
      if (key != null && key.isNotEmpty) {
        _cachedKey = key;
        (await SharedPreferences.getInstance()).setString('os_api_key_cache', key);
        return key;
      }
    } catch (_) {
      // اینترنت نبود یا سرور جواب نداد — برو سراغ کش محلی
    }

    final cached = (await SharedPreferences.getInstance()).getString('os_api_key_cache');
    if (cached != null && cached.isNotEmpty) {
      _cachedKey = cached;
      return cached;
    }

    throw Exception('دریافت کلید سرویس زیرنویس ناموفق بود — اتصال اینترنت را بررسی کنید');
  }

  static Future<Map<String, String>> _baseHeaders() async => {
        'Api-Key': await _getApiKey(),
        'User-Agent': _osUserAgent,
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

  static String _friendlyError(int status, String body) {
    String msg = body;
    try {
      final j = jsonDecode(body);
      if (j is Map && j['message'] != null) msg = j['message'].toString();
    } catch (_) {}
    final lower = msg.toLowerCase();
    if (status == 406 || status == 403 || lower.contains('limit') || lower.contains('quota') || lower.contains('reached')) {
      return 'به محدودیت دانلود روزانه رسیدید — ظرف چند ساعت دیگر دوباره امتحان کنید';
    }
    if (status == 400) return 'جستجوی نامعتبر — عبارت را تغییر دهید';
    return 'خطا (${status}): $msg';
  }

  static Future<dynamic> _get(String path, Map<String, String> params) async {
    final uri = Uri.parse('$_osBaseUrl$path').replace(queryParameters: params.isEmpty ? null : params);
    final client = HttpClient();
    try {
      final req = await client.getUrl(uri);
      (await _baseHeaders()).forEach((k, v) => req.headers.set(k, v));
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode != 200) throw Exception(_friendlyError(res.statusCode, body));
      return jsonDecode(body);
    } finally {
      client.close();
    }
  }

  /// مرحله ۱: جستجوی عنوان فیلم/سریال
  static Future<List<OsFeature>> searchTitle(String query) async {
    if (query.trim().length < 2) return [];
    final data = await _get('/features', {'query': query.trim()});
    final list = (data['data'] as List?) ?? [];
    return list
        .map((e) => OsFeature.fromJson(e as Map<String, dynamic>))
        .where((f) => f.type == 'movie' || f.type == 'tvshow')
        .toList();
  }

  /// مرحله ۲: جستجوی زیرنویس‌های یک فیلم یا یک قسمت خاص
  static Future<List<OsSubtitle>> searchSubtitles({
    required OsFeature feature,
    int? season,
    int? episode,
    String? language,
  }) async {
    final params = <String, String>{};
    if (feature.type == 'tvshow') {
      if (feature.imdbId != null) params['parent_imdb_id'] = '${feature.imdbId}';
      if (season != null) params['season_number'] = '$season';
      if (episode != null) params['episode_number'] = '$episode';
    } else {
      if (feature.imdbId != null) params['imdb_id'] = '${feature.imdbId}';
    }
    if (language != null && language.isNotEmpty) params['languages'] = language;
    if (params.isEmpty) throw Exception('اطلاعات کافی برای جستجو موجود نیست');

    final data = await _get('/subtitles', params);
    final list = (data['data'] as List?) ?? [];
    return list
        .map((e) => OsSubtitle.fromJson(e as Map<String, dynamic>))
        .where((s) => s.fileId != 0)
        .toList()
      ..sort((a, b) => b.downloadCount.compareTo(a.downloadCount));
  }

  /// مرحله ۳: دانلود فایل زیرنویس — فقط با API Key (بدون لاگین)، سهمیه‌ی رایگان روزانه
  static Future<String> downloadSubtitle({
    required OsSubtitle sub,
    required String videoPath,
    void Function(int remaining)? onQuota,
  }) async {
    final client = HttpClient();
    String? link;
    try {
      final req = await client.postUrl(Uri.parse('$_osBaseUrl/download'));
      (await _baseHeaders()).forEach((k, v) => req.headers.set(k, v));
      req.write(jsonEncode({'file_id': sub.fileId}));
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode != 200) throw Exception(_friendlyError(res.statusCode, body));
      final data = jsonDecode(body);
      link = data['link'] as String?;
      if (onQuota != null && data['remaining'] != null) {
        onQuota(int.tryParse('${data['remaining']}') ?? 0);
      }
    } finally {
      client.close();
    }
    if (link == null) throw Exception('لینک دانلود دریافت نشد — احتمالاً به محدودیت روزانه رسیده‌اید');

    // دانلود محتوای واقعی فایل srt از لینک موقت
    final client2 = HttpClient();
    String content;
    try {
      final req2 = await client2.getUrl(Uri.parse(link));
      final res2 = await req2.close();
      if (res2.statusCode != 200) throw Exception('دانلود فایل ناموفق (${res2.statusCode})');
      content = await res2.transform(utf8.decoder).join();
    } finally {
      client2.close();
    }

    final out = await SubtitleStorage.onlineSubtitlePath(videoPath, sub.language);
    await File(out).writeAsString(content, encoding: utf8);
    return out;
  }

  /// تجزیه نام فایل برای پیشنهاد خودکار عنوان/سال/فصل/قسمت
  static ParsedFileInfo parseFilename(String videoPath) {
    var name = p.basenameWithoutExtension(videoPath);
    name = name.replaceAll(RegExp(r'[._]'), ' ');

    int? season, episode;
    bool isSeries = false;
    String cutTitle = name;

    final m1 = RegExp(r'[Ss](\d{1,2})[Ee](\d{1,3})').firstMatch(name);
    final m2 = m1 == null ? RegExp(r'\b(\d{1,2})x(\d{1,3})\b').firstMatch(name) : null;

    if (m1 != null) {
      season = int.tryParse(m1.group(1)!);
      episode = int.tryParse(m1.group(2)!);
      isSeries = true;
      cutTitle = name.substring(0, m1.start);
    } else if (m2 != null) {
      season = int.tryParse(m2.group(1)!);
      episode = int.tryParse(m2.group(2)!);
      isSeries = true;
      cutTitle = name.substring(0, m2.start);
    }

    final qualityTags = RegExp(
      r'\b(1080p|720p|480p|2160p|4k|bluray|blu-ray|webdl|web-dl|web|hdtv|brrip|dvdrip|x264|x265|hevc|aac|ac3|yts|yify)\b',
      caseSensitive: false,
    );
    final qm = qualityTags.firstMatch(cutTitle);
    if (qm != null) cutTitle = cutTitle.substring(0, qm.start);

    int? year;
    final ym = RegExp(r'\b(19|20)\d{2}\b').firstMatch(cutTitle);
    if (ym != null) {
      year = int.tryParse(ym.group(0)!);
      cutTitle = cutTitle.substring(0, ym.start);
    }

    cutTitle = cutTitle.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cutTitle.isEmpty) cutTitle = name.trim();

    return ParsedFileInfo(title: cutTitle, year: year, season: season, episode: episode, isSeries: isSeries);
  }
}
