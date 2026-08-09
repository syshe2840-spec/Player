package com.vezoo.player

import android.media.AudioFormat
import android.media.AudioRecord
import android.media.projection.MediaProjection
import android.util.Base64
import android.util.Log
import okhttp3.*
import okio.ByteString
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

    private val MODEL = "gemini-3.5-live-translate-preview"
    private val WS_URL = "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1alpha.GenerativeService.BidiGenerateContent"

    private val SAMPLE_RATE = 16000
    private val CHUNK_MS = 200 // ارسال هر 200ms یه بار

    private val client = OkHttpClient.Builder()
        .readTimeout(0, TimeUnit.MILLISECONDS) // WebSocket نیاز به timeout=0 داره
        .writeTimeout(30, TimeUnit.SECONDS)
        .pingInterval(15, TimeUnit.SECONDS)
        .build()

    fun start(targetLang: String, proj: MediaProjection?) {
        if (running.getAndSet(true)) return
        projection = proj
        connectWs(targetLang)
    }

    private fun connectWs(targetLang: String) {
        val url = "$WS_URL?key=$apiKey"
        val req = Request.Builder().url(url).build()

        ws = client.newWebSocket(req, object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                Log.d(TAG, "WS connected")
                // setup message
                val prompt = "You are a live real-time translator. " +
                    "Translate everything you hear accurately to $targetLang language. " +
                    "Output ONLY the translation text. No explanations, no notes."
                val setup = JSONObject()
                    .put("setup", JSONObject()
                        .put("model", "models/$MODEL")
                        .put("system_instruction", JSONObject()
                            .put("parts", JSONArray().put(JSONObject().put("text", prompt))))
                        .put("generation_config", JSONObject()
                            .put("response_modalities", JSONArray().put("TEXT"))
                            .put("input_audio_transcription", JSONObject())))
                webSocket.send(setup.toString())
                connected.set(true)
                send("status", "connected")
                // شروع capture صدا
                startAudioCapture()
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                try {
                    val json = JSONObject(text)
                    val sc = json.optJSONObject("serverContent") ?: return
                    val mt = sc.optJSONObject("modelTurn") ?: return
                    val parts = mt.optJSONArray("parts") ?: return
                    val sb = StringBuilder()
                    for (i in 0 until parts.length()) {
                        val t = parts.getJSONObject(i).optString("text", "")
                        if (t.isNotEmpty()) sb.append(t)
                    }
                    val result = sb.toString().trim()
                    if (result.isNotEmpty()) {
                        send("transcript", mapOf("text" to result, "final" to true))
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Parse error: ${e.message}")
                }
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                Log.e(TAG, "WS error: ${t.message}")
                connected.set(false)
                send("error", t.message ?: "Connection failed")
                // reconnect
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

    private fun startAudioCapture() {
        val bufSize = AudioRecord.getMinBufferSize(
            SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT
        ).coerceAtLeast(SAMPLE_RATE * 2 * CHUNK_MS / 1000)

        val chunkSamples = SAMPLE_RATE * CHUNK_MS / 1000
        val chunkBytes = chunkSamples * 2 // 16-bit = 2 bytes/sample

        audioThread = Thread {
            // اگه MediaProjection داریم از AudioPlaybackCapture استفاده کن
            val recorder = if (projection != null && android.os.Build.VERSION.SDK_INT >= 29) {
                val config = android.media.AudioPlaybackCaptureConfiguration.Builder(projection!!)
                    .addMatchingUsage(android.media.AudioAttributes.USAGE_MEDIA)
                    .addMatchingUsage(android.media.AudioAttributes.USAGE_GAME)
                    .build()
                AudioRecord.Builder()
                    .setAudioPlaybackCaptureConfig(config)
                    .setAudioFormat(AudioFormat.Builder()
                        .setSampleRate(SAMPLE_RATE)
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .setChannelMask(AudioFormat.CHANNEL_IN_MONO)
                        .build())
                    .setBufferSizeInBytes(bufSize)
                    .build()
            } else {
                // fallback: میکروفون
                AudioRecord(
                    android.media.MediaRecorder.AudioSource.MIC,
                    SAMPLE_RATE,
                    AudioFormat.CHANNEL_IN_MONO,
                    AudioFormat.ENCODING_PCM_16BIT,
                    bufSize
                )
            }

            recorder.startRecording()
            send("status", "recording_started")

            val pcm = ShortArray(chunkSamples)
            val bytes = ByteArray(chunkBytes)

            while (running.get()) {
                val read = recorder.read(pcm, 0, chunkSamples)
                if (read > 0 && connected.get()) {
                    // تبدیل Short به ByteArray little-endian
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
