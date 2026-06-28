/*
 * vezoo.c — Pure C AES-256-GCM + HKDF-SHA256
 * بدون هیچ dependency خارجی — فقط C99 standard library
 */
#include "vezoo.h"
#include <string.h>
#include <stdlib.h>
#include <stdio.h>

/* ═══════════════════════════════════════════════════════
 *  AES-256 Implementation (FIPS 197)
 * ═══════════════════════════════════════════════════════ */
static const uint8_t sbox[256] = {
    0x63,0x7c,0x77,0x7b,0xf2,0x6b,0x6f,0xc5,0x30,0x01,0x67,0x2b,0xfe,0xd7,0xab,0x76,
    0xca,0x82,0xc9,0x7d,0xfa,0x59,0x47,0xf0,0xad,0xd4,0xa2,0xaf,0x9c,0xa4,0x72,0xc0,
    0xb7,0xfd,0x93,0x26,0x36,0x3f,0xf7,0xcc,0x34,0xa5,0xe5,0xf1,0x71,0xd8,0x31,0x15,
    0x04,0xc7,0x23,0xc3,0x18,0x96,0x05,0x9a,0x07,0x12,0x80,0xe2,0xeb,0x27,0xb2,0x75,
    0x09,0x83,0x2c,0x1a,0x1b,0x6e,0x5a,0xa0,0x52,0x3b,0xd6,0xb3,0x29,0xe3,0x2f,0x84,
    0x53,0xd1,0x00,0xed,0x20,0xfc,0xb1,0x5b,0x6a,0xcb,0xbe,0x39,0x4a,0x4c,0x58,0xcf,
    0xd0,0xef,0xaa,0xfb,0x43,0x4d,0x33,0x85,0x45,0xf9,0x02,0x7f,0x50,0x3c,0x9f,0xa8,
    0x51,0xa3,0x40,0x8f,0x92,0x9d,0x38,0xf5,0xbc,0xb6,0xda,0x21,0x10,0xff,0xf3,0xd2,
    0xcd,0x0c,0x13,0xec,0x5f,0x97,0x44,0x17,0xc4,0xa7,0x7e,0x3d,0x64,0x5d,0x19,0x73,
    0x60,0x81,0x4f,0xdc,0x22,0x2a,0x90,0x88,0x46,0xee,0xb8,0x14,0xde,0x5e,0x0b,0xdb,
    0xe0,0x32,0x3a,0x0a,0x49,0x06,0x24,0x5c,0xc2,0xd3,0xac,0x62,0x91,0x95,0xe4,0x79,
    0xe7,0xc8,0x37,0x6d,0x8d,0xd5,0x4e,0xa9,0x6c,0x56,0xf4,0xea,0x65,0x7a,0xae,0x08,
    0xba,0x78,0x25,0x2e,0x1c,0xa6,0xb4,0xc6,0xe8,0xdd,0x74,0x1f,0x4b,0xbd,0x8b,0x8a,
    0x70,0x3e,0xb5,0x66,0x48,0x03,0xf6,0x0e,0x61,0x35,0x57,0xb9,0x86,0xc1,0x1d,0x9e,
    0xe1,0xf8,0x98,0x11,0x69,0xd9,0x8e,0x94,0x9b,0x1e,0x87,0xe9,0xce,0x55,0x28,0xdf,
    0x8c,0xa1,0x89,0x0d,0xbf,0xe6,0x42,0x68,0x41,0x99,0x2d,0x0f,0xb0,0x54,0xbb,0x16,
};
static const uint8_t rsbox[256] = {
    0x52,0x09,0x6a,0xd5,0x30,0x36,0xa5,0x38,0xbf,0x40,0xa3,0x9e,0x81,0xf3,0xd7,0xfb,
    0x7c,0xe3,0x39,0x82,0x9b,0x2f,0xff,0x87,0x34,0x8e,0x43,0x44,0xc4,0xde,0xe9,0xcb,
    0x54,0x7b,0x94,0x32,0xa6,0xc2,0x23,0x3d,0xee,0x4c,0x95,0x0b,0x42,0xfa,0xc3,0x4e,
    0x08,0x2e,0xa1,0x66,0x28,0xd9,0x24,0xb2,0x76,0x5b,0xa2,0x49,0x6d,0x8b,0xd1,0x25,
    0x72,0xf8,0xf6,0x64,0x86,0x68,0x98,0x16,0xd4,0xa4,0x5c,0xcc,0x5d,0x65,0xb6,0x92,
    0x6c,0x70,0x48,0x50,0xfd,0xed,0xb9,0xda,0x5e,0x15,0x46,0x57,0xa7,0x8d,0x9d,0x84,
    0x90,0xd8,0xab,0x00,0x8c,0xbc,0xd3,0x0a,0xf7,0xe4,0x58,0x05,0xb8,0xb3,0x45,0x06,
    0xd0,0x2c,0x1e,0x8f,0xca,0x3f,0x0f,0x02,0xc1,0xaf,0xbd,0x03,0x01,0x13,0x8a,0x6b,
    0x3a,0x91,0x11,0x41,0x4f,0x67,0xdc,0xea,0x97,0xf2,0xcf,0xce,0xf0,0xb4,0xe6,0x73,
    0x96,0xac,0x74,0x22,0xe7,0xad,0x35,0x85,0xe2,0xf9,0x37,0xe8,0x1c,0x75,0xdf,0x6e,
    0x47,0xf1,0x1a,0x71,0x1d,0x29,0xc5,0x89,0x6f,0xb7,0x62,0x0e,0xaa,0x18,0xbe,0x1b,
    0xfc,0x56,0x3e,0x4b,0xc6,0xd2,0x79,0x20,0x9a,0xdb,0xc0,0xfe,0x78,0xcd,0x5a,0xf4,
    0x1f,0xdd,0xa8,0x33,0x88,0x07,0xc7,0x31,0xb1,0x12,0x10,0x59,0x27,0x80,0xec,0x5f,
    0x60,0x51,0x7f,0xa9,0x19,0xb5,0x4a,0x0d,0x2d,0xe5,0x7a,0x9f,0x93,0xc9,0x9c,0xef,
    0xa0,0xe0,0x3b,0x4d,0xae,0x2a,0xf5,0xb0,0xc8,0xeb,0xbb,0x3c,0x83,0x53,0x99,0x61,
    0x17,0x2b,0x04,0x7e,0xba,0x77,0xd6,0x26,0xe1,0x69,0x14,0x63,0x55,0x21,0x0c,0x7d,
};
static const uint8_t rcon[11] = {0x00,0x01,0x02,0x04,0x08,0x10,0x20,0x40,0x80,0x1b,0x36};

