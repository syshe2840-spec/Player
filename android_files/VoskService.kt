package com.vezoo.player

import android.content.Context
import android.media.*
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.widget.Toast
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import org.vosk.Model
import org.vosk.Recognizer
import java.io.File
import java.util.concurrent.ConcurrentLinkedQueue

class VoskService(
    private val context: Context,
    private val callback: MethodChannel? = null
) {
    private var recognizer: Recognizer? = null
    private var model: Model? = null
    private var recorder: AudioRecord? = null
    @Volatile private var running = false

    // صف رویدادها — Dart با polling میخونه
    val eventQueue = ConcurrentLinkedQueue<Map<String, Any>>()

    companion object {
        const val MODELS_DIR = "/storage/emulated/0/Download/Vezoo/VoskModels"
        const val SAMPLE_RATE = 16000
    }

    fun start(langCode: String, projection: android.media.projection.MediaProjection?) {
        if (running) return
        running = true
        // Toast برای تست — مستقل از هر channel
        Handler(Looper.getMainLooper()).post {
            Toast.makeText(context, "Vosk starting... lang=$langCode", Toast.LENGTH_LONG).show()
        }
        Thread { doStart(langCode, projection) }.start()
    }

    private fun doStart(langCode: String, projection: android.media.projection.MediaProjection?) {
        send("status", "VOSK START: lang=$langCode")

        val modelPath = findModel(langCode)
        if (modelPath == null) {
            val dir = File(MODELS_DIR)
            send("status", "VOSK: model NOT found. dir exists=${dir.exists()} contents=${dir.listFiles()?.map{it.name}}")
            send("error", "Model not found: $langCode")
            running = false; return
        }
        send("status", "VOSK: model found: $modelPath")

        try {
            model = Model(modelPath)
            recognizer = Recognizer(model, SAMPLE_RATE.toFloat())
            send("status", "VOSK: model loaded OK")
        } catch (e: Exception) {
            send("error", "Model load failed: ${e.message}")
            running = false; return
        }

        val buf = maxOf(AudioRecord.getMinBufferSize(SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT) * 2, 3200)

        try {
            if (projection != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val config = AudioPlaybackCaptureConfiguration.Builder(projection)
                    .addMatchingUsage(AudioAttributes.USAGE_MEDIA)
                    .addMatchingUsage(AudioAttributes.USAGE_GAME)
                    .build()
                recorder = AudioRecord.Builder()
                    .setAudioFormat(AudioFormat.Builder()
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .setSampleRate(SAMPLE_RATE)
                        .setChannelMask(AudioFormat.CHANNEL_IN_MONO).build())
                    .setBufferSizeInBytes(buf)
                    .setAudioPlaybackCaptureConfig(config).build()
                send("status", "VOSK: internal audio state=${recorder?.state}")
                if (recorder?.state != AudioRecord.STATE_INITIALIZED) {
                    recorder?.release(); recorder = null
                    useMic(buf)
                }
            } else {
                useMic(buf)
            }

            if (recorder?.state != AudioRecord.STATE_INITIALIZED) {
                send("error", "Audio init failed"); running = false; return
            }

            recorder?.startRecording()
            send("status", "VOSK: recording started")

            val chunk = ByteArray(buf / 4)
            var total = 0L
            while (running) {
                val read = recorder?.read(chunk, 0, chunk.size) ?: -1
                if (read > 0) {
                    total += read
                    if (total % (SAMPLE_RATE * 2 * 3L) < read) send("status", "VOSK: sent ${total/1024}kb")
                    val isFinal = recognizer?.acceptWaveForm(chunk, read) ?: false
                    if (isFinal) {
                        val res = JSONObject(recognizer?.result ?: "{}").optString("text", "")
                        if (res.isNotEmpty()) send("transcript", mapOf("text" to res, "final" to true))
                    } else {
                        val p = JSONObject(recognizer?.partialResult ?: "{}").optString("partial", "")
                        if (p.isNotEmpty()) send("transcript", mapOf("text" to p, "final" to false))
                    }
                } else if (read < 0) break
            }
        } catch (e: Exception) {
            send("error", "${e.javaClass.simpleName}: ${e.message}")
        } finally { stop() }
    }

    private fun useMic(buf: Int) {
        recorder = AudioRecord(MediaRecorder.AudioSource.MIC, SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, buf)
        send("status", "VOSK: using MIC state=${recorder?.state}")
    }

    private fun findModel(langCode: String): String? {
        val dir = File(MODELS_DIR)
        if (!dir.exists()) return null
        return dir.listFiles()?.firstOrNull { f ->
            f.isDirectory && (f.name.contains("-$langCode-") || f.name.contains("-$langCode.") || f.name.endsWith("-$langCode"))
        }?.absolutePath
    }

    // ارسال رویداد — هم به queue (polling) هم به callback channel
    private fun send(type: String, data: Any) {
        android.util.Log.d("VoskService", "EVENT type=$type data=$data")
        val event = mapOf("type" to type, "data" to data)
        eventQueue.offer(event)
        Handler(Looper.getMainLooper()).post {
            try { callback?.invokeMethod("onVoskEvent", event) } catch (e: Exception) {
                android.util.Log.e("VoskService", "callback error: ${e.message}")
            }
        }
    }

    fun getNextEvent(): Map<String, Any>? = eventQueue.poll()

    fun stop() {
        running = false
        try { recorder?.stop(); recorder?.release() } catch (_: Exception) {}
        try { recognizer?.close() } catch (_: Exception) {}
        try { model?.close() } catch (_: Exception) {}
        recorder = null; recognizer = null; model = null
        send("status", "VOSK: stopped")
    }
}

