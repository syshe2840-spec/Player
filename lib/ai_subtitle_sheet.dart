import 'dart:io';
import 'package:flutter/material.dart';
import 'whisper_service.dart';

class AiSubtitleSheet extends StatefulWidget {
  final String videoPath;
  final void Function(String srtPath) onDone;
  const AiSubtitleSheet({super.key, required this.videoPath, required this.onDone});

  static Future<void> show(BuildContext ctx, String videoPath, void Function(String) onDone) {
    return showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1C1C22),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => AiSubtitleSheet(videoPath: videoPath, onDone: onDone),
    );
  }

  @override State<AiSubtitleSheet> createState() => _AiSubtitleSheetState();
}

class _AiSubtitleSheetState extends State<AiSubtitleSheet> {
  WhisperModelDef? _active;
  String _lang = 'fa';
  bool _running = false;
  bool _done = false;
  String _status = '';
  double _progress = 0;
  String? _srtPath;
  bool _hasModel = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final m = await WhisperService.getActiveModel();
    bool has = false;
    if (m != null) has = await WhisperService.isDownloaded(m);
    if (mounted) setState(() { _active = m; _hasModel = has; });
  }

  Future<void> _start() async {
    setState(() { _running = true; _progress = 0; _status = 'شروع...'; });
    try {
      final path = await WhisperService.transcribe(
        videoPath: widget.videoPath,
        language: _lang,
        onStatus: (s, p) { if (mounted) setState(() { _status = s; _progress = p; }); },
      );
      if (mounted) setState(() { _running = false; _done = true; _srtPath = path; _status = '✓ موفق'; });
    } catch (e) {
      if (mounted) setState(() { _running = false; _status = 'خطا: $e'; });
    }
  }

  Future<void> _cancel() async {
    await WhisperService.cancelExtraction();
    if (mounted) setState(() { _running = false; _status = 'لغو شد'; });
  }

  @override
  Widget build(BuildContext ctx) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16, right: 16, top: 16,
        bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // ── Handle ──
        Container(width: 40, height: 4, decoration: BoxDecoration(
          color: Colors.white24, borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 16),
        const Text('زیرنویس AI', style: TextStyle(
          color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),

        if (_done) ..._buildDone()
        else if (_running) ..._buildRunning()
        else ..._buildIdle(),
      ]),
    );
  }

  List<Widget> _buildIdle() => [
    // ── مدل فعال ──
    Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A35),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        const Icon(Icons.memory, color: Color(0xFF7C3AED), size: 20),
        const SizedBox(width: 8),
        Expanded(child: _hasModel && _active != null
            ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('مدل: ${_active!.name}', style: const TextStyle(color: Colors.white, fontSize: 13)),
                Text(_active!.desc, style: const TextStyle(color: Colors.white54, fontSize: 11)),
              ])
            : const Text('مدل دانلود نشده', style: TextStyle(color: Colors.orange, fontSize: 13)),
        ),
        if (!_hasModel) TextButton(
          onPressed: () { Navigator.pop(context); },
          child: const Text('دانلود', style: TextStyle(color: Color(0xFF7C3AED))),
        ),
      ]),
    ),
    const SizedBox(height: 12),

    // ── انتخاب زبان ──
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A35), borderRadius: BorderRadius.circular(12)),
      child: DropdownButton<String>(
        value: _lang,
        dropdownColor: const Color(0xFF2A2A35),
        underline: const SizedBox(),
        isExpanded: true,
        style: const TextStyle(color: Colors.white, fontSize: 13),
        items: kLanguages.entries.map((e) =>
            DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
        onChanged: (v) { if (v != null) setState(() => _lang = v); },
      ),
    ),
    const SizedBox(height: 16),

    // ── دکمه تولید ──
    SizedBox(width: double.infinity, child: FilledButton.icon(
      onPressed: _hasModel ? _start : null,
      icon: const Icon(Icons.subtitles),
      label: const Text('تولید زیرنویس'),
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFF7C3AED),
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    )),
  ];

  List<Widget> _buildRunning() => [
    const SizedBox(height: 8),
    Text(_status, style: const TextStyle(color: Colors.white70, fontSize: 13),
      textAlign: TextAlign.center),
    const SizedBox(height: 12),
    LinearProgressIndicator(
      value: _progress > 0 ? _progress : null,
      backgroundColor: const Color(0xFF2A2A35),
      color: const Color(0xFF7C3AED),
      minHeight: 6,
      borderRadius: BorderRadius.circular(3),
    ),
    const SizedBox(height: 8),
    Text('${(_progress * 100).toInt()}%',
      style: const TextStyle(color: Colors.white54, fontSize: 12)),
    const SizedBox(height: 16),
    TextButton.icon(
      onPressed: _cancel,
      icon: const Icon(Icons.cancel_outlined, color: Colors.red),
      label: const Text('لغو', style: TextStyle(color: Colors.red)),
    ),
    const SizedBox(height: 8),
    const Text('برای لغو روی دکمه بزنید\nاپ هنگ نکرده — در حال پردازش است',
      style: TextStyle(color: Colors.white38, fontSize: 11), textAlign: TextAlign.center),
  ];

  List<Widget> _buildDone() => [
    const Icon(Icons.check_circle, color: Colors.green, size: 48),
    const SizedBox(height: 8),
    const Text('زیرنویس آماده شد', style: TextStyle(
      color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
    const SizedBox(height: 4),
    Text(_srtPath?.split('/').last ?? '',
      style: const TextStyle(color: Colors.white54, fontSize: 11)),
    const SizedBox(height: 16),
    SizedBox(width: double.infinity, child: FilledButton.icon(
      onPressed: () { Navigator.pop(context); widget.onDone(_srtPath!); },
      icon: const Icon(Icons.subtitles),
      label: const Text('بارگذاری زیرنویس'),
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFF7C3AED),
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    )),
  ];
}
