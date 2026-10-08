import 'dart:typed_data';
import 'package:bip39/bip39.dart' as bip39;
import 'package:hashlib/hashlib.dart';
import 'package:pointycastle/export.dart';
import '../crypto/dilithium_ffi_bindings.dart';
import '../models/wallet_keys.dart';

/// Core cryptographic service for the SoquShield PQ wallet.
///
/// Implements the complete key lifecycle using ML-DSA-44 (Dilithium Level 2):
///   BIP-39 mnemonic → PBKDF2 → 64-byte seed → HKDF-SHA256 → 32-byte Dilithium seed
///   → ML-DSA-44 keygen → 1312-byte pubkey → SHA-256 → 32-byte witness → Bech32m address
///
/// HKDF parameters match audited C++ pqderive.cpp (Halborn-reviewed):
///   Salt = SHA-256(masterSeed) — 256-bit pseudorandom (RFC 5869 §3.1)
///   Info = "soqucoin-pqwallet-v1" || PathToBytes(path) — domain-separated
///
/// Wire-compatible with soqucoin-build/src/wallet/pqwallet/pqderive.cpp
/// Patent: SOQ-P003 (Pure-Dart ML-DSA Mobile Wallet)
class KeyService {
  /// Generate a new 24-word BIP-39 mnemonic seed phrase.
  SeedPhrase generateMnemonic() {
    // 256 bits of entropy → 24 words
    final mnemonic = bip39.generateMnemonic(strength: 256);
    return SeedPhrase(words: mnemonic.split(' '));
  }

  /// Validate a mnemonic seed phrase.
  bool validateMnemonic(String mnemonic) {
    return bip39.validateMnemonic(mnemonic);
  }

  /// Derive a wallet keypair from a mnemonic seed phrase.
  ///
  /// Derivation chain:
  /// 1. BIP-39 mnemonic → PBKDF2(mnemonic, "mnemonic" + passphrase) → 64-byte master seed
  /// 2. HKDF-SHA256(master seed, info="m/44'/21329'/0'/0/{index}") → 32-byte Dilithium seed
  /// 3. Dilithium.generateKeyPair(LEVEL2, seed) → KeyPair
  /// 4. SHA-256(pubkey) → 32-byte witness → Bech32m address
  Future<WalletKeys> deriveFromMnemonic(
    SeedPhrase phrase, {
    SoqNetwork network = SoqNetwork.stagenet,
    int accountIndex = 0,
    String passphrase = '',
  }) async {
    // Step 1: BIP-39 → 64-byte master seed
    final masterSeedRaw = bip39.mnemonicToSeed(phrase.mnemonic, passphrase: passphrase);
    final masterSeed = Uint8List.fromList(masterSeedRaw);

    try {
      // Steps 2-3: HKDF-SHA256 → 32-byte Dilithium seed → FIPS 204 ML-DSA-44
      // keygen via native C FFI (the EXACT same C code as the Soqucoin node),
      // re-deriving past the node's 0xFF invalid-key marker (maxDeriveRetries).
      final (pubKeyBytes, secretKey) = _deriveKeyPairWithRetry(masterSeed, accountIndex);

      // A4-05: Zero the discarded secretKey immediately.
      // In deriveFromMnemonic we only need the pubkey for address derivation.
      secretKey.fillRange(0, secretKey.length, 0);

      // Step 4: Address derivation
      final address = deriveAddress(pubKeyBytes, network);
      final path = "m/44'/${WalletKeys.coinType}'/0'/0/$accountIndex";

      return WalletKeys(
        publicKey: pubKeyBytes,
        address: address,
        derivationPath: path,
        accountIndex: accountIndex,
        createdAt: DateTime.now(),
      );
    } finally {
      // A4-01: the 32-byte Dilithium seed is zeroed inside
      // _deriveKeyPairWithRetry as soon as the keypair exists.
      // A4-02: Zero masterSeed — the 64-byte BIP-39 seed derives ALL keys
      // for ALL accounts. This is the ultimate crown jewel.
      masterSeed.fillRange(0, masterSeed.length, 0);
    }
  }

