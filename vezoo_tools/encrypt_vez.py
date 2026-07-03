#!/usr/bin/env python3
"""
Vezoo File Encryptor v1.0
رمزگذاری فایل با فرمت .vez

نصب: pip install cryptography
استفاده: python encrypt_vez.py <input_file> <server_half_base64> [output.vez]

مثال:
  # گرفتن server_half از سرور:
  curl https://player.lastofanarchy.workers.dev/master-half

  # رمزگذاری:
  python encrypt_vez.py video.mkv ABC123base64==
  python encrypt_vez.py subtitle.srt ABC123base64== sub.vez
"""

import os, sys, json, struct, base64
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.hkdf import HKDF
from cryptography.hazmat.primitives import hashes

# ── ثابت‌ها — باید با اپ یکی باشن ──
MAGIC      = b'VEZOO\x01'
ALGO_GCM   = 0x01
CHUNK_SIZE = 5 * 1024 * 1024  # 5MB

# این باید با Kotlin یکی باشه — تغییر نده
APP_HALF   = bytes([
    0x56,0x45,0x5A,0x4F,0x4F,0x5F,0x41,0x50,
    0x50,0x5F,0x48,0x41,0x4C,0x46,0x5F,0x32,
    0x30,0x32,0x34,0x5F,0x56,0x31,0x5F,0x53,
    0x45,0x43,0x52,0x45,0x54,0x21,0x21,0x21,
])  # VEZOO_APP_HALF_2024_V1_SECRET!!!

SALT = b'vezoo-master-salt-v1'
INFO = b'vezoo-master-key-v1'

MIME = {
    'mkv':'video/x-matroska','mp4':'video/mp4','avi':'video/x-msvideo',
    'mov':'video/quicktime','wmv':'video/x-ms-wmv','ts':'video/mp2t',
    'srt':'text/plain','vtt':'text/vtt','ass':'text/plain','ssa':'text/plain',
    'mp3':'audio/mpeg','aac':'audio/aac','flac':'audio/flac','m4a':'audio/mp4',
}

def derive_master_key(server_half_b64: str) -> bytes:
    """Master Key = HKDF(Server_Half + App_Half)"""
    server_half = base64.b64decode(server_half_b64)
    hkdf = HKDF(algorithm=hashes.SHA256(), length=32, salt=SALT, info=INFO)
    return hkdf.derive(server_half + APP_HALF)

def gcm_encrypt(key: bytes, data: bytes) -> bytes:
    """AES-256-GCM → nonce(12) + ciphertext + tag(16)"""
    nonce = os.urandom(12)
    return nonce + AESGCM(key).encrypt(nonce, data, None)

def encrypt_vez(input_path: str, server_half_b64: str, output_path: str = None):
    if output_path is None:
        output_path = os.path.splitext(input_path)[0] + '.vez'

    master_key = derive_master_key(server_half_b64)

    # File Key تصادفی — هر فایل متفاوت
    file_key = os.urandom(32)
    enc_file_key = gcm_encrypt(master_key, file_key)

    ext = os.path.splitext(input_path)[1].lstrip('.').lower()
    file_size = os.path.getsize(input_path)

    # رمزگذاری chunk به chunk
    chunks = []
    with open(input_path, 'rb') as f:
        while True:
            data = f.read(CHUNK_SIZE)
            if not data: break
            chunks.append(gcm_encrypt(file_key, data))

    # metadata
    meta = json.dumps({
        'original_ext': ext,
        'original_type': MIME.get(ext, 'application/octet-stream'),
        'original_size': file_size,
        'chunk_size': CHUNK_SIZE,
        'chunk_count': len(chunks),
    }).encode('utf-8')
    enc_meta = gcm_encrypt(file_key, meta)

    # نوشتن فایل .vez
    with open(output_path, 'wb') as f:
        f.write(MAGIC)                                    # magic
        f.write(bytes([ALGO_GCM]))                        # algo
        f.write(struct.pack('>I', len(enc_file_key)))
        f.write(enc_file_key)                             # encrypted file key
        f.write(struct.pack('>I', len(enc_meta)))
        f.write(enc_meta)                                 # encrypted metadata
        for chunk in chunks:
            f.write(struct.pack('>I', len(chunk)))
            f.write(chunk)                                # encrypted chunks

    orig_mb = file_size / 1024 / 1024
    out_mb  = os.path.getsize(output_path) / 1024 / 1024
    print(f"✓ رمزگذاری موفق:")
    print(f"  ورودی:  {os.path.basename(input_path)} ({orig_mb:.1f} MB)")
    print(f"  خروجی: {os.path.basename(output_path)} ({out_mb:.1f} MB)")
    print(f"  فرمت: {ext.upper()} | chunks: {len(chunks)}")

if __name__ == '__main__':
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)
    encrypt_vez(sys.argv[1], sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else None)
