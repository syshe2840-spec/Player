import 'package:flutter/material.dart';
import 'whisper_service.dart';
import 'srt_translation_service.dart' show kTranslateLangDisplay, kTranslateLangs;
import 'l10n.dart';

/// تنظیمات زیرنویس زنده — قبل از شروع پردازش تکه‌تکه
class LiveSubSheet extends StatefulWidget {
  final String videoPath;
  final void Function(LiveSubConfig) onStart;
  const LiveSubSheet({super.key, required this.videoPath, required this.onStart});

  static Future<void> show(BuildContext ctx, String videoPath, void Function(LiveSubConfig) onStart) =>
      showModalBottomSheet(
        context: ctx, isScrollControlled: true,
        backgroundColor: const Color(0xFF1C1C22),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (_) => LiveSubSheet(videoPath: videoPath, onStart: onStart),
      );

  @override State<LiveSubSheet> createState() => _State();
}

class _State extends State<LiveSubSheet> {
  List<WhisperModelDef> _models = [];
  WhisperModelDef? _selected;
  String _lang = 'fa';
  bool _translate = false;
  int _chunkMs = 30000;
  bool _useOverlap = true;
  bool _syncTranslate = false;  // همگام‌سازی با ترجمه آنلاین
  String _syncLang = 'fa';      // زبان ترجمه
  LiveBehindAction _behindAction = LiveBehindAction.pause;
  double _behindSpeed = 0.75;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await WhisperService.allDownloadedModels();
    final active = await WhisperService.getActiveModel();
    final engine = await WhisperService.getActiveEngine();
    if (mounted) setState(() {
      _models = list;
      // مدل فعال یا اولین مدل موجود (شامل ایمپورتی‌ها)
      _selected = list.contains(active) ? active : (list.isNotEmpty ? list.first : null);
      _loading = false;
      if (engine != WhisperEngine.v2) {
        // اگه کاربر V1 داشت، هنوز نشون میدیم ولی توضیح میدیم
      }
    });
  }

  @override
  Widget build(BuildContext ctx) => SafeArea(
    child: ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
      child: SingleChildScrollView(
        padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: MediaQuery.of(ctx).viewInsets.bottom + 16),
        child: _loading
          ? const SizedBox(height: 100, child: Center(child: CircularProgressIndicator(color: Color(0xFF7C3AED))))
          : Column(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 14),
              Row(children: [
                const Icon(Icons.fiber_smart_record, color: Colors.red, size: 20),
                const SizedBox(width: 8),
                Text(L.liveSubtitleSettings, style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
                const Spacer(),
                TextButton(onPressed: () => Navigator.pop(ctx), child: Text(L.close)),
              ]),

              // توضیح
              Container(
                margin: const EdgeInsets.symmetric(vertical: 10),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: const Color(0xFF7C3AED).withOpacity(0.1), borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF7C3AED).withOpacity(0.3))),
                child: const Text(
                  L.liveSubDesc,
                  style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.5)),
              ),

              if (_models.isEmpty) ...[
                Padding(padding: EdgeInsets.all(16), child: Text(L.noModelDownloaded2,
                  textAlign: TextAlign.center, style: TextStyle(color: Colors.white54, fontSize: 13))),
              ] else ...[

                // ── مدل ──
                _row(L.aiModel, DropdownButton<WhisperModelDef>(
                  value: _selected, isExpanded: true, dropdownColor: const Color(0xFF2A2A35),
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  items: _models.map((m) => DropdownMenuItem(value: m, child: Row(children: [
                    Text(m.name),
                    const SizedBox(width: 6),
                    ...List.generate(m.speedStars, (_) => const Icon(Icons.bolt, size: 10, color: Colors.amber)),
                  ]))).toList(),
                  onChanged: (v) { if (v != null) setState(() => _selected = v); },
                )),
                const SizedBox(height: 10),

                // ── زبان ──
                _row(L.language, DropdownButton<String>(
                  value: _lang, isExpanded: true, dropdownColor: const Color(0xFF2A2A35),
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  items: kLanguages.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                  onChanged: (v) { if (v != null) setState(() => _lang = v); },
                )),
                const SizedBox(height: 10),

                // ── ترجمه ──
                _switchRow(L.translateToEn, _translate, (v) => setState(() => _translate = v)),
                const SizedBox(height: 10),

                // ── اندازه هر تکه ──
                _rowLabel(L.chunkSize),
                const SizedBox(height:6),
                SingleChildScrollView(scrollDirection:Axis.horizontal,child:Row(children:[
                  _chunkChip('15s', 15000),
                  const SizedBox(width:6),
                  _chunkChip('30s', 30000),
                  const SizedBox(width:6),
                  _chunkChip('1min', 60000),
                  const SizedBox(width:6),
                  _chunkChip('2min', 120000),
                  const SizedBox(width:6),
                  _chunkChip('3min', 180000),
                  const SizedBox(width:6),
                  _chunkChip('4min', 240000),
                  const SizedBox(width:6),
                  _chunkChip('5min', 300000),
                  const SizedBox(width:6),
                  _chunkChip('10min', 600000),
                  const SizedBox(width:6),
                  _chunkChip('15min', 900000),
                ])),
                const SizedBox(height:10),

                // ── Overlap ──
                _switchRow(L.overlapChunks, _useOverlap, (v) => setState(() => _useOverlap = v)),
                if(_useOverlap)
                  Padding(padding:const EdgeInsets.only(top:4,right:4),child:Text(
                    L.overlapDesc,
                    style:const TextStyle(color:Colors.white38,fontSize:10))),
                const SizedBox(height:10),

                // ── همگام‌سازی ترجمه آنلاین ──
                _switchRow(L.translateOnline, _syncTranslate, (v) => setState(() => _syncTranslate = v)),
                if(_syncTranslate)...[
                  const SizedBox(height:6),
                  Container(
                    padding:const EdgeInsets.symmetric(horizontal:10,vertical:4),
                    decoration:BoxDecoration(color:const Color(0xFF2A2A35),borderRadius:BorderRadius.circular(8)),
                    child:Row(children:[
                      Text(L.targetLanguage,style:TextStyle(color:Colors.white60,fontSize:12)),
                      const SizedBox(width:8),
                      Expanded(child:DropdownButton<String>(
                        value:_syncLang,isExpanded:true,dropdownColor:const Color(0xFF2A2A35),
                        style:const TextStyle(color:Colors.white,fontSize:12),
                        items:kTranslateLangDisplay.entries.map((e)=>
                          DropdownMenuItem(value:e.key,child:Text(e.value))).toList(),
                        onChanged:(v){if(v!=null)setState(()=>_syncLang=v);},
                      )),
                    ]),
                  ),
                  Padding(padding:const EdgeInsets.only(top:4,right:4),child:Text(
                    L.syncTranslateDesc,
                    style:const TextStyle(color:Colors.white38,fontSize:10))),
                ],
                const SizedBox(height:10),

                // ── وقتی جا موند ──
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: const Color(0xFF2A2A35), borderRadius: BorderRadius.circular(12)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(L.whenBehind, style: TextStyle(color: Colors.white60, fontSize: 12)),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(child: _behindChip(L.pauseVideo, LiveBehindAction.pause, Icons.pause_circle_outline)),
                      const SizedBox(width: 8),
                      Expanded(child: _behindChip(L.slowDown, LiveBehindAction.slowDown, Icons.slow_motion_video)),
                    ]),
                    if (_behindAction == LiveBehindAction.slowDown) ...[
                      const SizedBox(height: 8),
                      Row(children: [
                        Text(L.speedLabel, style: TextStyle(color: Colors.white54, fontSize: 12)),
                        ...[0.25, 0.5, 0.75].map((s) => Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: GestureDetector(onTap: () => setState(() => _behindSpeed = s), child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(color: _behindSpeed == s ? const Color(0xFF7C3AED) : const Color(0xFF1C1C22), borderRadius: BorderRadius.circular(8)),
                            child: Text('${s}x', style: TextStyle(color: _behindSpeed == s ? Colors.white : Colors.white60, fontSize: 12)),
                          )),
                        )),
                      ]),
                    ],
                  ]),
                ),
                const SizedBox(height: 14),

                // ── دکمه شروع ──
                SizedBox(width: double.infinity, child: FilledButton.icon(
                  onPressed: _selected == null ? null : () {
                    Navigator.pop(ctx);
                    widget.onStart(LiveSubConfig(
                      chunkMs: _chunkMs,
                      overlapMs: _useOverlap ? 5000 : 0,
                      language: _lang, model: _selected!,
                      isTranslate: _translate, behindAction: _behindAction, behindSpeed: _behindSpeed,
                      syncTranslate: _syncTranslate,
                      syncTranslateLang: _syncLang,
                    ));
                  },
                  icon: const Icon(Icons.play_arrow),
                  label: Text(L.startProcessing),
                  style: FilledButton.styleFrom(backgroundColor: Colors.red, padding: const EdgeInsets.symmetric(vertical: 14)),
                )),
              ],
            ]),
      ),
    ),
  );

  Widget _rowLabel(String label) => Text(label, style: const TextStyle(color: Colors.white60, fontSize: 11));

  Widget _row(String label, Widget child) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: const TextStyle(color: Colors.white60, fontSize: 11)),
    const SizedBox(height: 4),
    Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: const Color(0xFF2A2A35), borderRadius: BorderRadius.circular(10)),
      child: child),
  ]);

  Widget _switchRow(String label, bool val, void Function(bool) onChanged) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(color: const Color(0xFF2A2A35), borderRadius: BorderRadius.circular(12)),
    child: Row(children: [
      Text(label, style: const TextStyle(color: Colors.white, fontSize: 13)),
      const Spacer(),
      Switch(value: val, activeColor: const Color(0xFF7C3AED), onChanged: onChanged),
    ]),
  );

  Widget _chunkChip(String label, int ms) => GestureDetector(
    onTap: () => setState(() => _chunkMs = ms),
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: _chunkMs == ms ? const Color(0xFF7C3AED) : const Color(0xFF1C1C22),
        borderRadius: BorderRadius.circular(8)),
      child: Center(child: Text(label, style: TextStyle(color: _chunkMs == ms ? Colors.white : Colors.white60, fontSize: 12))),
    ),
  );

  Widget _behindChip(String label, LiveBehindAction action, IconData icon) => GestureDetector(
    onTap: () => setState(() => _behindAction = action),
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: _behindAction == action ? Colors.red.withOpacity(0.2) : const Color(0xFF1C1C22),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _behindAction == action ? Colors.red : Colors.white12)),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, size: 14, color: _behindAction == action ? Colors.red : Colors.white54),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: _behindAction == action ? Colors.red : Colors.white60, fontSize: 11)),
      ]),
    ),
  );
}
