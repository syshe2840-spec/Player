package com.vezoo.player

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ConcurrentLinkedQueue

class AndroidBuiltinSttService(private val context: Context) {

    private var recognizer: SpeechRecognizer? = null
    @Volatile private var running = false
    val eventQueue = ConcurrentLinkedQueue<Map<String, Any>>()
    private var callback: MethodChannel? = null
    private var langCode: String = "fa-IR"

    private val langMap = mapOf(
        "fa" to "fa-IR", "en" to "en-US", "ar" to "ar-SA",
        "zh" to "zh-CN", "ru" to "ru-RU", "es" to "es-ES",
        "fr" to "fr-FR", "de" to "de-DE", "tr" to "tr-TR",
        "hi" to "hi-IN", "ja" to "ja-JP", "ko" to "ko-KR",
        "it" to "it-IT", "pt" to "pt-BR", "nl" to "nl-NL",
        "pl" to "pl-PL", "uk" to "uk-UA", "vi" to "vi-VN",
        "th" to "th-TH", "id" to "id-ID", "sv" to "sv-SE",
        "da" to "da-DK", "fi" to "fi-FI", "no" to "nb-NO",
        "he" to "iw-IL", "el" to "el-GR", "hu" to "hu-HU",
        "ro" to "ro-RO", "cs" to "cs-CZ", "sk" to "sk-SK",
        "bg" to "bg-BG", "hr" to "hr-HR", "ms" to "ms-MY",
        "bn" to "bn-BD", "ur" to "ur-PK", "tl" to "tl-PH",
        "multi" to "und",
    )

    fun setCallback(ch: MethodChannel?) { callback = ch }

    fun start(lang: String) {
        if (running) return
        running = true
        langCode = langMap[lang] ?: "und"
        Handler(Looper.getMainLooper()).post { startListening() }
    }

    private fun startListening() {
        if (!running) return
        if (!SpeechRecognizer.isRecognitionAvailable(context)) {
            send("error", "Speech recognition not available on this device")
            running = false; return
        }

        recognizer?.destroy()
        recognizer = SpeechRecognizer.createSpeechRecognizer(context)
        recognizer?.setRecognitionListener(object : RecognitionListener {
            override fun onReadyForSpeech(params: Bundle?) { send("status", "listening") }
            override fun onBeginningOfSpeech() {}
            override fun onRmsChanged(rmsdB: Float) {}
            override fun onBufferReceived(buffer: ByteArray?) {}
            override fun onEndOfSpeech() {}
            override fun onError(error: Int) {
                if (!running) return
                // restart on common errors (silence, etc.)
                val retry = error == SpeechRecognizer.ERROR_NO_MATCH ||
                            error == SpeechRecognizer.ERROR_SPEECH_TIMEOUT ||
                            error == SpeechRecognizer.ERROR_RECOGNIZER_BUSY
                if (retry) {
                    Handler(Looper.getMainLooper()).postDelayed({ startListening() }, 300)
                } else {
                    send("error", "SpeechRecognizer error: $error")
                    running = false
                }
            }
            override fun onResults(results: Bundle?) {
                val matches = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                val text = matches?.firstOrNull() ?: ""
                if (text.isNotEmpty()) send("transcript", mapOf("text" to text, "final" to true))
                if (running) Handler(Looper.getMainLooper()).postDelayed({ startListening() }, 100)
            }
            override fun onPartialResults(partial: Bundle?) {
                val matches = partial?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                val text = matches?.firstOrNull() ?: ""
                if (text.isNotEmpty()) send("transcript", mapOf("text" to text, "final" to false))
            }
            override fun onEvent(eventType: Int, params: Bundle?) {}
        })

        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, langCode)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_PREFERENCE, langCode)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
        }
        recognizer?.startListening(intent)
        send("status", "started lang=$langCode")
    }

    fun stop() {
        running = false
        recognizer?.stopListening()
        recognizer?.destroy()
        recognizer = null
        send("status", "stopped")
    }

    private fun send(type: String, data: Any) {
        android.util.Log.d("AndroidStt", "EVENT type=$type data=$data")
        val event = mapOf("type" to type, "data" to data)
        eventQueue.offer(event)
        Handler(Looper.getMainLooper()).post {
            try { callback?.invokeMethod("onAndroidSttEvent", event) } catch (_: Exception) {}
        }
    }

    fun getNextEvent(): Map<String, Any>? = eventQueue.poll()
}
