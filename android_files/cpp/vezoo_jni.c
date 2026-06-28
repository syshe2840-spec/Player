/*
 * vezoo_jni.c — JNI wrapper برای صدا زدن از Kotlin
 * توابع JNI که از MainActivity صدا زده میشن
 */
#include "vezoo.h"
#include <jni.h>
#include <string.h>
#include <stdlib.h>
#include <android/log.h>

#define TAG "VezooJNI"
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__)

/* com.vezoo.player.MainActivity.nativeDecryptGcm */
JNIEXPORT jbyteArray JNICALL
Java_com_vezoo_player_MainActivity_nativeGcmDecrypt(
        JNIEnv* env, jobject obj,
        jbyteArray jkey, jbyteArray jdata) {

    jsize key_len  = (*env)->GetArrayLength(env, jkey);
    jsize data_len = (*env)->GetArrayLength(env, jdata);

    jbyte* key  = (*env)->GetByteArrayElements(env, jkey,  NULL);
    jbyte* data = (*env)->GetByteArrayElements(env, jdata, NULL);

    uint8_t* out = (uint8_t*)malloc(data_len);
    size_t out_len = 0;

    jbyteArray result = NULL;
    if (out && vez_gcm_decrypt(
            (uint8_t*)key,  (size_t)key_len,
            (uint8_t*)data, (size_t)data_len,
            out, &out_len) == 0) {
        result = (*env)->NewByteArray(env, (jsize)out_len);
        (*env)->SetByteArrayRegion(env, result, 0, (jsize)out_len, (jbyte*)out);
    } else {
        LOGE("GCM decrypt failed");
    }

    free(out);
    (*env)->ReleaseByteArrayElements(env, jkey,  key,  JNI_ABORT);
    (*env)->ReleaseByteArrayElements(env, jdata, data, JNI_ABORT);
    return result;
}

JNIEXPORT jbyteArray JNICALL
Java_com_vezoo_player_MainActivity_nativeGcmEncrypt(
        JNIEnv* env, jobject obj,
        jbyteArray jkey, jbyteArray jdata) {

    jsize key_len   = (*env)->GetArrayLength(env, jkey);
    jsize plain_len = (*env)->GetArrayLength(env, jdata);

    jbyte* key   = (*env)->GetByteArrayElements(env, jkey,  NULL);
    jbyte* plain = (*env)->GetByteArrayElements(env, jdata, NULL);

    size_t out_max = (size_t)plain_len + 12 + 16 + 32;
    uint8_t* out = (uint8_t*)malloc(out_max);
    size_t out_len = 0;

    jbyteArray result = NULL;
    if (out && vez_gcm_encrypt(
            (uint8_t*)key, (size_t)key_len,
            (uint8_t*)plain, (size_t)plain_len,
            out, &out_len) == 0) {
        result = (*env)->NewByteArray(env, (jsize)out_len);
        (*env)->SetByteArrayRegion(env, result, 0, (jsize)out_len, (jbyte*)out);
    }

    free(out);
    (*env)->ReleaseByteArrayElements(env, jkey,  key,   JNI_ABORT);
    (*env)->ReleaseByteArrayElements(env, jdata, plain, JNI_ABORT);
    return result;
}

JNIEXPORT jbyteArray JNICALL
Java_com_vezoo_player_MainActivity_nativeHkdf(
        JNIEnv* env, jobject obj,
        jbyteArray jikm, jbyteArray jsalt, jbyteArray jinfo, jint out_len) {

    jbyte* ikm  = (*env)->GetByteArrayElements(env, jikm,  NULL);
    jbyte* salt = (*env)->GetByteArrayElements(env, jsalt, NULL);
    jbyte* info = (*env)->GetByteArrayElements(env, jinfo, NULL);
    jsize ikm_len  = (*env)->GetArrayLength(env, jikm);
    jsize salt_len = (*env)->GetArrayLength(env, jsalt);
    jsize info_len = (*env)->GetArrayLength(env, jinfo);

    uint8_t* out = (uint8_t*)malloc((size_t)out_len);
    jbyteArray result = NULL;

    if (out && vez_hkdf(
            (uint8_t*)ikm,  (size_t)ikm_len,
            (uint8_t*)salt, (size_t)salt_len,
            (uint8_t*)info, (size_t)info_len,
            out, (size_t)out_len) == 0) {
        result = (*env)->NewByteArray(env, out_len);
        (*env)->SetByteArrayRegion(env, result, 0, out_len, (jbyte*)out);
    }

    free(out);
    (*env)->ReleaseByteArrayElements(env, jikm,  ikm,  JNI_ABORT);
    (*env)->ReleaseByteArrayElements(env, jsalt, salt, JNI_ABORT);
    (*env)->ReleaseByteArrayElements(env, jinfo, info, JNI_ABORT);
    return result;
}
