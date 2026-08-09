package com.vezoo.player

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.AudioTrack
import android.media.projection.MediaProjection
import android.util.Base64
import android.util.Log
import okhttp3.*
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

class GeminiLiveService(private val apiKey: String) {

    private val TAG = "GeminiLive"
    private var ws: WebSocket? = null
    private val running = AtomicBoolean(false)
    private val connected = AtomicBoolean(false)
    private val eventQueue = ConcurrentLinkedQueue<Map<String, Any>>()
    private var audioThread: Thread? = null
    private var projection: MediaProjection? = null
    private var audioTrack: AudioTrack? = null
    private var mode = "subtitle" // "subtitle" or "dub"

    // Gemini output audio sample rate
    private val OUTPUT_SAMPLE_RATE = 24000
    private val INPUT_SAMPLE_RATE = 16000
    private val CHUNK_MS = 200

    private val MODEL = "gemini-3.5-live-translate-preview"
    private val WS_URL = "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1alpha.GenerativeService.BidiGenerateContent"

    private val client = OkHttpClient.Builder()
        .readTimeout(0, TimeUnit.MILLISECONDS)
        .writeTimeout(30, TimeUnit.SECONDS)
        .pingInterval(15, TimeUnit.SECONDS)
        .build()

    fun start(targetLang: String, proj: MediaProjection?, dubMode: Boolean = false) {
        if (running.getAndSet(true)) return
        projection = proj
        mode = if (dubMode) "dub" else "subtitle"
        if (dubMode) initAudioTrack()
        connectWs(targetLang)
    }

    private fun initAudioTrack() {
        val bufSize = AudioTrack.getMinBufferSize(
            OUTPUT_SAMPLE_RATE,
            AudioFormat.CHANNEL_OUT_MONO,
            AudioFormat.ENCODING_PCM_16BIT
        ).coerceAtLeast(OUTPUT_SAMPLE_RATE * 2)

        audioTrack = AudioTrack.Builder()
            .setAudioAttributes(AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                .build())
            .setAudioFormat(AudioFormat.Builder()
                .setSampleRate(OUTPUT_SAMPLE_RATE)
                .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                .build())
            .setBufferSizeInBytes(bufSize)
            .setTransferMode(AudioTrack.MODE_STREAM)
            .build()
        audioTrack?.play()
    }

