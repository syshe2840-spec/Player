package com.vezoo.player

import android.content.Context
import android.media.*
import io.flutter.plugin.common.EventChannel
import okhttp3.*
import okio.ByteString
import org.json.JSONObject
import java.nio.ByteBuffer
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
        .pingInterval(25, TimeUnit.SECONDS)
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
            log("STEP1 FAIL: no key")
            sendEvent("error", "No API key"); running = false; return
        }
        log("STEP1 OK")

        val model = when (language) {
            "multi" -> "nova-2-general"
            "fa", "ar", "hi", "id", "tr", "uk", "nl", "sv" -> "nova-2"
            else -> "nova-3"
        }
        val langParam = if (language == "multi") "detect_language=true" else "language=$language"
        val wsUrl = "wss://api.deepgram.com/v1/listen?model=$model&$langParam" +
            "&punctuate=true&interim_results=true&endpointing=300" +
            "&encoding=linear16&sample_rate=16000&channels=1"
        log("STEP2: connecting...")

        ws = http.newWebSocket(
            Request.Builder().url(wsUrl).header("Authorization", "Token $apiKey").build(),
            object : WebSocketListener() {
                override fun onOpen(ws: WebSocket, response: Response) {
                    log("STEP2 OK: code=${response.code}")
                    sendEvent("status", "connected")
                    startAudioCapture()
                }
                override fun onMessage(ws: WebSocket, text: String) {
                    try {
                        val j = JSONObject(text)
                        val t = j.optJSONObject("channel")
                            ?.optJSONArray("alternatives")
                            ?.getJSONObject(0)?.optString("transcript", "") ?: ""
                        val fin = j.optBoolean("is_final") || j.optBoolean("speech_final")
                        if (t.isNotEmpty()) {
                            log("✓ '$t'")
                            sendEvent("transcript", mapOf("text" to t, "final" to fin))
                        } else {
                            log("MSG empty type=${j.optString("type")}")
                        }
                    } catch (e: Exception) { log("MSG parse: ${e.message}") }
                }
                override fun onFailure(ws: WebSocket, t: Throwable, response: Response?) {
                    log("FAIL: ${t.message} resp=${response?.code}")
                    sendEvent("error", "${t.message}"); stop()
                }
                override fun onClosed(ws: WebSocket, code: Int, reason: String) {
                    log("CLOSED $code $reason"); sendEvent("status", "closed"); stop()
                }
            }
        )
    }

    private fun startAudioCapture() {
        val url = streamUrl
        if (url.startsWith("http") && url.isNotEmpty()) {
            log("STEP3: MediaExtractor from URL: ${url.take(60)}")
            try { startMediaExtractor(url); return }
            catch (e: Exception) { log("STEP3 failed: ${e.message} — MIC") }
        } else {
            log("STEP3: no URL — MIC")
        }
        startMic()
    }

    private fun startMediaExtractor(url: String) {
        val extractor = MediaExtractor()
        log("STEP3: calling setDataSource...")
        var ok = false
        val t = Thread {
            try { extractor.setDataSource(url); ok = true; log("STEP3: setDataSource OK") }
            catch (e: Exception) { log("STEP3: setDataSource ERR: ${e.message}") }
        }
        t.start(); t.join(8000)
        if (!ok) { log("STEP3: TIMEOUT — MIC"); extractor.release(); startMic(); return }

        var idx = -1; var fmt: MediaFormat? = null; var mime = ""
        for (i in 0 until extractor.trackCount) {
            val f = extractor.getTrackFormat(i)
            val m = f.getString(MediaFormat.KEY_MIME) ?: continue
            if (m.startsWith("audio/")) { idx = i; fmt = f; mime = m; log("STEP3: audio track $i $m"); break }
        }
        if (idx < 0 || fmt == null) { log("STEP3: no audio — MIC"); extractor.release(); startMic(); return }

        extractor.selectTrack(idx)
        val sr = fmt.getInteger(MediaFormat.KEY_SAMPLE_RATE)
        val ch = fmt.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
        log("STEP3: rate=$sr ch=$ch")
        val codec = MediaCodec.createDecoderByType(mime)
        codec.configure(fmt, null, null, 0); codec.start()
        sendEvent("status", "capturing_stream_audio")

        Thread {
            val info = MediaCodec.BufferInfo(); var total = 0L; var inputDone = false
            while (running) {
                if (!inputDone) {
                    val i = codec.dequeueInputBuffer(10000L)
                    if (i >= 0) {
                        val b = codec.getInputBuffer(i)!!; b.clear()
                        val sz = extractor.readSampleData(b, 0)
                        if (sz < 0) { codec.queueInputBuffer(i,0,0,0,MediaCodec.BUFFER_FLAG_END_OF_STREAM); inputDone=true }
                        else { codec.queueInputBuffer(i,0,sz,extractor.sampleTime,0); extractor.advance() }
                    }
                }
                val o = codec.dequeueOutputBuffer(info, 10000L)
                if (o >= 0) {
                    val ob = codec.getOutputBuffer(o)!!
                    if (info.size > 0) {
                        val raw = ByteArray(info.size); ob.get(raw)
                        val pcm = resample(raw, sr, ch)
                        ws?.send(ByteString.of(*pcm))
                        total += pcm.size
                        if (total % (16000*2*3L) < pcm.size) log("STEP3: sent ${total/1024}kb")
                    }
                    codec.releaseOutputBuffer(o, false)
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) break
                }
            }
            codec.stop(); codec.release(); extractor.release()
        }.start()
    }

    private fun resample(src: ByteArray, srcRate: Int, srcCh: Int): ByteArray {
        val s = src.size / 2
        val out = (s.toLong() * 16000 / srcRate / srcCh).toInt()
        if (out <= 0) return ByteArray(0)
        val r = ByteArray(out * 2)
        val ratio = s.toDouble() / out / srcCh
        for (i in 0 until out) {
            val si = (i * ratio * srcCh).toInt().coerceIn(0, s - srcCh)
            var sum = 0L
            for (c in 0 until srcCh) {
                val bi = (si + c) * 2
                if (bi + 1 < src.size) sum += ((src[bi].toInt() and 0xFF) or (src[bi+1].toInt() shl 8)).toShort()
            }
            val m = (sum / srcCh).toInt().toShort()
            r[i*2] = (m.toInt() and 0xFF).toByte(); r[i*2+1] = (m.toInt() shr 8 and 0xFF).toByte()
        }
        return r
    }

    private fun startMic() {
        val sr = 16000
        val buf = maxOf(AudioRecord.getMinBufferSize(sr, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)*2, 3200)
        val rec = AudioRecord(MediaRecorder.AudioSource.MIC, sr, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, buf)
        log("MIC: state=${rec.state}"); sendEvent("status", "recording_mic_fallback")
        rec.startRecording()
        Thread {
            val chunk = ByteArray(buf/4); var total = 0L
            while (running) {
                val read = rec.read(chunk, 0, chunk.size)
                if (read > 0) {
                    ws?.send(ByteString.of(*chunk.copyOf(read)))
                    total += read
                    if (total % (sr*2*3L) < read) log("mic: sent ${total/1024}kb")
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

