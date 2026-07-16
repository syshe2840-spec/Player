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
        .pingInterval(20, TimeUnit.SECONDS)
        .build()

    fun setSink(s: EventChannel.EventSink?) { sink = s }
    fun setStreamUrl(url: String) { streamUrl = url }

    fun start(language: String) {
        if (running) return
        running = true
        Thread { doStart(language) }.start()
    }

    private fun doStart(language: String) {
        log("STEP1: fetching key...")
        val apiKey = try {
            val resp = http.newCall(
                Request.Builder().url("${workerUrl.trimEnd('/')}/deepgram-key").build()
            ).execute()
            val body = resp.body?.string() ?: ""
            log("STEP1: code=${resp.code}")
            JSONObject(body).optString("key", "")
        } catch (e: Exception) { log("STEP1 ERROR: ${e.message}"); "" }

        if (apiKey.isEmpty()) {
            sendEvent("error", "No API key"); running = false; return
        }
        log("STEP1 OK")

        val wsUrl = "wss://api.deepgram.com/v1/listen?" +
            "model=nova-3&language=en&" +
            "punctuate=true&interim_results=true&endpointing=300&" +
            "encoding=linear16&sample_rate=16000&channels=1"
        log("STEP2: connecting nova-3 en")

        ws = http.newWebSocket(
            Request.Builder().url(wsUrl).header("Authorization", "Token $apiKey").build(),
            object : WebSocketListener() {
                override fun onOpen(ws: WebSocket, response: Response) {
                    log("STEP2 OK: ${response.code}")
                    sendEvent("status", "connected")
                    // فوری شروع کن — بدون هیچ delay
                    startMicNow()
                }
                override fun onMessage(ws: WebSocket, text: String) {
                    log("RAW: ${text.take(100)}")
                    try {
                        val j = JSONObject(text)
                        val t = j.optJSONObject("channel")
                            ?.optJSONArray("alternatives")
                            ?.getJSONObject(0)?.optString("transcript", "") ?: ""
                        val fin = j.optBoolean("is_final") || j.optBoolean("speech_final")
                        if (t.isNotEmpty()) {
                            log("✓ '$t'")
                            sendEvent("transcript", mapOf("text" to t, "final" to fin))
                        }
                    } catch (e: Exception) { log("PARSE: ${e.message}") }
                }
                override fun onMessage(ws: WebSocket, bytes: okio.ByteString) {
                    log("BINARY: ${bytes.size}b")
                }
                override fun onFailure(ws: WebSocket, t: Throwable, response: Response?) {
                    log("FAIL: ${t.message} ${response?.code}")
                    sendEvent("error", "${t.message}"); stop()
                }
                override fun onClosed(ws: WebSocket, code: Int, reason: String) {
                    log("CLOSED $code $reason"); sendEvent("status", "closed"); stop()
                }
            }
        )
    }

    private fun startMicNow() {
        val sr = 16000
        val buf = maxOf(AudioRecord.getMinBufferSize(sr,
            AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT) * 2, 3200)
        val rec = AudioRecord(MediaRecorder.AudioSource.MIC, sr,
            AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, buf)
        log("MIC: state=${rec.state}")
        sendEvent("status", "recording_mic")
        rec.startRecording()
        Thread {
            val chunk = ByteArray(buf / 4)
            var total = 0L
            while (running) {
                val read = rec.read(chunk, 0, chunk.size)
                if (read > 0) {
                    val sent = ws?.send(ByteString.of(*chunk.copyOf(read))) ?: false
                    total += read
                    if (total % (sr * 2 * 5L) < read) log("mic: ${total/1024}kb ws=$sent")
                }
            }
            rec.stop(); rec.release()
        }.start()
    }

    fun stop() {
        running = false
        try { ws?.send("{\"type\":\"CloseStream\"}") } catch (_: Exception) {}
        try { ws?.close(1000, "Done") } catch (_: Exception) {}
        ws = null; log("STOPPED")
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

