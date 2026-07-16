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
        // STEP 1: key از Worker
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

        // STEP 2: WebSocket به Deepgram
        val model = if (language == "multi") "nova-2-general" else "nova-3"
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
        // STEP 3: MediaExtractor + MediaCodec — بدون هیچ permission
        val url = streamUrl
        if (url.startsWith("http") && !url.isEmpty()) {
            log("STEP3: MediaExtractor from URL: ${url.take(60)}")
            try {
                startMediaExtractor(url)
                return
            } catch (e: Exception) {
                log("STEP3 MediaExtractor failed: ${e.message} — fallback to MIC")
            }
        } else {
            log("STEP3: no URL — using MIC")
        }
        startMic()
    }

    private fun startMediaExtractor(url: String) {
        val extractor = MediaExtractor()
        log("STEP3: calling setDataSource...")
        var dataSourceSet = false
        val t = Thread {
            try {
                extractor.setDataSource(url)
                dataSourceSet = true
                log("STEP3: setDataSource OK")
            } catch (e: Exception) {
                log("STEP3: setDataSource ERROR: \${e.message}")
            }
        }
        t.start()
        t.join(8000) // 8 ثانیه timeout
        if (!dataSourceSet) {
            log("STEP3: setDataSource TIMEOUT — server blocking second connection — fallback to MIC")
            extractor.release()
            startMic()
            return
        }

        var audioTrackIndex = -1
        var audioFormat: MediaFormat? = null
        var mime = ""

        for (i in 0 until extractor.trackCount) {
            val fmt = extractor.getTrackFormat(i)
            val m = fmt.getString(MediaFormat.KEY_MIME) ?: continue
            if (m.startsWith("audio/")) {
                audioTrackIndex = i
                audioFormat = fmt
                mime = m
                log("STEP3: found audio track $i mime=$m")
                break
            }
        }

        if (audioTrackIndex < 0 || audioFormat == null) {
            log("STEP3: no audio track found — fallback to MIC")
            extractor.release()
            startMic()
            return
        }

        extractor.selectTrack(audioTrackIndex)

        val srcSampleRate = audioFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
        val srcChannels = audioFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
        log("STEP3: srcRate=$srcSampleRate srcCh=$srcChannels mime=$mime")

        val codec = MediaCodec.createDecoderByType(mime)
        codec.configure(audioFormat, null, null, 0)
        codec.start()

        sendEvent("status", "capturing_stream_audio")
        log("STEP3: MediaCodec started")

        Thread {
            val bufInfo = MediaCodec.BufferInfo()
            val timeoutUs = 10000L
            val pcmBuf = ByteBuffer.allocate(65536)
            var totalSent = 0L
            var inputDone = false

            while (running) {
                // Input
                if (!inputDone) {
                    val inIdx = codec.dequeueInputBuffer(timeoutUs)
                    if (inIdx >= 0) {
                        val inBuf = codec.getInputBuffer(inIdx)!!
                        inBuf.clear()
                        val sampleSize = extractor.readSampleData(inBuf, 0)
                        if (sampleSize < 0) {
                            codec.queueInputBuffer(inIdx, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputDone = true
                            log("STEP3: input done")
                        } else {
                            codec.queueInputBuffer(inIdx, 0, sampleSize, extractor.sampleTime, 0)
                            extractor.advance()
                        }
                    }
                }

                // Output
                val outIdx = codec.dequeueOutputBuffer(bufInfo, timeoutUs)
                if (outIdx >= 0) {
                    val outBuf = codec.getOutputBuffer(outIdx)!!
                    val pcmSize = bufInfo.size
                    if (pcmSize > 0) {
                        val rawPcm = ByteArray(pcmSize)
                        outBuf.get(rawPcm)
                        // resample + downmix به 16000Hz mono
                        val resampled = resampleToMono16k(rawPcm, srcSampleRate, srcChannels)
                        ws?.send(ByteString.of(*resampled))
                        totalSent += resampled.size
                        if (totalSent % (16000 * 2 * 3L) < resampled.size)
                            log("STEP3: sent ${totalSent/1024}kb")
                    }
                    codec.releaseOutputBuffer(outIdx, false)
                    if (bufInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                        log("STEP3: stream ended")
                        break
                    }
                }
            }

            codec.stop(); codec.release(); extractor.release()
            log("STEP3: MediaExtractor done")
        }.start()
    }

    // resample از srcRate/srcChannels به 16000Hz mono
    private fun resampleToMono16k(src: ByteArray, srcRate: Int, srcChannels: Int): ByteArray {
        val srcSamples = src.size / 2 // 16-bit
        val outSamples = (srcSamples.toLong() * 16000 / srcRate / srcChannels).toInt()
        if (outSamples <= 0) return ByteArray(0)
        val out = ByteArray(outSamples * 2)
        val ratio = srcSamples.toDouble() / outSamples / srcChannels
        for (i in 0 until outSamples) {
            val srcIdx = (i * ratio * srcChannels).toInt().coerceIn(0, srcSamples - srcChannels)
            // mix channels به mono
            var sum = 0L
            for (ch in 0 until srcChannels) {
                val byteIdx = (srcIdx + ch) * 2
                if (byteIdx + 1 < src.size) {
                    val sample = (src[byteIdx].toInt() and 0xFF) or (src[byteIdx + 1].toInt() shl 8)
                    sum += sample.toShort()
                }
            }
            val mono = (sum / srcChannels).toInt().toShort()
            out[i * 2] = (mono.toInt() and 0xFF).toByte()
            out[i * 2 + 1] = (mono.toInt() shr 8 and 0xFF).toByte()
        }
        return out
    }

    private fun startMic() {
        val sr = 16000
        val buf = maxOf(AudioRecord.getMinBufferSize(sr,
            AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT) * 2, 3200)
        val rec = AudioRecord(MediaRecorder.AudioSource.MIC, sr,
            AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, buf)
        log("MIC: state=${rec.state}")
        sendEvent("status", "recording_mic_fallback")
        rec.startRecording()
        Thread {
            val chunk = ByteArray(buf / 4)
            var total = 0L
            while (running) {
                val read = rec.read(chunk, 0, chunk.size)
                if (read > 0) {
                    ws?.send(ByteString.of(*chunk.copyOf(read)))
                    total += read
                    if (total % (sr * 2 * 3L) < read) log("mic: sent ${total/1024}kb")
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

