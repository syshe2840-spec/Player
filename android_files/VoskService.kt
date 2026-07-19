package com.vezoo.player

import android.media.*
import android.os.Build
import io.flutter.plugin.common.EventChannel
import org.json.JSONObject
import org.vosk.Model
import org.vosk.Recognizer
import java.io.File

class VoskService(private val context: android.content.Context) {

    private var recognizer: Recognizer? = null
    private var model: Model? = null
    private var recorder: AudioRecord? = null
    @Volatile private var running = false
    private var sink: EventChannel.EventSink? = null

    companion object {
        const val MODELS_DIR = "/storage/emulated/0/Download/Vezoo/VoskModels"
        const val SAMPLE_RATE = 16000
    }

    fun setSink(s: EventChannel.EventSink?) { sink = s }

    fun start(langCode: String, projection: android.media.projection.MediaProjection?) {
        if (running) return
        running = true
        Thread { doStart(langCode, projection) }.start()
    }

    private fun doStart(langCode: String, projection: android.media.projection.MediaProjection?) {
        log("VOSK START: lang=$langCode projection=${projection != null}")

        // STEP 1: پیدا کردن مدل
        val modelPath = findModel(langCode)
        if (modelPath == null) {
            log("VOSK ERROR: model not found for '$langCode' in $MODELS_DIR")
            val dir = File(MODELS_DIR)
            if (!dir.exists()) log("VOSK: models dir does not exist: $MODELS_DIR")
            else log("VOSK: models dir contents: ${dir.listFiles()?.map { it.name }}")
            sendEvent("error", "Model not found: $langCode — go to Settings > Vosk Models")
            running = false; return
        }
        log("VOSK: model found: $modelPath")

        // STEP 2: بارگذاری مدل
        try {
            model = Model(modelPath)
            recognizer = Recognizer(model, SAMPLE_RATE.toFloat())
            log("VOSK: model loaded OK")
        } catch (e: Exception) {
            log("VOSK ERROR: model load failed: ${e.message}")
            sendEvent("error", "Model load failed: ${e.message}"); running = false; return
        }

        // STEP 3: شروع capture
        val bufSize = maxOf(AudioRecord.getMinBufferSize(SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT) * 2, 3200)
        log("VOSK: bufSize=$bufSize projection=${projection != null} api=${Build.VERSION.SDK_INT}")

        try {
            if (projection != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                log("VOSK: setting up AudioPlaybackCaptureConfiguration...")
                val config = AudioPlaybackCaptureConfiguration.Builder(projection)
                    .addMatchingUsage(AudioAttributes.USAGE_MEDIA)
                    .addMatchingUsage(AudioAttributes.USAGE_GAME)
                    .addMatchingUsage(AudioAttributes.USAGE_UNKNOWN)
                    .build()
                recorder = AudioRecord.Builder()
                    .setAudioFormat(AudioFormat.Builder()
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .setSampleRate(SAMPLE_RATE)
                        .setChannelMask(AudioFormat.CHANNEL_IN_MONO).build())
                    .setBufferSizeInBytes(bufSize)
                    .setAudioPlaybackCaptureConfig(config)
                    .build()
                val state = recorder?.state ?: -1
                log("VOSK: AudioPlaybackCapture state=$state (1=OK 0=FAIL)")
                if (state != AudioRecord.STATE_INITIALIZED) {
                    log("VOSK: AudioPlaybackCapture not initialized, fallback MIC")
                    recorder?.release(); recorder = null
                    useMic(bufSize)
                } else {
                    log("VOSK: internal audio capture OK")
                    sendEvent("status", "capturing_internal_audio")
                }
            } else {
                log("VOSK: no projection or API<10, using MIC")
                useMic(bufSize)
            }

            val recState = recorder?.state ?: -1
            log("VOSK: recorder final state=$recState")
            if (recState != AudioRecord.STATE_INITIALIZED) {
                log("VOSK ERROR: recorder not initialized"); sendEvent("error", "Audio init failed"); running = false; return
            }

            recorder?.startRecording()
            log("VOSK: recording started")
            sendEvent("status", "recording_started")

            val chunk = ByteArray(bufSize / 4)
            var totalBytes = 0L
            while (running) {
                val read = recorder?.read(chunk, 0, chunk.size) ?: -1
                if (read > 0) {
                    totalBytes += read
                    if (totalBytes % (SAMPLE_RATE * 2 * 3L) < read) log("VOSK: sent ${totalBytes/1024}kb")
                    val isFinal = recognizer?.acceptWaveForm(chunk, read) ?: false
                    if (isFinal) {
                        val res = JSONObject(recognizer?.result ?: "{}").optString("text", "")
                        log("VOSK FINAL: '$res'")
                        if (res.isNotEmpty()) sendEvent("transcript", mapOf("text" to res, "final" to true))
                    } else {
                        val partial = JSONObject(recognizer?.partialResult ?: "{}").optString("partial", "")
                        if (partial.isNotEmpty()) sendEvent("transcript", mapOf("text" to partial, "final" to false))
                    }
                } else if (read < 0) { log("VOSK: read error=$read"); break }
            }
            val finalRes = JSONObject(recognizer?.finalResult ?: "{}").optString("text", "")
            if (finalRes.isNotEmpty()) sendEvent("transcript", mapOf("text" to finalRes, "final" to true))
        } catch (e: Exception) {
            log("VOSK ERROR: ${e.javaClass.simpleName}: ${e.message}")
            sendEvent("error", "${e.javaClass.simpleName}: ${e.message}")
        } finally {
            stop()
        }
    }

    private fun useMic(bufSize: Int) {
        recorder = AudioRecord(MediaRecorder.AudioSource.MIC, SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, bufSize)
        log("VOSK: using MIC state=${recorder?.state}")
        sendEvent("status", "capturing_mic")
    }

    private fun findModel(langCode: String): String? {
        val dir = File(MODELS_DIR)
        if (!dir.exists()) return null
        return dir.listFiles()?.firstOrNull { f ->
            f.isDirectory && (f.name.contains("-$langCode-") || f.name.contains("-$langCode.") || f.name.endsWith("-$langCode") || f.name == "vosk-model-$langCode")
        }?.absolutePath
    }

    fun stop() {
        running = false
        try { recorder?.stop(); recorder?.release() } catch (_: Exception) {}
        try { recognizer?.close() } catch (_: Exception) {}
        try { model?.close() } catch (_: Exception) {}
        recorder = null; recognizer = null; model = null
        sendEvent("status", "stopped"); log("VOSK: stopped")
    }

    private fun log(msg: String) {
        android.util.Log.d("VoskService", msg)
        sendEvent("status", msg)
    }
    private fun sendEvent(type: String, data: Any) {
        if (sink == null) android.util.Log.w("VoskService", "SINK IS NULL! type=$type data=$data")
        android.os.Handler(android.os.Looper.getMainLooper()).post {
            try { sink?.success(mapOf("type" to type, "data" to data)) } catch (e: Exception) {
                android.util.Log.e("VoskService", "sendEvent error: \${e.message}")
            }
        }
    }
}

