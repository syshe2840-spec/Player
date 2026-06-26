package ir.subteam.subtitle_player

import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

class MainActivity : FlutterActivity() {
    private val CHANNEL = "ir.subteam.subtitle_player/thumbnail"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "getThumbnail") {
                    val path = call.argument<String>("path") ?: return@setMethodCallHandler result.error("NO_PATH", "path null", null)
                    val width = call.argument<Int>("width") ?: 120
                    val height = call.argument<Int>("height") ?: 80
                    Thread {
                        try {
                            val retriever = MediaMetadataRetriever()
                            retriever.setDataSource(path)
                            val bitmap = retriever.getFrameAtTime(1_000_000)
                            retriever.release()
                            if (bitmap != null) {
                                val scaled = Bitmap.createScaledBitmap(bitmap, width, height, true)
                                val stream = ByteArrayOutputStream()
                                scaled.compress(Bitmap.CompressFormat.JPEG, 75, stream)
                                result.success(stream.toByteArray())
                            } else {
                                result.success(null)
                            }
                        } catch (e: Exception) {
                            result.success(null)
                        }
                    }.start()
                } else {
                    result.notImplemented()
                }
            }
    }
}

