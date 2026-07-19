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
    val eventQueue = ConcurrentLinkedQueue<Map<String, Any>>()

    companion object {
        const val MODELS_DIR = "/storage/emulated/0/Download/Vezoo/VoskModels"
        const val SAMPLE_RATE = 16000
    }

    fun start(langCode: String, projection: android.media.projection.MediaProjection?) {
        if (running) return
        running = true

        // Toast 1: تأیید start() صدا زده شد
        toast("✅ VoskService.start() called lang=$langCode")

        Thread {
            toast("✅ Thread started")
            doStart(langCode, projection)
        }.start()
    }

    private fun doStart(langCode: String, projection: android.media.projection.MediaProjection?) {
        toast("✅ doStart running")
        send("status", "STEP1: doStart lang=$langCode")

        // STEP 1: پیدا کردن مدل
        val dir = File(MODELS_DIR)
        send("status", "STEP1: models dir exists=${dir.exists()} path=$MODELS_DIR")
        if (dir.exists()) {
            val contents = dir.listFiles()?.map { it.name } ?: emptyList()
            send("status", "STEP1: dir contents=$contents")
        }

        val modelPath = findModel(langCode)
        if (modelPath == null) {
            toast("❌ Model NOT found for $langCode")
            send("error", "STEP1 FAIL: model not found for $langCode")
            running = false; return
        }
        toast("✅ Model found: $modelPath")
        send("status", "STEP1 OK: model=$modelPath")

        // STEP 2: بارگذاری مدل
        try {
            toast("⏳ Loading model...")
            model = Model(modelPath)
            recognizer = Recognizer(model, SAMPLE_RATE.toFloat())
            toast("✅ Model loaded!")
            send("status", "STEP2 OK: model loaded")
        } catch (e: Exception) {
            toast("❌ Model load failed: ${e.message}")
            send("error", "STEP2 FAIL: ${e.message}")
            running = false; return
        }

        // STEP 3: شروع capture
        val buf = maxOf(AudioRecord.getMinBufferSize(SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT) * 2, 3200)
        toast("⏳ Starting audio capture...")
        send("status", "STEP3: starting audio buf=$buf projection=${projection != null}")

        try {
            if (projection != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val config = AudioPlaybackCaptureConfiguration.Builder(projection)
                    .addMatchingUsage(AudioAttributes.USAGE_MEDIA)
                    .build()
                recorder = AudioRecord.Builder()
                    .setAudioFormat(AudioFormat.Builder()
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .setSampleRate(SAMPLE_RATE)
                        .setChannelMask(AudioFormat.CHANNEL_IN_MONO).build())
                    .setBufferSizeInBytes(buf)
                    .setAudioPlaybackCaptureConfig(config).build()
                send("status", "STEP3: internal audio state=${recorder?.state}")
                if (recorder?.state != AudioRecord.STATE_INITIALIZED) {
                    recorder?.release(); recorder = null; useMic(buf)
                }
            } else {
                useMic(buf)
            }

            if (recorder?.state != AudioRecord.STATE_INITIALIZED) {
                toast("❌ Audio recorder failed")
                send("error", "STEP3 FAIL: recorder not initialized")
                running = false; return
            }

            recorder?.startRecording()
            toast("✅ Recording started!")
            send("status", "STEP3 OK: recording started")

            val chunk = ByteArray(buf / 4)
            var total = 0L
            while (running) {
                val read = recorder?.read(chunk, 0, chunk.size) ?: -1
                if (read > 0) {
                    total += read
                    if (total % (SAMPLE_RATE * 2 * 3L) < read) send("status", "STEP4: sent ${total/1024}kb")
                    val isFinal = recognizer?.acceptWaveForm(chunk, read) ?: false
                    if (isFinal) {
                        val res = JSONObject(recognizer?.result ?: "{}").optString("text", "")
                        send("status", "STEP4 FINAL: '$res'")
                        if (res.isNotEmpty()) send("transcript", mapOf("text" to res, "final" to true))
                    } else {
                        val p = JSONObject(recognizer?.partialResult ?: "{}").optString("partial", "")
                        if (p.isNotEmpty()) send("transcript", mapOf("text" to p, "final" to false))
                    }
                } else if (read < 0) { send("status", "STEP4 ERROR: read=$read"); break }
            }
        } catch (e: Exception) {
            toast("❌ Exception: ${e.message}")
            send("error", "EXCEPTION: ${e.javaClass.simpleName}: ${e.message}")
        } finally { stop() }
    }

    private fun useMic(buf: Int) {
        recorder = AudioRecord(MediaRecorder.AudioSource.MIC, SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, buf)
        send("status", "STEP3: using MIC state=${recorder?.state}")
    }

    private fun findModel(langCode: String): String? {
        val dir = File(MODELS_DIR)
        if (!dir.exists()) return null
        return dir.listFiles()?.firstOrNull { f ->
            f.isDirectory && (f.name.contains("-$langCode-") || f.name.contains("-$langCode.") || f.name.endsWith("-$langCode"))
        }?.absolutePath
    }

    private fun toast(msg: String) {
        android.util.Log.d("VoskService", msg)
        Handler(Looper.getMainLooper()).post {
            Toast.makeText(context, msg, Toast.LENGTH_SHORT).show()
        }
    }

    private fun send(type: String, data: Any) {
        android.util.Log.d("VoskService", "send: $type = $data")
        val event = mapOf("type" to type, "data" to data)
        eventQueue.offer(event)
        Handler(Looper.getMainLooper()).post {
            try { callback?.invokeMethod("onVoskEvent", event) } catch (_: Exception) {}
        }
    }

    fun getNextEvent(): Map<String, Any>? = eventQueue.poll()

    fun stop() {
        running = false
        try { recorder?.stop(); recorder?.release() } catch (_: Exception) {}
        try { recognizer?.close() } catch (_: Exception) {}
        try { model?.close() } catch (_: Exception) {}
        recorder = null; recognizer = null; model = null
        send("status", "STOPPED")
    }
}

