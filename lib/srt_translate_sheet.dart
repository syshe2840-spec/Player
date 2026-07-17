import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'srt_translation_service.dart';
import 'whisper_service.dart' show WhisperService;
import 'main.dart' show showSnack;
import 'l10n.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'offline_translation_service.dart';

/// شیت ترجمه زیرنویس — آنلاین (Cloudflare) یا آفلاین (ML Kit)
class SrtTranslateSheet extends StatefulWidget {
  final String srtPath;
  final String? srtContent;
  final void Function(String translatedPath) onDone;
  final void Function(String translatedPath)? onDoneSecondary;
  final void Function(String partialPath)? onSrtUpdated;

  const SrtTranslateSheet({
    super.key,
    required this.srtPath,
    this.srtContent,
    required this.onDone,
    this.onDoneSecondary,
    this.onSrtUpdated,
  });

  static Future<void> show(
    BuildContext ctx,
    String srtPath,
    void Function(String) onDone, {
    void Function(String)? onDoneSecondary,
    String? srtContent,
    void Function(String)? onSrtUpdated,
  }) => showModalBottomSheet(
    context: ctx, isScrollControlled: true,
    backgroundColor: const Color(0xFF1C1C22),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => SrtTranslateSheet(srtPath: srtPath, srtContent: srtContent, onDone: onDone, onDoneSecondary: onDoneSecondary, onSrtUpdated: onSrtUpdated),
  );

  @override State<SrtTranslateSheet> createState() => _State();
}

class _State extends State<SrtTranslateSheet> {
  String _targetLang = 'fa';
  int _subTarget = 0; // 0=sub1, 1=sub2, 2=هر دو
  bool _offlineMode = false; // false=آنلاین Cloudflare, true=آفلاین ML Kit

  Future<void> _startOffline() async {
    Navigator.pop(context);
    showSnack(context, 'ترجمه آفلاین شروع شد...', color: const Color(0xFF7C3AED), seconds: 2);
    String srtPath = widget.srtPath;
    if (widget.srtContent != null) {
      final tmp = File('\${Directory.systemTemp.path}/tmp_offline_translate.srt');
      tmp.writeAsStringSync(widget.srtContent!, encoding: utf8);
      srtPath = tmp.path;
    }
    try {
      final content = File(srtPath).readAsStringSync(encoding: utf8);
      final tgtLang = TranslateLanguage.values.firstWhere(
        (l) => l.bcpCode == _targetLang, orElse: () => TranslateLanguage.persian);
      final translated = await OfflineTranslationService.translateSrt(
        content, tgt: tgtLang,
        onProgress: (_) {},
        onChunk: (partial) => widget.onSrtUpdated?.call(srtPath),
      );
      final outPath = srtPath.replaceAll('.srt', '_offline_\$_targetLang.srt');
      File(outPath).writeAsStringSync(translated, encoding: utf8);
      switch(_subTarget) {
        case 0: widget.onDone(outPath); break;
        case 1: widget.onDoneSecondary?.call(outPath); break;
        case 2: widget.onDone(outPath); widget.onDoneSecondary?.call(outPath); break;
      }
    } catch (e) {
      WhisperService.updateProgressNotification('⚠ Offline translate error: \$e', 0);
    }
  }

  Future<bool> _checkOfflineReady() async {
    final tgtLang = TranslateLanguage.values.firstWhere(
      (l) => l.bcpCode == _targetLang, orElse: () => TranslateLanguage.persian);
    final isReady = await OfflineTranslationService.isDownloaded(tgtLang);
    return isReady;
  }

  void _start() {
    if (_offlineMode) {
      // چک میکنیم مدل دانلود شده باشه
      _checkOfflineReady().then((ready) {
        if (!ready) {
          showSnack(context, '⚠ زبان مقصد دانلود نشده — به Offline Translation برو و دانلود کن',
            color: Colors.orange, seconds: 4);
        } else {
          _startOffline();
        }
      });
      return;
    }
    // فوری sheet رو می‌بندیم — ترجمه در پس‌زمینه ادامه میده
    Navigator.pop(context);

    // اگه content داشت اول ذخیره کن
    String srtPath = widget.srtPath;
    if (widget.srtContent != null) {
      final tmp = File('${Directory.systemTemp.path}/tmp_srt_translate.srt');
      tmp.writeAsStringSync(widget.srtContent!, encoding: utf8);
      srtPath = tmp.path;
    }

    SrtTranslationService.startBackground(
      srtPath: srtPath,
      targetLangCode: _targetLang,
      onSrtUpdated: (partial) => widget.onSrtUpdated?.call(partial),
      onDone: (path) {
        switch(_subTarget){
          case 0: widget.onDone(path); break;
          case 1: widget.onDoneSecondary?.call(path); break;
          case 2: widget.onDone(path); widget.onDoneSecondary?.call(path); break;
        }
      },
      onError: (err) {
        // نشون دادن خطا از طریق notification
        WhisperService.updateProgressNotification('⚠ ${L.errorMsg(err)}', 0);
      },
    );

    showSnack(context, L.startTranslate, color: const Color(0xFF7C3AED), seconds: 3);
  }

