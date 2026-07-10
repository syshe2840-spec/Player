import 'dart:io';
import 'package:flutter/material.dart';
import 'lyrics_service.dart';
import 'main.dart' show showSnack;
import 'l10n.dart';

String _lrcT(Duration d) =>
  '${d.inHours.toString().padLeft(2,'0')}:'
  '${(d.inMinutes%60).toString().padLeft(2,'0')}:'
  '${(d.inSeconds%60).toString().padLeft(2,'0')},'
  '${(d.inMilliseconds%1000).toString().padLeft(3,'0')}';

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

class _State extends State<LyricsSheet> {
  final _ctrl = TextEditingController();
  bool _loading = false;
  String? _error;
  List<LyricsTrack> _results = [];
  bool _applying = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialQuery != null) {
      _ctrl.text = widget.initialQuery!;
      WidgetsBinding.instance.addPostFrameCallback((_) => _search());
    }
  }

  @override void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _search() async {
    if (_ctrl.text.trim().isEmpty) return;
    setState(() { _loading = true; _error = null; _results = []; });
    try {
      final r = await LyricsService.search(_ctrl.text.trim());
      if (mounted) setState(() { _results = r['lrclib'] ?? []; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = '$e'; _loading = false; });
    }
  }

  Future<void> _apply(LyricsTrack track) async {
    setState(() { _applying = true; });
    try {
      final result = await LyricsService.fetchLrcLib(track.id);
      if (result == null) throw Exception(L.fetchFailed);

      String srtContent;
      String suffix;

      if (result.hasSynced) {
        srtContent = LyricsService.lrcToSrt(result.syncedLrc!);
        suffix = 'lrc_synced';
      } else if (result.plainLyrics != null) {
        final lines = result.plainLyrics!.split('\n').where((l) => l.trim().isNotEmpty).toList();
        final b = StringBuffer();
        for (int i = 0; i < lines.length; i++) {
          final start = Duration(seconds: i * 4);
          final end = Duration(seconds: (i + 1) * 4);
          b.writeln(i + 1);
          b.writeln('${_lrcT(start)} --> ${_lrcT(end)}');
          b.writeln(lines[i]);
          b.writeln();
        }
        srtContent = b.toString();
        suffix = 'lyrics_plain';
      } else {
        throw Exception(L.noLyrics);
      }

      final path = await LyricsService.saveAsSubtitle(widget.videoPath, srtContent, suffix);
      if (mounted) {
        Navigator.pop(context);
        widget.onDone(path);
        showSnack(context, track.hasSynced ? L.lrcSynced : L.textApplied);
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
        Container(width:40,height:4,margin:const EdgeInsets.symmetric(vertical:12),
          decoration:BoxDecoration(color:Colors.white24,borderRadius:BorderRadius.circular(2))),
        Padding(padding: const EdgeInsets.symmetric(horizontal:16),
          child: Row(children: [
            const Icon(Icons.music_note, color: Color(0xFF7C3AED), size: 20),
            const SizedBox(width: 8),
            Text(L.musicSubLabel, style: TextStyle(color:Colors.white, fontSize:16, fontWeight:FontWeight.bold)),
            const Spacer(),
            IconButton(icon:const Icon(Icons.close,color:Colors.white38), onPressed:()=>Navigator.pop(ctx)),
          ]),
        ),
        Padding(padding: const EdgeInsets.fromLTRB(16,8,16,8),
          child: Row(children: [
            Expanded(child: TextField(
              controller: _ctrl,
              style: const TextStyle(color:Colors.white, fontSize:13),
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                hintText: L.searchSong,
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
                ? SizedBox(width:16,height:16,child:CircularProgressIndicator(strokeWidth:2,color:Colors.white))
                : Text(L.search, style:TextStyle(fontSize:12)),
            ),
          ]),
        ),
        if (_error != null) Padding(
          padding: const EdgeInsets.all(8),
          child: Text(_error!, style:const TextStyle(color:Colors.red,fontSize:12))),
        Expanded(child: _results.isEmpty
          ? Center(child: Text(_loading ? L.searching2 : L.searchHint,
              style:const TextStyle(color:Colors.white38,fontSize:13)))
          : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal:8,vertical:4),
              itemCount: _results.length,
              itemBuilder: (_,i) {
                final t = _results[i];
                return Container(
                  margin: const EdgeInsets.only(bottom:6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2A35),
                    borderRadius: BorderRadius.circular(10)),
                  child: ListTile(
                    dense: true,
                    leading: Container(width:36,height:36,
                      decoration:BoxDecoration(color:const Color(0xFF7C3AED).withOpacity(0.15),borderRadius:BorderRadius.circular(8)),
                      child: Icon(t.hasSynced ? Icons.lyrics_rounded : Icons.text_fields_rounded,
                        color:t.hasSynced ? const Color(0xFF7C3AED) : Colors.white38, size:18)),
                    title: Text(t.title, style:const TextStyle(fontSize:13,color:Colors.white), maxLines:1, overflow:TextOverflow.ellipsis),
                    subtitle: Text('${t.artist}${t.album.isNotEmpty?" • ${t.album}":""}',
                      style:const TextStyle(fontSize:10,color:Colors.white54), maxLines:1, overflow:TextOverflow.ellipsis),
                    trailing: t.hasSynced
                      ? Container(padding:const EdgeInsets.symmetric(horizontal:6,vertical:2),
                          decoration:BoxDecoration(color:const Color(0xFF7C3AED).withOpacity(0.2),borderRadius:BorderRadius.circular(4)),
                          child:const Text('SYNC',style:TextStyle(color:Color(0xFF7C3AED),fontSize:9,fontWeight:FontWeight.bold)))
                      : const Icon(Icons.download_rounded,size:16,color:Colors.white38),
                    onTap: _applying ? null : () => _apply(t),
                  ),
                );
              },
            )),
        if (_applying) const LinearProgressIndicator(color:Color(0xFF7C3AED), backgroundColor:Colors.white12),
      ]),
    ),
  );
}
