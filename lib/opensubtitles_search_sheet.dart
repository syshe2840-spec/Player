import 'package:flutter/material.dart';
import 'opensubtitles_service.dart';
import 'srt_translate_sheet.dart';
import 'main.dart' show showSnack;
import 'l10n.dart';

/// شیت جستجو و دانلود زیرنویس آنلاین از OpenSubtitles
class OpenSubtitlesSheet extends StatefulWidget {
  final String videoPath;
  final void Function(String srtPath) onDone;
  final void Function(String srtPath)? onDoneSecondary; // برای sub2
  const OpenSubtitlesSheet({super.key, required this.videoPath, required this.onDone, this.onDoneSecondary});

  static Future<void> show(BuildContext ctx, String videoPath, void Function(String) onDone, {void Function(String)? onDoneSecondary}) =>
      showModalBottomSheet(
        context: ctx,
        isScrollControlled: true,
        backgroundColor: const Color(0xFF1C1C22),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (_) => OpenSubtitlesSheet(videoPath: videoPath, onDone: onDone, onDoneSecondary: onDoneSecondary),
      );

  @override State<OpenSubtitlesSheet> createState() => _State();
}

enum _Phase { titles, episode, subs }

class _State extends State<OpenSubtitlesSheet> {
  _Phase _phase = _Phase.titles;
  final _searchCtrl = TextEditingController();
  bool _loading = false;
  String? _error;
  int _subTarget = 0; // 0=sub1, 1=sub2, 2=هر دو

  List<OsFeature> _titles = [];
  OsFeature? _selectedFeature;
  int _season = 1, _episode = 1;
  List<OsSubtitle> _subs = [];
  String _langFilter = '';

  @override
  void initState() {
    super.initState();
    final parsed = OpenSubtitlesService.parseFilename(widget.videoPath);
    _searchCtrl.text = parsed.title;
    if (parsed.season != null) _season = parsed.season!;
    if (parsed.episode != null) _episode = parsed.episode!;
    _doTitleSearch();
  }

  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  Future<void> _doTitleSearch() async {
    if (_searchCtrl.text.trim().length < 2) return;
    setState((){ _loading = true; _error = null; _phase = _Phase.titles; });
    try {
      final r = await OpenSubtitlesService.searchTitle(_searchCtrl.text.trim());
      if (mounted) setState((){ _titles = r; _loading = false; });
    } catch (e) {
      if (mounted) setState((){ _error = '$e'; _loading = false; });
    }
  }

  Future<void> _selectFeature(OsFeature f) async {
    setState(() => _selectedFeature = f);
    if (f.type == 'tvshow') {
      setState(() => _phase = _Phase.episode);
    } else {
      await _doSubsSearch();
    }
  }

  Future<void> _doSubsSearch() async {
    if (_selectedFeature == null) return;
    setState((){ _loading = true; _error = null; _phase = _Phase.subs; });
    try {
      final r = await OpenSubtitlesService.searchSubtitles(
        feature: _selectedFeature!,
        season: _selectedFeature!.type == 'tvshow' ? _season : null,
        episode: _selectedFeature!.type == 'tvshow' ? _episode : null,
        language: _langFilter.isEmpty ? null : _langFilter,
      );
      if (mounted) setState((){ _subs = r; _loading = false; });
    } catch (e) {
      if (mounted) setState((){ _error = '$e'; _loading = false; });
    }
  }

