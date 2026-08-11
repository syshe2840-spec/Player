package com.vezoo.player

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.AudioTrack
import android.media.projection.MediaProjection
import android.util.Base64
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.InputStream
import java.io.OutputStream
import java.security.SecureRandom
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.atomic.AtomicBoolean
import javax.net.ssl.SSLSocketFactory

data class GeminiConfig(
    val targetLang: String = "fa",
    val silenceDurationMs: Int = 350,
    val prefixPaddingMs: Int = 20,
    val startSensitivity: String = "START_SENSITIVITY_HIGH",
    val endSensitivity: String = "END_SENSITIVITY_HIGH",
    val chunkMs: Int = 100,
    val dubMode: Boolean = false
)

class GeminiLiveService(private val apiKey: String) {

    private val TAG = "GeminiLive"
    private val HOST = "generativelanguage.googleapis.com"
    private val PORT = 443
    private val MODEL = "gemini-3.5-live-translate-preview"
    private val PATH = "/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent"

    private val OUTPUT_SAMPLE_RATE = 24000
    private val INPUT_SAMPLE_RATE = 16000

    private val running = AtomicBoolean(false)
    private val connected = AtomicBoolean(false)
    private val eventQueue = ConcurrentLinkedQueue<Map<String, Any>>()

    private var projection: MediaProjection? = null
    private var audioTrack: AudioTrack? = null
    private var config = GeminiConfig()

    private var socket: javax.net.ssl.SSLSocket? = null
    private var outputStream: OutputStream? = null
    private var inputStream: InputStream? = null
    private var audioThread: Thread? = null

    fun start(cfg: GeminiConfig, proj: MediaProjection?) {
        if (running.getAndSet(true)) return
        projection = proj
        config = cfg
        if (cfg.dubMode) initAudioTrack()
        Thread { connectAndStream() }.start()
    }