#define NK 8
#define NR 14
static uint32_t ks[60];

static uint32_t subword(uint32_t w){
    return ((uint32_t)sbox[w>>24]<<24)|((uint32_t)sbox[(w>>16)&0xff]<<16)|
           ((uint32_t)sbox[(w>>8)&0xff]<<8)|(uint32_t)sbox[w&0xff];
}
static uint32_t rotword(uint32_t w){return (w<<8)|(w>>24);}
static uint8_t xtime(uint8_t x){return (x<<1)^((x>>7)*0x1b);}
static uint8_t mul(uint8_t x,uint8_t y){
    uint8_t r=0,t=x;
    for(int i=0;i<8;i++){if(y&1)r^=t;t=xtime(t);y>>=1;}
    return r;
}

static void aes_key_expand(const uint8_t* key){
    for(int i=0;i<NK;i++)
        ks[i]=(key[4*i]<<24)|(key[4*i+1]<<16)|(key[4*i+2]<<8)|key[4*i+3];
    for(int i=NK;i<4*(NR+1);i++){
        uint32_t t=ks[i-1];
        if(i%NK==0) t=subword(rotword(t))^((uint32_t)rcon[i/NK]<<24);
        else if(i%NK==4) t=subword(t);
        ks[i]=ks[i-NK]^t;
    }
}
static void add_rk(uint8_t b[16],int r){
    for(int i=0;i<4;i++){
        uint32_t k=ks[r*4+i];
        b[4*i]^=k>>24; b[4*i+1]^=(k>>16)&0xff;
        b[4*i+2]^=(k>>8)&0xff; b[4*i+3]^=k&0xff;
    }
}
static void sub_bytes(uint8_t b[16]){for(int i=0;i<16;i++)b[i]=sbox[b[i]];}
static void shift_rows(uint8_t b[16]){
    uint8_t t;
    t=b[1];b[1]=b[5];b[5]=b[9];b[9]=b[13];b[13]=t;
    t=b[2];b[2]=b[10];b[10]=t; t=b[6];b[6]=b[14];b[14]=t;
    t=b[15];b[15]=b[11];b[11]=b[7];b[7]=b[3];b[3]=t;
}
static void mix_cols(uint8_t b[16]){
    for(int i=0;i<4;i++){
        uint8_t *c=b+4*i,s0=c[0],s1=c[1],s2=c[2],s3=c[3];
        c[0]=mul(0x02,s0)^mul(0x03,s1)^s2^s3;
        c[1]=s0^mul(0x02,s1)^mul(0x03,s2)^s3;
        c[2]=s0^s1^mul(0x02,s2)^mul(0x03,s3);
        c[3]=mul(0x03,s0)^s1^s2^mul(0x02,s3);
    }
}
static void aes_encrypt_block(uint8_t b[16]){
    add_rk(b,0);
    for(int r=1;r<NR;r++){sub_bytes(b);shift_rows(b);mix_cols(b);add_rk(b,r);}
    sub_bytes(b); shift_rows(b); add_rk(b,NR);
}

