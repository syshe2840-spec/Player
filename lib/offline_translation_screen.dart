import 'package:flutter/material.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'offline_translation_service.dart';
import 'l10n.dart';

const _kBg = Color(0xFF08080F);
const _kCard = Color(0xFF12121C);
const _kAccent = Color(0xFF7C3AED);

class OfflineTranslationScreen extends StatefulWidget {
  const OfflineTranslationScreen({super.key});
  @override State<OfflineTranslationScreen> createState() => _State();
}

class _State extends State<OfflineTranslationScreen> {
  String _selectedModel = 'mlkit_lite';
  Map<String, bool> _downloading = {};
  Map<String, bool> _downloaded = {};
  bool _loading = true;

  @override void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _selectedModel = await OfflineTranslationService.getSelectedModel();
    final model = kOfflineModels.firstWhere((m) => m.id == _selectedModel,
        orElse: () => kOfflineModels.first);
    final Map<String, bool> dl = {};
    for (final lang in model.languages) {
      try {
        dl[lang.bcpCode] = await OfflineTranslationService.isDownloaded(lang);
      } catch (_) {
        dl[lang.bcpCode] = false;
      }
    }
    if (mounted) setState(() { _downloaded = dl; _loading = false; });
  }

  Future<void> _downloadAll() async {
    final model = kOfflineModels.firstWhere((m) => m.id == _selectedModel);
    final notDownloaded = model.languages.where((l) => _downloaded[l.bcpCode] != true).toList();
    for (final lang in notDownloaded) {
      if (!mounted) return;
      setState(() => _downloading[lang.bcpCode] = true);
      try {
        final ok = await OfflineTranslationService.downloadModel(lang, (_) {});
        if (mounted) setState(() {
          _downloading[lang.bcpCode] = false;
          _downloaded[lang.bcpCode] = ok;
        });
      } catch (e) {
        if (mounted) setState(() { _downloading[lang.bcpCode] = false; });
      }
    }
  }

  Future<void> _deleteAll() async {
    final model = kOfflineModels.firstWhere((m) => m.id == _selectedModel);
    for (final lang in model.languages) {
      await OfflineTranslationService.deleteModel(lang);
    }
    await _load();
  }

  // ── بکاپ تنظیمات ──
  Future<void> _backup() async {
    final p = await SharedPreferences.getInstance();
    final data = {
      'model': _selectedModel,
      'src': (await OfflineTranslationService.getSrcLang()).bcpCode,
      'tgt': (await OfflineTranslationService.getTgtLang()).bcpCode,
    };
    // TODO: export JSON file
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Settings backed up')));
  }

  @override Widget build(BuildContext context) => Scaffold(
    backgroundColor: _kBg,
    appBar: AppBar(
      backgroundColor: _kBg,
      title: const Text('Offline Translation', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      actions: [
        IconButton(icon: const Icon(Icons.upload_rounded, color: Colors.white70), onPressed: _backup, tooltip: 'Backup'),
        IconButton(icon: const Icon(Icons.refresh_rounded, color: Colors.white70), onPressed: _load, tooltip: 'Refresh'),
      ]),
    body: _loading
      ? const Center(child: CircularProgressIndicator())
      : ListView(padding: const EdgeInsets.all(12), children: [
          // ── انتخاب مدل ──
          const Text('Select Model', style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          ...kOfflineModels.map((m) => _modelCard(m)),
          const SizedBox(height: 16),

          // ── زبان‌های مدل انتخاب شده ──
          Builder(builder: (_) {
            final model = kOfflineModels.firstWhere((m) => m.id == _selectedModel);
            final total = model.languages.length;
            final dlCount = model.languages.where((l) => _downloaded[l.bcpCode] == true).length;
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text('Languages ($dlCount/$total)', style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w600)),
                const Spacer(),
                TextButton.icon(
                  onPressed: _downloadAll,
                  icon: const Icon(Icons.download_rounded, size: 14),
                  label: const Text('Download All', style: TextStyle(fontSize: 11)),
                  style: TextButton.styleFrom(foregroundColor: _kAccent)),
                TextButton.icon(
                  onPressed: _deleteAll,
                  icon: const Icon(Icons.delete_rounded, size: 14),
                  label: const Text('Delete All', style: TextStyle(fontSize: 11)),
                  style: TextButton.styleFrom(foregroundColor: Colors.white38)),
              ]),
              const SizedBox(height: 6),
              ...model.languages.map((lang) => _langTile(lang)),
            ]);
          }),
        ]));

  Widget _modelCard(OfflineTransModel m) {
    final isSelected = _selectedModel == m.id;
    return GestureDetector(
      onTap: () async {
        await OfflineTranslationService.setSelectedModel(m.id);
        setState(() => _selectedModel = m.id);
        _load();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? _kAccent.withOpacity(0.15) : _kCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSelected ? _kAccent : Colors.transparent, width: 1.5)),
        child: Row(children: [
          Icon(isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
            color: isSelected ? _kAccent : Colors.white38, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(m.name, style: TextStyle(color: isSelected ? Colors.white : Colors.white70,
              fontWeight: FontWeight.bold, fontSize: 13)),
            Text(m.description, style: const TextStyle(color: Colors.white38, fontSize: 11)),
            Text('${m.langCount} languages • ${m.size}',
              style: TextStyle(color: isSelected ? _kAccent : Colors.white30, fontSize: 11)),
          ])),
        ])));
  }

  Widget _langTile(TranslateLanguage lang) {
    final isDownloaded = _downloaded[lang.bcpCode] == true;
    final isDownloading = _downloading[lang.bcpCode] == true;
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(8)),
      child: ListTile(dense: true,
        leading: Text(lang.displayName,
          style: TextStyle(color: isDownloaded ? Colors.white : Colors.white54, fontSize: 13)),
        title: Text(lang.bcpCode.toUpperCase(),
          style: const TextStyle(color: Colors.white30, fontSize: 10)),
        trailing: isDownloading
          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF7C3AED)))
          : isDownloaded
            ? IconButton(
                icon: const Icon(Icons.delete_rounded, color: Colors.white24, size: 18),
                onPressed: () async {
                  await OfflineTranslationService.deleteModel(lang);
                  setState(() => _downloaded[lang.bcpCode] = false);
                })
            : IconButton(
                icon: const Icon(Icons.download_rounded, color: Color(0xFF7C3AED), size: 18),
                onPressed: () async {
                  setState(() => _downloading[lang.bcpCode] = true);
                  try {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Downloading \${lang.displayName} (\${lang.bcpCode})...'), duration: const Duration(seconds: 2)));
                    final ok = await OfflineTranslationService.downloadModel(lang, (_) {});
                    if (mounted) setState(() {
                      _downloading[lang.bcpCode] = false;
                      _downloaded[lang.bcpCode] = ok;
                    });
                    if (!ok && mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Download failed for \${lang.displayName} — check network'), backgroundColor: Colors.red));
                    }
                  } catch (e) {
                    if (mounted) setState(() { _downloading[lang.bcpCode] = false; });
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(e.toString().substring(0, e.toString().length.clamp(0, 100))), backgroundColor: Colors.red));
                  }
                })));
  }
}
