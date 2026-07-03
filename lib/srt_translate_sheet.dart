import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'srt_translation_service.dart';
import 'whisper_service.dart' show WhisperService;

/// شیت ترجمه زیرنویس با Cloudflare AI
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

  void _start() {
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
        WhisperService.updateProgressNotification('⚠ خطا: $err', 0);
      },
    );

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('ترجمه به ${kTranslateLangDisplay[_targetLang] ?? _targetLang} در پس‌زمینه شروع شد'),
      backgroundColor: const Color(0xFF7C3AED),
      duration: const Duration(seconds: 3),
    ));
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
            const Text('ترجمه زیرنویس', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
            const Spacer(),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('بستن')),
          ]),
          const SizedBox(height: 4),
          const Text('متن توسط Cloudflare AI ترجمه میشه — timestamp ها دست‌نخورده می‌مونن',
            style: TextStyle(color: Colors.white54, fontSize: 11)),
          const SizedBox(height: 16),

          // ── انتخاب زبان مقصد ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(color: const Color(0xFF2A2A35), borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              const Text('زبان مقصد: ', style: TextStyle(color: Colors.white60, fontSize: 13)),
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
            const Text('اعمال روی:', style: TextStyle(color: Colors.white60, fontSize: 12)),
            const SizedBox(width: 10),
            _chip('Sub 1', 0),
            const SizedBox(width: 6),
            _chip('Sub 2', 1),
            const SizedBox(width: 6),
            _chip('هر دو', 2),
          ]),
          const SizedBox(height: 14),

          SizedBox(width: double.infinity, child: FilledButton.icon(
            onPressed: _start,
            icon: const Icon(Icons.translate),
            label: const Text('شروع ترجمه در پس‌زمینه'),
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
