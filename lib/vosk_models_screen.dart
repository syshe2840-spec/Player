import 'dart:io';
import 'package:flutter/material.dart';
import 'vosk_service.dart';

const _bg = Color(0xFF08080F);
const _card = Color(0xFF12121C);
const _acc = Color(0xFF7C3AED);

class VoskModelsScreen extends StatefulWidget {
  const VoskModelsScreen({super.key});
  @override State<VoskModelsScreen> createState() => _State();
}

class _State extends State<VoskModelsScreen> {
  Map<String, double> _progress = {};
  Map<String, String> _log = {};

  @override Widget build(BuildContext ctx) => Scaffold(
    backgroundColor: _bg,
    appBar: AppBar(
      backgroundColor: _bg,
      title: const Text('Vosk — مدل‌های زبان', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      actions: [
        IconButton(icon: const Icon(Icons.refresh_rounded, color: Colors.white54),
          onPressed: () => setState(() {})),
      ]),
    body: ListView(padding: const EdgeInsets.all(12), children: [
      Container(padding: const EdgeInsets.all(12), margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(color: _acc.withOpacity(0.1), borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _acc.withOpacity(0.3))),
        child: const Row(children: [
          Icon(Icons.info_outline_rounded, color: Color(0xFF7C3AED), size: 16),
          SizedBox(width: 8),
          Expanded(child: Text('مدل‌ها در /Download/Vezoo/VoskModels ذخیره میشن\nبعد از دانلود آفلاین کار میکنه',
            style: TextStyle(color: Colors.white60, fontSize: 11))),
        ])),
      ...kVoskModels.map((m) => _modelCard(m)),
    ]));

  Widget _modelCard(VoskModel m) {
    final isDownloaded = VoskService.isDownloaded(m);
    final prog = _progress[m.id];
    final isLoading = prog != null;
    final logMsg = _log[m.id];

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDownloaded ? _acc.withOpacity(0.1) : _card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDownloaded ? _acc.withOpacity(0.4) : Colors.transparent)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(m.name, style: TextStyle(
            color: isDownloaded ? Colors.white : Colors.white70,
            fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(width: 8),
          Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.08), borderRadius: BorderRadius.circular(4)),
            child: Text(m.size, style: const TextStyle(color: Colors.white38, fontSize: 10))),
          if (isDownloaded) ...[
            const SizedBox(width: 6),
            Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: Colors.green.withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
              child: const Text('✓ دانلود شده', style: TextStyle(color: Colors.green, fontSize: 9, fontWeight: FontWeight.bold))),
          ],
          const Spacer(),
          if (isLoading)
            SizedBox(width: 36, height: 36, child: CircularProgressIndicator(value: prog, strokeWidth: 3, color: _acc))
          else if (isDownloaded)
            IconButton(icon: const Icon(Icons.delete_outline_rounded, color: Colors.white24, size: 20),
              onPressed: () async { await VoskService.deleteModel(m); setState(() {}); })
          else
            FilledButton.icon(
              onPressed: () => _download(m),
              icon: const Icon(Icons.download_rounded, size: 14),
              label: Text('دانلود', style: const TextStyle(fontSize: 11)),
              style: FilledButton.styleFrom(backgroundColor: _acc,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6))),
        ]),
        if (isLoading) ...[
          const SizedBox(height: 8),
          ClipRRect(borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: prog, minHeight: 4, backgroundColor: Colors.white10, color: _acc)),
          const SizedBox(height: 4),
          Text('${(prog! * 100).toStringAsFixed(0)}%${prog > 0.8 ? " — در حال extract..." : " — در حال دانلود..."}',
            style: const TextStyle(color: Colors.white38, fontSize: 10)),
        ],
        if (logMsg != null && !isLoading) ...[
          const SizedBox(height: 4),
          Text(logMsg, style: const TextStyle(color: Colors.redAccent, fontSize: 10)),
        ],
      ]));
  }

  Future<void> _download(VoskModel m) async {
    setState(() { _progress[m.id] = 0.001; _log.remove(m.id); });
    try {
      await for (final p in VoskService.downloadModel(m)) {
        if (!mounted) return;
        setState(() => _progress[m.id] = p);
      }
      if (mounted) setState(() { _progress.remove(m.id); });
    } catch (e) {
      if (mounted) setState(() { _progress.remove(m.id); _log[m.id] = 'خطا: $e'; });
    }
  }
}

