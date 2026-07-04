import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'player.dart';

class OnlinePlayerSheet extends StatefulWidget {
  const OnlinePlayerSheet({super.key});

  static Future<void> show(BuildContext ctx) => showModalBottomSheet(
    context: ctx, isScrollControlled: true,
    backgroundColor: const Color(0xFF1C1C22),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => const OnlinePlayerSheet(),
  );

  @override State<OnlinePlayerSheet> createState() => _State();
}

class _State extends State<OnlinePlayerSheet> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  List<String> _recent = [];
  bool _loading = false;
  String? _error;

  // فرمت‌های پشتیبانی‌شده
  static const _hints = [
    'https://example.com/video.mp4',
    'https://stream.example.com/live.m3u8',
    'https://example.com/video.mkv',
  ];
  int _hintIdx = 0;

  @override
  void initState() {
    super.initState();
    _loadRecent();
    _startHintCycle();
  }

  @override
  void dispose() { _ctrl.dispose(); _focus.dispose(); super.dispose(); }

  void _startHintCycle() {
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _hintIdx = (_hintIdx + 1) % _hints.length);
      _startHintCycle();
    });
  }

  Future<void> _loadRecent() async {
    final p = await SharedPreferences.getInstance();
    setState(() => _recent = p.getStringList('recent_online_urls') ?? []);
  }

  Future<void> _saveRecent(String url) async {
    final p = await SharedPreferences.getInstance();
    final list = [url, ..._recent.where((u) => u != url)].take(10).toList();
    await p.setStringList('recent_online_urls', list);
    setState(() => _recent = list);
  }

  Future<void> _removeRecent(String url) async {
    final p = await SharedPreferences.getInstance();
    final list = _recent.where((u) => u != url).toList();
    await p.setStringList('recent_online_urls', list);
    setState(() => _recent = list);
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData('text/plain');
    if (data?.text != null) {
      _ctrl.text = data!.text!.trim();
      _ctrl.selection = TextSelection.fromPosition(TextPosition(offset: _ctrl.text.length));
    }
  }

  bool _isValidUrl(String url) =>
    url.startsWith('http://') || url.startsWith('https://') || url.startsWith('rtmp://');

  Future<void> _play(String url) async {
    url = url.trim();
    if (!_isValidUrl(url)) {
      setState(() => _error = 'URL باید با http:// یا https:// شروع شود');
      return;
    }
    setState(() { _loading = true; _error = null; });
    await _saveRecent(url);
    if (!mounted) return;
    Navigator.pop(context);
    await Navigator.push(context, MaterialPageRoute(
      builder: (_) => PlayerScreen(
        playlist: [File(url)], // MediaKit accepts URLs as file paths
        playlistIndex: 0,
        isOnlineUrl: true,
      ),
    ));
  }

  @override
  Widget build(BuildContext ctx) => SafeArea(
    child: ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.88),
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // ── Handle ──
          Container(width: 40, height: 4, margin: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),

          // ── Header ──
          Padding(padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              Container(padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: const Color(0xFF7C3AED).withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.play_circle_outline, color: Color(0xFF7C3AED), size: 24)),
              const SizedBox(width: 12),
              const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('پخش آنلاین', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                Text('MP4 · MKV · HLS · DASH', style: TextStyle(color: Colors.white38, fontSize: 11)),
              ]),
              const Spacer(),
              IconButton(icon: const Icon(Icons.close, color: Colors.white38), onPressed: () => Navigator.pop(ctx)),
            ]),
          ),
          const SizedBox(height: 16),

          // ── URL Input ──
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A35),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _focus.hasFocus ? const Color(0xFF7C3AED) : Colors.transparent, width: 1.5),
              ),
              child: Column(children: [
                Row(children: [
                  const SizedBox(width: 14),
                  const Icon(Icons.link, color: Colors.white38, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(
                    controller: _ctrl, focusNode: _focus,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.go,
                    onSubmitted: (_) => _play(_ctrl.text),
                    onChanged: (_) { if (_error != null) setState(() => _error = null); },
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: _hints[_hintIdx],
                      hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  )),
                  if (_ctrl.text.isNotEmpty)
                    IconButton(icon: const Icon(Icons.clear, color: Colors.white38, size: 18),
                      onPressed: () { _ctrl.clear(); setState(() {}); }),
                ]),
                Container(height: 1, color: Colors.white12),
                Row(children: [
                  TextButton.icon(onPressed: _paste,
                    icon: const Icon(Icons.content_paste, size: 15),
                    label: const Text('جای‌گذاری', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(foregroundColor: Colors.white54)),
                  const Spacer(),
                  Padding(padding: const EdgeInsets.only(right: 8),
                    child: FilledButton(
                      onPressed: _loading ? null : () => _play(_ctrl.text),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF7C3AED),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                      child: _loading
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.play_arrow, size: 18), SizedBox(width: 4), Text('پخش'),
                          ]),
                    )),
                ]),
              ]),
            ),
          ),

          // ── Error ──
          if (_error != null) Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 16),
              const SizedBox(width: 6),
              Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
            ]),
          ),

          // ── فرمت‌های پشتیبانی‌شده ──
          Padding(padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Row(children: [
              for (final f in ['MP4', 'MKV', 'M3U8', 'DASH', 'AVI']) ...[
                Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(6)),
                  child: Text(f, style: const TextStyle(color: Colors.white38, fontSize: 10))),
                const SizedBox(width: 4),
              ],
            ]),
          ),

          // ── تاریخچه ──
          if (_recent.isNotEmpty) ...[
            Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(children: [
                const Icon(Icons.history, color: Colors.white38, size: 14),
                const SizedBox(width: 6),
                const Text('اخیر', style: TextStyle(color: Colors.white38, fontSize: 12)),
              ]),
            ),
            Flexible(child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _recent.length,
              itemBuilder: (_, i) {
                final url = _recent[i];
                final isHls = url.contains('.m3u8');
                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  decoration: BoxDecoration(color: const Color(0xFF2A2A35), borderRadius: BorderRadius.circular(12)),
                  child: ListTile(
                    onTap: () { _ctrl.text = url; _play(url); },
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                    leading: Container(width: 32, height: 32,
                      decoration: BoxDecoration(color: const Color(0xFF7C3AED).withOpacity(0.15), shape: BoxShape.circle),
                      child: Icon(isHls ? Icons.stream : Icons.movie_outlined, color: const Color(0xFF7C3AED), size: 16)),
                    title: Text(url, style: const TextStyle(color: Colors.white, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(isHls ? 'HLS Stream' : 'Video', style: const TextStyle(color: Colors.white38, fontSize: 10)),
                    trailing: IconButton(icon: const Icon(Icons.close, color: Colors.white24, size: 16),
                      onPressed: () => _removeRecent(url), constraints: const BoxConstraints(), padding: const EdgeInsets.all(4)),
                  ),
                );
              },
            )),
          ],
          const SizedBox(height: 8),
        ]),
      ),
    ),
  );
}

