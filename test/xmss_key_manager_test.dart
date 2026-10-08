
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:soqushield/services/xmss_key_manager.dart';

/// Mock secure storage for testing (in-memory map).
class MockSecureStorage extends FlutterSecureStorage {
  final Map<String, String> _store = {};

  MockSecureStorage() : super();

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      _store[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      _store.remove(key);
    } else {
      _store[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _store.remove(key);
  }
}

void main() {
  group('XmssKeyManager', () {
    late XmssKeyManager mgr;

    setUp(() {
      mgr = XmssKeyManager(storage: MockSecureStorage());
    });

    test('hasVault returns false when no vault exists', () async {
      expect(await mgr.hasVault(), false);
    });

    test('initializeVault creates vault and stores seed', () async {
      final tree = await mgr.initializeVault(depth: 2);
      expect(tree.masterSeed.length, 32);
      expect(tree.keys.length, 4); // 2^2
      expect(await mgr.hasVault(), true);
    });

    test('initializeVault throws if vault already exists', () async {
      await mgr.initializeVault(depth: 2);
      expect(
        () => mgr.initializeVault(depth: 2),
        throwsA(isA<StateError>()),
      );
    });

    test('loadVault regenerates same tree from stored seed', () async {
      final original = await mgr.initializeVault(depth: 2);

      // Clear cache to force reload from storage
      mgr.clearCache();

      final reloaded = await mgr.loadVault();
      expect(reloaded, isNotNull);
      expect(reloaded!.merkleRoot, original.merkleRoot);
      expect(reloaded.keys.length, original.keys.length);

      // Same private keys (deterministic from seed)
      for (var i = 0; i < original.keys.length; i++) {
        expect(reloaded.keys[i].publicKeyHash, original.keys[i].publicKeyHash);
      }
    });

    test('getLeafIndex starts at 0', () async {
      await mgr.initializeVault(depth: 2);
      expect(await mgr.getLeafIndex(), 0);
    });

    test('advanceLeafIndex increments correctly', () async {
      await mgr.initializeVault(depth: 2);
      expect(await mgr.advanceLeafIndex(), 1);
      expect(await mgr.advanceLeafIndex(), 2);
      expect(await mgr.advanceLeafIndex(), 3);
      expect(await mgr.getLeafIndex(), 3);
    });

    test('getRemainingKeys returns correct count', () async {
      await mgr.initializeVault(depth: 2); // 4 keys total
      expect(await mgr.getRemainingKeys(), 4);
      await mgr.advanceLeafIndex();
      expect(await mgr.getRemainingKeys(), 3);
      await mgr.advanceLeafIndex();
      expect(await mgr.getRemainingKeys(), 2);
    });

    test('isExhausted returns true when all keys used', () async {
      await mgr.initializeVault(depth: 2); // 4 keys
      expect(await mgr.isExhausted(), false);

      // Use all 4 keys
      await mgr.advanceLeafIndex();
      await mgr.advanceLeafIndex();
      await mgr.advanceLeafIndex();
      await mgr.advanceLeafIndex();

      expect(await mgr.isExhausted(), true);
      expect(await mgr.getRemainingKeys(), 0);
    });

    test('isKeyExhaustionWarning triggers near exhaustion', () async {
      await mgr.initializeVault(depth: 2); // 4 keys, warn at <=3 remaining
      expect(await mgr.isKeyExhaustionWarning(), false); // 4 remaining

      await mgr.advanceLeafIndex(); // 3 remaining
      expect(await mgr.isKeyExhaustionWarning(), true);

      await mgr.advanceLeafIndex(); // 2 remaining
      expect(await mgr.isKeyExhaustionWarning(), true);

      await mgr.advanceLeafIndex(); // 1 remaining
      expect(await mgr.isKeyExhaustionWarning(), true);

      await mgr.advanceLeafIndex(); // 0 remaining (exhausted, not warning)
      expect(await mgr.isKeyExhaustionWarning(), false);
      expect(await mgr.isExhausted(), true);
    });

    test('getVaultInfo returns correct metadata', () async {
      await mgr.initializeVault(depth: 3); // 8 keys
      await mgr.advanceLeafIndex();
      await mgr.advanceLeafIndex();

      final info = await mgr.getVaultInfo();
      expect(info, isNotNull);
      expect(info!.leafIndex, 2);
      expect(info.maxKeys, 8);
      expect(info.remainingKeys, 6);
      expect(info.treeDepth, 3);
      expect(info.isExhausted, false);
      expect(info.isWarning, false);
      expect(info.merkleRoot, isNotNull);
      expect(info.merkleRoot!.length, 32);
      expect(info.createdAt, isNotNull);
    });

    test('wipeVault deletes everything', () async {
      await mgr.initializeVault(depth: 2);
      expect(await mgr.hasVault(), true);

      await mgr.wipeVault();
      expect(await mgr.hasVault(), false);
      expect(await mgr.loadVault(), null);
      expect(await mgr.getLeafIndex(), 0);
    });

    test('wipeVault allows re-initialization', () async {
      final original = await mgr.initializeVault(depth: 2);
      await mgr.wipeVault();

      final newTree = await mgr.initializeVault(depth: 3);
      expect(newTree.keys.length, 8); // 2^3
      // Different seed → different root
      expect(newTree.merkleRoot, isNot(original.merkleRoot));
    });

    test('loadVault returns null for empty vault', () async {
      expect(await mgr.loadVault(), null);
    });

    test('getMerkleRoot returns 32 bytes', () async {
      await mgr.initializeVault(depth: 2);
      final root = await mgr.getMerkleRoot();
      expect(root, isNotNull);
      expect(root!.length, 32);
    });
  });
}