    private fun connectWs(targetLang: String) {
        val url = "$WS_URL?key=$apiKey"
        val req = Request.Builder().url(url).build()

        // تنظیم response mode
        val responseModalities = if (mode == "dub")
            JSONArray().put("AUDIO") else JSONArray().put("TEXT")

        val prompt = "You are a real-time live interpreter. " +
            "Translate everything you hear accurately into $targetLang. " +
            if (mode == "dub") "Speak the translation naturally." else "Output ONLY the translated text."

        ws = client.newWebSocket(req, object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                Log.d(TAG, "WS connected — mode=$mode")

                val setupBuilder = JSONObject()
                    .put("model", "models/$MODEL")
                    .put("system_instruction", JSONObject()
                        .put("parts", JSONArray().put(JSONObject().put("text", prompt))))
                    .put("generation_config", JSONObject()
                        .put("response_modalities", responseModalities)
                        .apply {
                            if (mode == "dub") {
                                put("speech_config", JSONObject()
                                    .put("voice_config", JSONObject()
                                        .put("prebuilt_voice_config", JSONObject()
                                            .put("voice_name", "Charon"))))
                            }
                        })

                webSocket.send(JSONObject().put("setup", setupBuilder).toString())
                connected.set(true)
                send("status", "connected")
                send("status", "mode:$mode")
                startAudioCapture()
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                try {
                    val json = JSONObject(text)
                    val sc = json.optJSONObject("serverContent") ?: return
                    val mt = sc.optJSONObject("modelTurn") ?: return
                    val parts = mt.optJSONArray("parts") ?: return

                    for (i in 0 until parts.length()) {
                        val part = parts.getJSONObject(i)

                        if (mode == "subtitle") {
                            // متن ترجمه
                            val t = part.optString("text", "")
                            if (t.isNotEmpty()) {
                                send("transcript", mapOf("text" to t, "final" to true))
                            }
                        } else {
                            // صدای دوبله — PCM base64
                            val inline = part.optJSONObject("inlineData")
                            if (inline != null) {
                                val b64 = inline.optString("data", "")
                                if (b64.isNotEmpty()) {
                                    val pcm = Base64.decode(b64, Base64.DEFAULT)
                                    playAudio(pcm)
                                    send("status", "audio_chunk:${pcm.size}")
                                }
                            }
                            // متن هم بخونیم اگه بود (برای لاگ)
                            val t = part.optString("text", "")
                            if (t.isNotEmpty()) send("transcript", mapOf("text" to t, "final" to false))
                        }
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Parse error: ${e.message}")
                }
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                Log.e(TAG, "WS error: ${t.message}")
                connected.set(false)
                send("error", t.message ?: "Connection failed")
                if (running.get()) {
                    Thread.sleep(2000)
                    connectWs(targetLang)
                }
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                connected.set(false)
                send("status", "disconnected")
            }
        })
    }

    private fun playAudio(pcm: ByteArray) {
        audioTrack?.write(pcm, 0, pcm.size)
    }

    private fun startAudioCapture() {
        val chunkSamples = INPUT_SAMPLE_RATE * CHUNK_MS / 1000
        val bufSize = AudioRecord.getMinBufferSize(
            INPUT_SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT
        ).coerceAtLeast(chunkSamples * 2)

        audioThread = Thread {
            val recorder = if (projection != null && android.os.Build.VERSION.SDK_INT >= 29) {
                val config = android.media.AudioPlaybackCaptureConfiguration.Builder(projection!!)
                    .addMatchingUsage(android.media.AudioAttributes.USAGE_MEDIA)
                    .addMatchingUsage(android.media.AudioAttributes.USAGE_GAME)
                    .addMatchingUsage(android.media.AudioAttributes.USAGE_UNKNOWN)
                    .build()
                AudioRecord.Builder()
                    .setAudioPlaybackCaptureConfig(config)
                    .setAudioFormat(AudioFormat.Builder()
                        .setSampleRate(INPUT_SAMPLE_RATE)
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .setChannelMask(AudioFormat.CHANNEL_IN_MONO)
                        .build())
                    .setBufferSizeInBytes(bufSize)
                    .build()
            } else {
                AudioRecord(android.media.MediaRecorder.AudioSource.MIC,
                    INPUT_SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO,
                    AudioFormat.ENCODING_PCM_16BIT, bufSize)
            }

            recorder.startRecording()
            send("status", "recording_started")

            val pcm = ShortArray(chunkSamples)
            val bytes = ByteArray(chunkSamples * 2)

            while (running.get()) {
                val read = recorder.read(pcm, 0, chunkSamples)
                if (read > 0 && connected.get()) {
                    for (i in 0 until read) {
                        bytes[i * 2] = (pcm[i].toInt() and 0xFF).toByte()
                        bytes[i * 2 + 1] = ((pcm[i].toInt() shr 8) and 0xFF).toByte()
                    }
                    sendAudioChunk(bytes.copyOf(read * 2))
                }
            }
            try { recorder.stop(); recorder.release() } catch (_: Exception) {}
        }
        audioThread?.isDaemon = true
        audioThread?.start()
    }

    fun sendAudio(pcm: ByteArray) = sendAudioChunk(pcm)

    private fun sendAudioChunk(pcm: ByteArray) {
        val b64 = Base64.encodeToString(pcm, Base64.NO_WRAP)
        val msg = JSONObject()
            .put("realtimeInput", JSONObject()
                .put("mediaChunks", JSONArray().put(JSONObject()
                    .put("mimeType", "audio/pcm;rate=16000")
                    .put("data", b64))))
        ws?.send(msg.toString())
    }

    fun stop() {
        running.set(false)
        connected.set(false)
        audioThread?.interrupt()
        audioThread = null
        try { audioTrack?.stop(); audioTrack?.release() } catch (_: Exception) {}
        audioTrack = null
        ws?.close(1000, "stopped")
        ws = null
        try { projection?.stop() } catch (_: Exception) {}
        projection = null
        send("status", "stopped")
    }

    fun getNextEvent(): Map<String, Any>? = eventQueue.poll()

    private fun send(type: String, data: Any) {
        eventQueue.offer(mapOf("type" to type, "data" to data))
        if (eventQueue.size > 200) eventQueue.poll()
    }
}
