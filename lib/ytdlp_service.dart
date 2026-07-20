import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// سرویس پخش آنلاین — فقط YouTube
class YtDlpService {
  static final _yt = YoutubeExplode();

  static Future<String> getStreamUrl(String url) async {
    try {
      final videoId = VideoId(url);
      // v3.1.0 — try multiple clients for reliability
      final manifest = await _yt.videos.streams.getManifest(
        videoId,
        ytClients: [
          YoutubeApiClient.safari,
          YoutubeApiClient.androidVr,
          YoutubeApiClient.android,
          YoutubeApiClient.tv,
        ],
      );
      final muxed = manifest.muxed;
      if (muxed.isNotEmpty) return muxed.sortByVideoQuality().first.url.toString();
      final video = manifest.videoOnly;
      if (video.isNotEmpty) return video.sortByVideoQuality().first.url.toString();
      throw Exception('No stream found');
    } catch (e) {
      throw Exception('YouTube error: $e');
    }
  }
}