/* ═══════════════════════════════════════════════════════
 *  SHA-256 (FIPS 180-4) — by Brad Conte, public domain
 * ═══════════════════════════════════════════════════════ */
#define RR(a,b) (((a)>>(b))|((a)<<(32-(b))))
#define CH(x,y,z) (((x)&(y))^(~(x)&(z)))
#define MAJ(x,y,z) (((x)&(y))^((x)&(z))^((y)&(z)))
#define EP0(x) (RR(x,2)^RR(x,13)^RR(x,22))
#define EP1(x) (RR(x,6)^RR(x,11)^RR(x,25))
#define SIG0(x) (RR(x,7)^RR(x,18)^((x)>>3))
#define SIG1(x) (RR(x,17)^RR(x,19)^((x)>>10))

static const uint32_t k256[64]={
    0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
    0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
    0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
    0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
    0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
    0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
    0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
    0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2,
};
typedef struct{uint8_t data[64];uint32_t len,blen,h[8];uint64_t bits;} SHA256;
static void sha256_init(SHA256*c){
    c->len=c->blen=c->bits=0;
    c->h[0]=0x6a09e667;c->h[1]=0xbb67ae85;c->h[2]=0x3c6ef372;c->h[3]=0xa54ff53a;
    c->h[4]=0x510e527f;c->h[5]=0x9b05688c;c->h[6]=0x1f83d9ab;c->h[7]=0x5be0cd19;
}
static void sha256_transform(SHA256*c,const uint8_t*d){
    uint32_t a,b,e,f,g,h,t1,t2,m[64];
    uint32_t ci=c->h[0],di=c->h[1];a=ci;b=di;
    uint32_t cc=c->h[2],dc=c->h[3];uint32_t ce=c->h[4],de=c->h[5];
    e=ce;f=de;g=c->h[6];h=c->h[7];
    a=c->h[0];b=c->h[1];uint32_t cv=c->h[2];uint32_t dv=c->h[3];
    e=c->h[4];f=c->h[5];g=c->h[6];h=c->h[7];
    for(int i=0;i<16;i++) m[i]=((uint32_t)d[i*4]<<24)|((uint32_t)d[i*4+1]<<16)|((uint32_t)d[i*4+2]<<8)|d[i*4+3];
    for(int i=16;i<64;i++) m[i]=SIG1(m[i-2])+m[i-7]+SIG0(m[i-15])+m[i-16];
    for(int i=0;i<64;i++){
        t1=h+EP1(e)+CH(e,f,g)+k256[i]+m[i];
        t2=EP0(a)+MAJ(a,b,cv);
        h=g;g=f;f=e;e=dv+t1;dv=cv;cv=b;b=a;a=t1+t2;
    }
    c->h[0]+=a;c->h[1]+=b;c->h[2]+=cv;c->h[3]+=dv;
    c->h[4]+=e;c->h[5]+=f;c->h[6]+=g;c->h[7]+=h;
}
static void sha256_update(SHA256*c,const uint8_t*d,size_t n){
    for(size_t i=0;i<n;i++){
        c->data[c->len++]=d[i];c->bits+=8;
        if(c->len==64){sha256_transform(c,c->data);c->len=0;}
    }
}
static void sha256_final(SHA256*c,uint8_t*h){
    uint32_t i=c->len;
    c->data[i++]=0x80;
    if(c->len<56){while(i<56)c->data[i++]=0;}
    else{while(i<64)c->data[i++]=0;sha256_transform(c,c->data);memset(c->data,0,56);i=56;}
    c->data[63]=c->bits;c->data[62]=c->bits>>8;c->data[61]=c->bits>>16;c->data[60]=c->bits>>24;
    c->data[59]=c->bits>>32;c->data[58]=c->bits>>40;c->data[57]=c->bits>>48;c->data[56]=c->bits>>56;
    sha256_transform(c,c->data);
    for(i=0;i<4;i++){
        h[i]=(c->h[0]>>(24-i*8))&0xff;h[i+4]=(c->h[1]>>(24-i*8))&0xff;
        h[i+8]=(c->h[2]>>(24-i*8))&0xff;h[i+12]=(c->h[3]>>(24-i*8))&0xff;
        h[i+16]=(c->h[4]>>(24-i*8))&0xff;h[i+20]=(c->h[5]>>(24-i*8))&0xff;
        h[i+24]=(c->h[6]>>(24-i*8))&0xff;h[i+28]=(c->h[7]>>(24-i*8))&0xff;
    }
}
static void sha256(const uint8_t*d,size_t n,uint8_t*h){SHA256 c;sha256_init(&c);sha256_update(&c,d,n);sha256_final(&c,h);}

