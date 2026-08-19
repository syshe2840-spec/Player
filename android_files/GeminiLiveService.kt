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
    val model: String = "gemini-3.5-live-translate-preview",
    val silenceDurationMs: Int = 350,
    val prefixPaddingMs: Int = 20,
    val startSensitivity: String = "START_SENSITIVITY_HIGH",
    val endSensitivity: String = "END_SENSITIVITY_HIGH",
    val chunkMs: Int = 100,
    val dubMode: Boolean = false,
    val voice: String = "Charon"
)

class GeminiLiveService(private val apiKey: String) {

    private val TAG = "GeminiLive"
    private val HOST = "generativelanguage.googleapis.com"
    private val PORT = 443
    private val PATH = "/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent"

    private val OUTPUT_SAMPLE_RATE = 24000
    private val OUTPUT_FRAME_BYTES = 4800  // 100ms @ 24kHz mono s16le
    private val INPUT_SAMPLE_RATE = 16000
    private val MAX_OUTPUT_BYTES = OUTPUT_SAMPLE_RATE * 2 * 12  // 12s cap

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
    private var playThread: Thread? = null
    private var sendThread: Thread? = null
    private var audioQueue: java.util.concurrent.LinkedBlockingQueue<ByteArray>? = null
    // INPUT_QUEUE — مثل e2dub: Queue(50), oldest dropped when full
    private val inputQueue = java.util.concurrent.LinkedBlockingQueue<ByteArray>(50)

    // AudioBuffer — مثل e2dub: bytearray با lock
    private val audioBuffer = ByteArrayBuffer(MAX_OUTPUT_BYTES)

    @Volatile private var dubVolume: Float = 1.0f
    @Volatile private var isPlayingDub: Boolean = false
    @Volatile private var lastAudioHash: Int = 0

    fun start(cfg: GeminiConfig, proj: MediaProjection?) {
        if (running.get()) { stop() }  // بدون sleep — async stop
        running.set(true)
        projection = proj
        config = cfg
        if (cfg.dubMode) initAudioTrack()
        Thread { connectAndStream() }.start()
    }

    private fun initAudioTrack() {
        val buf = AudioTrack.getMinBufferSize(OUTPUT_SAMPLE_RATE,
            AudioFormat.CHANNEL_OUT_MONO, AudioFormat.ENCODING_PCM_16BIT)
            .coerceAtLeast(OUTPUT_FRAME_BYTES * 4)
        audioTrack = AudioTrack.Builder()
            .setAudioAttributes(AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ASSISTANT)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                // هیچ‌کس نمیتونه این صدا رو capture کنه
                .setAllowedCapturePolicy(AudioAttributes.ALLOW_CAPTURE_BY_NONE)
                .build())
            .setAudioFormat(AudioFormat.Builder().setSampleRate(OUTPUT_SAMPLE_RATE)
                .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                .setChannelMask(AudioFormat.CHANNEL_OUT_MONO).build())
            .setBufferSizeInBytes(buf).setTransferMode(AudioTrack.MODE_STREAM).build()
        audioTrack?.play()

