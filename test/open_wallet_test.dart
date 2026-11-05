// Opening another wallet on the device.
//
// ⛔ A switch is not a view change. It puts another person's balance,
// address and whole payment history on the screen, and it puts that
// wallet's coins one tap from being spent. The device credential is asked
// for BEFORE anything moves, and the key of the wallet being closed leaves
// memory before the one being opened is read.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:soqushield/models/wallet_record.dart';
import 'package:soqushield/providers/auth_provider.dart';
import 'package:soqushield/providers/wallet_provider.dart';

import 'lite_test_support.dart';

/// Refuses the credential, and counts how often it was asked.
class _RefusingAuth extends FakeAuthService {
  int asked = 0;
  @override
  Future<bool> authenticateWithBiometrics() async {
    asked++;
    return false;
  }
}

/// No screen lock on this device at all.
class _NoDeviceAuth extends FakeAuthService {
  @override
  Future<bool> isDeviceAuthAvailable() async => false;
}

class _RefusingHttpClient implements HttpClient {
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) =>
      throw const SocketException('no network in tests');
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _RefusingOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _RefusingHttpClient();
}

const _mnemonicA =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon '
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon '
    'abandon abandon abandon abandon abandon art';
const _mnemonicB =
    'legal winner thank year wave sausage worth useful legal winner thank '
    'year wave sausage worth useful legal will';

