package ir.subteam.subtitle_player

import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val CHANNEL = "ir.subteam.subtitle_player/thumbnail"
    private val executor = Executors.newCachedThreadPool()
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "getThumbnail") {
                    val path = call.argument<String>("path")
                    if (path == null) { mainHandler.post { result.success(null) }; return@setMethodCallHandler }
                    executor.execute {
                        val bytes = generateThumbnail(path)
                        mainHandler.post { result.success(bytes) }
                    }
                } else {
                    result.notImplemented()
                }
            }
    }

    private fun generateThumbnail(path: String): ByteArray? {
        val retriever = MediaMetadataRetriever()
        return try {
            // امتحان با Uri (قابل اطمینان‌تر برای Android 10+)
            val file = File(path)
            if (!file.exists()) return null
            retriever.setDataSource(applicationContext, Uri.fromFile(file))

            var bitmap: Bitmap? = null
            // امتحان چند زمان مختلف
            for (us in longArrayOf(1_000_000L, 500_000L, 0L, 5_000_000L)) {
                bitmap = retriever.getFrameAtTime(us, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                if (bitmap != null) break
            }
            if (bitmap == null) return null

            val w = 160; val h = 90
            val scaled = Bitmap.createScaledBitmap(bitmap, w, h, true)
            val out = ByteArrayOutputStream()
            scaled.compress(Bitmap.CompressFormat.JPEG, 75, out)
            out.toByteArray()
        } catch (_: Exception) {
            null
        } finally {
            try { retriever.release() } catch (_: Exception) {}
        }
    }
}

