import 'dart:io';
import 'package:flutter/material.dart';
import 'vosk_service.dart';

const _bg   = Color(0xFF08080F);
const _card  = Color(0xFF12121C);
const _acc   = Color(0xFF7C3AED);
const _gold  = Color(0xFFF59E0B);

class VoskModelsScreen extends StatefulWidget {
  const VoskModelsScreen({super.key});
  @override State<VoskModelsScreen> createState() => _State();
}

class _State extends State<VoskModelsScreen> {
  final Map<String, double> _progress = {};
  final Map<String, String> _log = {};
  final Map<String, bool> _cancelled = {};
  final _scroll = ScrollController();

  // گروه‌بندی مدل‌ها بر اساس langCode
  Map<String, List<VoskModel>> get _grouped {
    final map = <String, List<VoskModel>>{};
    for (final m in kVoskModels) {
      map.putIfAbsent(m.langCode, () => []).add(m);
    }
    return map;
  }

  @override Widget build(BuildContext ctx) => Scaffold(
    backgroundColor: _bg,
    appBar: AppBar(
      backgroundColor: _bg,
      elevation: 0,
      title: const Text('Vosk — مدل‌های زبان',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh_rounded, color: Colors.white54),
          onPressed: () => setState(() {})),
      ]),
    body: Column(children: [
      // اطلاعیه
      Container(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: _acc.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _acc.withOpacity(0.25))),
        child: const Row(children: [
          Icon(Icons.info_outline_rounded, color: _acc, size: 15),
          SizedBox(width: 8),
          Expanded(child: Text(
            'مدل‌ها آفلاین کار میکنن • Small: سریع | Large: دقیق‌تر\n'
            'مسیر: /Download/Vezoo/VoskModels',
            style: TextStyle(color: Colors.white54, fontSize: 11))),
        ])),
      // لیست
      Expanded(child: ListView(
        controller: _scroll,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
        children: [
          ..._grouped.entries.map((e) => _langGroup(e.key, e.value)),
          // ── مدل‌های Custom ──
          if (VoskService.customModels.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A2A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.withOpacity(0.3))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(2, 0, 2, 8),
                  child: Row(children: [
                    Icon(Icons.folder_special_rounded, color: Colors.orange, size: 16),
                    SizedBox(width: 8),
                    Text('مدل‌های Custom', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 13)),
                    SizedBox(width: 8),
                    Text('(دانلود دستی)', style: TextStyle(color: Colors.white38, fontSize: 10)),
                  ])),
                ...VoskService.customModels.map((m) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(children: [
                    const Icon(Icons.folder_rounded, color: Colors.white38, size: 14),
                    const SizedBox(width: 8),
                    Expanded(child: Text(m.name, style: const TextStyle(color: Colors.white70, fontSize: 12))),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: Colors.orange.withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
                      child: const Text('Custom', style: TextStyle(color: Colors.orange, fontSize: 9))),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => _confirmDelete(m),
                      child: const Icon(Icons.delete_outline_rounded, color: Colors.white24, size: 16)),
                  ]))),
              ])),
          ],
        ])),
    ]));

  Widget _langGroup(String langCode, List<VoskModel> models) {
    final anyDownloaded = models.any((m) => VoskService.isDownloaded(m));
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: anyDownloaded ? _acc.withOpacity(0.3) : Colors.transparent)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // هدر زبان
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
            child: Row(children: [
              Text(models.first.name.split(' ').first,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(width: 8),
              Text(langCode.toUpperCase(),
                style: const TextStyle(color: Colors.white38, fontSize: 10)),
              const Spacer(),
              if (anyDownloaded)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4)),
                  child: const Text('✓ نصب شده',
                    style: TextStyle(color: Colors.green, fontSize: 9, fontWeight: FontWeight.bold))),
            ])),
          const Divider(height: 1, color: Colors.white10),
          // مدل‌ها
          ...models.map((m) => _modelRow(m)),
          const SizedBox(height: 4),
        ]));
  }

  Widget _modelRow(VoskModel m) {
    final isDl = VoskService.isDownloaded(m);
    final prog = _progress[m.id];
    final isLoading = prog != null;
    final logMsg = _log[m.id];

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          // نوع مدل
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: m.isLarge ? _gold.withOpacity(0.15) : _acc.withOpacity(0.12),
              borderRadius: BorderRadius.circular(4)),
            child: Text(m.isLarge ? 'Large' : 'Small',
              style: TextStyle(
                color: m.isLarge ? _gold : _acc,
                fontSize: 10, fontWeight: FontWeight.bold))),
          const SizedBox(width: 6),
          Text(m.size, style: const TextStyle(color: Colors.white54, fontSize: 11)),
          const Spacer(),
          // دکمه
          if (isLoading)
            Row(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(width: 32, height: 32,
                child: CircularProgressIndicator(value: prog, strokeWidth: 2.5, color: _acc)),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () => setState(() => _cancelled[m.id] = true),
                child: const Icon(Icons.cancel_rounded, color: Colors.red, size: 20)),
            ])
          else if (isDl)
            GestureDetector(
              onTap: () => _confirmDelete(m),
              child: const Icon(Icons.delete_outline_rounded, color: Colors.white24, size: 18))
          else
            GestureDetector(
              onTap: () => _download(m),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _acc.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: _acc.withOpacity(0.4))),
                child: const Text('دانلود',
                  style: TextStyle(color: _acc, fontSize: 11, fontWeight: FontWeight.bold)))),
        ]),
        if (isLoading) ...[
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: prog, minHeight: 3,
              backgroundColor: Colors.white10, color: _acc)),
          const SizedBox(height: 3),
          Text('${(prog! * 100).toStringAsFixed(0)}%${prog > 0.87 ? " — در حال extract..." : ""}',
            style: const TextStyle(color: Colors.white38, fontSize: 9)),
        ],
        if (logMsg != null && !isLoading) ...[
          const SizedBox(height: 3),
          Text(logMsg, style: const TextStyle(color: Colors.redAccent, fontSize: 9)),
        ],
      ]));
  }

  void _confirmDelete(VoskModel m) {
    showDialog(context: context, builder: (_) => AlertDialog(
      backgroundColor: const Color(0xFF1A1A2A),
      title: Text('حذف ${m.name}?', style: const TextStyle(color: Colors.white, fontSize: 14)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('لغو')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () async {
            Navigator.pop(context);
            await VoskService.deleteModel(m);
            if (mounted) setState(() {});
          },
          child: const Text('حذف')),
      ]));
  }

  Future<void> _download(VoskModel m) async {
    setState(() { _progress[m.id] = 0.001; _log.remove(m.id); _cancelled[m.id] = false; });
    try {
      await for (final p in VoskService.downloadModel(m)) {
        if (!mounted) return;
        if (_cancelled[m.id] == true) {
          // حذف فایل ناقص
          try {
            final zipFile = File('/storage/emulated/0/Download/Vezoo/VoskModels/${m.id}.zip');
            if (zipFile.existsSync()) zipFile.deleteSync();
          } catch (_) {}
          if (mounted) setState(() { _progress.remove(m.id); _cancelled.remove(m.id); _log[m.id] = 'دانلود لغو شد'; });
          return;
        }
        setState(() => _progress[m.id] = p);
      }
      if (mounted) setState(() { _progress.remove(m.id); _cancelled.remove(m.id); });
    } catch (e) {
      if (mounted) setState(() { _progress.remove(m.id); _cancelled.remove(m.id); _log[m.id] = 'خطا: $e'; });
    }
  }
}