/* ═══════════════════════════════════════════════════════
 *  HMAC-SHA256 (RFC 2104)
 * ═══════════════════════════════════════════════════════ */
static void hmac_sha256(const uint8_t*k,size_t kl,const uint8_t*d,size_t dl,uint8_t*out){
    uint8_t ko[32],ki[32],kpad[64],tmp[32];
    if(kl>64){sha256(k,kl,kpad);kl=32;}else{memcpy(kpad,k,kl);}
    memset(kpad+kl,0,64-kl);
    uint8_t ipad[64],opad[64];
    for(int i=0;i<64;i++){ipad[i]=kpad[i]^0x36;opad[i]=kpad[i]^0x5c;}
    SHA256 c;sha256_init(&c);sha256_update(&c,ipad,64);sha256_update(&c,d,dl);sha256_final(&c,tmp);
    sha256_init(&c);sha256_update(&c,opad,64);sha256_update(&c,tmp,32);sha256_final(&c,out);
    (void)ko;(void)ki;
}

/* ═══════════════════════════════════════════════════════
 *  HKDF-SHA256 (RFC 5869)
 * ═══════════════════════════════════════════════════════ */
int vez_hkdf(const uint8_t*ikm,size_t ikm_len,const uint8_t*salt,size_t salt_len,
             const uint8_t*info,size_t info_len,uint8_t*out,size_t out_len){
    if(out_len>32*255) return -1;
    /* Extract */
    uint8_t prk[32];
    if(!salt||salt_len==0){uint8_t s[32];memset(s,0,32);hmac_sha256(s,32,ikm,ikm_len,prk);}
    else hmac_sha256(salt,salt_len,ikm,ikm_len,prk);
    /* Expand */
    uint8_t prev[32],buf[128+1];size_t off=0;uint8_t ctr=1;
    memset(prev,0,32);
    while(off<out_len){
        size_t pl=(ctr==1)?0:32;
        memcpy(buf,prev,pl);memcpy(buf+pl,info,info_len);buf[pl+info_len]=ctr;
        hmac_sha256(prk,32,buf,pl+info_len+1,prev);
        size_t cp=32<(out_len-off)?32:(out_len-off);
        memcpy(out+off,prev,cp);off+=cp;ctr++;
    }
    return 0;
}

/* ═══════════════════════════════════════════════════════
 *  AES-GCM (NIST SP 800-38D)
 * ═══════════════════════════════════════════════════════ */