  /// Derive the native FIPS 204 key pair for transaction signing.
  ///
  /// Returns `(publicKey, secretKey)` as raw byte arrays.
  /// SECURITY: The returned secret key is 2560 bytes.
  /// Callers MUST NOT persist or log it.
  /// The secret key should be used for signing and then zeroed.
  Future<(Uint8List publicKey, Uint8List secretKey)> deriveNativeKeyPair(
    SeedPhrase phrase, {
    SoqNetwork network = SoqNetwork.stagenet,
    int accountIndex = 0,
    String passphrase = '',
  }) async {
    final masterSeedRaw = bip39.mnemonicToSeed(phrase.mnemonic, passphrase: passphrase);
    final masterSeed = Uint8List.fromList(masterSeedRaw);
    try {
      return _deriveKeyPairWithRetry(masterSeed, accountIndex);
    } finally {
      // A4-01/A4-02: the Dilithium seed is zeroed in _deriveKeyPairWithRetry;
      // zero the master seed here.
      masterSeed.fillRange(0, masterSeed.length, 0);
    }
  }

  /// Sign a message hash with the native FIPS 204 ML-DSA-44 implementation.
  ///
  /// Signs the 32-byte SHA256d transaction hash (sighash).
  /// Returns a 2420-byte ML-DSA-44 signature.
  ///
  /// Uses the EXACT same C code as soqucoin-build/src/crypto/dilithium/sign.c
  /// ensuring byte-for-byte compatibility with the node's verify.
  /// The C library internally applies the FIPS 204 context prefix
  /// (pre = [0x00, 0x00]) and uses 64-byte tr.
  Uint8List signNative(Uint8List secretKey, Uint8List messageHash) {
    final native = DilithiumNative.instance;
    final signature = native.sign(messageHash, secretKey);
    assert(signature.length == WalletKeys.signatureSize,
      'Expected ${WalletKeys.signatureSize} byte signature, got ${signature.length}');
    return signature;
  }

  /// Verify a signature using the native FIPS 204 ML-DSA-44 implementation.
  bool verifyNative(
    Uint8List publicKey,
    Uint8List signature,
    Uint8List messageHash,
  ) {
    final native = DilithiumNative.instance;
    return native.verify(signature, messageHash, publicKey);
  }

  /// Derive a Bech32m address from a Dilithium public key.
  ///
  /// Pipeline: pubkey (1312 bytes) → SHA-256 → 32-byte hash
  ///   → witness v1 (OP_1 <32-byte-hash>) → Bech32m encode
  ///
  /// Compatible with: soqucoin-build/src/wallet/rpcwallet.cpp:142-148
  /// (getnewaddress → CSHA256 → WitnessV1ScriptHash → EncodeDestination)
  ///
  /// NOTE: The PQ wallet module (pqaddress.h) uses BLAKE2b-160 (20 bytes)
  /// but the consensus-active path uses SHA-256 (32 bytes). We MUST match
  /// the consensus path or sendtoaddress/validateaddress will reject our
  /// addresses. See SOQ-INFRA-009 in SECURITY_ISSUE_REGISTRY.md.
  String deriveAddress(Uint8List publicKey, SoqNetwork network) {
    assert(publicKey.length == WalletKeys.pubKeySize,
      'Expected ${WalletKeys.pubKeySize} byte public key, got ${publicKey.length}');

    // SHA-256 hash of public key (matches C++ CSHA256 in rpcwallet.cpp:143)
    final hash = sha256.convert(publicKey);
    final hashBytes = Uint8List.fromList(hash.bytes);

    // Encode as Bech32m witness v1 (32-byte program)
    return _encodeBech32m(hashBytes, network.hrp);
  }

  // ─── Private Helpers ───

  /// Domain separator for wallet key derivation (Whitepaper §10.4)
  static const String _domainWallet = 'soqucoin-pqwallet-v1';

  /// Build the HKDF info field: domain || PathToBytes(m/44'/21329'/0'/0/index)
  /// Matches C++ pqderive.cpp DeriveKeyMaterial() L200-203.
  /// Invalid-marker retry rule, shared with the node (pqderive.h,
  /// MAX_DERIVE_RETRIES) and soqushield_sdk. The node's CPubKey treats a public
  /// key whose first byte is 0xFF as its invalid-key sentinel: one path in 256
  /// derives a key whose address receives and can never spend. Retry 0 is the
  /// unchanged derivation (info = domain || path bytes); retry r >= 1 appends a
  /// single byte r to the HKDF info; the first key not starting with 0xFF is THE
  /// key for that path. Existing valid keys and addresses are unaffected.
  static const int maxDeriveRetries = 8;