  @override
  Widget build(BuildContext ctx) => SafeArea(
    child: ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.75),
      child: SingleChildScrollView(
        padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: MediaQuery.of(ctx).viewInsets.bottom + 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 14),
          Row(children: [
            const Icon(Icons.translate, color: Color(0xFF7C3AED), size: 20),
            const SizedBox(width: 8),
            Text(L.translateSub, style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
            const Spacer(),
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(L.close)),
          ]),
          const SizedBox(height: 4),
          Text(_offlineMode ? 'ML Kit — آفلاین بدون اینترنت' : L.cloudflareAiNote,
            style: TextStyle(color: Colors.white54, fontSize: 11)),
          const SizedBox(height: 10),
          // ── toggle آنلاین / آفلاین ──
          Row(children: [
            Expanded(child: GestureDetector(
              onTap: () => setState(() => _offlineMode = false),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: !_offlineMode ? const Color(0xFF7C3AED) : const Color(0xFF1A1A2A),
                  borderRadius: BorderRadius.circular(8)),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.cloud_rounded, size: 14, color: Colors.white70),
                  const SizedBox(width: 4),
                  Text('آنلاین', style: TextStyle(color: !_offlineMode ? Colors.white : Colors.white38, fontSize: 12, fontWeight: FontWeight.w600)),
                ])))),
            const SizedBox(width: 8),
            Expanded(child: GestureDetector(
              onTap: () => setState(() => _offlineMode = true),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: _offlineMode ? const Color(0xFF7C3AED) : const Color(0xFF1A1A2A),
                  borderRadius: BorderRadius.circular(8)),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.wifi_off_rounded, size: 14, color: Colors.white70),
                  const SizedBox(width: 4),
                  Text('آفلاین', style: TextStyle(color: _offlineMode ? Colors.white : Colors.white38, fontSize: 12, fontWeight: FontWeight.w600)),
                ])))),
          ]),
          const SizedBox(height: 16),

          // ── انتخاب زبان مقصد ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(color: const Color(0xFF2A2A35), borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              Text(L.targetLang, style: TextStyle(color: Colors.white60, fontSize: 13)),
              const SizedBox(width: 8),
              Expanded(child: DropdownButton<String>(
                value: _targetLang, isExpanded: true, dropdownColor: const Color(0xFF2A2A35),
                style: const TextStyle(color: Colors.white, fontSize: 13),
                items: kTranslateLangDisplay.entries.map((e) =>
                  DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                onChanged: (v) { if (v != null) setState(() => _targetLang = v); },
              )),
            ]),
          ),
          const SizedBox(height: 12),

          // ── انتخاب Sub1 / Sub2 / هر دو ──
          Row(children:[
            Text(L.applyTo, style: TextStyle(color: Colors.white60, fontSize: 12)),
            const SizedBox(width: 10),
            _chip('Sub 1', 0),
            const SizedBox(width: 6),
            _chip('Sub 2', 1),
            const SizedBox(width: 6),
            _chip(L.both, 2),
          ]),
          const SizedBox(height: 14),

          SizedBox(width: double.infinity, child: FilledButton.icon(
            onPressed: _start,
            icon: const Icon(Icons.translate),
            label: Text(L.startTranslate),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF7C3AED),
              padding: const EdgeInsets.symmetric(vertical: 14)),
          )),
        ]),
      ),
    ),
  );

  Widget _chip(String label, int idx) => GestureDetector(
    onTap: () => setState(() => _subTarget = idx),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: _subTarget == idx ? const Color(0xFF7C3AED) : const Color(0xFF2A2A35),
        borderRadius: BorderRadius.circular(16)),
      child: Text(label, style: TextStyle(color: _subTarget == idx ? Colors.white : Colors.white60, fontSize: 11)),
    ),
  );
}
