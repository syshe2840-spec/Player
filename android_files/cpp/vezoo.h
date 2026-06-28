#ifndef VEZOO_H
#define VEZOO_H
#include <stdint.h>
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif
int vez_gcm_encrypt(const uint8_t* key, size_t key_len,
                    const uint8_t* plain, size_t plain_len,
                    uint8_t* out, size_t* out_len);
int vez_gcm_decrypt(const uint8_t* key, size_t key_len,
                    const uint8_t* data, size_t data_len,
                    uint8_t* out, size_t* out_len);
int vez_hkdf(const uint8_t* ikm, size_t ikm_len,
             const uint8_t* salt, size_t salt_len,
             const uint8_t* info, size_t info_len,
             uint8_t* out, size_t out_len);
void vez_random(uint8_t* buf, size_t len);
#ifdef __cplusplus
}
#endif
#endif