  Future<void> _download(OsSubtitle sub) async {
    setState((){ _loading = true; _error = null; });
    try {
      int? remaining;
      final path = await OpenSubtitlesService.downloadSubtitle(
        sub: sub, videoPath: widget.videoPath,
        onQuota: (r) => remaining = r,
      );
      if (mounted) {
        Navigator.pop(context);
        // مسیردهی بر اساس انتخاب sub1/sub2/هر دو
        switch (_subTarget) {
          case 0: widget.onDone(path); break;
          case 1: widget.onDoneSecondary?.call(path); break;
          case 2: widget.onDone(path); widget.onDoneSecondary?.call(path); break;
        }
        final msg = remaining != null
          ? '${L.subtitleDownloaded} — \$remaining ${L.downloadCount} ${L.remaining}'
          : _subTarget == 1 ? L.sub2Applied : L.subtitleDownloaded;
        // بعد از دانلود: پیشنهاد ترجمه
        showSnack(context, msg, actionLabel: L.translationLabel, onAction: () => SrtTranslateSheet.show(context, path, (translated) { widget.onDone(translated); }));
      }
    } catch (e) {
      if (mounted) setState((){ _error = '$e'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext ctx) => SafeArea(
    child: ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
      child: SingleChildScrollView(
        padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: MediaQuery.of(ctx).viewInsets.bottom + 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 14),
          Row(children: [
            const Icon(Icons.cloud_download_outlined, color: Color(0xFF7C3AED), size: 20),
            const SizedBox(width: 8),
            Text(L.onlineSubtitleLabel, style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
            const Spacer(),
            if (_phase != _Phase.titles) TextButton(
              onPressed: () => setState(() => _phase = _selectedFeature?.type == 'tvshow' && _phase == _Phase.subs ? _Phase.episode : _Phase.titles),
              child: Text(L.back, style: TextStyle(fontSize: 12))),
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(L.close)),
          ]),
          const SizedBox(height: 10),

          // ── جستجوی دستی (همیشه در دسترس) ──
          Row(children: [
            Expanded(child: TextField(
              controller: _searchCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: L.movieOrShow,
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                filled: true, fillColor: const Color(0xFF2A2A35),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              ),
              onSubmitted: (_) => _doTitleSearch(),
            )),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _doTitleSearch,
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF7C3AED), minimumSize: const Size(0, 44)),
              child: const Icon(Icons.search, size: 18),
            ),
          ]),
          const SizedBox(height: 10),

          // ── انتخاب Sub1 / Sub2 / هر دو ──
          Row(children: [
            _subChip('Sub 1', 0),
            const SizedBox(width: 6),
            _subChip('Sub 2', 1),
            const SizedBox(width: 6),
            _subChip(L.both, 2),
          ]),
          const SizedBox(height: 12),

