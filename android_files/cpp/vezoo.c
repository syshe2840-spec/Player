/*
 * vezoo.c — کریپتو C برای Vezoo
 * از OpenSSL که با Android NDK (API 28+) میاد استفاده میکنه
 * بدون dependency خارجی
 */
#include "vezoo.h"
#include <openssl/evp.h>
#include <openssl/kdf.h>
#include <openssl/rand.h>
#include <string.h>
#include <stdlib.h>

#define NONCE_LEN 12
#define TAG_LEN   16

int vez_gcm_decrypt(const uint8_t* key, size_t key_len,
                    const uint8_t* data, size_t data_len,
                    uint8_t* out, size_t* out_len) {
    if (!key || !data || !out || !out_len) return -1;
    if (data_len < NONCE_LEN + TAG_LEN) return -1;

    const uint8_t* nonce = data;
    size_t ct_len = data_len - NONCE_LEN - TAG_LEN;
    const uint8_t* ct  = data + NONCE_LEN;
    const uint8_t* tag = data + NONCE_LEN + ct_len;

    EVP_CIPHER_CTX* ctx = EVP_CIPHER_CTX_new();
    if (!ctx) return -1;

    int len = 0, result = -1;
    const EVP_CIPHER* cipher = (key_len == 32) ? EVP_aes_256_gcm() : EVP_aes_128_gcm();

    if (EVP_DecryptInit_ex(ctx, cipher, NULL, NULL, NULL) == 1 &&
        EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_IVLEN, NONCE_LEN, NULL) == 1 &&
        EVP_DecryptInit_ex(ctx, NULL, NULL, key, nonce) == 1 &&
        EVP_DecryptUpdate(ctx, out, &len, ct, (int)ct_len) == 1 &&
        EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_TAG, TAG_LEN, (void*)tag) == 1 &&
        EVP_DecryptFinal_ex(ctx, out + len, &len) == 1) {
        *out_len = ct_len;
        result = 0;
    }

    EVP_CIPHER_CTX_free(ctx);
    return result;
}

int vez_gcm_encrypt(const uint8_t* key, size_t key_len,
                    const uint8_t* plain, size_t plain_len,
                    uint8_t* out, size_t* out_len) {
    if (!key || !plain || !out || !out_len) return -1;

    uint8_t nonce[NONCE_LEN];
    if (RAND_bytes(nonce, NONCE_LEN) != 1) return -1;

    EVP_CIPHER_CTX* ctx = EVP_CIPHER_CTX_new();
    if (!ctx) return -1;

    int len = 0, result = -1;
    uint8_t tag[TAG_LEN];
    uint8_t* ct = out + NONCE_LEN;
    const EVP_CIPHER* cipher = (key_len == 32) ? EVP_aes_256_gcm() : EVP_aes_128_gcm();

    if (EVP_EncryptInit_ex(ctx, cipher, NULL, NULL, NULL) == 1 &&
        EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_IVLEN, NONCE_LEN, NULL) == 1 &&
        EVP_EncryptInit_ex(ctx, NULL, NULL, key, nonce) == 1 &&
        EVP_EncryptUpdate(ctx, ct, &len, plain, (int)plain_len) == 1 &&
        EVP_EncryptFinal_ex(ctx, ct + len, &len) == 1 &&
        EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_GET_TAG, TAG_LEN, tag) == 1) {
        memcpy(out, nonce, NONCE_LEN);
        memcpy(out + NONCE_LEN + plain_len, tag, TAG_LEN);
        *out_len = NONCE_LEN + plain_len + TAG_LEN;
        result = 0;
    }

    EVP_CIPHER_CTX_free(ctx);
    return result;
}

int vez_hkdf(const uint8_t* ikm, size_t ikm_len,
             const uint8_t* salt, size_t salt_len,
             const uint8_t* info, size_t info_len,
             uint8_t* out, size_t out_len) {
    EVP_PKEY_CTX* ctx = EVP_PKEY_CTX_new_id(EVP_PKEY_HKDF, NULL);
    if (!ctx) return -1;

    int result = -1;
    size_t len = out_len;

    if (EVP_PKEY_derive_init(ctx) == 1 &&
        EVP_PKEY_CTX_set_hkdf_md(ctx, EVP_sha256()) == 1 &&
        EVP_PKEY_CTX_set1_hkdf_salt(ctx, salt, (int)salt_len) == 1 &&
        EVP_PKEY_CTX_set1_hkdf_key(ctx, ikm, (int)ikm_len) == 1 &&
        EVP_PKEY_CTX_add1_hkdf_info(ctx, info, (int)info_len) == 1 &&
        EVP_PKEY_derive(ctx, out, &len) == 1) {
        result = 0;
    }

    EVP_PKEY_CTX_free(ctx);
    return result;
}

void vez_random(uint8_t* buf, size_t len) {
    RAND_bytes(buf, (int)len);
}
