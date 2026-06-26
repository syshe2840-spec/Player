package ir.subteam.subtitle_player

import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val CHANNEL = "ir.subteam.subtitle_player/thumbnail"
    private val executor = Executors.newCachedThreadPool()
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getThumbnail" -> {
                        val path = call.argument<String>("path")
                        if (path == null) { result.success(null); return@setMethodCallHandler }
                        executor.execute {
                            val bytes = generateThumbnail(path)
                            // نتیجه باید از main thread فرستاده شود
                            mainHandler.post { result.success(bytes) }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun generateThumbnail(path: String): ByteArray? {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(path)
            // امتحان چند موقعیت مختلف
            var bitmap: Bitmap? = null
            val times = longArrayOf(1_000_000L, 0L, 3_000_000L, 10_000_000L)
            for (t in times) {
                bitmap = retriever.getFrameAtTime(t, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                if (bitmap != null) break
            }
            if (bitmap == null) return null
            val scaled = Bitmap.createScaledBitmap(bitmap, 160, 90, true)
            val stream = ByteArrayOutputStream()
            scaled.compress(Bitmap.CompressFormat.JPEG, 80, stream)
            stream.toByteArray()
        } catch (e: Exception) {
            null
        } finally {
            try { retriever.release() } catch (_: Exception) {}
        }
    }
}

