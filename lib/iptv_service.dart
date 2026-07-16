import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// ── مدل‌ها ──
class IptvAccount {
  final String name, server, username, password;
  IptvAccount({required this.name, required this.server, required this.username, required this.password});
  Map<String,String> toJson() => {'name':name,'server':server,'username':username,'password':password};
  factory IptvAccount.fromJson(Map m) => IptvAccount(
    name:m['name']??'', server:m['server']??'', username:m['username']??'', password:m['password']??'');
  String get baseUrl => '${server.endsWith('/')?server.substring(0,server.length-1):server}';

}

class IptvCategory { final String id, name; IptvCategory(this.id, this.name); }

class IptvChannel {
  final String id, name, logo, categoryId, url;
  IptvChannel({required this.id, required this.name, required this.logo,
    required this.categoryId, required this.url});
}

class IptvVod {
  final String id, name, poster, categoryId, url, streamType;
  IptvVod({required this.id, required this.name, required this.poster,
    required this.categoryId, required this.url, required this.streamType});
}

class IptvSeries {
  final String id, name, poster, categoryId;
  IptvSeries({required this.id, required this.name, required this.poster, required this.categoryId});
}

class IptvEpisode {
  final String id, title, url, seriesId;
  final int season, episode;
  IptvEpisode({required this.id, required this.title, required this.url,
    required this.seriesId, required this.season, required this.episode});
}

// ── سرویس ──
class IptvService {
  static const _kKey = 'iptv_accounts';

  // ── حساب‌ها ──
  static Future<List<IptvAccount>> getAccounts() async {
    final p = await SharedPreferences.getInstance();
    final list = p.getStringList(_kKey) ?? [];
    return list.map((s) => IptvAccount.fromJson(jsonDecode(s))).toList();
  }

  static Future<void> saveAccount(IptvAccount acc) async {
    final p = await SharedPreferences.getInstance();
    final list = p.getStringList(_kKey) ?? [];
    final accounts = list.map((s) => IptvAccount.fromJson(jsonDecode(s))).toList();
    accounts.removeWhere((a) => a.server == acc.server && a.username == acc.username);
    accounts.insert(0, acc);
    await p.setStringList(_kKey, accounts.map((a) => jsonEncode(a.toJson())).toList());
  }

  static Future<void> deleteAccount(IptvAccount acc) async {
    final p = await SharedPreferences.getInstance();
    final list = p.getStringList(_kKey) ?? [];
    final accounts = list.map((s) => IptvAccount.fromJson(jsonDecode(s))).toList();
    accounts.removeWhere((a) => a.server == acc.server && a.username == acc.username);
    await p.setStringList(_kKey, accounts.map((a) => jsonEncode(a.toJson())).toList());
  }

  // ── Xtream Codes API ──
  static String _api(IptvAccount a) =>
    '${a.baseUrl}/player_api.php?username=${a.username}&password=${a.password}';

  static Future<bool> testAccount(IptvAccount acc) async {
    try {
      final r = await http.get(Uri.parse('${_api(acc)}&action=get_account_info'))
        .timeout(const Duration(seconds: 10));
      if (r.statusCode != 200) return false;
      final json = jsonDecode(r.body);
      return json['user_info']?['auth'] == 1;
    } catch (_) { return false; }
  }

  static Future<List<IptvCategory>> getLiveCategories(IptvAccount acc) async {
    final r = await http.get(Uri.parse('${_api(acc)}&action=get_live_categories'))
      .timeout(const Duration(seconds: 15));
    final list = jsonDecode(r.body) as List;
    return list.map((c) => IptvCategory(c['category_id'].toString(), c['category_name']??'?')).toList();
  }

  static Future<List<IptvChannel>> getLiveStreams(IptvAccount acc, {String? categoryId}) async {
    final cat = categoryId != null ? '&category_id=$categoryId' : '';
    final r = await http.get(Uri.parse('${_api(acc)}&action=get_live_streams$cat'))
      .timeout(const Duration(seconds: 30));
    final list = jsonDecode(r.body) as List;
    return list.map((c) => IptvChannel(
      id: c['stream_id'].toString(),
      name: c['name']??'',
      logo: c['stream_icon']??'',
      categoryId: c['category_id']?.toString()??'',
      url: '${acc.baseUrl}/live/${acc.username}/${acc.password}/${c['stream_id']}.ts',
      // format: ts برای max compatibility با libmpv
    )).toList();
  }

  static Future<List<IptvCategory>> getVodCategories(IptvAccount acc) async {
    final r = await http.get(Uri.parse('${_api(acc)}&action=get_vod_categories'))
      .timeout(const Duration(seconds: 15));
    final list = jsonDecode(r.body) as List;
    return list.map((c) => IptvCategory(c['category_id'].toString(), c['category_name']??'?')).toList();
  }

  static Future<List<IptvVod>> getVodStreams(IptvAccount acc, {String? categoryId}) async {
    final cat = categoryId != null ? '&category_id=$categoryId' : '';
    final r = await http.get(Uri.parse('${_api(acc)}&action=get_vod_streams$cat'))
      .timeout(const Duration(seconds: 30));
    final list = jsonDecode(r.body) as List;
    return list.map((v) => IptvVod(
      id: v['stream_id'].toString(),
      name: v['name']??'',
      poster: v['stream_icon']??'',
      categoryId: v['category_id']?.toString()??'',
      url: '${acc.baseUrl}/movie/${acc.username}/${acc.password}/${v['stream_id']}.${v['container_extension']??'mp4'}',
      streamType: v['container_extension']??'mp4',
    )).toList();
  }

