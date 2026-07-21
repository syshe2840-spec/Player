import 'dart:io';
import 'package:flutter/material.dart';
import 'ytdlp_service.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:flutter_go_torrent_streamer/flutter_go_torrent_streamer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';
import 'player.dart';
import 'l10n.dart';

enum _UrlType { direct, youtube, torrent, ytdlp }

_UrlType _detectType(String url) {
  if (url.startsWith('magnet:') || url.endsWith('.torrent')) return _UrlType.torrent;
  if (url.contains('youtube.com') || url.contains('youtu.be')) return _UrlType.youtube;
  // فایل مستقیم → پخش مستقیم
  final lower = url.toLowerCase();
  final isDirect = lower.contains('.mp4') || lower.contains('.mkv') ||
    lower.contains('.m3u8') || lower.contains('.mpd') || lower.contains('.avi') ||
    lower.contains('.mov') || lower.contains('.ts') || lower.contains('.flv') ||
    lower.contains('rtmp://') || lower.contains('rtsp://');
  if (isDirect) return _UrlType.direct;
  // بقیه → yt-dlp
  return _UrlType.ytdlp;
}

class _Quality { final String label, url; _Quality(this.label, this.url); }

class OnlinePlayerSheet extends StatefulWidget {
  const OnlinePlayerSheet({super.key});
  @override State<OnlinePlayerSheet> createState() => _State();
}

class _State extends State<OnlinePlayerSheet> {
  final _ctrl = TextEditingController();
  final _yt = YoutubeExplode();
  bool _loading = false, _cancelled = false, _hasCookies = false;
  String? _error, _title;
  List<_Quality> _qualities = [];
  List<String> _recentUrls = [];
  CancelToken? _dlToken;
  double _dlProgress = 0;
  String _dlStatus = '';
  TorrentStreamSession? _session;

  static const _kKey = 'online_recent_urls';
  static const _savePath = '/storage/emulated/0/Download/Vezoo';

  @override void initState() { super.initState(); _loadRecent(); _checkCookies(); }
  void _checkCookies() => setState(() => _hasCookies = YtDlpService.hasCookies());

