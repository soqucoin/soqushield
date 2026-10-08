/**
 * dilithium_ffi.c — Thin FFI wrapper around the Soqucoin Dilithium C library.
 *
 * Exports functions callable via dart:ffi for ML-DSA-44 (FIPS 204)
 * key generation, signing, and verification. Uses the EXACT same C code
 * as the Soqucoin node to ensure byte-for-byte signature compatibility.
 */

#include "sign.h"
#include "api.h"
#include "params.h"
#include <string.h>

/* ---- Key generation from seed ---- */
int soq_dilithium_keypair_from_seed(
    uint8_t *pk,    /* out: CRYPTO_PUBLICKEYBYTES (1312) */
    uint8_t *sk,    /* out: CRYPTO_SECRETKEYBYTES (2560) */
    const uint8_t *seed,  /* in: 32 bytes */
    int seed_len)
{
    if (seed_len != 32) return -1;
    return crypto_sign_seed_keypair(pk, sk, seed);
}

/* ---- Random key generation ---- */
int soq_dilithium_keypair(
    uint8_t *pk,    /* out: CRYPTO_PUBLICKEYBYTES (1312) */
    uint8_t *sk)    /* out: CRYPTO_SECRETKEYBYTES (2560) */
{
    return crypto_sign_keypair(pk, sk);
}

/* ---- Sign message ---- */
int soq_dilithium_sign(
    uint8_t *sig,           /* out: CRYPTO_BYTES (2420) */
    size_t  *siglen,        /* out: actual sig length */
    const uint8_t *msg,     /* in: message bytes */
    size_t  msglen,         /* in: message length */
    const uint8_t *sk)      /* in: CRYPTO_SECRETKEYBYTES */
{
    /* ctx=NULL, ctxlen=0 — matches the node's calling convention */
    return crypto_sign_signature(sig, siglen, msg, msglen, NULL, 0, sk);
}

/* ---- Verify signature ---- */
int soq_dilithium_verify(
    const uint8_t *sig,     /* in: CRYPTO_BYTES (2420) */
    size_t  siglen,         /* in: sig length */
    const uint8_t *msg,     /* in: message bytes */
    size_t  msglen,         /* in: message length */
    const uint8_t *pk)      /* in: CRYPTO_PUBLICKEYBYTES */
{
    return crypto_sign_verify(sig, siglen, msg, msglen, NULL, 0, pk);
}

/* ---- Constants for Dart side ---- */
int soq_dilithium_pk_bytes(void)  { return CRYPTO_PUBLICKEYBYTES; }
int soq_dilithium_sk_bytes(void)  { return CRYPTO_SECRETKEYBYTES; }
int soq_dilithium_sig_bytes(void) { return CRYPTO_BYTES; }
