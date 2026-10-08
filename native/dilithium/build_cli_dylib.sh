#!/usr/bin/env bash
# Build the dilithium_soq ML-DSA-44 dylib for a Dart CLI harness (macOS).
# Same C as the node (src/crypto/dilithium) → byte-compatible sign/verify.
# Used by soqushield_sdk/test/dilithium_native_interop_test.dart.
set -euo pipefail
cd "$(dirname "$0")"
clang -O2 -fPIC -shared -o libdilithium_soq.dylib \
  dilithium_ffi.c sign.c packing.c polyvec.c poly.c ntt.c reduce.c rounding.c \
  fips202.c symmetric-shake.c randombytes.c -I.
echo "built $(pwd)/libdilithium_soq.dylib"
