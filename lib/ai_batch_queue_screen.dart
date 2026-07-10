import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'whisper_service.dart';
import 'l10n.dart';

enum _ItemStatus { pending, running, done, error, skipped }

class _QueueItem {
  final String path;
  _ItemStatus status = _ItemStatus.pending;
  String message = '';
  _QueueItem(this.path);
}

/// صف ساخت دسته‌ای زیرنویس برای چند ویدیو پشت‌سرهم
class AiBatchQueueScreen extends StatefulWidget {
  const AiBatchQueueScreen({super.key});
  @override State<AiBatchQueueScreen> createState() => _AiBatchQueueScreenState();
}

class _AiBatchQueueScreenState extends State<AiBatchQueueScreen> {
  final List<_QueueItem> _queue = [];
  List<WhisperModelDef> _downloaded = [];
  WhisperModelDef? _selected;
  String _lang = 'fa';
  WhisperEngine _engine = WhisperEngine.v1;
  bool _running = false;
  bool _cancelRequested = false;
  int _currentIndex = -1;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final list = await WhisperService.allDownloadedModels();
    final active = await WhisperService.getActiveModel();
    final engine = await WhisperService.getActiveEngine();
    if (mounted) setState((){
      _downloaded = list;
      _selected = active ?? (list.isNotEmpty ? list.first : null);
      _engine = engine;
    });
  }

  Future<void> _addVideos() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.video, allowMultiple: true);
    if (res == null) return;
    setState(() {
      for (final f in res.files) {
        if (f.path != null && !_queue.any((q) => q.path == f.path)) {
          _queue.add(_QueueItem(f.path!));
        }
      }
    });
  }

  void _removeItem(int i) {
    if (_running) return;
    setState(() => _queue.removeAt(i));
  }

  Future<void> _startQueue() async {
    if (_selected == null || _queue.isEmpty) return;
    setState((){ _running = true; _cancelRequested = false; });

    for (int i = 0; i < _queue.length; i++) {
      if (_cancelRequested) {
        setState(() => _queue[i].status = _ItemStatus.skipped);
        continue;
      }
      setState((){ _currentIndex = i; _queue[i].status = _ItemStatus.running; _queue[i].message = L.startingLabel; });
      try {
        await WhisperService.transcribe(
          videoPath: _queue[i].path,
          language: _lang,
          model: _selected!,
          useVad: true,
          engine: _engine,
          onStatus: (s, p) {
            if (mounted) setState(() => _queue[i].message = '$s (${(p*100).toInt()}%)');
          },
        );
        if (mounted) setState((){ _queue[i].status = _ItemStatus.done; _queue[i].message = L.done; });
      } catch (e) {
        if (mounted) setState((){ _queue[i].status = _ItemStatus.error; _queue[i].message = L.errorMsg(e); });
      }
    }

    if (mounted) setState((){ _running = false; _currentIndex = -1; });
  }

  void _cancelQueue() {
    setState(() => _cancelRequested = true);
    WhisperService.cancelExtraction();
  }

  Color _statusColor(_ItemStatus s) => switch (s) {
    _ItemStatus.pending => Colors.white38,
    _ItemStatus.running => const Color(0xFF7C3AED),
    _ItemStatus.done => Colors.green,
    _ItemStatus.error => Colors.red,
    _ItemStatus.skipped => Colors.orange,
  };

  IconData _statusIcon(_ItemStatus s) => switch (s) {
    _ItemStatus.pending => Icons.schedule,
    _ItemStatus.running => Icons.autorenew,
    _ItemStatus.done => Icons.check_circle,
    _ItemStatus.error => Icons.error,
    _ItemStatus.skipped => Icons.skip_next,
  };

  @override
  Widget build(BuildContext context) {
    final doneCount = _queue.where((q) => q.status == _ItemStatus.done).length;

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1C1C22),
        title: Text('${L.batchQueue} (${_queue.length})', style: const TextStyle(color: Colors.white, fontSize: 14)),
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: _running ? null : () => Navigator.pop(context)),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(children: [
            Row(children: [
              if (_downloaded.isNotEmpty) Expanded(child: DropdownButton<WhisperModelDef>(
                value: _selected, isExpanded: true, dropdownColor: const Color(0xFF2A2A35),
                style: const TextStyle(color: Colors.white, fontSize: 12),
                items: _downloaded.map((m) => DropdownMenuItem(value: m, child: Text(m.name))).toList(),
                onChanged: _running ? null : (v) { if (v != null) setState(() => _selected = v); },
              )),
              const SizedBox(width: 8),
              Flexible(child: DropdownButton<String>(
                value: _lang, dropdownColor: const Color(0xFF2A2A35), isExpanded: false,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                items: kLanguages.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                onChanged: _running ? null : (v) { if (v != null) setState(() => _lang = v); },
              )),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: OutlinedButton.icon(
                onPressed: _running ? null : _addVideos,
                icon: const Icon(Icons.add, size: 16),
                label: Text(L.addVideo, style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFF7C3AED))),
              )),
              const SizedBox(width: 8),
              Expanded(child: FilledButton.icon(
                onPressed: (_running || _queue.isEmpty || _selected == null) ? (_running ? _cancelQueue : null) : _startQueue,
                icon: Icon(_running ? Icons.stop : Icons.play_arrow, size: 16),
                label: Text(_running ? L.cancelQueue : L.startProcessing, style: const TextStyle(fontSize: 12)),
                style: FilledButton.styleFrom(backgroundColor: _running ? Colors.red : const Color(0xFF7C3AED)),
              )),
            ]),
            if (_running) Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('${doneCount}/${_queue.length}', style: const TextStyle(color: Colors.white54, fontSize: 11)),
            ),
          ]),
        ),
        const Divider(color: Colors.white12, height: 1),
        Expanded(
          child: _queue.isEmpty
            ? Center(child: Text(L.noVideoAdded, style: TextStyle(color: Colors.white38, fontSize: 13)))
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _queue.length,
                itemBuilder: (_, i) {
                  final item = _queue[i];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C1C22), borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _currentIndex == i ? const Color(0xFF7C3AED) : Colors.white12),
                    ),
                    child: Row(children: [
                      Icon(_statusIcon(item.status), color: _statusColor(item.status), size: 18),
                      const SizedBox(width: 10),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(item.path.split('/').last, style: const TextStyle(color: Colors.white, fontSize: 12), overflow: TextOverflow.ellipsis),
                        if (item.message.isNotEmpty) Text(item.message, style: TextStyle(color: _statusColor(item.status), fontSize: 10)),
                      ])),
                      if (!_running) IconButton(
                        icon: const Icon(Icons.close, color: Colors.white38, size: 16),
                        onPressed: () => _removeItem(i),
                      ),
                    ]),
                  );
                },
              ),
        ),
      ]),
    );
  }
}