static void gcm_mult(uint8_t*z,const uint8_t*x,const uint8_t*y){
    uint8_t v[16],r[16];memset(r,0,16);memcpy(v,y,16);
    for(int i=0;i<16;i++){
        for(int j=7;j>=0;j--){
            if((x[i]>>j)&1){for(int k=0;k<16;k++)r[k]^=v[k];}
            uint8_t lsb=v[15]&1;
            for(int k=15;k>0;k--)v[k]=(v[k]>>1)|((v[k-1]&1)<<7);
            v[0]>>=1;if(lsb)v[0]^=0xe1;
        }
    }
    memcpy(z,r,16);
}
static void ghash(const uint8_t*h,const uint8_t*a,size_t al,const uint8_t*c,size_t cl,uint8_t*tag){
    uint8_t x[16];memset(x,0,16);
    /* AAD */
    for(size_t i=0;i<al;){
        uint8_t b[16];memset(b,0,16);size_t n=al-i<16?al-i:16;
        memcpy(b,a+i,n);for(int j=0;j<16;j++)x[j]^=b[j];gcm_mult(x,x,h);i+=n;
    }
    /* Ciphertext */
    for(size_t i=0;i<cl;){
        uint8_t b[16];memset(b,0,16);size_t n=cl-i<16?cl-i:16;
        memcpy(b,c+i,n);for(int j=0;j<16;j++)x[j]^=b[j];gcm_mult(x,x,h);i+=n;
    }
    /* Length */
    uint8_t len[16];uint64_t abl=(uint64_t)al*8,cbl=(uint64_t)cl*8;
    for(int i=0;i<8;i++){len[i]=(uint8_t)(abl>>(56-i*8));len[8+i]=(uint8_t)(cbl>>(56-i*8));}
    for(int i=0;i<16;i++)x[i]^=len[i];gcm_mult(x,x,h);
    memcpy(tag,x,16);
}
static void gctr(const uint32_t*rks,uint8_t*ctr_block,const uint8_t*in,uint8_t*out,size_t len){
    size_t n=len/16,r=len%16;
    for(size_t i=0;i<n;i++){
        uint8_t ks[16];memcpy(ks,ctr_block,16);aes_encrypt_block(ks);
        for(int j=0;j<16;j++)out[i*16+j]=in[i*16+j]^ks[j];
        for(int j=15;j>=12;j--){ctr_block[j]++;if(ctr_block[j])break;}
    }
    if(r){uint8_t ks[16];memcpy(ks,ctr_block,16);aes_encrypt_block(ks);for(size_t j=0;j<r;j++)out[n*16+j]=in[n*16+j]^ks[j];}
    (void)rks;
}

static int gcm_crypt(const uint8_t*key,const uint8_t*iv,const uint8_t*in,uint8_t*out,size_t len,uint8_t*tag,int enc){
    aes_key_expand(key);
    /* H = E(K, 0^128) */
    uint8_t h[16];memset(h,0,16);aes_encrypt_block(h);
    /* J0 */
    uint8_t j0[16];memcpy(j0,iv,12);j0[12]=0;j0[13]=0;j0[14]=0;j0[15]=1;
    /* Counter start = inc(J0) */
    uint8_t ctr[16];memcpy(ctr,j0,16);ctr[15]++;
    gctr(ks,ctr,in,out,len);
    /* Tag = GHASH ⊕ E(J0) */
    uint8_t t[16];
    if(enc) ghash(h,NULL,0,out,len,t);
    else    ghash(h,NULL,0,in,len,t);
    uint8_t ej0[16];memcpy(ej0,j0,16);aes_encrypt_block(ej0);
    for(int i=0;i<16;i++)tag[i]=t[i]^ej0[i];
    return 0;
}

/* ═══════════════════════════════════════════════════════
 *  Public API
 * ═══════════════════════════════════════════════════════ */
#define NONCE 12
#define TAG   16

int vez_gcm_encrypt(const uint8_t*key,size_t kl,const uint8_t*plain,size_t pl,uint8_t*out,size_t*out_len){
    if(kl!=32||!key||!plain||!out||!out_len) return -1;
    vez_random(out,NONCE);
    uint8_t tag[TAG];
    gcm_crypt(key,out,plain,out+NONCE,pl,tag,1);
    memcpy(out+NONCE+pl,tag,TAG);
    *out_len=NONCE+pl+TAG;
    return 0;
}

int vez_gcm_decrypt(const uint8_t*key,size_t kl,const uint8_t*data,size_t dl,uint8_t*out,size_t*out_len){
    if(kl!=32||!key||!data||!out||!out_len) return -1;
    if(dl<NONCE+TAG) return -1;
    size_t cl=dl-NONCE-TAG;
    const uint8_t*iv=data,*ct=data+NONCE,*tag=data+NONCE+cl;
    uint8_t computed[TAG];
    gcm_crypt(key,iv,ct,out,cl,computed,0);
    /* Verify tag */
    uint8_t diff=0;for(int i=0;i<TAG;i++)diff|=tag[i]^computed[i];
    if(diff){memset(out,0,cl);return -1;}
    *out_len=cl;
    return 0;
}

void vez_random(uint8_t*buf,size_t len){
    FILE*f=fopen("/dev/urandom","rb");
    if(f){fread(buf,1,len,f);fclose(f);}
    else memset(buf,0xAB,len);
}
