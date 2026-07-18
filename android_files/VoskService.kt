package com.vezoo.player

import android.content.Context
import android.media.*
import android.os.Build
import io.flutter.plugin.common.EventChannel
import org.json.JSONObject
import org.vosk.Model
import org.vosk.Recognizer
import java.io.File

class VoskService(private val context: Context) {

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
        // بارگذاری مدل
        log("VOSK: loading model lang=$langCode")
        val modelPath = findModel(langCode)
        if (modelPath == null) {
            log("VOSK: model not found for $langCode")
            sendEvent("error", "Model not found: $langCode — please download from Settings")
            running = false
            return
        }
        log("VOSK: model found at $modelPath")
        try {
            model = Model(modelPath)
            recognizer = Recognizer(model, SAMPLE_RATE.toFloat())
            recognizer?.setMaxAlternatives(0)
            recognizer?.setWords(false)
            log("VOSK: model loaded OK")
        } catch (e: Exception) {
            log("VOSK: model load error: ${e.message}")
            sendEvent("error", "Model load failed: ${e.message}")
            running = false
            return
        }

        // شروع capture صدا
        val bufSize = maxOf(
            AudioRecord.getMinBufferSize(SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT) * 2,
            3200
        )

        try {
            if (projection != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                // MediaProjection — صدای داخلی خالص
                val config = AudioPlaybackCaptureConfiguration.Builder(projection)
                    .addMatchingUsage(AudioAttributes.USAGE_MEDIA)
                    .addMatchingUsage(AudioAttributes.USAGE_GAME)
                    .addMatchingUsage(AudioAttributes.USAGE_UNKNOWN)
                    .build()
                recorder = AudioRecord.Builder()
                    .setAudioFormat(AudioFormat.Builder()
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .setSampleRate(SAMPLE_RATE)
                        .setChannelMask(AudioFormat.CHANNEL_IN_MONO)
                        .build())
                    .setBufferSizeInBytes(bufSize)
                    .setAudioPlaybackCaptureConfig(config)
                    .build()
                log("VOSK: using MediaProjection (internal audio)")
                sendEvent("status", "capturing_internal_audio")
            } else {
                // fallback: میکروفون
                recorder = AudioRecord(
                    MediaRecorder.AudioSource.MIC,
                    SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO,
                    AudioFormat.ENCODING_PCM_16BIT, bufSize
                )
                log("VOSK: using MIC fallback")
                sendEvent("status", "capturing_mic")
            }

            if (recorder?.state != AudioRecord.STATE_INITIALIZED) {
                log("VOSK: recorder not initialized")
                sendEvent("error", "Audio capture failed")
                running = false
                return
            }

            recorder?.startRecording()
            sendEvent("status", "started")
            log("VOSK: recording started")

            // حلقه اصلی — هر 100ms
            val chunk = ByteArray(bufSize / 4)
            while (running) {
                val read = recorder?.read(chunk, 0, chunk.size) ?: -1
                if (read > 0) {
                    val isFinal = recognizer?.acceptWaveForm(chunk, read) ?: false
                    if (isFinal) {
                        val result = JSONObject(recognizer?.result ?: "{}").optString("text", "")
                        if (result.isNotEmpty()) {
                            log("FINAL: $result")
                            sendEvent("transcript", mapOf("text" to result, "final" to true))
                        }
                    } else {
                        val partial = JSONObject(recognizer?.partialResult ?: "{}").optString("partial", "")
                        if (partial.isNotEmpty()) {
                            sendEvent("transcript", mapOf("text" to partial, "final" to false))
                        }
                    }
                } else if (read < 0) {
                    log("VOSK: read error=$read")
                    break
                }
            }

            // آخرین نتیجه
            val finalResult = JSONObject(recognizer?.finalResult ?: "{}").optString("text", "")
            if (finalResult.isNotEmpty()) {
                sendEvent("transcript", mapOf("text" to finalResult, "final" to true))
            }

        } catch (e: Exception) {
            log("VOSK: error: ${e.message}")
            sendEvent("error", e.message ?: "Unknown error")
        } finally {
            stop()
        }
    }

    private fun findModel(langCode: String): String? {
        val dir = File(MODELS_DIR)
        if (!dir.exists()) return null
        // پیدا کردن پوشه مدل برای این زبان
        val modelDir = dir.listFiles()?.firstOrNull { f ->
            f.isDirectory && (f.name.contains("-$langCode-") || f.name.contains("-$langCode.") || f.name.endsWith("-$langCode"))
        }
        return modelDir?.absolutePath
    }

    fun stop() {
        running = false
        try { recorder?.stop(); recorder?.release() } catch (_: Exception) {}
        try { recognizer?.close() } catch (_: Exception) {}
        try { model?.close() } catch (_: Exception) {}
        recorder = null; recognizer = null; model = null
        sendEvent("status", "stopped")
        log("VOSK: stopped")
    }

    private fun log(msg: String) {
        android.util.Log.d("VoskService", msg)
        sendEvent("status", msg)
    }

    private fun sendEvent(type: String, data: Any) {
        android.os.Handler(android.os.Looper.getMainLooper()).post {
            try { sink?.success(mapOf("type" to type, "data" to data)) } catch (_: Exception) {}
        }
    }
}

