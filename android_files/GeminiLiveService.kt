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
    private var dubMode = false

    // مثل e2dub: 100ms chunks
    private val INPUT_SAMPLE_RATE = 16000
    private val OUTPUT_SAMPLE_RATE = 24000
    private val INPUT_CHUNK_BYTES = 3200  // 100ms @ 16kHz mono s16le
    private val OUTPUT_FRAME_BYTES = 4800 // 100ms @ 24kHz mono s16le

    // v1beta — مثل e2dub
    private val MODEL = "gemini-3.5-live-translate-preview"
    private val HOST = "generativelanguage.googleapis.com"
    private val WS_URL = "wss://$HOST/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent"

    private val client = OkHttpClient.Builder()
        .readTimeout(0, TimeUnit.MILLISECONDS)
        .writeTimeout(30, TimeUnit.SECONDS)
        .pingInterval(20, TimeUnit.SECONDS)
        .build()

    fun start(targetLang: String, proj: MediaProjection?, isDubMode: Boolean = false) {
        if (running.getAndSet(true)) return
        projection = proj
        dubMode = isDubMode
        if (dubMode) initAudioTrack()
        connectWs(targetLang)
    }

    private fun initAudioTrack() {
        val bufSize = AudioTrack.getMinBufferSize(OUTPUT_SAMPLE_RATE,
            AudioFormat.CHANNEL_OUT_MONO, AudioFormat.ENCODING_PCM_16BIT)
            .coerceAtLeast(OUTPUT_SAMPLE_RATE * 2)
        audioTrack = AudioTrack.Builder()
            .setAudioAttributes(AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
            .setAudioFormat(AudioFormat.Builder()
                .setSampleRate(OUTPUT_SAMPLE_RATE)
                .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                .setChannelMask(AudioFormat.CHANNEL_OUT_MONO).build())
            .setBufferSizeInBytes(bufSize)
            .setTransferMode(AudioTrack.MODE_STREAM).build()
        audioTrack?.play()
    }

    private fun connectWs(targetLang: String) {
        val url = "$WS_URL?key=$apiKey"
        val req = Request.Builder()
            .url(url)
            .addHeader("User-Agent", "Vezoo/1.0")
            .build()

        ws = client.newWebSocket(req, object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                Log.d(TAG, "WS connected — mode=${if(dubMode)"DUB" else "subtitle"}")
                // Setup مثل e2dub — ساختار درست
                val responseModalities = if (dubMode)
                    JSONArray().put("AUDIO") else JSONArray().put("TEXT")

                val setup = JSONObject()
                    .put("model", "models/$MODEL")
                    .put("generationConfig", JSONObject()
                        .put("responseModalities", responseModalities)
                        .put("translationConfig", JSONObject()
                            .put("targetLanguageCode", targetLang)
                            .put("echoTargetLanguage", false)))
                    .put("realtimeInputConfig", JSONObject()
                        .put("automaticActivityDetection", JSONObject()
                            .put("disabled", false)
                            .put("startOfSpeechSensitivity", "START_SENSITIVITY_HIGH")
                            .put("endOfSpeechSensitivity", "END_SENSITIVITY_HIGH")
                            .put("prefixPaddingMs", 20)
                            .put("silenceDurationMs", 350)))
                    .put("sessionResumption", JSONObject())
                    .put("contextWindowCompression", JSONObject()
                        .put("slidingWindow", JSONObject()))

                webSocket.send(JSONObject().put("setup", setup).toString())
                send("status", "connecting")
                Log.d(TAG, "Setup sent, waiting for setupComplete...")
                Thread {
                    Thread.sleep(15000)
                    if (!connected.get() && running.get()) {
                        send("error", "Timeout: No response from Gemini after 15s. Check API key/network.")
                    }
                }.start()
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                Log.d(TAG, "MSG: ${text.take(200)}")
                send("status", "raw:${text.take(120)}")
                try {
                    val json = JSONObject(text)

                    if (!json.isNull("setupComplete")) {
                        connected.set(true)
                        send("status", "connected")
                        send("status", "recording_started")
                        startAudioCapture()
                        return
                    }

                    val err = json.optJSONObject("error")
                    if (err != null) {
                        val errMsg = "[${err.optInt("code")}] ${err.optString("status")}: ${err.optString("message")}"
                        Log.e(TAG, "API error: $errMsg")
                        send("error", errMsg)
                        return
                    }

                    // serverContent
                    val sc = json.optJSONObject("serverContent") ?: return
                    val mt = sc.optJSONObject("modelTurn") ?: return
                    val parts = mt.optJSONArray("parts") ?: return

                    for (i in 0 until parts.length()) {
                        val part = parts.getJSONObject(i)
                        if (dubMode) {
                            // audio PCM از Gemini
                            val inline = part.optJSONObject("inlineData")
                            if (inline != null) {
                                val data = inline.optString("data", "")
                                if (data.isNotEmpty()) {
                                    val pcm = Base64.decode(data, Base64.DEFAULT)
                                    audioTrack?.write(pcm, 0, pcm.size)
                                    send("status", "audio_chunk:${pcm.size}")
                                }
                            }
                        } else {
                            // text زیرنویس
                            val t = part.optString("text", "")
                            if (t.isNotEmpty()) {
                                send("transcript", mapOf("text" to t, "final" to true))
                            }
                        }
                    }

                    // inputTranscription (تشخیص زبان مبدأ)
                    val inputT = sc.optJSONObject("inputTranscription")
                    if (inputT != null) {
                        val lang = inputT.optString("languageCode", "auto")
                        send("status", "detected_lang:$lang")
                    }

                } catch (e: Exception) {
                    Log.e(TAG, "Parse error: ${e.message}")
                }
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                val code = response?.code ?: 0
                val msg = t.message ?: "unknown"
                Log.e(TAG, "WS error [$code]: $msg")
                connected.set(false)
                send("error", "WS[$code]: $msg")
                if (running.get()) {
                    Thread.sleep(3000)
                    connectWs(targetLang)
                }
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                connected.set(false)
                send("status", "disconnected:$code")
            }
        })
    }

    private fun startAudioCapture() {
        audioThread = Thread {
            val bufSize = AudioRecord.getMinBufferSize(
                INPUT_SAMPLE_RATE,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT
            ).coerceAtLeast(INPUT_CHUNK_BYTES * 4)

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
                        .setChannelMask(AudioFormat.CHANNEL_IN_MONO).build())
                    .setBufferSizeInBytes(bufSize).build()
            } else {
                AudioRecord(android.media.MediaRecorder.AudioSource.MIC,
                    INPUT_SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO,
                    AudioFormat.ENCODING_PCM_16BIT, bufSize)
            }

            recorder.startRecording()
            Log.d(TAG, "Audio capture started — projection=${projection != null}")

            val chunkSamples = INPUT_CHUNK_BYTES / 2 // short = 2 bytes
            val pcm = ShortArray(chunkSamples)
            val bytes = ByteArray(INPUT_CHUNK_BYTES)

            while (running.get()) {
                val read = recorder.read(pcm, 0, chunkSamples)
                if (read > 0 && ws != null) {
                    for (i in 0 until read) {
                        bytes[i * 2] = (pcm[i].toInt() and 0xFF).toByte()
                        bytes[i * 2 + 1] = ((pcm[i].toInt() shr 8) and 0xFF).toByte()
                    }
                    val chunk = bytes.copyOf(read * 2)
                    // مثل e2dub: ساختار audio صحیح
                    val b64 = Base64.encodeToString(chunk, Base64.NO_WRAP)
                    val msg = JSONObject()
                        .put("realtimeInput", JSONObject()
                            .put("audio", JSONObject()
                                .put("mimeType", "audio/pcm;rate=16000")
                                .put("data", b64)))
                    try { ws?.send(msg.toString()) } catch (_: Exception) {}
                }
            }

            try { recorder.stop(); recorder.release() } catch (_: Exception) {}
            Log.d(TAG, "Audio capture stopped")
        }
        audioThread?.isDaemon = true
        audioThread?.start()
    }

    fun sendAudio(pcm: ByteArray) {
        if (!running.get() || ws == null) return
        val b64 = Base64.encodeToString(pcm, Base64.NO_WRAP)
        val msg = JSONObject().put("realtimeInput", JSONObject()
            .put("audio", JSONObject().put("mimeType", "audio/pcm;rate=16000").put("data", b64)))
        try { ws?.send(msg.toString()) } catch (_: Exception) {}
    }

    fun stop() {
        running.set(false)
        connected.set(false)
        audioThread?.interrupt()
        audioThread = null
        try { audioTrack?.stop(); audioTrack?.release() } catch (_: Exception) {}
        audioTrack = null
        try { ws?.close(1000, "stopped"); ws = null } catch (_: Exception) {}
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
