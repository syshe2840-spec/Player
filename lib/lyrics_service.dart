import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

const _workerBase = 'https://player.lastofanarchy.workers.dev';

// ── مدل‌ها ──

class LyricsTrack {
  final dynamic id;
  final String title;
  final String artist;
  final String album;
  final int? duration;
  final bool hasSynced;
  final String source; // 'lrclib' | 'genius'
  final String? thumbnail;
  final String? geniusUrl;
  LyricsTrack({required this.id, required this.title, required this.artist,
    this.album = '', this.duration, this.hasSynced = false,
    required this.source, this.thumbnail, this.geniusUrl});
}

class LyricsResult {
  final String? syncedLrc;   // LRC format با timestamp
  final String? plainLyrics; // متن ساده
  final String title;
  final String artist;
  LyricsResult({this.syncedLrc, this.plainLyrics, required this.title, required this.artist});
  bool get hasSynced => syncedLrc != null && syncedLrc!.trim().isNotEmpty;
}

// ── سرویس ──

class LyricsService {
  static Future<Map<String, List<LyricsTrack>>> search(String query) async {
    final uri = Uri.parse('$_workerBase/lyrics/search?q=${Uri.encodeComponent(query)}&source=all');
    final client = HttpClient();
    try {
      final req = await client.getUrl(uri);
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      final data = jsonDecode(body) as Map<String, dynamic>;
      return {
        'lrclib': ((data['lrclib'] as List?) ?? []).map((t) => LyricsTrack(
          id: t['id'], title: t['title'] ?? '', artist: t['artist'] ?? '',
          album: t['album'] ?? '', duration: t['duration'],
          hasSynced: t['hasSynced'] == true, source: 'lrclib',
        )).toList(),
        'genius': ((data['genius'] as List?) ?? []).map((t) => LyricsTrack(
          id: t['id'], title: t['title'] ?? '', artist: t['artist'] ?? '',
          hasSynced: false, source: 'genius',
          thumbnail: t['thumbnail'], geniusUrl: t['url'],
        )).toList(),
      };
    } catch (e) {
      debugPrint('[Lyrics] search error: $e');
      return {'lrclib': [], 'genius': []};
    } finally {
      client.close();
    }
  }

  static Future<LyricsResult?> fetchLrcLib(dynamic id) async {
    final uri = Uri.parse('$_workerBase/lyrics/lrc?id=$id');
    final client = HttpClient();
    try {
      final req = await client.getUrl(uri);
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      final d = jsonDecode(body) as Map<String, dynamic>;
      return LyricsResult(
        syncedLrc: d['synced'] as String?,
        plainLyrics: d['plain'] as String?,
        title: d['title'] ?? '',
        artist: d['artist'] ?? '',
      );
    } catch (e) {
      debugPrint('[Lyrics] fetch error: $e');
      return null;
    } finally {
      client.close();
    }
  }

  /// تبدیل LRC به SRT برای نمایش روی ویدیو
  static String lrcToSrt(String lrc) {
    final lines = lrc.split('\n');
    final entries = <_LrcLine>[];

    for (final line in lines) {
      final m = RegExp(r'^\[(\d{1,2}):(\d{2})\.(\d{1,3})\](.*)$').firstMatch(line.trim());
      if (m == null) continue;
      final min = int.parse(m.group(1)!);
      final sec = int.parse(m.group(2)!);
      final ms = int.parse(m.group(3)!.padRight(3, '0').substring(0, 3));
      final text = m.group(4)!.trim();
      if (text.isEmpty) continue;
      entries.add(_LrcLine(
        Duration(minutes: min, seconds: sec, milliseconds: ms),
        text,
      ));
    }

    if (entries.isEmpty) return '';
    final b = StringBuffer();
    for (int i = 0; i < entries.length; i++) {
      final start = entries[i].time;
      final end = i + 1 < entries.length
        ? entries[i + 1].time - const Duration(milliseconds: 100)
        : entries[i].time + const Duration(seconds: 5);
      b.writeln(i + 1);
      b.writeln('${formatSrtTime(start)} --> ${formatSrtTime(end)}');
      b.writeln(entries[i].text);
      b.writeln();
    }
    return b.toString();
  }

  /// ذخیره SRT کنار ویدیو
  static Future<String> saveAsSubtitle(String videoPath, String srtContent, String suffix) async {
    // موزیک زیرنویس → /storage/emulated/0/Download/Vezoo/Music/
    const musicDir = '/storage/emulated/0/Download/Vezoo/Music';
    await Directory(musicDir).create(recursive: true);
    final base = p.basenameWithoutExtension(videoPath);
    final outPath = p.join(musicDir, '${base}_$suffix.srt');
    await File(outPath).writeAsString(srtContent, encoding: utf8);
    return outPath;
  }

  static String formatSrtTime(Duration d) =>
    '${d.inHours.toString().padLeft(2,'0')}:'
    '${(d.inMinutes%60).toString().padLeft(2,'0')}:'
    '${(d.inSeconds%60).toString().padLeft(2,'0')},'
    '${(d.inMilliseconds%1000).toString().padLeft(3,'0')}';
}

class _LrcLine {
  final Duration time;
  final String text;
  _LrcLine(this.time, this.text);
}