  static Future<List<IptvCategory>> getSeriesCategories(IptvAccount acc) async {
    final r = await http.get(Uri.parse('${_api(acc)}&action=get_series_categories'))
      .timeout(const Duration(seconds: 15));
    final list = jsonDecode(r.body) as List;
    return list.map((c) => IptvCategory(c['category_id'].toString(), c['category_name']??'?')).toList();
  }

  static Future<List<IptvSeries>> getSeries(IptvAccount acc, {String? categoryId}) async {
    final cat = categoryId != null ? '&category_id=$categoryId' : '';
    final r = await http.get(Uri.parse('${_api(acc)}&action=get_series$cat'))
      .timeout(const Duration(seconds: 30));
    final list = jsonDecode(r.body) as List;
    return list.map((s) => IptvSeries(
      id: s['series_id'].toString(),
      name: s['name']??'',
      poster: s['cover']??'',
      categoryId: s['category_id']?.toString()??'',
    )).toList();
  }

  static Future<List<IptvEpisode>> getSeriesEpisodes(IptvAccount acc, String seriesId) async {
    final r = await http.get(Uri.parse('${_api(acc)}&action=get_series_info&series_id=$seriesId'))
      .timeout(const Duration(seconds: 15));
    final json = jsonDecode(r.body);
    final episodes = json['episodes'] as Map<String,dynamic>? ?? {};
    final List<IptvEpisode> result = [];
    for (final season in episodes.entries) {
      for (final ep in (season.value as List)) {
        result.add(IptvEpisode(
          id: ep['id'].toString(),
          title: ep['title']??'Episode ${ep['episode_num']}',
          url: '${acc.baseUrl}/series/${acc.username}/${acc.password}/${ep['id']}.${ep['container_extension']??'ts'}',
            
          seriesId: seriesId,
          season: int.tryParse(season.key)??1,
          episode: ep['episode_num']??1,
        ));
      }
    }
    result.sort((a,b) => a.season!=b.season ? a.season-b.season : a.episode-b.episode);
    return result;
  }

  // ── M3U parser ──
  static Future<List<IptvChannel>> parseM3U(String urlOrContent) async {
    String content;
    if (urlOrContent.startsWith('http')) {
      final r = await http.get(Uri.parse(urlOrContent)).timeout(const Duration(seconds: 30));
      content = r.body;
    } else { content = urlOrContent; }

    final channels = <IptvChannel>[];
    final lines = content.split('\n');
    String name='', logo='', groupTitle='';
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.startsWith('#EXTINF')) {
        name = _m3uAttr(line, 'tvg-name') ?? _m3uTitle(line) ?? 'Channel';
        logo = _m3uAttr(line, 'tvg-logo') ?? '';
        groupTitle = _m3uAttr(line, 'group-title') ?? '';
      } else if (line.startsWith('http') || line.startsWith('rtmp')) {
        channels.add(IptvChannel(
          id: i.toString(), name: name, logo: logo,
          categoryId: groupTitle, url: line));
        name=''; logo=''; groupTitle='';
      }
    }
    return channels;
  }

  static String? _m3uAttr(String line, String attr) {
    final re = RegExp('$attr="([^"]*)"');
    return re.firstMatch(line)?.group(1);
  }

  static String? _m3uTitle(String line) {
    final parts = line.split(',');
    return parts.length > 1 ? parts.last.trim() : null;
  }

  // ── تنظیمات refresh ──
  static const _kInterval = 'iptv_refresh_interval_';
  static const _kLastRefresh = 'iptv_last_refresh_';

  static String _accKey(IptvAccount acc) => '${acc.server}_${acc.username}';

  // interval: -1=never, 0=on_open, 60=1h, 120=2h, 360=6h, 720=12h, 1440=24h
  static Future<int> getRefreshInterval(IptvAccount acc) async {
    final p = await SharedPreferences.getInstance();
    return p.getInt('$_kInterval${_accKey(acc)}') ?? 0; // default: on open
  }

  static Future<void> setRefreshInterval(IptvAccount acc, int minutes) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt('$_kInterval${_accKey(acc)}', minutes);
  }

  static Future<DateTime?> getLastRefresh(IptvAccount acc) async {
    final p = await SharedPreferences.getInstance();
    final ms = p.getInt('$_kLastRefresh${_accKey(acc)}');
    return ms != null ? DateTime.fromMillisecondsSinceEpoch(ms) : null;
  }

  static Future<void> setLastRefresh(IptvAccount acc) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt('$_kLastRefresh${_accKey(acc)}', DateTime.now().millisecondsSinceEpoch);
  }

  static Future<bool> shouldRefresh(IptvAccount acc) async {
    final interval = await getRefreshInterval(acc);
    if (interval == -1) return false; // never
    if (interval == 0) return true;   // on every open
    final last = await getLastRefresh(acc);
    if (last == null) return true;
    return DateTime.now().difference(last).inMinutes >= interval;
  }

}