package com.vezoo.player

import ai.onnxruntime.*
import android.content.Context
import android.util.Log
import io.flutter.plugin.common.EventChannel
import java.io.File
import java.nio.LongBuffer
import java.nio.FloatBuffer

/**
 * ONNX-based offline translation
 * از NLLB-200 و SentencePiece برای tokenization استفاده میکنه
 * بدون هیچ نیاز به Google Play Services
 */
class OfflineTranslatorService(private val context: Context) {

    private var ortEnv: OrtEnvironment? = null
    private var encoderSession: OrtSession? = null
    private var decoderSession: OrtSession? = null
    private var tokenizer: NllbTokenizer? = null
    private var currentModelId: String? = null

    companion object {
        private const val TAG = "OfflineTranslator"
        const val MODELS_DIR = "/storage/emulated/0/Download/Vezoo/OfflineModels"
    }

    // ── مدل‌های موجود ──
    data class ModelInfo(
        val id: String,
        val name: String,
        val desc: String,
        val sizeMb: Int,
        val langCount: Int,
        val encoderUrl: String,
        val decoderUrl: String,
        val tokenizerUrl: String,
    )

    val availableModels = listOf(
        ModelInfo(
            id = "nllb_600m",
            name = "NLLB-600M",
            desc = "200 زبان — کیفیت خوب — سریع",
            sizeMb = 300,
            langCount = 200,
            encoderUrl = "https://huggingface.co/niedev/RTranslator/resolve/main/nllb_encoder_q8.onnx",
            decoderUrl = "https://huggingface.co/niedev/RTranslator/resolve/main/nllb_decoder_q8.onnx",
            tokenizerUrl = "https://huggingface.co/niedev/RTranslator/resolve/main/flores200_sacrebleu_tokenizer.spm",
        ),
        ModelInfo(
            id = "nllb_1b3",
            name = "NLLB-1.3B",
            desc = "200 زبان — کیفیت عالی",
            sizeMb = 650,
            langCount = 200,
            encoderUrl = "https://huggingface.co/facebook/nllb-200-distilled-1.3B/resolve/main/onnx/encoder_model_quantized.onnx",
            decoderUrl = "https://huggingface.co/facebook/nllb-200-distilled-1.3B/resolve/main/onnx/decoder_model_quantized.onnx",
            tokenizerUrl = "https://huggingface.co/niedev/RTranslator/resolve/main/flores200_sacrebleu_tokenizer.spm",
        ),
    )

    // ── بارگذاری مدل ──
    fun loadModel(modelId: String): Boolean {
        if (currentModelId == modelId) return true
        val model = availableModels.find { it.id == modelId } ?: return false
        val dir = File(MODELS_DIR, modelId)
        if (!dir.exists()) return false
        return try {
            ortEnv?.close()
            encoderSession?.close()
            decoderSession?.close()
            ortEnv = OrtEnvironment.getEnvironment()
            val opts = OrtSession.SessionOptions()
            encoderSession = ortEnv!!.createSession(File(dir, "encoder.onnx").absolutePath, opts)
            decoderSession = ortEnv!!.createSession(File(dir, "decoder.onnx").absolutePath, opts)
            tokenizer = NllbTokenizer(File(dir, "tokenizer.spm").absolutePath)
            currentModelId = modelId
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to load model: ${e.message}")
            false
        }
    }