        // pcm_writer — دقیقاً مثل e2dub
        playThread = Thread {
            var nextTick = System.currentTimeMillis()
            while (running.get()) {
                val at = audioTrack
                if (at == null || at.state != AudioTrack.STATE_INITIALIZED) break
                try {
                    val frame = audioBuffer.take(OUTPUT_FRAME_BYTES)
                    at.write(frame, 0, frame.size)
                } catch (_: Exception) { break }
                nextTick += 100
                val delay = nextTick - System.currentTimeMillis()
                if (delay > 0) {
                    try { Thread.sleep(delay) } catch (_: InterruptedException) { break }
                } else if (delay < -1000) {
                    nextTick = System.currentTimeMillis()
                }
            }
        }
        playThread?.isDaemon = true
        playThread?.start()
    }

    private fun connectAndStream() {
        try {
            send("status", "connecting")
            val factory = SSLSocketFactory.getDefault() as SSLSocketFactory
            val raw = factory.createSocket(HOST, PORT) as javax.net.ssl.SSLSocket
            raw.soTimeout = 30_000
            raw.startHandshake()
            socket = raw; outputStream = raw.outputStream; inputStream = raw.inputStream

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
            if (!respLine.contains("101")) {
                val sb = StringBuilder(respLine + "\n")
                var line = readLine(inputStream!!); var bodyLen = 0
                while (line.isNotEmpty()) {
                    if (line.lowercase().startsWith("content-length:")) bodyLen = line.substringAfter(":").trim().toIntOrNull() ?: 0
                    sb.append(line).append("\n"); line = readLine(inputStream!!)
                }
                if (bodyLen > 0) { val body = ByteArray(bodyLen.coerceAtMost(400)); inputStream!!.read(body); sb.append("BODY: ").append(String(body, Charsets.UTF_8).take(300)) }
                send("error", "WS failed: ${sb.toString().take(400)}"); return
            }
            var line = readLine(inputStream!!); while (line.isNotEmpty()) { line = readLine(inputStream!!) }

            // Setup
            val modalities = if (config.dubMode) JSONArray().put("AUDIO") else JSONArray().put("TEXT")
            val setup = JSONObject()
                .put("model", "models/${config.model}")
                .put("generationConfig", JSONObject().apply {
                        put("responseModalities", modalities)
                        if (config.dubMode) {
                            // DUB mode: translate audio to target language
                            put("translationConfig", JSONObject()
                                .put("targetLanguageCode", config.targetLang)
                                .put("echoTargetLanguage", false))
                            if (config.voice.isNotEmpty()) {
                                put("speechConfig", JSONObject()
                                    .put("voiceConfig", JSONObject()
                                        .put("prebuiltVoiceConfig", JSONObject()
                                            .put("voiceName", config.voice))))
                            }
                        } else {
                            // SUBTITLE mode: transcribe + translate to text
                            put("translationConfig", JSONObject()
                                .put("targetLanguageCode", config.targetLang)
                                .put("echoTargetLanguage", false))
                        }
                    })
                .put("realtimeInputConfig", JSONObject()
                    .put("automaticActivityDetection", JSONObject()
                        .put("disabled", false)
                        .put("startOfSpeechSensitivity", "START_SENSITIVITY_HIGH")
                        .put("endOfSpeechSensitivity", "END_SENSITIVITY_HIGH")
                        .put("prefixPaddingMs", 20)
                        .put("silenceDurationMs", 350)))
                .put("sessionResumption", JSONObject())
                .put("contextWindowCompression", JSONObject().put("slidingWindow", JSONObject()))

            wsSend(JSONObject().put("setup", setup).toString())
            send("status", "setup_sent")

            raw.soTimeout = 15_000
            val setupMsg = wsReceive() ?: run { send("error", "Timeout waiting for setupComplete"); return }
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
                        val hash = pcm.take(32).hashCode()
                        if (hash != lastAudioHash) {
                            lastAudioHash = hash
                            audioBuffer.append(pcm)
                            send("status", "audio:${pcm.size}")
                        }
                    }
                } else {
                    val t = part.optString("text","")
                    if (t.isNotEmpty()) send("transcript", mapOf("text" to t, "final" to true))
                }
            }
            // outputTranscription (subtitle mode)
            val outputT = sc.optJSONObject("outputTranscription")
            if (outputT != null) {
                val t = outputT.optString("text","")
                if (t.isNotEmpty()) send("transcript", mapOf("text" to t, "final" to true))
            }
            // inputTranscription هم بگیر (وقتی source==target)
            val inputT = sc.optJSONObject("inputTranscription")
            if (inputT != null && !config.dubMode) {
                val t = inputT.optString("text","")
                if (t.isNotEmpty()) send("transcript", mapOf("text" to t, "final" to true))
            }
        } catch (e: Exception) { Log.e(TAG, "Parse: ${e.message}") }
    }

    private fun startAudioCapture() {
        val chunkBytes = INPUT_SAMPLE_RATE * config.chunkMs / 1000 * 2
        val chunkSamples = chunkBytes / 2
        val bufSize = AudioRecord.getMinBufferSize(INPUT_SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT).coerceAtLeast(chunkBytes * 4)

        audioThread = Thread {
            val recorder = if (projection != null && android.os.Build.VERSION.SDK_INT >= 29) {
                val cfg2 = android.media.AudioPlaybackCaptureConfiguration.Builder(projection!!)
                    .addMatchingUsage(android.media.AudioAttributes.USAGE_MEDIA)
                    .addMatchingUsage(android.media.AudioAttributes.USAGE_GAME)
                    // USAGE_ASSISTANT حذف شد — جلوگیری از capture صدای دوبله
                    .build()
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

            // stdin_reader مثل e2dub
            while (running.get()) {
                val read = recorder.read(pcm, 0, chunkSamples)
                if (read > 0) {
                    for (i in 0 until read) {
                        bytes[i*2] = (pcm[i].toInt() and 0xFF).toByte()
                        bytes[i*2+1] = ((pcm[i].toInt() shr 8) and 0xFF).toByte()
                    }
                    val chunk = bytes.copyOf(read*2)
                    // مثل e2dub — اگه queue پر بود، قدیمی رو drop کن
                    if (!inputQueue.offer(chunk)) {
                        inputQueue.poll()
                        inputQueue.offer(chunk)
                    }
                }
            }
            try { recorder.stop(); recorder.release() } catch (_: Exception) {}
        }
        audioThread?.isDaemon = true
        audioThread?.start()

        // send thread — مثل e2dub: get(timeout=0.25)
        sendThread = Thread {
            while (running.get()) {
                try {
                    val chunk = inputQueue.poll(250, java.util.concurrent.TimeUnit.MILLISECONDS) ?: continue
                    if (!connected.get()) continue
                    // وقتی دوبله داره پخش میشه، این chunk رو skip کن (feedback loop prevention)
                    if (isPlayingDub) continue
                    val b64 = Base64.encodeToString(chunk, Base64.NO_WRAP)
                    wsSend(JSONObject().put("realtimeInput", JSONObject()
                        .put("audio", JSONObject().put("mimeType","audio/pcm;rate=$INPUT_SAMPLE_RATE").put("data",b64))).toString())
                } catch (_: InterruptedException) { break }
                  catch (_: Exception) {}
            }
        }
        sendThread?.isDaemon = true
        sendThread?.start()
    }

    private fun wsSend(payload: String) {
        val data = payload.toByteArray(Charsets.UTF_8)
        val len = data.size
        val mask = SecureRandom().generateSeed(4)
        val header = when {
            len <= 125 -> byteArrayOf(0x81.toByte(), (0x80 or len).toByte())
            len <= 65535 -> byteArrayOf(0x81.toByte(), (0x80 or 126).toByte(), (len shr 8).toByte(), len.toByte())
            else -> byteArrayOf(0x81.toByte(), (0x80 or 127).toByte(), 0,0,0,0, (len shr 24).toByte(),(len shr 16).toByte(),(len shr 8).toByte(),len.toByte())
        }
        val masked = ByteArray(len) { i -> (data[i].toInt() xor mask[i%4].toInt()).toByte() }
        synchronized(this) { outputStream?.write(header + mask + masked); outputStream?.flush() }
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
        var off = 0; while (off < buf.size) { val r=inp.read(buf,off,buf.size-off); if(r<0) return null; off+=r }
        return String(buf, Charsets.UTF_8)
    }

    private fun readLine(inp: InputStream): String {
        val sb = StringBuilder(); var b = inp.read()
        while (b >= 0 && b.toChar() != '\n') { if (b.toChar() != '\r') sb.append(b.toChar()); b = inp.read() }
        return sb.toString()
    }

    fun clearBuffer() {
        audioBuffer.clear()
        android.util.Log.d(TAG, "Audio buffer cleared")
    }

    fun setDubVolume(vol: Float) { dubVolume = vol.coerceIn(0f, 1f); audioTrack?.setVolume(dubVolume) }
    fun setOrigVolume(vol: Float) {} // کنترل از player side

    fun sendAudio(pcm: ByteArray) {
        if (!connected.get()) return
        val b64 = Base64.encodeToString(pcm, Base64.NO_WRAP)
        try { wsSend(JSONObject().put("realtimeInput", JSONObject()
            .put("audio", JSONObject().put("mimeType","audio/pcm;rate=$INPUT_SAMPLE_RATE").put("data",b64))).toString())
        } catch (_: Exception) {}
    }

    fun stop() {
        running.set(false); connected.set(false)
        playThread?.interrupt(); playThread = null
        sendThread?.interrupt(); sendThread = null
        audioThread?.interrupt(); audioThread = null
        audioQueue?.let { SharedAudioService.removeConsumer(it) }
        audioQueue = null
        inputQueue.clear()
        stopInternal(); send("status", "stopped")
    }

    private fun stopInternal() {
        audioBuffer.clear()
        try { audioTrack?.stop(); audioTrack?.release() } catch (_:Exception) {}; audioTrack = null
        try { socket?.close(); socket = null } catch (_:Exception) {}
        // projection توسط SharedAudioService مدیریت میشه
        projection = null
    }

    fun getNextEvent(): Map<String,Any>? = eventQueue.poll()
    private fun send(type: String, data: Any) {
        eventQueue.offer(mapOf("type" to type, "data" to data))
        if (eventQueue.size > 200) eventQueue.poll()
    }
}

// AudioBuffer — دقیقاً مثل e2dub
class ByteArrayBuffer(private val maxBytes: Int) {
    private val data = java.util.ArrayDeque<Byte>()
    private val lock = Any()

    fun append(bytes: ByteArray) {
        synchronized(lock) {
            bytes.forEach { data.addLast(it) }
            while (data.size > maxBytes) data.removeFirst()
        }
    }

    fun take(size: Int): ByteArray {
        synchronized(lock) {
            val count = minOf(size, data.size)
            val result = ByteArray(size)
            for (i in 0 until count) result[i] = data.removeFirst()
            return result  // بقیه silence (zero) میمونه
        }
    }

    fun clear() { synchronized(lock) { data.clear() } }
}