  Future<void> _showCookieSheet(BuildContext ctx) async {
    showModalBottomSheet(context: ctx, isScrollControlled: true, backgroundColor: const Color(0xFF12121C),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => StatefulBuilder(builder: (ctx2, ss) => DraggableScrollableSheet(
        initialChildSize: 0.75, maxChildSize: 0.95, minChildSize: 0.5, expand: false,
        builder: (_, sc) => ListView(controller: sc, padding: const EdgeInsets.all(20), children: [
          Row(children: [
            const Icon(Icons.cookie_rounded, color: Color(0xFF7C3AED), size: 20),
            const SizedBox(width: 8),
            const Text('مدیریت Cookie', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            const Spacer(),
            TextButton(onPressed: () => Navigator.pop(ctx2), child: const Text('بستن')),
          ]),
          const SizedBox(height: 8),
          // وضعیت
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _hasCookies ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _hasCookies ? Colors.green.withOpacity(0.3) : Colors.orange.withOpacity(0.3))),
            child: Row(children: [
              Icon(_hasCookies ? Icons.check_circle_rounded : Icons.warning_rounded,
                color: _hasCookies ? Colors.green : Colors.orange, size: 18),
              const SizedBox(width: 8),
              Text(_hasCookies ? '✅ Cookie فعال است' : '⚠️ Cookie تنظیم نشده',
                style: TextStyle(color: _hasCookies ? Colors.green : Colors.orange, fontSize: 13)),
            ])),
          const SizedBox(height: 16),
          // دکمه‌ها
          FilledButton.icon(
            onPressed: () async {
              final r = await FilePicker.platform.pickFiles(
                type: FileType.custom, allowedExtensions: ['txt'],
                dialogTitle: 'انتخاب فایل cookies.txt');
              if (r == null || r.files.isEmpty) return;
              final content = File(r.files.first.path!).readAsStringSync();
              await YtDlpService.saveCookies(content);
              setState(() => _hasCookies = true);
              ss(() {});
            },
            icon: const Icon(Icons.upload_file_rounded, size: 18),
            label: const Text('ایمپورت cookies.txt'),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF7C3AED))),
          const SizedBox(height: 8),
          if (_hasCookies) OutlinedButton.icon(
            onPressed: () async {
              await YtDlpService.deleteCookies();
              setState(() => _hasCookies = false);
              ss(() {});
            },
            icon: const Icon(Icons.delete_rounded, size: 18, color: Colors.red),
            label: const Text('حذف Cookie', style: TextStyle(color: Colors.red)),
            style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red))),
          const SizedBox(height: 20),
          // راهنما
          const Text('📖 راهنمای دریافت Cookie', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 12),
          _cookieMethod('1️⃣ Chrome Extension (آسان‌ترین)', [
            'نصب افزونه "Get cookies.txt LOCALLY" از Chrome Web Store',
            'باز کردن سایت مورد نظر (اینستا، TikTok...)',
            'کلیک روی آیکون افزونه',
            'انتخاب "Export" → دانلود cookies.txt',
            'ایمپورت فایل در Vezoo',
          ]),
          const SizedBox(height: 12),
          _cookieMethod('2️⃣ Firefox Extension', [
            'نصب "cookies.txt" addon از Firefox Add-ons',
            'ورود به سایت',
            'کلیک روی addon → "Current Site"',
            'ذخیره فایل و ایمپورت',
          ]),
          const SizedBox(height: 12),
          _cookieMethod('3️⃣ DevTools (پیشرفته)', [
            'F12 در مرورگر → Application → Cookies',
            'انتخاب سایت → کپی value ها',
            'ساخت فایل Netscape Cookie Format',
            'هدر: # Netscape HTTP Cookie File',
          ]),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
            child: const Text(
              '💡 نکته: Cookie باید از مرورگری باشه که به اون سایت login کردی. '
              'بعد از import، اینستا، TikTok و سایت‌های نیاز به login کار میکنن.',
              style: TextStyle(color: Colors.white60, fontSize: 11))),
          const SizedBox(height: 20),
        ]))));
  }

  Widget _cookieMethod(String title, List<String> steps) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: const Color(0xFF1A1A2A), borderRadius: BorderRadius.circular(10)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
      const SizedBox(height: 8),
      ...steps.asMap().entries.map((e) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${e.key+1}. ', style: const TextStyle(color: Color(0xFF7C3AED), fontSize: 11, fontWeight: FontWeight.bold)),
          Expanded(child: Text(e.value, style: const TextStyle(color: Colors.white60, fontSize: 11))),
        ]))),
    ]));

  void _showSupportedSites(BuildContext ctx) {
    showDialog(context: ctx, builder: (_) => AlertDialog(
      backgroundColor: const Color(0xFF12121C),
      title: Row(children: [
        const Icon(Icons.public_rounded, color: Color(0xFF7C3AED), size: 18),
        const SizedBox(width: 8),
        const Text('سایت‌های پشتیبانی شده', style: TextStyle(color: Colors.white, fontSize: 14)),
        const Spacer(),
        Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: const Color(0xFF7C3AED), borderRadius: BorderRadius.circular(12)),
          child: const Text('۱۰۰۰+ سایت', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))),
      ]),
      content: SizedBox(width: 280, height: 350,
        child: ListView.separated(
          itemCount: YtDlpService.supportedSites.length,
          separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.white10),
          itemBuilder: (_, i) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(YtDlpService.supportedSites[i],
              style: const TextStyle(color: Colors.white70, fontSize: 13))))),
      actions: [TextButton(
        onPressed: () => Navigator.pop(ctx),
        child: const Text('بستن', style: TextStyle(color: Color(0xFF7C3AED))))],
    ));
  }
  @override void dispose() { _ctrl.dispose(); _yt.close(); super.dispose(); }

  Future<void> _loadRecent() async {
    final p = await SharedPreferences.getInstance();
    setState(() => _recentUrls = p.getStringList(_kKey) ?? []);
  }

  Future<void> _saveRecent(String url) async {
    _recentUrls.remove(url); _recentUrls.insert(0, url);
    if (_recentUrls.length > 15) _recentUrls = _recentUrls.take(15).toList();
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_kKey, _recentUrls);
    if (mounted) setState(() {});
  }

  void _cancel() {
    _cancelled = true;
    _dlToken?.cancel();
    setState(() { _loading = false; _dlStatus = ''; _dlProgress = 0; });
  }

  Future<void> _analyze(String url) async {
    url = url.trim();
    if (url.isEmpty) return;
    if (!url.startsWith('http') && !url.startsWith('magnet:')) {
      setState(() => _error = L.invalidUrl); return;
    }
    setState(() { _loading = true; _error = null; _qualities = []; _title = null; _dlStatus = ''; _cancelled = false; });
    final type = _detectType(url);
    try {
      if (type == _UrlType.youtube) { await _analyzeYoutube(url); }
      else if (type == _UrlType.torrent) { await _analyzeTorrent(url); }
      else if (type == _UrlType.ytdlp) { await _analyzeYtDlp(url); }
      else { await _playDirect(url); }
    } catch (e) {
      if (mounted && !_cancelled) setState(() { _error = 'Error: $e'; _loading = false; _dlStatus = ''; });
    }
  }

  // ── YouTube ──
  Future<void> _analyzeYoutube(String url) async {
    setState(() => _dlStatus = L.fetchingInfo);
    final video = await _yt.videos.get(VideoId(url));
    if (_cancelled) return;
    setState(() => _dlStatus = L.loadingQualities);
    final manifest = await _yt.videos.streams.getManifest(
      VideoId(url), ytClients: [YoutubeApiClient.ios, YoutubeApiClient.androidVr]);
    if (_cancelled) return;
    final list = <_Quality>[];
    for (final s in manifest.muxed.sortByVideoQuality()) {
      list.add(_Quality('${s.qualityLabel} ${s.container.name.toUpperCase()}', s.url.toString()));
    }
    await _saveRecent(url);
    if (mounted) setState(() { _title = video.title; _qualities = list; _loading = false; _dlStatus = ''; });
  }

  // ── Torrent ──
  Future<void> _analyzeTorrent(String url) async {
    setState(() => _dlStatus = L.connectingPeers);
    _cancelled = false;
    final streamer = FlutterTorrentStreamer();
    _session = await streamer.startStream(url, '$_savePath/Torrent');
    // poll تا ready
    for (int i = 0; i < 60; i++) {
      if (_cancelled) return;
      await Future.delayed(const Duration(seconds: 1));
      final sessions = await streamer.getAllSessions();
      final info = sessions.firstOrNull;
      if (info != null) {
        if (mounted) setState(() {
          _dlStatus = '🧲 ${info.state} — ${info.progress.toStringAsFixed(1)}%  ↓${(info.downloadSpeed/1024).toStringAsFixed(0)} KB/s';
        });
        if (info.state == 'Ready' || info.state == 'Seeding') {
          if (_cancelled) return;
          await _saveRecent(url);
          if (!mounted) return;
          // آماده — نمایش دکمه‌های stream و download
          setState(() { _loading = false; _dlStatus = '✓ Ready to play or download'; });
          return;
        }
      } else {
        if (mounted) setState(() => _dlStatus = '${L.connectingPeers} (${i+1}s)');
      }
    }
    if (mounted) setState(() { _error = L.nopeersTimeout; _loading = false; _dlStatus = ''; });
  }

  void _streamTorrent() {
    final s = _session;
    if (s == null) return;
    Navigator.pop(context);
    Navigator.push(context, MaterialPageRoute(builder: (_) =>
      PlayerScreen(playlist: [File(s.streamUrl)], playlistIndex: 0)));
  }

  Future<void> _downloadTorrent() async {
    final s = _session;
    if (s == null) return;
    setState(() { _dlProgress = 0; _dlStatus = L.downloading; });
    final streamer = FlutterTorrentStreamer();
    // polling تا دانلود کامل شه
    for (int i = 0; i < 3600; i++) {
      if (_cancelled) { setState(() => _dlStatus = L.cancelled); return; }
      await Future.delayed(const Duration(seconds: 1));
      final sessions = await streamer.getAllSessions();
      final info = sessions.firstOrNull;
      if (info != null) {
        final pct = info.progress / 100;
        if (mounted) setState(() {
          _dlProgress = pct;
          _dlStatus = '⬇ ${info.progress.toStringAsFixed(1)}%  ${(info.downloadSpeed/1024).toStringAsFixed(0)} KB/s';
        });
        if (info.progress >= 100) {
          if (mounted) setState(() { _dlStatus = '✓ ${L.saved}: $_savePath/Torrent/'; _dlProgress = 0; });
          return;
        }
      }
    }
  }

  // ── Direct ──
  Future<void> _playDirect(String url) async {
    await _saveRecent(url);
    if (!mounted) return;
    Navigator.pop(context);
    Navigator.push(context, MaterialPageRoute(builder: (_) =>
      PlayerScreen(playlist: [File(url)], playlistIndex: 0)));
  }

  Future<void> _analyzeYtDlp(String url) async {
    setState(() => _dlStatus = '⏳ دریافت اطلاعات yt-dlp...');
    try {
      final info = await YtDlpService.getStreamUrl(url);
      if (_cancelled) return;
      final streamUrl = info['url'] as String? ?? '';
      final title = info['title'] as String? ?? '';
      final extractor = info['extractor'] as String? ?? '';
      if (streamUrl.isEmpty) throw Exception('stream URL دریافت نشد');
      if (mounted) setState(() {
        _title = title.isEmpty ? extractor : '$title ($extractor)';
        _qualities = [_Quality('بهترین کیفیت', streamUrl)];
        _loading = false;
        _dlStatus = '';
      });
    } catch (e) {
      if (mounted && !_cancelled) setState(() {
        // نشون دادن خطای کامل
        String errMsg = e.toString();
        // حذف Exception: prefix
        if (errMsg.startsWith('Exception: ')) errMsg = errMsg.substring(11);
        _error = errMsg;
        _loading = false;
        _dlStatus = '';
      });
    }
  }

  Future<void> _downloadYtDlp(String url, String label) async {
    final fileName = '${DateTime.now().millisecondsSinceEpoch}.mp4';
    final dir = '/storage/emulated/0/Download/Vezoo';
    _downloadYt(url, label); // استفاده از همون downloader موجود
  }

  void _playYt(String url) {
    Navigator.pop(context);
    Navigator.push(context, MaterialPageRoute(builder: (_) =>
      PlayerScreen(playlist: [File(url)], playlistIndex: 0)));
  }

  Future<void> _downloadYt(String url, String label) async {
    final dir = Directory('$_savePath/YouTube');
    await dir.create(recursive: true);
    final safe = (_title ?? 'video').replaceAll(RegExp(r'[/\\:*?"<>|]'), '_');
    final ext = label.contains('WEBM') ? 'webm' : 'mp4';
    final dest = '${dir.path}/$safe ($label).$ext';
    setState(() { _dlProgress = 0; _dlStatus = L.downloading; });
    _dlToken = CancelToken();
    try {
      await Dio().download(url, dest, cancelToken: _dlToken,
        onReceiveProgress: (r, t) { if (mounted && t > 0) setState(() { _dlProgress = r / t;
          _dlStatus = '⬇ ${(r/1024/1024).toStringAsFixed(1)}MB / ${(t/1024/1024).toStringAsFixed(1)}MB'; }); });
      if (mounted) setState(() { _dlStatus = '✓ ${L.saved}: YouTube/'; _dlProgress = 0; });
    } on DioException catch (e) {
      if (mounted) setState(() { _dlStatus = e.type == DioExceptionType.cancel ? L.cancelled : 'Error'; _dlProgress = 0; });
    }
  }

  @override Widget build(BuildContext context) {
    final bot = MediaQuery.of(context).viewPadding.bottom;
    final torrentReady = _session != null && !_loading && _dlStatus.contains('✓ Ready');
    return DraggableScrollableSheet(
      initialChildSize: 0.7, maxChildSize: 0.95, minChildSize: 0.4,
      builder: (_, sc) => Container(
        decoration: const BoxDecoration(color: Color(0xFF0E0E1A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
        child: Column(children: [
          Container(width: 40, height: 4, margin: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(L.onlineVideo, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white))),
          const SizedBox(height: 10),
          // ── input ──
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Row(children: [
            IconButton(
              onPressed: () => _showSupportedSites(context),
              icon: const Icon(Icons.help_outline_rounded, color: Colors.white54, size: 20),
              tooltip: 'سایت‌های پشتیبانی شده',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints()),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: () => _showCookieSheet(context),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _hasCookies ? Colors.green.withOpacity(0.2) : Colors.white12,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: _hasCookies ? Colors.green : Colors.white24)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.cookie_rounded, size: 13, color: _hasCookies ? Colors.green : Colors.white38),
                  const SizedBox(width: 4),
                  Text(_hasCookies ? 'Cookie ✓' : 'Cookie', style: TextStyle(fontSize: 11, color: _hasCookies ? Colors.green : Colors.white38)),
                ]))),
            const SizedBox(width: 4),
            Expanded(child: TextField(controller: _ctrl,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'YouTube / Instagram / TikTok / ۱۰۰۰+ سایت...',
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                suffixIcon: _ctrl.text.isNotEmpty ? IconButton(
                  icon: const Icon(Icons.clear, size: 16, color: Colors.white38),
                  onPressed: () { _ctrl.clear(); setState(() {}); }) : null,
                filled: true, fillColor: const Color(0xFF1A1A2A),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10)),
              onChanged: (_) => setState(() {}),
              onSubmitted: _analyze)),
            const SizedBox(width: 8),
            if (_loading)
              OutlinedButton(onPressed: _cancel,
                style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent,
                  side: const BorderSide(color: Colors.redAccent),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
                child: Text(L.cancel, style: const TextStyle(fontSize: 12)))
            else
              FilledButton(onPressed: () => _analyze(_ctrl.text),
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF7C3AED),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12)),
                child: const Icon(Icons.play_arrow_rounded, size: 22)),
          ])),
          if (_error != null) Padding(padding: const EdgeInsets.fromLTRB(16,8,16,0),
            child: Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12))),
          // ── progress ──
          if (_dlProgress > 0 || _dlStatus.isNotEmpty) Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (_dlProgress > 0 && _dlProgress < 1) ClipRRect(borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: _dlProgress, minHeight: 6,
                  backgroundColor: Colors.white12, color: const Color(0xFF7C3AED))),
              const SizedBox(height: 4),
              Row(children: [
                Expanded(child: Text(_dlStatus, style: const TextStyle(color: Colors.white60, fontSize: 11))),
                if (_loading) GestureDetector(onTap: _cancel,
                  child: Text(L.cancel, style: const TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.w600))),
              ]),
            ])),
          // ── torrent action buttons ──
          if (torrentReady) Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Row(children: [
              Expanded(child: FilledButton.icon(
                onPressed: _streamTorrent,
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: Text(L.streamNow),
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF22c55e)))),
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton.icon(
                onPressed: _downloadTorrent,
                icon: const Icon(Icons.download_rounded, size: 18),
                label: Text(L.downloadFull))),
            ])),
          const SizedBox(height: 8),
          Expanded(child: ListView(controller: sc,
            padding: EdgeInsets.fromLTRB(16, 0, 16, bot + 16),
            children: [
              // YouTube qualities
              if (_qualities.isNotEmpty) ...[
                if (_title != null) Padding(padding: const EdgeInsets.only(bottom: 8),
                  child: Text(_title!, style: const TextStyle(color: Colors.white70, fontSize: 13),
                    maxLines: 2, overflow: TextOverflow.ellipsis)),
                ...List.generate(_qualities.length, (i) {
                  final q = _qualities[i];
                  return Container(margin: const EdgeInsets.only(bottom: 6),
                    decoration: BoxDecoration(color: const Color(0xFF1A1A2A), borderRadius: BorderRadius.circular(10)),
                    child: ListTile(dense: true,
                      leading: const Icon(Icons.play_circle_outline_rounded, color: Color(0xFF7C3AED), size: 20),
                      title: Text(q.label, style: const TextStyle(color: Colors.white, fontSize: 13)),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(icon: const Icon(Icons.play_arrow_rounded, color: Color(0xFF7C3AED), size: 22),
                          onPressed: () => _playYt(q.url), tooltip: L.play),
                        IconButton(icon: const Icon(Icons.download_rounded, color: Colors.white54, size: 20),
                          onPressed: () => _downloadYt(q.url, q.label), tooltip: L.download),
                      ])));
                }),
              ],
              // Recent
              if (_qualities.isEmpty && !torrentReady && _recentUrls.isNotEmpty) ...[
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text(L.recentUrls, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                  TextButton(onPressed: () async {
                    final p = await SharedPreferences.getInstance();
                    await p.remove(_kKey); setState(() => _recentUrls = []);
                  }, child: Text(L.deleteAll, style: const TextStyle(fontSize: 11, color: Colors.white38))),
                ]),
                ...List.generate(_recentUrls.length, (i) => ListTile(dense: true,
                  leading: Icon(_detectType(_recentUrls[i]) == _UrlType.torrent
                    ? Icons.cloud_queue_rounded : _detectType(_recentUrls[i]) == _UrlType.youtube
                    ? Icons.smart_display_rounded : Icons.link_rounded,
                    color: Colors.white38, size: 16),
                  title: Text(_recentUrls[i], style: const TextStyle(color: Colors.white60, fontSize: 11),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () { _ctrl.text = _recentUrls[i]; setState(() {}); _analyze(_recentUrls[i]); })),
              ],
            ])),
        ]),
      ),
    );
  }
}
