import 'dart:typed_data';

/// Immutable wallet key model for ML-DSA-44 (Dilithium Level 2).
///
/// Key sizes (NIST FIPS 204, DILITHIUM_MODE=2):
/// - Public key:  1,312 bytes
/// - Secret key:  2,560 bytes
/// - Signature:   2,420 bytes
///
/// Wire-compatible with soqucoin-build/src/wallet/pqwallet/pqkeys.h
class WalletKeys {
  /// ML-DSA-44 public key (1312 bytes)
  final Uint8List publicKey;

  /// Bech32m-encoded address (sq1... for mainnet, ssq1... for stagenet)
  final String address;

  /// BIP-44 derivation path: m/44'/21329'/account'/change/index
  final String derivationPath;

  /// Account index for HD derivation
  final int accountIndex;

  /// When this keypair was created
  final DateTime createdAt;

  const WalletKeys({
    required this.publicKey,
    required this.address,
    required this.derivationPath,
    required this.accountIndex,
    required this.createdAt,
  });

  /// ML-DSA-44 constant sizes (must match C++ node)
  static const int pubKeySize = 1312;
  static const int secKeySize = 2560;
  static const int signatureSize = 2420;

  /// BIP-44 coin type for Soqucoin (0x5351)
  static const int coinType = 21329;

  /// Seed size for Dilithium keygen
  static const int seedSize = 32;
}

/// Network configuration
enum SoqNetwork {
  mainnet('sq', 'Mainnet', 33389),
  stagenet('ssq', 'Stagenet', 28332);  // Community pre-mainnet — separate chain, HRP 'ssq', RPC 28332

  final String hrp;
  final String displayName;
  final int rpcPort;
  const SoqNetwork(this.hrp, this.displayName, this.rpcPort);

  /// Network-aware ticker symbol (tSOQ for testnet/stagenet, SOQ for mainnet).
  String get ticker => this == SoqNetwork.mainnet ? 'SOQ' : 'tSOQ';

  /// Network-aware address prefix — stagenet uses 'ssq1', mainnet/testnet use 'sq1'.
  String get addressPrefix => this == SoqNetwork.stagenet ? 'ssq1' : 'sq1';

  /// Network-aware label for UI badges.
  String get networkLabel {
    switch (this) {
      case SoqNetwork.mainnet:  return 'MAINNET';
      case SoqNetwork.stagenet: return 'STAGENET';
    }
  }

  /// Network-aware RPC source label for data provenance badges.
  String get rpcLabel {
    switch (this) {
      case SoqNetwork.mainnet:  return 'MAINNET RPC';
      case SoqNetwork.stagenet: return 'STAGENET RPC';
    }
  }

  // ── ElectrumX REST API endpoints (Phase B1) ──

  /// Primary ElectrumX REST URL — via Cloudflare Worker (HTTPS, DDoS-protected).
  String get electrumApiUrl {
    switch (this) {
      case SoqNetwork.stagenet:
        return 'https://soqushield-api.research-c26.workers.dev';
      case SoqNetwork.mainnet:
        return 'https://mainnet-api.soqu.org';
    }
  }

  /// Fallback ElectrumX REST URL.
  /// SB-10: was a plaintext address on the Services host (A5-03 MITM vector, and
  /// iOS ATS now blocks cleartext). Points at the HTTPS worker until a dedicated
  /// TLS ElectrumX endpoint exists.
  /// TODO(infra): expose :3001 over TLS (e.g. electrum.soqu.org) for a truly
  /// independent HTTPS fallback rather than re-hitting the worker.
  String get electrumFallbackUrl {
    switch (this) {
      case SoqNetwork.stagenet:
        return 'https://soqushield-api.research-c26.workers.dev';
      case SoqNetwork.mainnet:
        return 'https://mainnet-api.soqu.org';
    }
  }
}

/// Represents a seed phrase for wallet backup/restore
class SeedPhrase {
  /// 24-word BIP-39 mnemonic
  final List<String> words;

  /// Whether the user has confirmed the backup
  final bool backupConfirmed;

  const SeedPhrase({
    required this.words,
    this.backupConfirmed = false,
  });

  /// Pretty-print as numbered list
  String toDisplayString() {
    return words
        .asMap()
        .entries
        .map((e) => '${(e.key + 1).toString().padLeft(2)}. ${e.value}')
        .join('\n');
  }

  /// Reconstruct mnemonic string for crypto operations
  String get mnemonic => words.join(' ');
}
