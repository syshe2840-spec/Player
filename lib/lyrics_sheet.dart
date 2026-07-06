import 'dart:io';
import 'package:flutter/material.dart';
import 'lyrics_service.dart';

class LyricsSheet extends StatefulWidget {
  final String videoPath;
  final String? initialQuery;
  final void Function(String srtPath) onDone;

  const LyricsSheet({super.key, required this.videoPath, this.initialQuery, required this.onDone});

  static Future<void> show(BuildContext ctx, String videoPath, void Function(String) onDone, {String? query}) =>
    showModalBottomSheet(
      context: ctx, isScrollControlled: true,
      backgroundColor: const Color(0xFF1C1C22),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => LyricsSheet(videoPath: videoPath, initialQuery: query, onDone: onDone),
    );

  @override State<LyricsSheet> createState() => _State();
}

class _State extends State<LyricsSheet> with SingleTickerProviderStateMixin {
  late TabController _tab;
  final _ctrl = TextEditingController();
  bool _loading = false;
  String? _error;
  Map<String, List<LyricsTrack>> _results = {'lrclib': [], 'genius': []};
  LyricsTrack? _selected;
  bool _applying = false;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    if (widget.initialQuery != null) {
      _ctrl.text = widget.initialQuery!;
      WidgetsBinding.instance.addPostFrameCallback((_) => _search());
    }
  }

  @override void dispose() { _tab.dispose(); _ctrl.dispose(); super.dispose(); }

  Future<void> _search() async {
    if (_ctrl.text.trim().isEmpty) return;
    setState(() { _loading = true; _error = null; _results = {'lrclib':[],'genius':[]}; });
    try {
      final r = await LyricsService.search(_ctrl.text.trim());
      if (mounted) setState(() { _results = r; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = '$e'; _loading = false; });
    }
  }

  Future<void> _apply(LyricsTrack track) async {
    setState(() { _selected = track; _applying = true; });
    try {
      String srtContent = '';
      String suffix = 'lyrics';

      if (track.source == 'lrclib') {
        final result = await LyricsService.fetchLrcLib(track.id);
        if (result == null) throw Exception('دریافت ناموفق');
        if (result.hasSynced) {
          srtContent = LyricsService.lrcToSrt(result.syncedLrc!);
          suffix = 'lrc_synced';
        } else if (result.plainLyrics != null) {
          // متن ساده بدون sync — یه SRT ساده با فاصله ۴ ثانیه
          final lines = result.plainLyrics!.split('\n').where((l) => l.trim().isNotEmpty).toList();
          final b = StringBuffer();
          for (int i = 0; i < lines.length; i++) {
            final start = Duration(seconds: i * 4);
            final end = Duration(seconds: (i + 1) * 4);
            b.writeln(i + 1);
            b.writeln('${LyricsService._t(start)} --> ${LyricsService._t(end)}');
            b.writeln(lines[i]);
            b.writeln();
          }
          srtContent = b.toString();
          suffix = 'lyrics_plain';
        }
      } else if (track.source == 'genius') {
        // Genius فقط متن داره — نشون بده
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Genius فقط متن دارد (sync ندارد) — در مرورگر باز شود؟'),
          action: SnackBarAction(label: 'باز کن', textColor: Colors.white, onPressed: () {
            // open genius URL
          }),
          backgroundColor: const Color(0xFF7C3AED)));
        setState(() { _applying = false; });
        return;
      }

      if (srtContent.isEmpty) throw Exception('متن یافت نشد');

      final path = await LyricsService.saveAsSubtitle(widget.videoPath, srtContent, suffix);
      if (mounted) {
        Navigator.pop(context);
        widget.onDone(path);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(track.hasSynced ? '✓ LRC sync شده اعمال شد' : '✓ متن اعمال شد (بدون sync)'),
          backgroundColor: const Color(0xFF7C3AED)));
      }
    } catch (e) {
      if (mounted) setState(() { _applying = false; _error = '$e'; });
    }
  }

  @override
  Widget build(BuildContext ctx) => SafeArea(
    child: ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.9),
      child: Column(children: [
        // ── Handle ──
        Container(width:40,height:4,margin:const EdgeInsets.symmetric(vertical:12),
          decoration:BoxDecoration(color:Colors.white24,borderRadius:BorderRadius.circular(2))),

        // ── Header ──
        Padding(padding: const EdgeInsets.symmetric(horizontal:16),
          child: Row(children: [
            const Icon(Icons.music_note, color: Color(0xFF7C3AED), size: 20),
            const SizedBox(width: 8),
            const Text('زیرنویس موزیک', style: TextStyle(color:Colors.white, fontSize:16, fontWeight:FontWeight.bold)),
            const Spacer(),
            IconButton(icon:const Icon(Icons.close,color:Colors.white38), onPressed:()=>Navigator.pop(ctx)),
          ]),
        ),

        // ── Search ──
        Padding(padding: const EdgeInsets.fromLTRB(16,8,16,8),
          child: Row(children: [
            Expanded(child: TextField(
              controller: _ctrl,
              style: const TextStyle(color:Colors.white, fontSize:13),
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                hintText: 'نام آهنگ + خواننده...',
                hintStyle: const TextStyle(color:Colors.white30, fontSize:12),
                filled: true, fillColor: const Color(0xFF2A2A35),
                border: OutlineInputBorder(borderRadius:BorderRadius.circular(10), borderSide:BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal:12, vertical:10),
                prefixIcon: const Icon(Icons.search, color:Colors.white38, size:18),
                isDense: true,
              ),
            )),
            const SizedBox(width:8),
            FilledButton(
              onPressed: _loading ? null : _search,
              style: FilledButton.styleFrom(backgroundColor:const Color(0xFF7C3AED), padding:const EdgeInsets.symmetric(horizontal:14,vertical:10)),
              child: _loading
                ? const SizedBox(width:16,height:16,child:CircularProgressIndicator(strokeWidth:2,color:Colors.white))
                : const Text('جستجو', style:TextStyle(fontSize:12)),
            ),
          ]),
        ),

        // ── Tabs ──
        TabBar(controller:_tab, tabs:[
          Tab(text:'LRCLib (sync) ${_results['lrclib']!.isNotEmpty ? "(${_results['lrclib']!.length})" : ""}'),
          Tab(text:'Genius ${_results['genius']!.isNotEmpty ? "(${_results['genius']!.length})" : ""}'),
        ], indicatorColor:const Color(0xFF7C3AED), labelColor:const Color(0xFF7C3AED), unselectedLabelColor:Colors.white54,
          labelStyle:const TextStyle(fontSize:12)),

        // ── Error ──
        if (_error != null) Padding(
          padding: const EdgeInsets.all(8),
          child: Text(_error!, style:const TextStyle(color:Colors.red,fontSize:12))),

        // ── Results ──
        Expanded(child: TabBarView(controller:_tab, children:[
          _buildList(_results['lrclib']!),
          _buildList(_results['genius']!),
        ])),

        if (_applying) const LinearProgressIndicator(color:Color(0xFF7C3AED), backgroundColor:Colors.white12),
      ]),
    ),
  );

  Widget _buildList(List<LyricsTrack> tracks) {
    if (tracks.isEmpty) return Center(
      child: Text(_loading ? 'در حال جستجو...' : 'نتیجه‌ای نیست',
        style:const TextStyle(color:Colors.white38,fontSize:13)));
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal:8,vertical:4),
      itemCount: tracks.length,
      itemBuilder: (_,i) {
        final t = tracks[i];
        final isSelected = _selected?.id == t.id && _selected?.source == t.source;
        return Container(
          margin: const EdgeInsets.only(bottom:6),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF7C3AED).withOpacity(0.2) : const Color(0xFF2A2A35),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: isSelected ? const Color(0xFF7C3AED) : Colors.transparent)),
          child: ListTile(
            dense: true,
            leading: Container(width:36,height:36,
              decoration:BoxDecoration(color:const Color(0xFF7C3AED).withOpacity(0.15),borderRadius:BorderRadius.circular(8)),
              child: Icon(t.hasSynced ? Icons.lyrics_rounded : Icons.text_fields_rounded,
                color:t.hasSynced ? const Color(0xFF7C3AED) : Colors.white38, size:18)),
            title: Text('${t.title}', style:const TextStyle(fontSize:13,color:Colors.white), maxLines:1, overflow:TextOverflow.ellipsis),
            subtitle: Text('${t.artist}${t.album.isNotEmpty?" • ${t.album}":""}',
              style:const TextStyle(fontSize:10,color:Colors.white54), maxLines:1, overflow:TextOverflow.ellipsis),
            trailing: Column(mainAxisAlignment:MainAxisAlignment.center, children:[
              if (t.hasSynced) Container(padding:const EdgeInsets.symmetric(horizontal:6,vertical:2),
                decoration:BoxDecoration(color:const Color(0xFF7C3AED).withOpacity(0.2),borderRadius:BorderRadius.circular(4)),
                child:const Text('SYNC',style:TextStyle(color:Color(0xFF7C3AED),fontSize:9,fontWeight:FontWeight.bold))),
              const SizedBox(height:2),
              const Icon(Icons.download_rounded,size:16,color:Colors.white38),
            ]),
            onTap: _applying ? null : () => _apply(t),
          ),
        );
      },
    );
  }
}
