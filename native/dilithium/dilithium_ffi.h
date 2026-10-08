/**
 * dilithium_ffi.h — Public header for SoquShield Dilithium FFI.
 *
 * Exports functions callable via dart:ffi for ML-DSA-44 (FIPS 204)
 * key generation, signing, and verification.
 */

#ifndef DILITHIUM_FFI_H
#define DILITHIUM_FFI_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Key generation from 32-byte seed */
int soq_dilithium_keypair_from_seed(
    uint8_t *pk,
    uint8_t *sk,
    const uint8_t *seed,
    int seed_len);

/* Random key generation */
int soq_dilithium_keypair(
    uint8_t *pk,
    uint8_t *sk);

/* Sign message */
int soq_dilithium_sign(
    uint8_t *sig,
    size_t  *siglen,
    const uint8_t *msg,
    size_t  msglen,
    const uint8_t *sk);

/* Verify signature */
int soq_dilithium_verify(
    const uint8_t *sig,
    size_t  siglen,
    const uint8_t *msg,
    size_t  msglen,
    const uint8_t *pk);

/* Constants */
int soq_dilithium_pk_bytes(void);
int soq_dilithium_sk_bytes(void);
int soq_dilithium_sig_bytes(void);

#ifdef __cplusplus
}
#endif

#endif /* DILITHIUM_FFI_H */
