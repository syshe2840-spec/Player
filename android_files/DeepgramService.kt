package com.vezoo.player

import android.content.Context
import android.media.*
import io.flutter.plugin.common.EventChannel
import okhttp3.*
import okio.ByteString
import org.json.JSONObject
import java.util.concurrent.TimeUnit

class DeepgramService(
    private val context: Context,
    private val workerUrl: String,
) {
    private var ws: WebSocket? = null
    @Volatile private var running = false
    private var sink: EventChannel.EventSink? = null
    private var streamUrl: String = ""

    private val http = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(0, TimeUnit.SECONDS)
        .build()

    fun setSink(s: EventChannel.EventSink?) { sink = s }
    fun setStreamUrl(url: String) { streamUrl = url }

    fun start(language: String) {
        if (running) return
        running = true
        Thread { doStart(language) }.start()
    }

    private fun doStart(language: String) {
        log("STEP1: fetching key from $workerUrl")
        val apiKey = try {
            val resp = http.newCall(
                Request.Builder().url("${workerUrl.trimEnd('/')}/deepgram-key").build()
            ).execute()
            val body = resp.body?.string() ?: ""
            log("STEP1: code=${resp.code} body=${body.take(30)}")
            JSONObject(body).optString("key", "")
        } catch (e: Exception) { log("STEP1 ERROR: ${e.javaClass.simpleName}: ${e.message}"); "" }

        if (apiKey.isEmpty()) {
            log("STEP1 FAIL: key empty")
            sendEvent("error", "No API key"); running = false; return
        }
        log("STEP1 OK: key=${apiKey.take(8)}...")

        // nova-3 از مارس 2026 فارسی، عربی، عبری رو پشتیبانی میکنه
        val model = "nova-3"
        val langParam = if (language == "multi") "detect_language=true" else "language=$language"
        val wsUrl = "wss://api.deepgram.com/v1/listen?" +
            "model=$model&$langParam&" +
            "punctuate=true&interim_results=true&endpointing=100&" +
            "encoding=linear16&sample_rate=16000&channels=1"
        log("STEP2: connecting model=$model lang=$langParam")

        ws = http.newWebSocket(
            Request.Builder().url(wsUrl).header("Authorization", "Token $apiKey").build(),
            object : WebSocketListener() {
                override fun onOpen(ws: WebSocket, response: Response) {
                    log("STEP2 OK: code=${response.code}")
                    sendEvent("status", "connected")
                    startCapture()
                }
                override fun onMessage(ws: WebSocket, text: String) {
                    log("RAW: ${text.take(120)}")
                    try {
                        val j = JSONObject(text)
                        val t = j.optJSONObject("channel")
                            ?.optJSONArray("alternatives")
                            ?.getJSONObject(0)?.optString("transcript", "") ?: ""
                        val fin = j.optBoolean("is_final") || j.optBoolean("speech_final")
                        val type = j.optString("type", "?")
                        log("MSG: type=$type transcript='$t' final=$fin")
                        if (t.isNotEmpty()) {
                            log("✓ TRANSCRIPT: '$t'")
                            sendEvent("transcript", mapOf("text" to t, "final" to fin))
                        }
                    } catch (e: Exception) { log("PARSE ERROR: ${e.message}") }
                }
                override fun onMessage(ws: WebSocket, bytes: okio.ByteString) {
                    log("BINARY MSG: ${bytes.size}b")
                }
                override fun onFailure(ws: WebSocket, t: Throwable, response: Response?) {
                    log("FAIL: ${t.javaClass.simpleName}: ${t.message} resp=${response?.code} ${response?.message}")
                    sendEvent("error", "${t.message}"); stop()
                }
                override fun onClosing(ws: WebSocket, code: Int, reason: String) {
                    log("CLOSING: $code $reason")
                }
                override fun onClosed(ws: WebSocket, code: Int, reason: String) {
                    log("CLOSED: $code $reason"); sendEvent("status", "closed"); stop()
                }
            }
        )
    }

    private fun startCapture() {
        val sr = 16000
        val buf = maxOf(AudioRecord.getMinBufferSize(sr,
            AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT) * 2, 3200)

        // REMOTE_SUBMIX — صدای خروجی دستگاه بدون نویز محیط
        var recorder: AudioRecord? = null
        var captureMode = "UNKNOWN"

        try {
            log("AUDIO: trying REMOTE_SUBMIX...")
            recorder = AudioRecord(
                MediaRecorder.AudioSource.REMOTE_SUBMIX,
                sr, AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT, buf
            )
            val state = recorder.state
            log("AUDIO: REMOTE_SUBMIX state=$state (1=initialized, 0=uninitialized)")
            // state=1 → initialized, state=0 → ممکن هنوز کار کنه روی بعضی دیوایس‌ها
            if (state == AudioRecord.STATE_INITIALIZED || state == 0) {
                captureMode = "REMOTE_SUBMIX"
                log("AUDIO: REMOTE_SUBMIX OK state=$state — capturing internal audio")
            } else {
                log("AUDIO: REMOTE_SUBMIX bad state=$state — releasing")
                recorder.release()
                recorder = null
            }
        } catch (e: Exception) {
            log("AUDIO: REMOTE_SUBMIX EXCEPTION: ${e.javaClass.simpleName}: ${e.message}")
            recorder = null
        }

        // fallback: میکروفون
        if (recorder == null) {
            try {
                log("AUDIO: fallback to MICROPHONE...")
                recorder = AudioRecord(
                    MediaRecorder.AudioSource.MIC,
                    sr, AudioFormat.CHANNEL_IN_MONO,
                    AudioFormat.ENCODING_PCM_16BIT, buf
                )
                val state = recorder.state
                log("AUDIO: MIC state=$state")
                captureMode = "MIC"
            } catch (e: Exception) {
                log("AUDIO: MIC FAILED: ${e.message}")
                sendEvent("error", "Audio capture failed"); return
            }
        }

        sendEvent("status", "recording_$captureMode")
        log("AUDIO: starting recording mode=$captureMode buf=$buf")
        recorder!!.startRecording()

        // ارسال audio به Deepgram
        Thread {
            val chunk = ByteArray(buf / 4)
            var total = 0L
            var lastLog = 0L
            log("AUDIO LOOP: started chunkSize=${chunk.size}")

            while (running) {
                val read = recorder.read(chunk, 0, chunk.size)
                if (read > 0) {
                    val sent = ws?.send(ByteString.of(*chunk.copyOf(read))) ?: false
                    total += read
                    // لاگ هر ۳ ثانیه
                    if (total - lastLog >= sr * 2 * 3L) {
                        log("AUDIO: sent=${total/1024}kb ws=$sent mode=$captureMode")
                        lastLog = total
                    }
                } else if (read < 0) {
                    log("AUDIO: read error=$read — stopping")
                    break
                }
            }
            log("AUDIO LOOP: ended total=${total/1024}kb")
            try { recorder.stop(); recorder.release() } catch (_: Exception) {}
        }.start()
    }

    fun stop() {
        log("STOP: called")
        running = false
        try { ws?.send("{\"type\":\"CloseStream\"}") } catch (_: Exception) {}
        try { ws?.close(1000, "Done") } catch (_: Exception) {}
        ws = null
        log("STOP: done")
    }

    private fun log(msg: String) {
        android.util.Log.d("DG", msg)
        sendEvent("status", msg)
    }

    private fun sendEvent(type: String, data: Any) {
        android.os.Handler(android.os.Looper.getMainLooper()).post {
            try { sink?.success(mapOf("type" to type, "data" to data)) } catch (_: Exception) {}
        }
    }
}

