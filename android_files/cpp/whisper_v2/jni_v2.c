/*
 * jni_v2.c — JNI wrapper برای whisper.cpp بومی (AI v2)
 * بر اساس نمونه رسمی whisper.android (whisper.cpp v1.9.1)
 *
 * توابع JNI صدا زده‌شده از Kotlin:
 *   com.vezoo.player.WhisperV2Bridge.nativeInitContext(modelPath)   -> long (ctx ptr)
 *   com.vezoo.player.WhisperV2Bridge.nativeFreeContext(ctx)         -> void
 *   com.vezoo.player.WhisperV2Bridge.nativeTranscribeWav(...)       -> String
 *   com.vezoo.player.WhisperV2Bridge.nativeGetSystemInfo()          -> String
 */
#include <jni.h>
#include <android/log.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <stdio.h>
#include "whisper.h"

#define TAG "VezooWhisperV2"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO,  TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__)

/* خواندن WAV ساده (16kHz, mono, 16-bit PCM) — همونی که Kotlin extraction میسازه */
static float* read_wav_pcm16(const char* path, int* out_samples) {
    FILE* f = fopen(path, "rb");
    if (!f) { LOGE("cannot open wav: %s", path); return NULL; }

    uint8_t header[44];
    if (fread(header, 1, 44, f) != 44) { fclose(f); LOGE("wav header too short"); return NULL; }

    /* چک سریع RIFF/WAVE */
    if (memcmp(header, "RIFF", 4) != 0 || memcmp(header + 8, "WAVE", 4) != 0) {
        fclose(f); LOGE("not a valid wav file"); return NULL;
    }

    uint32_t data_size = header[40] | (header[41]<<8) | (header[42]<<16) | ((uint32_t)header[43]<<24);
    int n_samples = data_size / 2; /* 16-bit */

    int16_t* pcm16 = (int16_t*)malloc(data_size);
    if (!pcm16) { fclose(f); return NULL; }
    size_t got = fread(pcm16, 1, data_size, f);
    fclose(f);
    if (got != data_size) { free(pcm16); LOGE("wav data read incomplete"); return NULL; }

    float* pcmf32 = (float*)malloc(sizeof(float) * n_samples);
    if (!pcmf32) { free(pcm16); return NULL; }
    for (int i = 0; i < n_samples; i++) pcmf32[i] = (float)pcm16[i] / 32768.0f;

    free(pcm16);
    *out_samples = n_samples;
    return pcmf32;
}

JNIEXPORT jlong JNICALL
Java_com_vezoo_player_WhisperV2Bridge_nativeInitContext(JNIEnv *env, jobject thiz, jstring model_path) {
    const char* path = (*env)->GetStringUTFChars(env, model_path, NULL);
    LOGI("Loading model: %s", path);

    struct whisper_context_params cparams = whisper_context_default_params();
    struct whisper_context* ctx = whisper_init_from_file_with_params(path, cparams);

    (*env)->ReleaseStringUTFChars(env, model_path, path);

    if (!ctx) { LOGE("whisper_init_from_file_with_params failed"); return 0; }
    LOGI("Model loaded OK");
    return (jlong)(intptr_t)ctx;
}

JNIEXPORT void JNICALL
Java_com_vezoo_player_WhisperV2Bridge_nativeFreeContext(JNIEnv *env, jobject thiz, jlong ctx_ptr) {
    struct whisper_context* ctx = (struct whisper_context*)(intptr_t)ctx_ptr;
    if (ctx) whisper_free(ctx);
}

JNIEXPORT jstring JNICALL
Java_com_vezoo_player_WhisperV2Bridge_nativeTranscribeWav(
        JNIEnv *env, jobject thiz,
        jlong ctx_ptr, jstring wav_path, jstring language, jint threads, jboolean translate) {

    struct whisper_context* ctx = (struct whisper_context*)(intptr_t)ctx_ptr;
    if (!ctx) return (*env)->NewStringUTF(env, "");

    const char* wpath = (*env)->GetStringUTFChars(env, wav_path, NULL);
    const char* lang  = (*env)->GetStringUTFChars(env, language, NULL);

    int n_samples = 0;
    float* pcmf32 = read_wav_pcm16(wpath, &n_samples);
    (*env)->ReleaseStringUTFChars(env, wav_path, wpath);

    if (!pcmf32) {
        (*env)->ReleaseStringUTFChars(env, language, lang);
        return (*env)->NewStringUTF(env, "");
    }

    struct whisper_full_params params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
    params.print_realtime   = false;
    params.print_progress   = false;
    params.print_timestamps = false;
    params.print_special    = false;
    params.translate        = (translate == JNI_TRUE); /* whisper فقط به انگلیسی ترجمه می‌کند */
    params.language         = lang;                     /* زبان مبدا — حتی موقع ترجمه باید مبدا باشد */
    params.n_threads        = threads > 0 ? threads : 4;
    params.offset_ms        = 0;
    params.no_context       = true;
    params.single_segment   = false;

    LOGI("Running whisper_full: %d samples, lang=%s, threads=%d, translate=%d",
         n_samples, lang, params.n_threads, params.translate);
    int rc = whisper_full(ctx, params, pcmf32, n_samples);
    free(pcmf32);
    (*env)->ReleaseStringUTFChars(env, language, lang);

    if (rc != 0) { LOGE("whisper_full failed: %d", rc); return (*env)->NewStringUTF(env, ""); }

    /* خروجی: هر خط = start_ms|end_ms|text */
    int n_segs = whisper_full_n_segments(ctx);
    size_t buf_cap = 4096;
    char* buf = (char*)malloc(buf_cap);
    buf[0] = '\0';
    size_t buf_len = 0;

    for (int i = 0; i < n_segs; i++) {
        int64_t t0 = whisper_full_get_segment_t0(ctx, i) * 10; /* whisper گزارش به 10ms */
        int64_t t1 = whisper_full_get_segment_t1(ctx, i) * 10;
        const char* text = whisper_full_get_segment_text(ctx, i);

        char line[1024];
        int n = snprintf(line, sizeof(line), "%lld|%lld|%s\n", (long long)t0, (long long)t1, text);
        if (n < 0) continue;

        if (buf_len + n + 1 > buf_cap) {
            buf_cap = (buf_len + n + 1) * 2;
            char* nb = (char*)realloc(buf, buf_cap);
            if (!nb) break;
            buf = nb;
        }
        memcpy(buf + buf_len, line, n);
        buf_len += n;
        buf[buf_len] = '\0';
    }

    jstring result = (*env)->NewStringUTF(env, buf);
    free(buf);
    return result;
}

JNIEXPORT jstring JNICALL
Java_com_vezoo_player_WhisperV2Bridge_nativeGetSystemInfo(JNIEnv *env, jobject thiz) {
    const char* info = whisper_print_system_info();
    return (*env)->NewStringUTF(env, info);
}

