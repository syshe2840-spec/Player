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
import java.io.BufferedReader
import java.io.InputStream
import java.io.InputStreamReader
import java.io.OutputStream
import java.net.Socket
import java.security.SecureRandom
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.atomic.AtomicBoolean
import javax.net.ssl.SSLSocketFactory

/**
 * Gemini Live Translation — دقیقاً مثل e2dub
 * Raw SSL socket + manual WebSocket (بدون OkHttp)
 */
class GeminiLiveService(private val apiKey: String) {

    private val TAG = "GeminiLive"
    private val HOST = "generativelanguage.googleapis.com"
    private val PORT = 443
    private val MODEL = "gemini-3.5-live-translate-preview"
    private val PATH = "/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent"

    private val INPUT_SAMPLE_RATE = 16000
    private val OUTPUT_SAMPLE_RATE = 24000
    private val INPUT_CHUNK_BYTES = 3200   // 100ms @ 16kHz s16le mono
    private val OUTPUT_FRAME_BYTES = 4800  // 100ms @ 24kHz s16le mono

    private val running = AtomicBoolean(false)
    private val connected = AtomicBoolean(false)
    private val eventQueue = ConcurrentLinkedQueue<Map<String, Any>>()

    private var projection: MediaProjection? = null
    private var audioTrack: AudioTrack? = null
    private var dubMode = false

    private var socket: javax.net.ssl.SSLSocket? = null
    private var outputStream: OutputStream? = null
    private var inputStream: InputStream? = null

    private var audioThread: Thread? = null
    private var readThread: Thread? = null

    fun start(targetLang: String, proj: MediaProjection?, isDubMode: Boolean = false) {
        if (running.getAndSet(true)) return
        projection = proj
        dubMode = isDubMode
        if (dubMode) initAudioTrack()
        Thread { connectAndStream(targetLang) }.start()
    }

