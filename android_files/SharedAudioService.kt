package com.vezoo.player

import android.media.AudioFormat
import android.media.AudioRecord
import android.media.projection.MediaProjection
import android.util.Log
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.atomic.AtomicBoolean

/**
 * سرویس مشترک capture صدا
 * یه بار MediaProjection → PCM به همه consumers میده
 */
object SharedAudioService {

    private val TAG = "SharedAudio"
    private val running = AtomicBoolean(false)

    // هر consumer یه queue داره
    private val consumers = CopyOnWriteArrayList<LinkedBlockingQueue<ByteArray>>()

    private var audioThread: Thread? = null
    private var projection: MediaProjection? = null

    val SAMPLE_RATE = 16000
    val CHUNK_MS = 100
    val CHUNK_BYTES = SAMPLE_RATE * CHUNK_MS / 1000 * 2  // s16le mono

    fun start(proj: MediaProjection) {
        if (running.getAndSet(true)) return
        projection = proj
        audioThread = Thread { captureLoop() }
        audioThread?.isDaemon = true
        audioThread?.start()
        Log.d(TAG, "Started — consumers: ${consumers.size}")
    }

    fun stop() {
        running.set(false)
        audioThread?.interrupt()
        audioThread = null
        consumers.clear()
        try { projection?.stop() } catch (_: Exception) {}
        projection = null
        Log.d(TAG, "Stopped")
    }

    fun isRunning() = running.get()

    /** ثبت consumer جدید — یه queue برمیگردونه */
    fun addConsumer(): LinkedBlockingQueue<ByteArray> {
        val q = LinkedBlockingQueue<ByteArray>(50)
        consumers.add(q)
        return q
    }

    /** حذف consumer */
    fun removeConsumer(q: LinkedBlockingQueue<ByteArray>) {
        consumers.remove(q)
    }

    private fun captureLoop() {
        val chunkSamples = CHUNK_BYTES / 2
        val bufSize = AudioRecord.getMinBufferSize(
            SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT
        ).coerceAtLeast(CHUNK_BYTES * 4)

        val proj = projection
        val recorder = if (proj != null && android.os.Build.VERSION.SDK_INT >= 29) {
            val cfg = android.media.AudioPlaybackCaptureConfiguration.Builder(proj)
                .addMatchingUsage(android.media.AudioAttributes.USAGE_MEDIA)
                .addMatchingUsage(android.media.AudioAttributes.USAGE_GAME)
                .build()
            AudioRecord.Builder()
                .setAudioPlaybackCaptureConfig(cfg)
                .setAudioFormat(AudioFormat.Builder()
                    .setSampleRate(SAMPLE_RATE)
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setChannelMask(AudioFormat.CHANNEL_IN_MONO).build())
                .setBufferSizeInBytes(bufSize).build()
        } else {
            AudioRecord(android.media.MediaRecorder.AudioSource.MIC,
                SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT, bufSize)
        }

        recorder.startRecording()
        Log.d(TAG, "Recording started")

        val pcm = ShortArray(chunkSamples)
        val bytes = ByteArray(CHUNK_BYTES)

        while (running.get()) {
            val read = recorder.read(pcm, 0, chunkSamples)
            if (read <= 0) continue

            // تبدیل به little-endian bytes
            for (i in 0 until read) {
                bytes[i * 2] = (pcm[i].toInt() and 0xFF).toByte()
                bytes[i * 2 + 1] = ((pcm[i].toInt() shr 8) and 0xFF).toByte()
            }
            val chunk = bytes.copyOf(read * 2)

            // ارسال به همه consumers
            val iter = consumers.iterator()
            while (iter.hasNext()) {
                val q = iter.next()
                if (!q.offer(chunk)) {
                    q.poll(); q.offer(chunk)  // drop oldest
                }
            }
        }

        try { recorder.stop(); recorder.release() } catch (_: Exception) {}
        Log.d(TAG, "Recording stopped")
    }
}
