import 'package:flutter/material.dart';
import 'whisper_service.dart';

/// ویرایشگر دستی زیرنویس — اصلاح متن و زمان‌بندی هر خط
class SrtEditorScreen extends StatefulWidget {
  final String srtPath;
  const SrtEditorScreen({super.key, required this.srtPath});
  @override State<SrtEditorScreen> createState() => _SrtEditorScreenState();
}

class _SrtEditorScreenState extends State<SrtEditorScreen> {
  late List<SrtEntry> _entries;
  late List<TextEditingController> _textCtrls;
  bool _dirty = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _entries = readSrtEntries(widget.srtPath);
    _textCtrls = _entries.map((e) => TextEditingController(text: e.text)).toList();
  }

  @override
  void dispose() {
    for (final c in _textCtrls) c.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Duration? _parseShort(String s) {
    final parts = s.split(':');
    if (parts.length != 2) return null;
    final m = int.tryParse(parts[0]);
    final sec = int.tryParse(parts[1]);
    if (m == null || sec == null) return null;
    return Duration(minutes: m, seconds: sec);
  }

  Future<void> _editTime(int index, bool isStart) async {
    final entry = _entries[index];
    final current = isStart ? entry.from : entry.to;
    final ctrl = TextEditingController(text: _fmt(current));
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C22),
        title: Text(isStart ? 'زمان شروع (mm:ss)' : 'زمان پایان (mm:ss)',
          style: const TextStyle(color: Colors.white, fontSize: 14)),
        content: TextField(
          controller: ctrl, autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(hintText: '00:05', hintStyle: TextStyle(color: Colors.white38)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('لغو')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('ثبت')),
        ],
      ),
    );
    if (result == null) return;
    final parsed = _parseShort(result);
    if (parsed == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('فرمت اشتباه — باید mm:ss باشد'), backgroundColor: Colors.red));
      return;
    }
    setState(() {
      if (isStart) _entries[index].from = parsed; else _entries[index].to = parsed;
      _dirty = true;
    });
  }

  void _deleteEntry(int index) {
    setState(() {
      _entries.removeAt(index);
      _textCtrls.removeAt(index).dispose();
      _dirty = true;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    for (int i = 0; i < _entries.length; i++) {
      _entries[i].text = _textCtrls[i].text;
    }
    writeSrtEntries(widget.srtPath, _entries);
    setState((){ _saving = false; _dirty = false; });
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('✓ ذخیره شد'), backgroundColor: Colors.green));
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_dirty,
    onPopInvokedWithResult: (didPop, _) async {
      if (didPop) return;
      final leave = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C22),
        title: const Text('تغییرات ذخیره نشده', style: TextStyle(color: Colors.white, fontSize: 15)),
        content: const Text('بدون ذخیره خارج می‌شوید؟', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ماندن')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red), child: const Text('خروج بدون ذخیره')),
        ],
      ));
      if (leave == true && context.mounted) Navigator.pop(context);
    },
    child: Scaffold(
      backgroundColor: const Color(0xFF0F0F14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1C1C22),
        title: Text('ویرایش زیرنویس (${_entries.length} خط)', style: const TextStyle(color: Colors.white, fontSize: 14)),
        actions: [
          if (_dirty) IconButton(
            icon: _saving
              ? const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2,color:Colors.white))
              : const Icon(Icons.save, color: Color(0xFF7C3AED)),
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
      body: _entries.isEmpty
        ? const Center(child: Text('زیرنویسی برای ویرایش وجود ندارد', style: TextStyle(color: Colors.white54)))
        : ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: _entries.length,
            itemBuilder: (_, i) => Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFF1C1C22), borderRadius: BorderRadius.circular(12)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text('#${i + 1}', style: const TextStyle(color: Colors.white38, fontSize: 11)),
                  const Spacer(),
                  GestureDetector(onTap: () => _editTime(i, true),
                    child: Text(_fmt(_entries[i].from), style: const TextStyle(color: Color(0xFF7C3AED), fontSize: 12))),
                  const Text('  →  ', style: TextStyle(color: Colors.white38, fontSize: 12)),
                  GestureDetector(onTap: () => _editTime(i, false),
                    child: Text(_fmt(_entries[i].to), style: const TextStyle(color: Color(0xFF7C3AED), fontSize: 12))),
                  const SizedBox(width: 8),
                  GestureDetector(onTap: () => _deleteEntry(i),
                    child: const Icon(Icons.delete_outline, color: Colors.red, size: 16)),
                ]),
                const SizedBox(height: 6),
                TextField(
                  controller: _textCtrls[i],
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  maxLines: null,
                  onChanged: (_) => setState(() => _dirty = true),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  ),
                ),
              ]),
            ),
          ),
      bottomNavigationBar: _dirty ? SafeArea(child: Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(width: double.infinity, child: FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: const Icon(Icons.save),
          label: const Text('ذخیره تغییرات'),
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF7C3AED), padding: const EdgeInsets.symmetric(vertical: 14)),
        )),
      )) : null,
    ),
  );
}