    private fun connectAndStream(targetLang: String) {
        try {
            // ---- SSL connect ----
            send("status", "connecting")
            val factory = SSLSocketFactory.getDefault() as SSLSocketFactory
            val raw = factory.createSocket(HOST, PORT) as javax.net.ssl.SSLSocket
            raw.soTimeout = 30_000
            raw.startHandshake()
            socket = raw
            outputStream = raw.outputStream
            inputStream  = raw.inputStream
            Log.d(TAG, "SSL connected")

            // ---- WebSocket handshake ---- مثل e2dub
            val nonce = Base64.encodeToString(SecureRandom().generateSeed(16), Base64.NO_WRAP)
            val req = "GET $PATH?key=$apiKey HTTP/1.1\r\n" +
                "Host: $HOST\r\n" +
                "Upgrade: websocket\r\n" +
                "Connection: Upgrade\r\n" +
                "Sec-WebSocket-Key: $nonce\r\n" +
                "Sec-WebSocket-Version: 13\r\n" +
    "User-Agent: e2dub/0.1.9\r\n" +
"\r\n"
            outputStream!!.write(req.toByteArray(Charsets.US_ASCII))
            outputStream!!.flush()

            // خواندن HTTP response
            val respLine = readLine(inputStream!!)
            Log.d(TAG, "HTTP: $respLine")
            if (!respLine.contains("101")) {
                val sb = StringBuilder(respLine + "\n")
                var line = readLine(inputStream!!)
                var bodyLen = 0
                while (line.isNotEmpty()) {
                    if (line.lowercase().startsWith("content-length:"))
                        bodyLen = line.substringAfter(":").trim().toIntOrNull() ?: 0
                    sb.append(line).append("\n")
                    line = readLine(inputStream!!)
                }
                // خواندن body
                if (bodyLen > 0) {
                    val body = ByteArray(bodyLen.coerceAtMost(500))
                    inputStream!!.read(body)
                    sb.append("\nBODY: ").append(String(body, Charsets.UTF_8).take(300))
                }
                send("error", "WS upgrade failed: ${sb.toString().take(400)}")
                return
            }
            // مابقی headers
            var line = readLine(inputStream!!)
            while (line.isNotEmpty()) { line = readLine(inputStream!!) }
            Log.d(TAG, "WebSocket handshake OK")

            // ---- Setup message ----
            val modalities = if (dubMode) JSONArray().put("AUDIO") else JSONArray().put("TEXT")
            val setup = JSONObject()
                .put("model", "models/$MODEL")
                .put("generationConfig", JSONObject()
                    .put("responseModalities", modalities)
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

            wsSend(JSONObject().put("setup", setup).toString())
            Log.d(TAG, "Setup sent")
            send("status", "setup_sent")

            // ---- انتظار setupComplete ----
            raw.soTimeout = 15_000
            val setupMsg = wsReceive() ?: run { send("error", "Timeout waiting for setupComplete"); return }
            Log.d(TAG, "First msg: ${setupMsg.take(200)}")
            send("status", "raw:${setupMsg.take(100)}")

            val setupJson = JSONObject(setupMsg)
            if (setupJson.isNull("setupComplete")) {
                val err = setupJson.optJSONObject("error")
                val msg = if (err != null) "[${err.optInt("code")}] ${err.optString("status")}: ${err.optString("message")}"
                    else "Unexpected: ${setupMsg.take(100)}"
                send("error", msg); return
            }

            // ---- Connected! ----
            connected.set(true)
            raw.soTimeout = 0  // blocking read
            send("status", "connected")
            send("status", "recording_started")
            startAudioCapture()

            // ---- Read loop ----
            while (running.get()) {
                try {
                    raw.soTimeout = 5000
                    val msg = wsReceive() ?: break
                    handleMessage(msg)
                } catch (e: java.net.SocketTimeoutException) {
                    continue  // normal polling timeout
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Stream error: ${e.message}")
            if (running.get()) send("error", "Connection: ${e.message?.take(100) ?: "unknown"}")
        } finally {
            stopInternal()
        }
    }

    private fun handleMessage(text: String) {
        try {
            val json = JSONObject(text)
            val err = json.optJSONObject("error")
            if (err != null) {
                send("error", "[${err.optInt("code")}] ${err.optString("status")}: ${err.optString("message")}"); return
            }
            val sc = json.optJSONObject("serverContent") ?: return
            val mt = sc.optJSONObject("modelTurn") ?: return
            val parts = mt.optJSONArray("parts") ?: return
            for (i in 0 until parts.length()) {
                val part = parts.getJSONObject(i)
                if (dubMode) {
                    val inline = part.optJSONObject("inlineData")
                    if (inline != null) {
                        val pcm = Base64.decode(inline.optString("data", ""), Base64.DEFAULT)
                        audioTrack?.write(pcm, 0, pcm.size)
                        send("status", "audio_chunk:${pcm.size}")
                    }
                } else {
                    val t = part.optString("text", "")
                    if (t.isNotEmpty()) send("transcript", mapOf("text" to t, "final" to true))
                }
            }
            val inputT = sc.optJSONObject("inputTranscription")
            if (inputT != null) send("status", "detected:${inputT.optString("languageCode")}")
        } catch (e: Exception) { Log.e(TAG, "Parse: ${e.message}") }
    }

    // ---- WebSocket frame sending (مثل e2dub) ----
    private fun wsSend(payload: String) {
        val data = payload.toByteArray(Charsets.UTF_8)
        val len = data.size
        val mask = SecureRandom().generateSeed(4)
        val header = when {
            len <= 125 -> byteArrayOf(0x81.toByte(), (0x80 or len).toByte())
            len <= 65535 -> byteArrayOf(0x81.toByte(), (0x80 or 126).toByte(),
                (len shr 8).toByte(), len.toByte())
            else -> byteArrayOf(0x81.toByte(), (0x80 or 127).toByte(),
                0,0,0,0, (len shr 24).toByte(),(len shr 16).toByte(),(len shr 8).toByte(),len.toByte())
        }
        val masked = ByteArray(len) { i -> (data[i].toInt() xor mask[i % 4].toInt()).toByte() }
        synchronized(outputStream ?: return) {
            outputStream!!.write(header + mask + masked)
            outputStream!!.flush()
        }
    }

    // ---- WebSocket frame receiving ----
    private fun wsReceive(): String? {
        val inp = inputStream ?: return null
        try {
            val b0 = inp.read(); if (b0 < 0) return null
            val b1 = inp.read(); if (b1 < 0) return null
            val opcode = b0 and 0x0F
            if (opcode == 8) return null  // close frame
            var len = (b1 and 0x7F).toLong()
            if (len == 126L) { len = ((inp.read() shl 8) or inp.read()).toLong() }
            else if (len == 127L) { var l = 0L; repeat(8) { l = (l shl 8) or inp.read().toLong() }; len = l }
            val buf = ByteArray(len.toInt())
            var off = 0
            while (off < buf.size) { val r = inp.read(buf, off, buf.size - off); if (r < 0) return null; off += r }
            return String(buf, Charsets.UTF_8)
        } catch (e: Exception) { throw e }
    }

    private fun readLine(inp: InputStream): String {
        val sb = StringBuilder()
        var b = inp.read()
        while (b >= 0 && b.toChar() != '\n') { if (b.toChar() != '\r') sb.append(b.toChar()); b = inp.read() }
        return sb.toString()
    }

    private fun startAudioCapture() {
        audioThread = Thread {
            val chunkSamples = INPUT_CHUNK_BYTES / 2
            val bufSize = AudioRecord.getMinBufferSize(INPUT_SAMPLE_RATE,
                AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
                .coerceAtLeast(INPUT_CHUNK_BYTES * 4)

            val recorder = if (projection != null && android.os.Build.VERSION.SDK_INT >= 29) {
                val cfg = android.media.AudioPlaybackCaptureConfiguration.Builder(projection!!)
                    .addMatchingUsage(android.media.AudioAttributes.USAGE_MEDIA)
                    .addMatchingUsage(android.media.AudioAttributes.USAGE_UNKNOWN).build()
                AudioRecord.Builder().setAudioPlaybackCaptureConfig(cfg)
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
            val bytes = ByteArray(INPUT_CHUNK_BYTES)

            while (running.get()) {
                val read = recorder.read(pcm, 0, chunkSamples)
                if (read > 0 && connected.get()) {
                    for (i in 0 until read) {
                        bytes[i*2] = (pcm[i].toInt() and 0xFF).toByte()
                        bytes[i*2+1] = ((pcm[i].toInt() shr 8) and 0xFF).toByte()
                    }
                    val b64 = Base64.encodeToString(bytes.copyOf(read*2), Base64.NO_WRAP)
                    try {
                        wsSend(JSONObject().put("realtimeInput", JSONObject()
                            .put("audio", JSONObject()
                                .put("mimeType", "audio/pcm;rate=16000")
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
        val bufSize = AudioTrack.getMinBufferSize(OUTPUT_SAMPLE_RATE,
            AudioFormat.CHANNEL_OUT_MONO, AudioFormat.ENCODING_PCM_16BIT)
            .coerceAtLeast(OUTPUT_SAMPLE_RATE * 2)
        audioTrack = AudioTrack.Builder()
            .setAudioAttributes(AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
            .setAudioFormat(AudioFormat.Builder().setSampleRate(OUTPUT_SAMPLE_RATE)
                .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                .setChannelMask(AudioFormat.CHANNEL_OUT_MONO).build())
            .setBufferSizeInBytes(bufSize).setTransferMode(AudioTrack.MODE_STREAM).build()
        audioTrack?.play()
    }

    fun sendAudio(pcm: ByteArray) {
        if (!connected.get()) return
        val b64 = Base64.encodeToString(pcm, Base64.NO_WRAP)
        try {
            wsSend(JSONObject().put("realtimeInput", JSONObject()
                .put("audio", JSONObject().put("mimeType","audio/pcm;rate=16000").put("data",b64))).toString())
        } catch (_: Exception) {}
    }

    fun stop() {
        running.set(false)
        connected.set(false)
        audioThread?.interrupt()
        audioThread = null
        stopInternal()
        send("status", "stopped")
    }

    private fun stopInternal() {
        try { audioTrack?.stop(); audioTrack?.release() } catch (_: Exception) {}
        audioTrack = null
        try { socket?.close() } catch (_: Exception) {}
        socket = null
        try { projection?.stop() } catch (_: Exception) {}
        projection = null
    }

    fun getNextEvent(): Map<String, Any>? = eventQueue.poll()

    private fun send(type: String, data: Any) {
        eventQueue.offer(mapOf("type" to type, "data" to data))
        if (eventQueue.size > 200) eventQueue.poll()
    }
}
