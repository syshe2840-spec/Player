import 'package:flutter/material.dart';
import 'whisper_service.dart';

class AiModelsScreen extends StatefulWidget {
  const AiModelsScreen({super.key});
  @override State<AiModelsScreen> createState() => _AiModelsScreenState();
}

class _AiModelsScreenState extends State<AiModelsScreen> {
  Map<String, bool> _downloaded = {};
  String? _active;
  Map<String, double> _progress = {};
  Map<String, bool> _downloading = {};

  @override
  void initState() { super.initState(); _refresh(); }

  Future<void> _refresh() async {
    final a = await WhisperService.getActiveModel();
    final Map<String, bool> dl = {};
    for (final m in kWhisperModels) {
      dl[m.model.modelName] = await WhisperService.isDownloaded(m);
    }
    if (mounted) setState(() { _downloaded = dl; _active = a?.model.modelName; });
  }

  Future<void> _download(WhisperModelDef m) async {
    setState(() { _downloading[m.model.modelName] = true; _progress[m.model.modelName] = 0; });
    try {
      await for (final p in WhisperService.downloadModel(m)) {
        if (!mounted) break;
        setState(() => _progress[m.model.modelName] = p);
      }
      await _refresh();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطا: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _downloading[m.model.modelName] = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1C1C22),
        title: const Text('مدل‌های AI', style: TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('یک مدل دانلود کنید تا بتوانید زیرنویس AI بسازید.',
          style: TextStyle(color: Colors.white60, fontSize: 13)),
        const SizedBox(height: 4),
        const Text('هر بار فقط یک مدل فعال می‌تواند باشد.',
          style: TextStyle(color: Colors.white38, fontSize: 11)),
        const SizedBox(height: 16),
        ...kWhisperModels.map((m) => _buildCard(m)),
      ]),
    );
  }

  Widget _buildCard(WhisperModelDef m) {
    final dl = _downloaded[m.model.modelName] ?? false;
    final isActive = _active == m.model.modelName;
    final isDling = _downloading[m.model.modelName] ?? false;
    final prog = _progress[m.model.modelName] ?? 0.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C22),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isActive ? const Color(0xFF7C3AED) : Colors.white12,
          width: isActive ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            // ── icon + name ──
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF7C3AED).withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(m.name, style: const TextStyle(
                color: Color(0xFF7C3AED), fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 8),
            if (isActive) Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.2), borderRadius: BorderRadius.circular(6)),
              child: const Text('فعال', style: TextStyle(color: Colors.green, fontSize: 11)),
            ),
            const Spacer(),
            Text('~${m.sizeMb} MB', style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ]),
          const SizedBox(height: 8),
          Text(m.desc, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 6),
          Row(children: [
            _stars('سرعت', m.speedStars),
            const SizedBox(width: 16),
            _stars('دقت', m.accStars),
          ]),

          // ── Progress ──
          if (isDling) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: prog,
              backgroundColor: const Color(0xFF2A2A35),
              color: const Color(0xFF7C3AED),
              minHeight: 4,
              borderRadius: BorderRadius.circular(2),
            ),
            const SizedBox(height: 4),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('دانلود: ${(prog * 100).toInt()}%',
                style: const TextStyle(color: Colors.white54, fontSize: 11)),
              TextButton(
                onPressed: () { WhisperService.cancelDownload(); setState(() => _downloading[m.model.modelName] = false); },
                child: const Text('لغو', style: TextStyle(color: Colors.red, fontSize: 11)),
              ),
            ]),
          ],

          // ── Buttons ──
          if (!isDling) ...[
            const SizedBox(height: 12),
            Row(children: [
              if (!dl) Expanded(child: FilledButton.icon(
                onPressed: () => _download(m),
                icon: const Icon(Icons.download, size: 16),
                label: Text('دانلود ${m.name}'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF7C3AED),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              )),
              if (dl && !isActive) Expanded(child: FilledButton.icon(
                onPressed: () async {
                  await WhisperService.setActive(m);
                  await _refresh();
                },
                icon: const Icon(Icons.check_circle, size: 16),
                label: const Text('انتخاب'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.green,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              )),
              if (dl) ...[
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    final ok = await showDialog<bool>(context: context,
                      builder: (_) => AlertDialog(
                        backgroundColor: const Color(0xFF1C1C22),
                        title: const Text('حذف مدل', style: TextStyle(color: Colors.white)),
                        content: Text('مدل ${m.name} حذف شود؟', style: const TextStyle(color: Colors.white70)),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('لغو')),
                          FilledButton(onPressed: () => Navigator.pop(context, true),
                            style: FilledButton.styleFrom(backgroundColor: Colors.red),
                            child: const Text('حذف')),
                        ],
                      ));
                    if (ok == true) { await WhisperService.deleteModel(m); await _refresh(); }
                  },
                  icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
                  label: const Text('حذف', style: TextStyle(color: Colors.red, fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.red),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ]),
          ],
        ]),
      ),
    );
  }

  Widget _stars(String label, int count) => Row(mainAxisSize: MainAxisSize.min, children: [
    Text('$label: ', style: const TextStyle(color: Colors.white54, fontSize: 11)),
    ...List.generate(5, (i) => Icon(
      i < count ? Icons.star : Icons.star_border,
      size: 12,
      color: i < count ? const Color(0xFF7C3AED) : Colors.white24,
    )),
  ]);
}

