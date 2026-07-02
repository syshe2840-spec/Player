import 'package:flutter/material.dart';
import 'whisper_service.dart';

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
  LiveBehindAction _behindAction = LiveBehindAction.pause;
  double _behindSpeed = 0.75;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await WhisperService.downloadedModels();
    final active = await WhisperService.getActiveModel();
    final engine = await WhisperService.getActiveEngine();
    if (mounted) setState(() {
      _models = list;
      // زیرنویس زنده فقط V2 — مدل فعال رو پیش‌فرض می‌گیریم
      _selected = active ?? (list.isNotEmpty ? list.first : null);
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
                const Text('زیرنویس زنده (V2)', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
                const Spacer(),
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('بستن')),
              ]),

              // توضیح
              Container(
                margin: const EdgeInsets.symmetric(vertical: 10),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: const Color(0xFF7C3AED).withOpacity(0.1), borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF7C3AED).withOpacity(0.3))),
                child: const Text(
                  'همزمان با پخش ویدیو، صدا تکه‌تکه پردازش میشه و زیرنویس روی صفحه نمایش داده میشه. SRT نهایی کنار فایل ویدیو ذخیره میشه.',
                  style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.5)),
              ),

              if (_models.isEmpty) ...[
                const Padding(padding: EdgeInsets.all(16), child: Text('هیچ مدل AI دانلودشده‌ای نیست\nابتدا از بخش AI مدل دانلود کنید',
                  textAlign: TextAlign.center, style: TextStyle(color: Colors.white54, fontSize: 13))),
              ] else ...[

                // ── مدل ──
                _row('مدل AI', DropdownButton<WhisperModelDef>(
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
                _row('زبان', DropdownButton<String>(
                  value: _lang, isExpanded: true, dropdownColor: const Color(0xFF2A2A35),
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  items: kLanguages.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                  onChanged: (v) { if (v != null) setState(() => _lang = v); },
                )),
                const SizedBox(height: 10),

                // ── ترجمه ──
                _switchRow('ترجمه به انگلیسی', _translate, (v) => setState(() => _translate = v)),
                const SizedBox(height: 10),

                // ── اندازه chunk ──
                _row('اندازه هر تکه', Row(children: [
                  _chunkChip('۱۵ ثانیه', 15000),
                  const SizedBox(width: 6),
                  _chunkChip('۳۰ ثانیه', 30000),
                  const SizedBox(width: 6),
                  _chunkChip('۶۰ ثانیه', 60000),
                ])),
                const SizedBox(height: 10),

                // ── وقتی جا موند ──
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: const Color(0xFF2A2A35), borderRadius: BorderRadius.circular(12)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('وقتی زیرنویس جا ماند:', style: TextStyle(color: Colors.white60, fontSize: 12)),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(child: _behindChip('توقف ویدیو', LiveBehindAction.pause, Icons.pause_circle_outline)),
                      const SizedBox(width: 8),
                      Expanded(child: _behindChip('کاهش سرعت', LiveBehindAction.slowDown, Icons.slow_motion_video)),
                    ]),
                    if (_behindAction == LiveBehindAction.slowDown) ...[
                      const SizedBox(height: 8),
                      Row(children: [
                        const Text('سرعت: ', style: TextStyle(color: Colors.white54, fontSize: 12)),
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
                      chunkMs: _chunkMs, language: _lang, model: _selected!,
                      isTranslate: _translate, behindAction: _behindAction, behindSpeed: _behindSpeed,
                    ));
                  },
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('شروع زیرنویس زنده'),
                  style: FilledButton.styleFrom(backgroundColor: Colors.red, padding: const EdgeInsets.symmetric(vertical: 14)),
                )),
              ],
            ]),
      ),
    ),
  );

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

