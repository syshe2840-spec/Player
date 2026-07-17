import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'offline_translation_service.dart';
import 'l10n.dart';

const _bg = Color(0xFF08080F);
const _card = Color(0xFF12121C);
const _accent = Color(0xFF7C3AED);

class OfflineTranslationScreen extends StatefulWidget {
  const OfflineTranslationScreen({super.key});
  @override State<OfflineTranslationScreen> createState() => _State();
}

class _State extends State<OfflineTranslationScreen> {
  String _selectedModel = 'nllb_600m_q8';
  String _srcLang = 'en', _tgtLang = 'fa';
  Map<String, double> _downloadProgress = {};
  bool _loading = true;

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    _selectedModel = await OfflineTranslationService.getSelectedModel();
    _srcLang = await OfflineTranslationService.getSrcLang();
    _tgtLang = await OfflineTranslationService.getTgtLang();
    if (mounted) setState(() => _loading = false);
  }

  OfflineTransModel get _current => kOfflineModels.firstWhere(
    (m) => m.id == _selectedModel, orElse: () => kOfflineModels.first);

  Future<void> _download(OfflineTransModel m) async {
    setState(() => _downloadProgress[m.id] = 0.0);
    try {
      await for (final p in OfflineTranslationService.downloadModel(m)) {
        if (!mounted) return;
        setState(() => _downloadProgress[m.id] = p);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString().substring(0, e.toString().length.clamp(0, 80))}'),
          backgroundColor: Colors.red));
    }
    if (mounted) setState(() => _downloadProgress.remove(m.id));
  }

  Future<void> _delete(OfflineTransModel m) async {
    await OfflineTranslationService.deleteModel(m);
    setState(() {});
  }

  Future<void> _backup() async {
    final settings = await OfflineTranslationService.exportSettings();
    final json = jsonEncode(settings);
    final dir = Directory('/storage/emulated/0/Download/Vezoo/Backup');
    await dir.create(recursive: true);
    final file = File('${dir.path}/offline_translation_settings.json');
    await file.writeAsString(json);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('✓ Saved to ${file.path}'), backgroundColor: Colors.green));
  }

  Future<void> _import() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['json']);
    if (res == null || res.files.single.path == null) return;
    final json = await File(res.files.single.path!).readAsString();
    await OfflineTranslationService.importSettings(Map<String, String>.from(jsonDecode(json)));
    await _load();
  }

  @override Widget build(BuildContext ctx) => Scaffold(
    backgroundColor: _bg,
    appBar: AppBar(
      backgroundColor: _bg,
      title: const Text('Offline Translation', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      actions: [
        IconButton(icon: const Icon(Icons.upload_rounded, color: Colors.white70), onPressed: _backup, tooltip: 'Backup'),
        IconButton(icon: const Icon(Icons.download_done_rounded, color: Colors.white70), onPressed: _import, tooltip: 'Import'),
      ]),
    body: _loading ? const Center(child: CircularProgressIndicator())
      : ListView(padding: const EdgeInsets.all(12), children: [
          // ── انتخاب زبان ──
          _sectionTitle('Default Languages'),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _langDropdown('Source', _srcLang, _current.langCodes, (v) async {
              await OfflineTranslationService.setSrcLang(v); setState(() => _srcLang = v); })),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Icon(Icons.arrow_forward_rounded, color: Colors.white38)),
            Expanded(child: _langDropdown('Target', _tgtLang, _current.langCodes, (v) async {
              await OfflineTranslationService.setTgtLang(v); setState(() => _tgtLang = v); })),
          ]),
          const SizedBox(height: 20),
          _sectionTitle('AI Models'),
          const SizedBox(height: 8),
          ...kOfflineModels.map((m) => _modelCard(m)),
          const SizedBox(height: 12),
          const Text('مدل‌ها در /Download/Vezoo/OfflineModels ذخیره میشن',
            style: TextStyle(color: Colors.white24, fontSize: 10), textAlign: TextAlign.center),
        ]));

  Widget _sectionTitle(String t) => Text(t, style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w600));

  Widget _langDropdown(String label, String value, List<String> langs, void Function(String) onChanged) =>
    Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(8)),
      child: DropdownButton<String>(
        value: langs.contains(value) ? value : langs.first,
        dropdownColor: _card,
        isExpanded: true,
        style: const TextStyle(color: Colors.white, fontSize: 12),
        underline: const SizedBox(),
        hint: Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11)),
        items: langs.map((l) => DropdownMenuItem(value: l, child: Text(langNames[l] ?? l))).toList(),
        onChanged: (v) { if (v != null) onChanged(v); },
      ));

  Widget _modelCard(OfflineTransModel m) {
    final isSelected = _selectedModel == m.id;
    final isDownloaded = OfflineTranslationService.isDownloaded(m);
    final progress = _downloadProgress[m.id];
    final isDownloading = progress != null;

    return GestureDetector(
      onTap: () async {
        await OfflineTranslationService.setSelectedModel(m.id);
        setState(() => _selectedModel = m.id);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? _accent.withOpacity(0.12) : _card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isSelected ? _accent : Colors.transparent, width: 1.5)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
              color: isSelected ? _accent : Colors.white38, size: 18),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(m.name, style: TextStyle(color: isSelected ? Colors.white : Colors.white70,
                fontWeight: FontWeight.bold, fontSize: 14)),
              Text(m.desc, style: const TextStyle(color: Colors.white38, fontSize: 11)),
              Row(children: [
                _tag('${m.langCount} زبان', Colors.blue),
                const SizedBox(width: 4),
                _tag('~${m.sizeMb}MB', Colors.orange),
                if (isDownloaded) ...[const SizedBox(width: 4), _tag('✓ دانلود شده', Colors.green)],
              ]),
            ])),
            // دکمه‌های دانلود / حذف
            if (isDownloading)
              SizedBox(width: 40, height: 40, child: CircularProgressIndicator(
                value: progress, strokeWidth: 3, color: _accent))
            else if (isDownloaded)
              IconButton(icon: const Icon(Icons.delete_outline_rounded, color: Colors.white30),
                onPressed: () => _delete(m))
            else
              FilledButton.icon(
                onPressed: () => _download(m),
                icon: const Icon(Icons.download_rounded, size: 14),
                label: const Text('Download', style: TextStyle(fontSize: 11)),
                style: FilledButton.styleFrom(backgroundColor: _accent,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6))),
          ]),
          if (isDownloading) ...[
            const SizedBox(height: 8),
            ClipRRect(borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: progress, minHeight: 4,
                backgroundColor: Colors.white12, color: _accent)),
            Padding(padding: const EdgeInsets.only(top: 4),
              child: Text('${(progress! * 100).toStringAsFixed(0)}%',
                style: const TextStyle(color: Colors.white38, fontSize: 10))),
          ],
          // لیست زبان‌ها
          if (isSelected) ...[
            const SizedBox(height: 10),
            const Divider(color: Colors.white12, height: 1),
            const SizedBox(height: 8),
            Wrap(spacing: 4, runSpacing: 4,
              children: m.langCodes.map((l) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.07), borderRadius: BorderRadius.circular(4)),
                child: Text(langNames[l] ?? l, style: const TextStyle(color: Colors.white54, fontSize: 9)))).toList()),
          ],
        ])));
  }

  Widget _tag(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
    child: Text(label, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w600)));
}