  Uint8List _buildDeriveInfo(int accountIndex, {int retry = 0}) {
    final domainBytes = Uint8List.fromList(_domainWallet.codeUnits);
    final pathBytesArr = _pathToBytes(44, WalletKeys.coinType, 0, 0, accountIndex);
    final info = Uint8List(domainBytes.length + pathBytesArr.length + (retry > 0 ? 1 : 0));
    info.setRange(0, domainBytes.length, domainBytes);
    info.setRange(domainBytes.length, domainBytes.length + pathBytesArr.length, pathBytesArr);
    if (retry > 0) info[info.length - 1] = retry;
    return info;
  }

  /// Derive the ML-DSA-44 key pair for [accountIndex], applying the
  /// invalid-marker retry rule. Returns (publicKey, secretKey); the caller owns
  /// zeroing the secret key.
  (Uint8List, Uint8List) _deriveKeyPairWithRetry(Uint8List masterSeed, int accountIndex) {
    final native = DilithiumNative.instance;
    for (var retry = 0; retry <= maxDeriveRetries; retry++) {
      final dilithiumSeed = _hkdfDerive(masterSeed, _buildDeriveInfo(accountIndex, retry: retry));
      try {
        final (pk, sk) = native.keypairFromSeed(dilithiumSeed);
        if (pk[0] != 0xFF) return (pk, sk);
        sk.fillRange(0, sk.length, 0); // the marker key is discarded
      } finally {
        dilithiumSeed.fillRange(0, dilithiumSeed.length, 0);
      }
    }
    throw StateError('key derivation produced only invalid-marker keys for index $accountIndex');
  }

  /// Serialize BIP44 derivation path as 20 bytes (5 × 4-byte big-endian uint32).
  /// Hardened bit (0x80000000) set on purpose/coinType/account.
  /// Matches C++ pqderive.cpp PathToBytes().
  Uint8List _pathToBytes(int purpose, int coinType, int account, int change, int index) {
    final buf = Uint8List(20);
    final bd = ByteData.view(buf.buffer);
    bd.setUint32(0, (purpose | 0x80000000) & 0xFFFFFFFF);   // Hardened
    bd.setUint32(4, (coinType | 0x80000000) & 0xFFFFFFFF);  // Hardened
    bd.setUint32(8, (account | 0x80000000) & 0xFFFFFFFF);   // Hardened
    bd.setUint32(12, change);                                // Not hardened
    bd.setUint32(16, index);                                 // Not hardened
    return buf;
  }

  /// SB-2: Derive the deterministic XMSS vault seed from the BIP-39 master seed
  /// so the quantum vault is recoverable from the 24-word mnemonic alone. Same
  /// HKDF-SHA256 construction as the Dilithium derivation, but a DISTINCT domain
  /// so the vault seed is independent of every account/Dilithium key.
  static Uint8List deriveXmssVaultSeed(Uint8List masterSeed) {
    final info = Uint8List.fromList('soqucoin-xmss-vault-v1'.codeUnits);

    // Salt = SHA-256(masterSeed); HKDF-Extract: PRK = HMAC-SHA256(salt, masterSeed)
    final salt = Uint8List.fromList(sha256.convert(masterSeed).bytes);
    final extract = HMac(SHA256Digest(), 64)..init(KeyParameter(salt));
    final prk = Uint8List(32);
    extract.update(masterSeed, 0, masterSeed.length);
    extract.doFinal(prk, 0);

    // HKDF-Expand: OKM = HMAC-SHA256(PRK, info || 0x01)
    final expandInput = Uint8List(info.length + 1);
    expandInput.setRange(0, info.length, info);
    expandInput[info.length] = 0x01;
    final expand = HMac(SHA256Digest(), 64)..init(KeyParameter(prk));
    final okm = Uint8List(32);
    expand.update(expandInput, 0, expandInput.length);
    expand.doFinal(okm, 0);

    prk.fillRange(0, prk.length, 0); // zero the PRK
    return okm;
  }

