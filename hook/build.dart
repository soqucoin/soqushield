/// Native assets build hook for SoquShield.
///
/// Compiles the Soqucoin node's FIPS 204 ML-DSA-44 (Dilithium) C library
/// into a native dynamic library that is bundled with the Flutter app.
/// This ensures byte-for-byte cryptographic compatibility with the node.
///
/// The C sources are copied from soqucoin-build/src/crypto/dilithium/ and
/// include the FIPS 204 context prefix, 64-byte tr, and 64-byte CRH that
/// the pub.dev `dilithium_crypto` Dart package does NOT implement.
library;

import 'dart:io' show stderr;
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    final cBuilder = CBuilder.library(
      name: 'dilithium_soq',
      assetName: 'dilithium_ffi_bindings.dart',
      sources: [
        'native/dilithium/fips202.c',
        'native/dilithium/ntt.c',
        'native/dilithium/packing.c',
        'native/dilithium/poly.c',
        'native/dilithium/polyvec.c',
        'native/dilithium/reduce.c',
        'native/dilithium/rounding.c',
        'native/dilithium/sign.c',
        'native/dilithium/symmetric-shake.c',
        'native/dilithium/randombytes.c',
        'native/dilithium/dilithium_ffi.c',
      ],
      includes: [
        'native/dilithium/',
      ],
      defines: {
        'DILITHIUM_MODE': '2', // ML-DSA-44 (security level 2)
      },
    );

    await cBuilder.run(
      input: input,
      output: output,
      logger: Logger('')
        ..level = Level.ALL
        ..onRecord.listen((record) => stderr.writeln(record.message)),
    );
  });
}
