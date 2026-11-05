// The wallets screen: one row per wallet, which one is open, and the three
// things the owner can do from it.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:soqushield/models/wallet_record.dart';
import 'package:soqushield/providers/auth_provider.dart';
import 'package:soqushield/providers/wallet_provider.dart';
import 'package:soqushield/screens/wallets/wallets_pilot_screen.dart';

import 'lite_test_support.dart';

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

class _RefusingAuth extends FakeAuthService {
  @override
  Future<bool> authenticateWithBiometrics() async => false;
}

const _addrA =
    'sq1p3j6nd46xrh8vl8ac86x8sm4dlynv95ckpyn5y4d46kte8js05k2qarf5vn';
const _mnemonicA =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon '
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon '
    'abandon abandon abandon abandon abandon art';
const _mnemonicB =
    'legal winner thank year wave sausage worth useful legal winner thank '
    'year wave sausage worth useful legal will';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  var disposed = false;

  ProviderContainer makeContainer([FakeAuthService? auth]) => ProviderContainer(
        overrides: [
          authServiceProvider.overrideWithValue(auth ?? FakeAuthService()),
        ],
      );

  setUp(() {
    disposed = false;
    installSecureStorageMock();
    SharedPreferences.setMockInitialValues({});
    HttpOverrides.global = _RefusingOverrides();
    secureStore['soq_mnemonic_v2'] = _mnemonicA;
    secureStore['soq_address_v2'] = _addrA;
    secureStore['soq_deriv_path_v2'] = "m/44'/21329'/0'/0/0";
    secureStore['soq_account_index_v2'] = '0';
    secureStore['soq_backup_confirmed_v2'] = 'true';
    secureStore['soq_network_v2'] = 'mainnet';
    container = makeContainer();
  });

  tearDown(() {
    if (!disposed) container.dispose();
    HttpOverrides.global = null;
  });

  Future<void> pumpScreen(WidgetTester t) async {
    await t.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: WalletsPilotScreen()),
    ));
    // The wallet boots and the list resolves.
    for (var i = 0; i < 40; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  /// Ends a test with no poll armed.
  ///
  /// ⛔ The container is disposed INSIDE the test body. The binding checks
  /// for pending timers before tearDown runs, so disposing there is too
  /// late — the wallet's periodic refresh is still armed and every test
  /// fails on a timer rather than on what it was testing.
  Future<void> quiesce(WidgetTester t) async {
    container.dispose();
    disposed = true;
    await t.pump(const Duration(milliseconds: 50));
  }

  Future<WalletRecord> addSecond() async {
    final r = await container
        .read(walletProvider.notifier)
        .importAdditionalWallet(name: 'Savings', mnemonic: _mnemonicB);
    return r!;
  }

  testWidgets('every wallet on the device has a row', (t) async {
    await addSecond();
    await pumpScreen(t);

    expect(find.text('Main wallet'), findsOneWidget);
    expect(find.text('Savings'), findsOneWidget);

    await quiesce(t);
  });

  testWidgets('the open wallet is the one marked OPEN, and only it',
      (t) async {
    await addSecond();
    await pumpScreen(t);

    expect(find.text('OPEN'), findsOneWidget,
        reason: 'exactly one wallet is open at a time');

    await quiesce(t);
  });

  testWidgets('a row shows an address shortened, not a full one', (t) async {
    await pumpScreen(t);
    expect(find.text(_addrA), findsNothing,
        reason: 'a row tells wallets apart; Receive is for reading an '
            'address off');
    expect(find.textContaining('…'), findsWidgets);

    await quiesce(t);
  });

  testWidgets('tapping another wallet asks before it prompts', (t) async {
    final second = await addSecond();
    await pumpScreen(t);

    await t.tap(find.byKey(ValueKey('wallet ${second.id}')));
    await t.pumpAndSettle();

    expect(find.textContaining('Open Savings?'), findsOneWidget);
    expect(find.textContaining('confirm it is you'), findsOneWidget,
        reason: 'the credential prompt is announced, not sprung');

    await quiesce(t);
  });

  testWidgets('cancelling the confirmation opens nothing', (t) async {
    final second = await addSecond();
    await pumpScreen(t);

    await t.tap(find.byKey(ValueKey('wallet ${second.id}')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('dialog cancel')));
    await t.pumpAndSettle();

    expect(container.read(walletProvider.notifier).openWalletId,
        WalletRecord.primaryId);

    await quiesce(t);
  });

  testWidgets('a refused credential leaves the open wallet open', (t) async {
    container.dispose();
    container = makeContainer(_RefusingAuth());
    final second = await addSecond();
    await pumpScreen(t);

    await t.tap(find.byKey(ValueKey('wallet ${second.id}')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('dialog confirm')));
    await t.pumpAndSettle();

    expect(container.read(walletProvider.notifier).openWalletId,
        WalletRecord.primaryId,
        reason: 'the wallet that was open is still open');

    await quiesce(t);
  });

  testWidgets('tapping the open wallet does nothing at all', (t) async {
    await addSecond();
    await pumpScreen(t);

    await t.tap(find.byKey(const ValueKey('wallet primary')));
    await t.pumpAndSettle();

    expect(find.textContaining('Open '), findsNothing,
        reason: 'no confirmation, because there is nothing to confirm');

    await quiesce(t);
  });

  testWidgets('a wallet can be renamed from its row', (t) async {
    await pumpScreen(t);

    await t.tap(find.byKey(const ValueKey('rename primary')));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).first, 'Day to day');
    await t.tap(find.byKey(const ValueKey('dialog confirm')));
    await t.pumpAndSettle();

    expect(find.text('Day to day'), findsOneWidget);
    expect(find.text('Main wallet'), findsNothing);

    await quiesce(t);
  });

  testWidgets('the add rows are both present and named plainly', (t) async {
    await pumpScreen(t);
    expect(find.text('Create a wallet'), findsOneWidget);
    expect(find.text('Import a wallet'), findsOneWidget);

    await quiesce(t);
  });

  testWidgets('creating a wallet adds a row and says to back it up',
      (t) async {
    await pumpScreen(t);

    await t.tap(find.byKey(const ValueKey('nav Create a wallet')));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).first, 'Savings');
    await t.tap(find.byKey(const ValueKey('dialog confirm')));
    await t.pumpAndSettle();

    expect(find.text('Savings'), findsOneWidget);
    expect(find.textContaining('recovery phrase'), findsWidgets,
        reason: 'a new seed the owner has not written down yet');

    await quiesce(t);
  });

  testWidgets('importing the words of a wallet already here is refused',
      (t) async {
    await pumpScreen(t);

    await t.tap(find.byKey(const ValueKey('nav Import a wallet')));
    await t.pumpAndSettle();
    final fields = find.byType(TextField);
    await t.enterText(fields.at(0), 'Copy');
    await t.enterText(fields.at(1), _mnemonicA);
    await t.tap(find.byKey(const ValueKey('dialog confirm')));
    await t.pumpAndSettle();

    expect(find.text('Copy'), findsNothing);
    expect(find.textContaining('already on this device'), findsOneWidget);

    await quiesce(t);
  });

  testWidgets('the screen says each wallet needs its own backup', (t) async {
    await pumpScreen(t);
    expect(find.textContaining('own seed'), findsOneWidget);
    expect(find.textContaining('Back up each one'), findsOneWidget);

    await quiesce(t);
  });
}