  /// HKDF-SHA256 key derivation.
  /// Extracts 32 bytes suitable as a Dilithium seed.
  ///
  /// Matches audited C++ pqderive.cpp DeriveKeyMaterial():
  ///   Salt = SHA-256(masterSeed) — 256-bit pseudorandom (RFC 5869 §3.1)
  ///   PRK = HMAC-SHA256(salt, masterSeed)
  ///   OKM = HMAC-SHA256(PRK, info || 0x01)
  Uint8List _hkdfDerive(Uint8List masterSeed, Uint8List info) {
    // Salt = SHA-256(masterSeed) — matches pqderive.cpp L193-198
    final saltHash = sha256.convert(masterSeed);
    final salt = Uint8List.fromList(saltHash.bytes);

    // HKDF-Extract: PRK = HMAC-SHA256(salt, masterSeed)
    final hmacExtract = HMac(SHA256Digest(), 64)
      ..init(KeyParameter(salt));
    final prk = Uint8List(32);
    hmacExtract.update(masterSeed, 0, masterSeed.length);
    hmacExtract.doFinal(prk, 0);

    // HKDF-Expand: OKM = HMAC-SHA256(PRK, info || 0x01)
    final expandInput = Uint8List(info.length + 1);
    expandInput.setRange(0, info.length, info);
    expandInput[info.length] = 0x01;

    final hmacExpand = HMac(SHA256Digest(), 64)
      ..init(KeyParameter(prk));
    final okm = Uint8List(32);
    hmacExpand.update(expandInput, 0, expandInput.length);
    hmacExpand.doFinal(okm, 0);

    // A5-04: Zero the PRK — it can re-derive Dilithium seeds for any
    // account index if leaked from heap.
    prk.fillRange(0, prk.length, 0);

    return okm;
  }

  /// Bech32m encoding.
  ///
  /// Format: [HRP]1[witness_version_5bit][witness_program_5bit][checksum]
  ///
  /// Matches C++ EncodeDestination() which produces:
  ///   witness_version = 1 (OP_1 → Dilithium)
  ///   witness_program = 32-byte SHA-256 hash of pubkey
  ///
  /// Compatible with DecodeDestination() in utiladdress.cpp:73
  /// which requires conv.size() == 32.
  String _encodeBech32m(Uint8List witnessProgram, String hrp) {
    assert(witnessProgram.length == 32,
      'Witness program must be 32 bytes (SHA-256), got ${witnessProgram.length}');

    // Witness version 1 (Dilithium) as first 5-bit value
    // Then convert the 32-byte witness program from 8-bit to 5-bit groups
    final converted = <int>[1] + _convertBits(witnessProgram, 8, 5, true);

    // Bech32m encode
    return _bech32mEncode(hrp, converted);
  }

  /// Convert between bit groups (e.g., 8→5 for Bech32)
  List<int> _convertBits(Uint8List data, int fromBits, int toBits, bool pad) {
    int acc = 0;
    int bits = 0;
    final ret = <int>[];
    final maxv = (1 << toBits) - 1;

    for (final value in data) {
      acc = (acc << fromBits) | value;
      bits += fromBits;
      while (bits >= toBits) {
        bits -= toBits;
        ret.add((acc >> bits) & maxv);
      }
    }
    if (pad && bits > 0) {
      ret.add((acc << (toBits - bits)) & maxv);
    }
    return ret;
  }

  /// Bech32m encoding implementation.
  /// Constant: 0x2bc830a3 (Bech32m) vs 1 (Bech32)
  String _bech32mEncode(String hrp, List<int> data) {
    const bech32mConst = 0x2bc830a3;
    const charset = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l';

    final values = _bech32HrpExpand(hrp) + data;
    final polymod = _bech32Polymod(values + [0, 0, 0, 0, 0, 0]) ^ bech32mConst;

    final checksum = List<int>.generate(6, (i) => (polymod >> (5 * (5 - i))) & 31);

    final combined = data + checksum;
    return '$hrp${1}${combined.map((d) => charset[d]).join()}';
  }

  List<int> _bech32HrpExpand(String hrp) {
    final ret = <int>[];
    for (final c in hrp.codeUnits) {
      ret.add(c >> 5);
    }
    ret.add(0);
    for (final c in hrp.codeUnits) {
      ret.add(c & 31);
    }
    return ret;
  }

  int _bech32Polymod(List<int> values) {
    const gen = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3];
    var chk = 1;
    for (final v in values) {
      final b = chk >> 25;
      chk = ((chk & 0x1ffffff) << 5) ^ v;
      for (var i = 0; i < 5; i++) {
        if ((b >> i) & 1 == 1) {
          chk ^= gen[i];
        }
      }
    }
    return chk;
  }
}