    private fun connectAndStream() {
        try {
            send("status", "connecting")
            val factory = SSLSocketFactory.getDefault() as SSLSocketFactory
            val raw = factory.createSocket(HOST, PORT) as javax.net.ssl.SSLSocket
            raw.soTimeout = 30_000
            raw.startHandshake()
            socket = raw
            outputStream = raw.outputStream
            inputStream = raw.inputStream

            // WebSocket handshake — دقیقاً مثل e2dub
            val nonce = Base64.encodeToString(SecureRandom().generateSeed(16), Base64.NO_WRAP)
            val req = "GET $PATH?key=$apiKey HTTP/1.1\r\n" +
                "Host: $HOST\r\n" +
                "Upgrade: websocket\r\n" +
                "Connection: Upgrade\r\n" +
                "Sec-WebSocket-Key: $nonce\r\n" +
                "Sec-WebSocket-Version: 13\r\n" +
                "User-Agent: e2dub/0.1.9\r\n\r\n"
            outputStream!!.write(req.toByteArray(Charsets.US_ASCII))
            outputStream!!.flush()

            val respLine = readLine(inputStream!!)
            Log.d(TAG, "HTTP: $respLine")
            if (!respLine.contains("101")) {
                val sb = StringBuilder(respLine + "\n")
                var line = readLine(inputStream!!)
                var bodyLen = 0
                while (line.isNotEmpty()) {
                    if (line.lowercase().startsWith("content-length:"))
                        bodyLen = line.substringAfter(":").trim().toIntOrNull() ?: 0
                    sb.append(line).append("\n"); line = readLine(inputStream!!)
                }
                if (bodyLen > 0) {
                    val body = ByteArray(bodyLen.coerceAtMost(400))
                    inputStream!!.read(body)
                    sb.append("\nBODY: ").append(String(body, Charsets.UTF_8).take(300))
                }
                send("error", "WS failed: ${sb.toString().take(400)}")
                return
            }
            var line = readLine(inputStream!!); while (line.isNotEmpty()) { line = readLine(inputStream!!) }

            // Setup — دقیقاً مثل e2dub با تنظیمات کاربر
            val modalities = if (config.dubMode) JSONArray().put("AUDIO") else JSONArray().put("TEXT")
            val setup = JSONObject()
                .put("model", "models/$MODEL")
                .put("generationConfig", JSONObject()
                    .put("responseModalities", modalities)
                    .put("translationConfig", JSONObject()
                        .put("targetLanguageCode", config.targetLang)
                        .put("echoTargetLanguage", false)))
                .put("realtimeInputConfig", JSONObject()
                    .put("automaticActivityDetection", JSONObject()
                        .put("disabled", false)
                        .put("startOfSpeechSensitivity", config.startSensitivity)
                        .put("endOfSpeechSensitivity", config.endSensitivity)
                        .put("prefixPaddingMs", config.prefixPaddingMs)
                        .put("silenceDurationMs", config.silenceDurationMs)))
                .put("sessionResumption", JSONObject())
                .put("contextWindowCompression", JSONObject().put("slidingWindow", JSONObject()))

            wsSend(JSONObject().put("setup", setup).toString())
            send("status", "setup_sent")

            raw.soTimeout = 15_000
            val setupMsg = wsReceive() ?: run { send("error", "Timeout waiting for setupComplete"); return }
            Log.d(TAG, "setupResp: ${setupMsg.take(200)}")
            send("status", "raw:${setupMsg.take(100)}")

            val setupJson = JSONObject(setupMsg)
            if (setupJson.isNull("setupComplete")) {
                val err = setupJson.optJSONObject("error")
                send("error", if (err != null) "[${err.optInt("code")}] ${err.optString("message")}" else "Bad setup: ${setupMsg.take(100)}")
                return
            }

            connected.set(true)
            raw.soTimeout = 5000
            send("status", "connected")
            send("status", "recording_started")
            startAudioCapture()

            // read loop
            while (running.get()) {
                try {
                    val msg = wsReceive() ?: break
                    handleMessage(msg)
                } catch (_: java.net.SocketTimeoutException) { continue }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error: ${e.message}")
            if (running.get()) send("error", "${e.message?.take(100) ?: "unknown"}")
        } finally { stopInternal() }
    }

    private fun handleMessage(text: String) {
        try {
            val json = JSONObject(text)
            val err = json.optJSONObject("error")
            if (err != null) { send("error", "[${err.optInt("code")}] ${err.optString("message")}"); return }
            val sc = json.optJSONObject("serverContent") ?: return
            val mt = sc.optJSONObject("modelTurn") ?: return
            val parts = mt.optJSONArray("parts") ?: return
            for (i in 0 until parts.length()) {
                val part = parts.getJSONObject(i)
                if (config.dubMode) {
                    val inline = part.optJSONObject("inlineData")
                    if (inline != null) {
                        val pcm = Base64.decode(inline.optString("data",""), Base64.DEFAULT)
                        audioTrack?.write(pcm, 0, pcm.size)
                        send("status", "audio:${pcm.size}")
                    }
                } else {
                    val t = part.optString("text","")
                    if (t.isNotEmpty()) send("transcript", mapOf("text" to t, "final" to true))
                }
            }
            // نشون دادن متن ترجمه شده (حتی در حالت دوبله برای subtitle)
            val inputT = sc.optJSONObject("outputTranscription")
            if (inputT != null) {
                val t = inputT.optString("text","")
                if (t.isNotEmpty()) send("transcript", mapOf("text" to t, "final" to true))
            }
        } catch (e: Exception) { Log.e(TAG, "Parse: ${e.message}") }
    }

    private fun startAudioCapture() {
        val chunkBytes = INPUT_SAMPLE_RATE * config.chunkMs / 1000 * 2
        val chunkSamples = chunkBytes / 2
        val bufSize = AudioRecord.getMinBufferSize(INPUT_SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
            .coerceAtLeast(chunkBytes * 4)

        audioThread = Thread {
            val recorder = if (projection != null && android.os.Build.VERSION.SDK_INT >= 29) {
                val cfg2 = android.media.AudioPlaybackCaptureConfiguration.Builder(projection!!)
                    .addMatchingUsage(android.media.AudioAttributes.USAGE_MEDIA)
                    .addMatchingUsage(android.media.AudioAttributes.USAGE_UNKNOWN).build()
                AudioRecord.Builder().setAudioPlaybackCaptureConfig(cfg2)
                    .setAudioFormat(AudioFormat.Builder().setSampleRate(INPUT_SAMPLE_RATE)
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .setChannelMask(AudioFormat.CHANNEL_IN_MONO).build())
                    .setBufferSizeInBytes(bufSize).build()
            } else {
                AudioRecord(android.media.MediaRecorder.AudioSource.MIC, INPUT_SAMPLE_RATE,
                    AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, bufSize)
            }
            recorder.startRecording()
            val pcm = ShortArray(chunkSamples)
            val bytes = ByteArray(chunkBytes)
            var lastSentHash = 0  // fix تکرار: hash آخرین chunk

            while (running.get()) {
                val read = recorder.read(pcm, 0, chunkSamples)
                if (read > 0 && connected.get()) {
                    for (i in 0 until read) {
                        bytes[i*2] = (pcm[i].toInt() and 0xFF).toByte()
                        bytes[i*2+1] = ((pcm[i].toInt() shr 8) and 0xFF).toByte()
                    }
                    val chunk = bytes.copyOf(read*2)
                    val hash = chunk.take(16).hashCode()
                    if (hash == lastSentHash) continue  // جلوگیری از تکرار
                    lastSentHash = hash
                    val b64 = Base64.encodeToString(chunk, Base64.NO_WRAP)
                    try {
                        wsSend(JSONObject().put("realtimeInput", JSONObject()
                            .put("audio", JSONObject()
                                .put("mimeType", "audio/pcm;rate=$INPUT_SAMPLE_RATE")
                                .put("data", b64))).toString())
                    } catch (_: Exception) {}
                }
            }
            try { recorder.stop(); recorder.release() } catch (_: Exception) {}
        }
        audioThread?.isDaemon = true
        audioThread?.start()
    }

    private fun initAudioTrack() {
        val buf = AudioTrack.getMinBufferSize(OUTPUT_SAMPLE_RATE,
            AudioFormat.CHANNEL_OUT_MONO, AudioFormat.ENCODING_PCM_16BIT)
            .coerceAtLeast(OUTPUT_SAMPLE_RATE * 2)
        audioTrack = AudioTrack.Builder()
            .setAudioAttributes(AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
            .setAudioFormat(AudioFormat.Builder().setSampleRate(OUTPUT_SAMPLE_RATE)
                .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                .setChannelMask(AudioFormat.CHANNEL_OUT_MONO).build())
            .setBufferSizeInBytes(buf).setTransferMode(AudioTrack.MODE_STREAM).build()
        audioTrack?.play()
    }

    private fun wsSend(payload: String) {
        val data = payload.toByteArray(Charsets.UTF_8)
        val len = data.size
        val mask = SecureRandom().generateSeed(4)
        val header = when {
            len <= 125  -> byteArrayOf(0x81.toByte(), (0x80 or len).toByte())
            len <= 65535 -> byteArrayOf(0x81.toByte(), (0x80 or 126).toByte(), (len shr 8).toByte(), len.toByte())
            else -> {
                val lb = ByteArray(8)
                for (i in 7 downTo 0) lb[i] = (len shr (8*(7-i))).toByte()
                byteArrayOf(0x81.toByte(), (0x80 or 127).toByte()) + lb
            }
        }
        val masked = ByteArray(len) { i -> (data[i].toInt() xor mask[i%4].toInt()).toByte() }
        synchronized(this) {
            outputStream?.write(header + mask + masked)
            outputStream?.flush()
        }
    }

    private fun wsReceive(): String? {
        val inp = inputStream ?: return null
        val b0 = inp.read(); if (b0 < 0) return null
        val b1 = inp.read(); if (b1 < 0) return null
        if ((b0 and 0x0F) == 8) return null
        var len = (b1 and 0x7F).toLong()
        if (len == 126L) len = ((inp.read() shl 8) or inp.read()).toLong()
        else if (len == 127L) { var l=0L; repeat(8){l=(l shl 8) or inp.read().toLong()}; len=l }
        val buf = ByteArray(len.toInt())
        var off = 0
        while (off < buf.size) { val r=inp.read(buf,off,buf.size-off); if(r<0) return null; off+=r }
        return String(buf, Charsets.UTF_8)
    }

    private fun readLine(inp: InputStream): String {
        val sb = StringBuilder()
        var b = inp.read()
        while (b >= 0 && b.toChar() != '\n') { if (b.toChar() != '\r') sb.append(b.toChar()); b = inp.read() }
        return sb.toString()
    }

    fun sendAudio(pcm: ByteArray) {
        if (!connected.get()) return
        val b64 = Base64.encodeToString(pcm, Base64.NO_WRAP)
        try {
            wsSend(JSONObject().put("realtimeInput", JSONObject()
                .put("audio", JSONObject().put("mimeType","audio/pcm;rate=$INPUT_SAMPLE_RATE").put("data",b64))).toString())
        } catch (_: Exception) {}
    }

    fun stop() {
        running.set(false); connected.set(false)
        audioThread?.interrupt(); audioThread = null
        stopInternal()
        send("status", "stopped")
    }

    private fun stopInternal() {
        try { audioTrack?.stop(); audioTrack?.release() } catch (_:Exception) {}
        audioTrack = null
        try { socket?.close(); socket = null } catch (_:Exception) {}
        try { projection?.stop() } catch (_:Exception) {}
        projection = null
    }

    fun getNextEvent(): Map<String,Any>? = eventQueue.poll()

    private fun send(type: String, data: Any) {
        eventQueue.offer(mapOf("type" to type, "data" to data))
        if (eventQueue.size > 200) eventQueue.poll()
    }
}
