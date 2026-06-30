package com.vezoo.player

/**
 * WhisperV2Bridge — پل JNI به whisper.cpp بومی (AI v2)
 *
 * این یک کتابخانه C++ جداگانه‌ست (libvezoo_whisper.so) که مستقل از
 * vezoo crypto (libvezoo.so) کامپایل می‌شود. v1 (whisper_ggml_plus)
 * دست‌نخورده باقی می‌ماند.
 *
 * مرحله فعلی: فقط اعتبارسنجی کامپایل + transcribe ساده روی فایل WAV.
 * Live caption / streaming هنوز پیاده‌سازی نشده.
 */
object WhisperV2Bridge {
    init {
        System.loadLibrary("vezoo_whisper")
    }

    /** بارگذاری مدل از مسیر .bin — برمی‌گرداند pointer به whisper_context (یا 0 در خطا) */
    external fun nativeInitContext(modelPath: String): Long

    /** آزاد کردن context */
    external fun nativeFreeContext(ctxPtr: Long)

    /**
     * Transcribe یک فایل WAV (16kHz, mono, 16-bit PCM).
     * خروجی: هر خط به فرمت "start_ms|end_ms|text"
     */
    external fun nativeTranscribeWav(
        ctxPtr: Long,
        wavPath: String,
        language: String,
        threads: Int,
        useVad: Boolean
    ): String

    /** اطلاعات سیستم (CPU features: NEON, AVX, ...) — برای دیباگ */
    external fun nativeGetSystemInfo(): String
}

