import 'package:flutter/material.dart';
import 'srt_translation_service.dart';

/// شیت ترجمه زیرنویس با Cloudflare AI
class SrtTranslateSheet extends StatefulWidget {
  final String srtPath;           // مسیر SRT
  final String? srtContent;       // محتوا (اگه فایل نداره)
  final void Function(String translatedPath) onDone;

  const SrtTranslateSheet({
    super.key,
    required this.srtPath,
    this.srtContent,
    required this.onDone,
  });

  static Future<void> show(
    BuildContext ctx,
    String srtPath,
    void Function(String) onDone, {
    String? srtContent,
  }) => showModalBottomSheet(
    context: ctx, isScrollControlled: true,
    backgroundColor: const Color(0xFF1C1C22),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => SrtTranslateSheet(srtPath: srtPath, srtContent: srtContent, onDone: onDone),
  );

  @override State<SrtTranslateSheet> createState() => _State();
}

class _State extends State<SrtTranslateSheet> {
  String _targetLang = 'fa';
  bool _running = false;
  String _status = '';
  double _progress = 0;
  String? _error;

  Future<void> _start() async {
    setState(() { _running = true; _error = null; _status = 'شروع...'; _progress = 0; });
    try {
      String path;
      if (widget.srtContent != null) {
        path = await SrtTranslationService.translateSrtContent(
          content: widget.srtContent!,
          targetLangCode: _targetLang,
          onStatus: (s, p) { if (mounted) setState(() { _status = s; _progress = p; }); },
        );
      } else {
        path = await SrtTranslationService.translateSrtFile(
          srtPath: widget.srtPath,
          targetLangCode: _targetLang,
          onStatus: (s, p) { if (mounted) setState(() { _status = s; _progress = p; }); },
        );
      }
      if (mounted) {
        Navigator.pop(context);
        widget.onDone(path);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('✓ ترجمه شد به ${kTranslateLangDisplay[_targetLang] ?? _targetLang}'),
          backgroundColor: const Color(0xFF7C3AED)));
      }
    } catch (e) {
      if (mounted) setState(() { _running = false; _error = '$e'; });
    }
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
            TextButton(onPressed: _running ? null : () => Navigator.pop(ctx), child: const Text('بستن')),
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
                onChanged: _running ? null : (v) { if (v != null) setState(() => _targetLang = v); },
              )),
            ]),
          ),
          const SizedBox(height: 14),

          if (_error != null) Container(
            padding: const EdgeInsets.all(10),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(color: Colors.red.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
            child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
          ),

          if (_running) ...[
            Text(_status, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: _progress > 0 ? _progress : null,
              backgroundColor: Colors.white12, color: const Color(0xFF7C3AED)),
            const SizedBox(height: 12),
          ],

          SizedBox(width: double.infinity, child: FilledButton.icon(
            onPressed: _running ? null : _start,
            icon: _running
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.translate),
            label: Text(_running ? _status : 'ترجمه کن'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF7C3AED),
              padding: const EdgeInsets.symmetric(vertical: 14)),
          )),
        ]),
      ),
    ),
  );
}
 