    // ── ترجمه ──
    fun translate(text: String, srcLang: String, tgtLang: String): String {
        val env = ortEnv ?: throw IllegalStateException("Model not loaded")
        val enc = encoderSession ?: throw IllegalStateException("Encoder not loaded")
        val dec = decoderSession ?: throw IllegalStateException("Decoder not loaded")
        val tok = tokenizer ?: throw IllegalStateException("Tokenizer not loaded")

        try {
            // Tokenize
            val inputIds = tok.encode(text, srcLang)
            val attentionMask = LongArray(inputIds.size) { 1L }

            // Encoder
            val inputTensor = OnnxTensor.createTensor(env, LongBuffer.wrap(inputIds), longArrayOf(1, inputIds.size.toLong()))
            val maskTensor = OnnxTensor.createTensor(env, LongBuffer.wrap(attentionMask), longArrayOf(1, attentionMask.size.toLong()))
            val encoderOutputs = enc.run(mapOf("input_ids" to inputTensor, "attention_mask" to maskTensor))
            val encoderHidden = encoderOutputs["last_hidden_state"] as OnnxTensor

            // Decoder (greedy search)
            val tgtLangId = tok.langToId(tgtLang)
            val maxLen = 512
            val generatedIds = mutableListOf(tgtLangId)

            for (step in 0 until maxLen) {
                val decoderInput = LongArray(generatedIds.size) { generatedIds[it].toLong() }
                val decoderInputTensor = OnnxTensor.createTensor(env, LongBuffer.wrap(decoderInput), longArrayOf(1, decoderInput.size.toLong()))
                val decoderOutputs = dec.run(mapOf(
                    "input_ids" to decoderInputTensor,
                    "attention_mask" to maskTensor,
                    "encoder_hidden_states" to encoderHidden))
                val logits = (decoderOutputs["logits"] as OnnxTensor).floatBuffer
                val vocabSize = logits.capacity() / decoderInput.size
                val lastLogits = FloatArray(vocabSize)
                logits.position(logits.capacity() - vocabSize)
                logits.get(lastLogits)
                val nextToken = lastLogits.indices.maxByOrNull { lastLogits[it] } ?: break
                if (nextToken == tok.eosId) break
                generatedIds.add(nextToken)
            }

            return tok.decode(generatedIds.map { it.toLong() }.toLongArray())
        } catch (e: Exception) {
            Log.e(TAG, "Translation error: ${e.message}")
            throw e
        }
    }

    fun close() {
        encoderSession?.close()
        decoderSession?.close()
        ortEnv?.close()
        tokenizer = null
        currentModelId = null
    }
}

/**
 * SentencePiece tokenizer wrapper برای NLLB-200
 * از فایل .spm استفاده میکنه
 */
class NllbTokenizer(private val spmPath: String) {
    private val spm = SentencePieceProcessor()
    val eosId: Int get() = spm.eosId()

    init { spm.load(spmPath) }

    // زبان‌های NLLB Flores-200
    private val langMap = mapOf(
        "fa" to "fas_Arab", "en" to "eng_Latn", "ar" to "arb_Arab",
        "zh" to "zho_Hans", "ru" to "rus_Cyrl", "es" to "spa_Latn",
        "fr" to "fra_Latn", "de" to "deu_Latn", "tr" to "tur_Latn",
        "hi" to "hin_Deva", "ja" to "jpn_Jpan", "ko" to "kor_Hang",
        "it" to "ita_Latn", "pt" to "por_Latn", "nl" to "nld_Latn",
        "pl" to "pol_Latn", "uk" to "ukr_Cyrl", "id" to "ind_Latn",
        "sv" to "swe_Latn", "no" to "nob_Latn", "da" to "dan_Latn",
        "fi" to "fin_Latn", "el" to "ell_Grek", "he" to "heb_Hebr",
        "hu" to "hun_Latn", "ro" to "ron_Latn", "cs" to "ces_Latn",
        "bg" to "bul_Cyrl", "th" to "tha_Thai", "vi" to "vie_Latn",
        "ms" to "zsm_Latn", "bn" to "ben_Beng", "ur" to "urd_Arab",
        "sw" to "swh_Latn", "ka" to "kat_Geor",
    )

    fun langToId(lang: String): Int {
        val flores = langMap[lang] ?: "eng_Latn"
        return spm.pieceToId("__${flores}__")
    }

    fun encode(text: String, srcLang: String): LongArray {
        val srcId = langToId(srcLang)
        val tokens = spm.encodeAsIds(text)
        return longArrayOf(srcId.toLong()) + tokens.map { it.toLong() }.toLongArray() + longArrayOf(eosId.toLong())
    }

    fun decode(ids: LongArray): String {
        return spm.decodeIds(ids.drop(1).map { it.toInt() }.toIntArray())
    }
}