          if (_error != null) Container(
            padding: const EdgeInsets.all(10),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(color: Colors.red.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
            child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
          ),

          if (_loading) Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator(color: Color(0xFF7C3AED)))
          else if (_phase == _Phase.titles) ..._buildTitles()
          else if (_phase == _Phase.episode) ..._buildEpisodePicker()
          else ..._buildSubs(),
        ]),
      ),
    ),
  );

  List<Widget> _buildTitles() {
    if (_titles.isEmpty) return [Padding(padding: EdgeInsets.all(20),
      child: Text(L.notFoundTry, style: TextStyle(color: Colors.white38, fontSize: 12)))];
    return _titles.map((f) => Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(color: const Color(0xFF2A2A35), borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        onTap: () => _selectFeature(f),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: f.imgUrl != null && f.imgUrl!.startsWith('http')
            ? Image.network(f.imgUrl!, width: 42, height: 58, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _posterFallback())
            : _posterFallback(),
        ),
        title: Text(f.title, style: const TextStyle(color: Colors.white, fontSize: 13), maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Row(children: [
          if (f.year != null) Text(f.year!, style: const TextStyle(color: Colors.white54, fontSize: 11)),
          const SizedBox(width: 6),
          Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(color: const Color(0xFF7C3AED).withOpacity(0.2), borderRadius: BorderRadius.circular(6)),
            child: Text(f.type == 'tvshow' ? L.tvShow : L.movie, style: const TextStyle(color: Color(0xFF7C3AED), fontSize: 10))),
        ]),
        trailing: const Icon(Icons.chevron_left, color: Colors.white38, size: 18),
      ),
    )).toList();
  }

  Widget _posterFallback() => Container(width: 42, height: 58, color: const Color(0xFF1C1C22),
    child: const Icon(Icons.movie_outlined, color: Colors.white24, size: 20));

  List<Widget> _buildEpisodePicker() => [
    Text(_selectedFeature?.title ?? '', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
    const SizedBox(height: 12),
    Row(children: [
      Expanded(child: _numberField(L.season, _season, (v) => setState(() => _season = v))),
      const SizedBox(width: 10),
      Expanded(child: _numberField(L.episode, _episode, (v) => setState(() => _episode = v))),
    ]),
    const SizedBox(height: 14),
    SizedBox(width: double.infinity, child: FilledButton.icon(
      onPressed: _doSubsSearch,
      icon: const Icon(Icons.search, size: 16),
      label: Text(L.searchThisEpisode),
      style: FilledButton.styleFrom(backgroundColor: const Color(0xFF7C3AED), padding: const EdgeInsets.symmetric(vertical: 14)),
    )),
  ];

  Widget _numberField(String label, int value, void Function(int) onChanged) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    decoration: BoxDecoration(color: const Color(0xFF2A2A35), borderRadius: BorderRadius.circular(10)),
    child: Row(children: [
      Expanded(child: Text(label, style: const TextStyle(color: Colors.white60, fontSize: 12))),
      IconButton(icon: const Icon(Icons.remove, color: Colors.white54, size: 16),
        onPressed: value > 1 ? () => onChanged(value - 1) : null, constraints: const BoxConstraints(), padding: const EdgeInsets.all(4)),
      Text('$value', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
      IconButton(icon: const Icon(Icons.add, color: Colors.white54, size: 16),
        onPressed: () => onChanged(value + 1), constraints: const BoxConstraints(), padding: const EdgeInsets.all(4)),
    ]),
  );

  List<Widget> _buildSubs() {
    if (_subs.isEmpty) return [Padding(padding: EdgeInsets.all(20),
      child: Text(L.noSubtitleFound, style: TextStyle(color: Colors.white38, fontSize: 12)))];

    // زبان‌های موجود — برای دیدن این که چه کشورهایی موجودند
    final langs = _subs.map((s) => s.language).toSet().toList()..sort();

    return [
      if (langs.length > 1) Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
          _langChip(L.allItems, ''),
          ...langs.map((l) => Padding(padding: const EdgeInsets.only(left: 6), child: _langChip(l.toUpperCase(), l))),
        ])),
      ),
      ..._subs.map((s) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: const Color(0xFF2A2A35), borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: const Color(0xFF7C3AED).withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
            child: Text(s.language.toUpperCase(), style: const TextStyle(color: Color(0xFF7C3AED), fontSize: 11, fontWeight: FontWeight.bold))),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.release.isEmpty ? L.noName : s.release, style: const TextStyle(color: Colors.white, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Row(children: [
              if (s.hd) Container(padding: const EdgeInsets.symmetric(horizontal: 4), decoration: BoxDecoration(color: Colors.green.withOpacity(0.2), borderRadius: BorderRadius.circular(4)),
                child: const Text('HD', style: TextStyle(color: Colors.green, fontSize: 9))),
              const SizedBox(width: 6),
              Text('\${s.downloadCount} \${L.downloadCount}', style: const TextStyle(color: Colors.white38, fontSize: 10)),
            ]),
          ])),
          IconButton(icon: const Icon(Icons.download, color: Color(0xFF7C3AED)), onPressed: () => _download(s)),
        ]),
      )),
    ];
  }

  Widget _subChip(String label, int idx) => GestureDetector(
    onTap: () => setState(() => _subTarget = idx),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: _subTarget == idx ? const Color(0xFF7C3AED) : const Color(0xFF2A2A35),
        borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(color: _subTarget == idx ? Colors.white : Colors.white60, fontSize: 12)),
    ),
  );

  Widget _langChip(String label, String code) => GestureDetector(
    onTap: () { setState(() => _langFilter = code); _doSubsSearch(); },
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _langFilter == code ? const Color(0xFF7C3AED) : const Color(0xFF2A2A35),
        borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(color: _langFilter == code ? Colors.white : Colors.white60, fontSize: 11)),
    ),
  );
}
