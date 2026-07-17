package com.vezoo.player

import android.content.Context

/**
 * Offline Translator — stub
 * All inference handled in Dart via flutter_onnxruntime + dart_sentencepiece_tokenizer
 */
class OfflineTranslatorService(private val context: Context) {
    companion object {
        const val MODELS_DIR = "/storage/emulated/0/Download/Vezoo/OfflineModels"
    }
}

