
package com.vezoo.player

import android.content.Context
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLRequest
import com.yausername.youtubedl_android.mapper.VideoInfo
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*
import org.json.JSONArray
import org.json.JSONObject

class YtDlpService(private val context: Context) {

    companion object {
        private var initialized = false

        fun init(context: Context) {
            if (initialized) return
            try {
                YoutubeDL.getInstance().init(context)
                initialized = true
                android.util.Log.d("YtDlpService", "✅ yt-dlp initialized")
            } catch (e: Exception) {
                android.util.Log.e("YtDlpService", "❌ init failed: ${e.message}")
            }
        }

        fun update(context: Context, onProgress: (String) -> Unit) {
            CoroutineScope(Dispatchers.IO).launch {
                try {
                    val status = YoutubeDL.getInstance().updateYoutubeDL(context)
                    withContext(Dispatchers.Main) {
                        onProgress("yt-dlp update: $status")
                    }
                } catch (e: Exception) {
                    withContext(Dispatchers.Main) {
                        onProgress("update failed: ${e.message}")
                    }
                }
            }
        }
    }

    // گرفتن stream URL از هر سایتی
    fun getStreamUrl(url: String, result: MethodChannel.Result) {
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val info: VideoInfo = YoutubeDL.getInstance().getInfo(
                    YoutubeDLRequest(url).apply {
                        addOption("--no-playlist")
                        addOption("-f", "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best")
                    }
                )
                val streamUrl = info.url ?: throw Exception("No stream URL found")
                withContext(Dispatchers.Main) {
                    result.success(mapOf(
                        "url" to streamUrl,
                        "title" to (info.title ?: ""),
                        "thumbnail" to (info.thumbnail ?: ""),
                        "duration" to (info.duration ?: 0),
                        "extractor" to (info.extractor ?: ""),
                    ))
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    result.error("YTDLP_ERROR", e.message, null)
                }
            }
        }
    }

    // گرفتن همه format ها
    fun getFormats(url: String, result: MethodChannel.Result) {
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val info: VideoInfo = YoutubeDL.getInstance().getInfo(
                    YoutubeDLRequest(url).apply {
                        addOption("--no-playlist")
                    }
                )
                val formats = info.formats?.map { f ->
                    mapOf(
                        "formatId" to (f.formatId ?: ""),
                        "ext" to (f.ext ?: ""),
                        "url" to (f.url ?: ""),
                        "vcodec" to (f.vcodec ?: "none"),
                        "acodec" to (f.acodec ?: "none"),
                        "width" to (f.width ?: 0),
                        "height" to (f.height ?: 0),
                    )
                } ?: emptyList()
                withContext(Dispatchers.Main) {
                    result.success(mapOf(
                        "title" to (info.title ?: ""),
                        "extractor" to (info.extractor ?: ""),
                        "formats" to formats,
                    ))
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    result.error("YTDLP_ERROR", e.message, null)
                }
            }
        }
    }

    // update yt-dlp
    fun updateYtDlp(result: MethodChannel.Result) {
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val status = YoutubeDL.getInstance().updateYoutubeDL(context)
                withContext(Dispatchers.Main) {
                    result.success(status.toString())
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    result.error("UPDATE_ERROR", e.message, null)
                }
            }
        }
    }
}
