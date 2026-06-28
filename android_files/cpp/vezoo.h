#ifndef VEZOO_H
#define VEZOO_H
#include <stdint.h>
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif

/* AES-256-GCM رمزگشایی
 * data = nonce(12) + ciphertext + tag(16)
 * برمیگردونه: 0 موفق، -1 خطا
 */
int vez_gcm_decrypt(const uint8_t* key,   size_t key_len,
                    const uint8_t* data,  size_t data_len,
                    uint8_t*       out,   size_t* out_len);

/* AES-256-GCM رمزگذاری
 * برمیگردونه: nonce(12) + ciphertext + tag(16)
 */
int vez_gcm_encrypt(const uint8_t* key,   size_t key_len,
                    const uint8_t* plain, size_t plain_len,
                    uint8_t*       out,   size_t* out_len);

/* HKDF-SHA256 */
int vez_hkdf(const uint8_t* ikm,  size_t ikm_len,
             const uint8_t* salt, size_t salt_len,
             const uint8_t* info, size_t info_len,
             uint8_t* out, size_t out_len);

/* random bytes */
void vez_random(uint8_t* buf, size_t len);

#ifdef __cplusplus
}
#endif
#endif