Future<void> _settle([int turns = 30]) async {
  for (var i = 0; i < turns; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
}

Future<WalletState> _boot(ProviderContainer c) async {
  c.read(walletProvider);
  for (var i = 0; i < 400; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 25));
    if (!c.read(walletProvider).isLoading) break;
  }
  await _settle();
  return c.read(walletProvider);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late FakeAuthService auth;

  ProviderContainer makeContainer(FakeAuthService a) {
    auth = a;
    return ProviderContainer(
      overrides: [authServiceProvider.overrideWithValue(a)],
    );
  }

  setUp(() {
    installSecureStorageMock();
    SharedPreferences.setMockInitialValues({});
    HttpOverrides.global = _RefusingOverrides();
    // A device that already carries the pre-registry wallet.
    secureStore['soq_mnemonic_v2'] = _mnemonicA;
    secureStore['soq_address_v2'] =
        'sq1p3j6nd46xrh8vl8ac86x8sm4dlynv95ckpyn5y4d46kte8js05k2qarf5vn';
    secureStore['soq_deriv_path_v2'] = "m/44'/21329'/0'/0/0";
    secureStore['soq_account_index_v2'] = '0';
    secureStore['soq_backup_confirmed_v2'] = 'true';
    secureStore['soq_network_v2'] = 'mainnet';
    container = makeContainer(FakeAuthService());
  });

  tearDown(() {
    container.dispose();
    HttpOverrides.global = null;
  });

  /// Adds a second wallet through the real provider and returns its record.
  Future<WalletRecord> addSecond() async {
    final n = container.read(walletProvider.notifier);
    final r = await n.importAdditionalWallet(
        name: 'Second', mnemonic: _mnemonicB);
    expect(r, isNotNull, reason: 'the second wallet was written');
    return r!;
  }

  group('the credential gates the switch', () {
    test('a refused credential opens nothing and moves nothing', () async {
      container.dispose();
      container = makeContainer(_RefusingAuth());
      await _boot(container);
      final second = await addSecond();
      final before = container.read(walletProvider).address;

      final n = container.read(walletProvider.notifier);
      expect(await n.openWallet(second.id), isFalse);

      expect((auth as _RefusingAuth).asked, 1, reason: 'it did ask');
      expect(n.openWalletId, WalletRecord.primaryId,
          reason: 'still the wallet that was open');
      expect(container.read(walletProvider).address, before);
      expect(await container.read(walletProvider.notifier).listWallets(),
          hasLength(2));
    });

    test('a device with no screen lock is refused, with a reason', () async {
      container.dispose();
      container = makeContainer(_NoDeviceAuth());
      await _boot(container);
      final second = await addSecond();

      final n = container.read(walletProvider.notifier);
      expect(await n.openWallet(second.id), isFalse);
      expect(container.read(walletProvider).error, contains('screen lock'));
      expect(n.openWalletId, WalletRecord.primaryId);
    });

    test('the credential is asked for exactly once per switch', () async {
      await _boot(container);
      final second = await addSecond();
      final n = container.read(walletProvider.notifier);
      expect(await n.openWallet(second.id), isTrue);
      await _settle();
      expect(auth.prompts, 1);
    });

    test('opening the wallet already open asks for nothing', () async {
      await _boot(container);
      final n = container.read(walletProvider.notifier);
      expect(await n.openWallet(WalletRecord.primaryId), isTrue);
      expect(auth.prompts, 0);
    });

    test('a wallet that is not here is refused before the credential',
        () async {
      await _boot(container);
      final n = container.read(walletProvider.notifier);
      expect(await n.openWallet('no-such-wallet'), isFalse);
      expect(auth.prompts, 0, reason: 'nothing to authorise');
      expect(container.read(walletProvider).error, contains('not on this'));
    });
  });

  group('what a switch actually moves', () {
    test('the open wallet changes, and so does the address on screen',
        () async {
      await _boot(container);
      final first = container.read(walletProvider).address;
      final second = await addSecond();

      final n = container.read(walletProvider.notifier);
      expect(await n.openWallet(second.id), isTrue);
      await _settle();

      expect(n.openWalletId, second.id);
      expect(container.read(walletProvider).address, second.address);
      expect(container.read(walletProvider).address, isNot(first));
      expect(await container.read(walletProvider.notifier).listWallets(),
          hasLength(2));
    });

    test('the pointer survives, so the next boot opens the same wallet',
        () async {
      await _boot(container);
      final second = await addSecond();
      await container.read(walletProvider.notifier).openWallet(second.id);
      await _settle();

      expect(secureStore['soq_active_wallet_v1'], second.id);

      // A fresh container is the next launch.
      container.dispose();
      container = makeContainer(FakeAuthService());
      final s = await _boot(container);
      expect(s.address, second.address,
          reason: 'the app reopens the wallet that was left open');
    });

    test('each wallet keeps its own seed across a switch and back', () async {
      await _boot(container);
      final second = await addSecond();
      final n = container.read(walletProvider.notifier);

      await n.openWallet(second.id);
      await _settle();
      await n.openWallet(WalletRecord.primaryId);
      await _settle();

      expect(secureStore['soq_mnemonic_v2'], _mnemonicA);
      expect(secureStore['soq_w_${second.id}_soq_mnemonic_v2'], _mnemonicB);
      expect(container.read(walletProvider).address,
          'sq1p3j6nd46xrh8vl8ac86x8sm4dlynv95ckpyn5y4d46kte8js05k2qarf5vn');
    });

    test('the closed wallet\'s signing key is zeroed, not carried over',
        () async {
      // ⛔ The one failure here that moves coins. _cachedSk is the ML-DSA-44
      // SECRET KEY of the wallet being closed. Left in place, the next send
      // would sign the newly opened wallet's transaction with it.
      await _boot(container);
      final second = await addSecond();
      final n = container.read(walletProvider.notifier);

      final sk = Uint8List.fromList(List.filled(32, 7));
      n.cacheKeypairForTest(Uint8List.fromList(const [1, 2, 3]), sk);
      expect(n.hasCachedKeypair, isTrue, reason: 'as a send leaves it');

      expect(await n.openWallet(second.id), isTrue);
      await _settle();

      expect(n.hasCachedKeypair, isFalse,
          reason: 'the closed wallet\'s key must not sign for the open one');
      expect(sk.every((b) => b == 0), isTrue,
          reason: 'and the bytes are zeroed, not merely dropped');
    });

    test('a refused switch keeps the open wallet\'s key, which is still its own',
        () async {
      container.dispose();
      container = makeContainer(_RefusingAuth());
      await _boot(container);
      final second = await addSecond();
      final n = container.read(walletProvider.notifier);

      n.cacheKeypairForTest(Uint8List.fromList(const [1]),
          Uint8List.fromList(List.filled(32, 7)));
      expect(await n.openWallet(second.id), isFalse);

      expect(n.hasCachedKeypair, isTrue,
          reason: 'nothing moved, so the open wallet keeps working');
    });

    test('the coins of the wallet being closed do not come with it', () async {
      secureStore['soq_utxo_set_mainnet'] = jsonEncode([
        {
          'txid': 'ab' * 32,
          'vout': 0,
          'value': 5.0,
          'valueSat': 500000000,
          'scriptPubKey': '5120${'00' * 32}',
          'address':
              'sq1p3j6nd46xrh8vl8ac86x8sm4dlynv95ckpyn5y4d46kte8js05k2qarf5vn',
          'height': 100,
          'confirmations': 10,
          'locked': false,
          'assetType': 0,
          'visibility': 0,
        }
      ]);
      await _boot(container);
      expect(container.read(walletProvider).balance, closeTo(5.0, 1e-9));

      final second = await addSecond();
      await container.read(walletProvider.notifier).openWallet(second.id);
      await _settle();

      expect(container.read(walletProvider).balance, 0,
          reason: 'the opened wallet owns none of those coins');
      expect(secureStore['soq_utxo_set_mainnet'], isNotNull,
          reason: "and the first wallet's coins are still its own");
    });
  });
}
