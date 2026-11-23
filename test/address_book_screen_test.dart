// The address book on screen: the list by network, saving from the dialog
// with a refusal shown in place, renaming, removing, the full address behind
// a row; the picker on Send offering the wallet's network only; and the SENT
// screen's offer to save a recipient the book does not hold.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:soqushield/guide/guide_content.dart';
import 'package:soqushield/models/wallet_keys.dart';
import 'package:soqushield/providers/auth_provider.dart';
import 'package:soqushield/providers/session_provider.dart';
import 'package:soqushield/providers/wallet_provider.dart';
import 'package:soqushield/screens/address_book/address_book_screen.dart';
import 'package:soqushield/screens/send/address_book_picker.dart';
import 'package:soqushield/screens/send/send_pilot_screen.dart';
import 'package:soqushield/services/address_book_service.dart';

import 'lite_test_support.dart';

const _mainnet =
    'sq1p3j6nd46xrh8vl8ac86x8sm4dlynv95ckpyn5y4d46kte8js05k2qarf5vn';
const _stagenet =
    'ssq1p3j6nd46xrh8vl8ac86x8sm4dlynv95ckpyn5y4d46kte8js05k2qvft6ee';
const _key = AddressBookService.storageKey;

WalletState _wallet(SoqNetwork network) => WalletState(
      balance: 5,
      blockHeight: 100,
      keys: WalletKeys(
        publicKey: Uint8List(WalletKeys.pubKeySize),
        address: network == SoqNetwork.mainnet ? _mainnet : _stagenet,
        derivationPath: "m/44'/21329'/0'/0/0",
        accountIndex: 0,
        createdAt: DateTime(2026, 1, 1),
      ),
      network: network,
      backupConfirmed: true,
      isInitialized: true,
      isLoading: false,
    );

/// A wallet whose send succeeds, for the SENT screen.
class _SendingNotifier extends MockWalletNotifier {
  _SendingNotifier(super.state);
  final sent = <(String, double)>[];
  @override
  Future<String> sendTransaction(
      {required String toAddress, required double amount}) async {
    sent.add((toAddress, amount));
    return 'ab' * 32;
  }
}

Widget _scoped(Widget child,
        {SoqNetwork network = SoqNetwork.mainnet, WalletNotifier? wallet}) =>
    ProviderScope(
      overrides: [
        authProvider
            .overrideWith(() => MockAuthNotifier(AuthStatus.authenticated)),
        authServiceProvider.overrideWithValue(FakeAuthService()),
        sessionProvider.overrideWith(MockSessionNotifier.new),
        quietDisplayPrefs,
        quietPrice,
        walletProvider.overrideWith(
            () => wallet ?? MockWalletNotifier(_wallet(network))),
      ],
      child: MaterialApp(home: child),
    );

void _seed(List<Map<String, dynamic>> rows) =>
    secureStore[_key] = json.encode(rows);

Map<String, dynamic> _row(String id, String name, String address) => {
      'id': id,
      'name': name,
      'address': address,
      'createdAt': '2026-10-14T00:00:00Z',
    };

List<dynamic> _stored() =>
    json.decode(secureStore[_key] ?? '[]') as List<dynamic>;

/// Fixed pumps, long enough for a sheet or a dialog to open or close. The
/// send screen's figure breathes without end, so it never settles.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Replace the tree so every provider is disposed, then drain the timers the
/// send screen arms.
Future<void> _tearDownTree(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
  await tester.pump(const Duration(minutes: 1));
}

String _recipient(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField).at(1)).controller!.text;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    installSecureStorageMock();
    SharedPreferences.setMockInitialValues({});
  });

  group('the address book screen', () {
    testWidgets('lists the saved addresses by network, the wallet\'s first, '
        'shortened', (tester) async {
      _seed([_row('s', 'Stage', _stagenet), _row('m', 'Alice', _mainnet)]);
      await tester.pumpWidget(_scoped(const AddressBookScreen()));
      await _settle(tester);
      expect(find.text('ON MAINNET'), findsOneWidget);
      expect(find.text('ON STAGENET'), findsOneWidget);
      expect(tester.getTopLeft(find.text('ON MAINNET')).dy,
          lessThan(tester.getTopLeft(find.text('ON STAGENET')).dy));
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Stage'), findsOneWidget);
      expect(find.text(_mainnet), findsNothing,
          reason: 'a row shows the first and last of an address');
      expect(find.textContaining('…'), findsNWidgets(2));
    });

    testWidgets('the empty book says so and offers to save one',
        (tester) async {
      await tester.pumpWidget(_scoped(const AddressBookScreen()));
      await _settle(tester);
      expect(find.textContaining('No saved addresses yet'), findsOneWidget);
      expect(find.text('Save an address'), findsOneWidget);
      expect(find.textContaining('ON MAINNET'), findsNothing);
    });

    testWidgets('saves from the dialog, and a bad address is refused in '
        'place with the book\'s reason', (tester) async {
      await tester.pumpWidget(_scoped(const AddressBookScreen()));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('nav Save an address')));
      await tester.pumpAndSettle();
      expect(find.text('SAVE AN ADDRESS'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('entry-name')), 'Alice');
      await tester.enterText(find.byKey(const Key('entry-address')),
          '${_mainnet.substring(0, _mainnet.length - 1)}m');
      await tester.tap(find.byKey(const ValueKey('dialog confirm')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('entry-refusal')), findsOneWidget);
      expect(find.textContaining('checksum'), findsOneWidget);
      expect(find.text('SAVE AN ADDRESS'), findsOneWidget,
          reason: 'the dialog stays open on a refusal');
      expect(_stored(), isEmpty);

      await tester.enterText(
          find.byKey(const Key('entry-address')), _mainnet.toUpperCase());
      await tester.tap(find.byKey(const ValueKey('dialog confirm')));
      await tester.pumpAndSettle();
      expect(find.text('SAVE AN ADDRESS'), findsNothing);
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('ON MAINNET'), findsOneWidget);
      expect(_stored().single['address'], _mainnet);
      expect(find.text('Alice saved'), findsOneWidget);
    });

    testWidgets('renames from the row, keeping the address', (tester) async {
      _seed([_row('m', 'Alice', _mainnet)]);
      await tester.pumpWidget(_scoped(const AddressBookScreen()));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('rename m')));
      await tester.pumpAndSettle();
      expect(find.text('RENAME'), findsOneWidget);
      expect(find.text(_mainnet), findsOneWidget,
          reason: 'the address is shown, not editable');
      expect(find.byKey(const Key('entry-address')), findsNothing);
      await tester.enterText(find.byKey(const Key('entry-name')), 'Alice B');
      await tester.tap(find.byKey(const ValueKey('dialog confirm')));
      await tester.pumpAndSettle();
      expect(find.text('Alice B'), findsOneWidget);
      expect(find.text('Alice'), findsNothing);
      expect(_stored().single['address'], _mainnet);
    });

    testWidgets('removes after a confirmation, and not before',
        (tester) async {
      _seed([_row('m', 'Alice', _mainnet)]);
      await tester.pumpWidget(_scoped(const AddressBookScreen()));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('remove m')));
      await tester.pumpAndSettle();
      expect(find.text('Remove Alice?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('dialog cancel')));
      await tester.pumpAndSettle();
      expect(find.text('Alice'), findsOneWidget);
      expect(_stored(), hasLength(1));

      await tester.tap(find.byKey(const ValueKey('remove m')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('dialog confirm')));
      await tester.pumpAndSettle();
      expect(find.text('Alice'), findsNothing);
      expect(_stored(), isEmpty);
      expect(find.textContaining('No saved addresses yet'), findsOneWidget);
    });

    testWidgets('a row opens the full address, with its network and a copy '
        'action', (tester) async {
      _seed([_row('s', 'Stage', _stagenet)]);
      await tester.pumpWidget(_scoped(const AddressBookScreen()));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('entry s')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('entry-full-address')), findsOneWidget);
      expect(find.text(_stagenet), findsOneWidget);
      expect(find.text('ON STAGENET'), findsNWidgets(2),
          reason: 'the section header behind, and the dialog');
      await tester.tap(find.byKey(const ValueKey('dialog confirm')));
      await tester.pumpAndSettle();
      expect(find.text('Address copied'), findsOneWidget);
    });
  });

  group('the picker on Send', () {
    testWidgets('lists the wallet\'s network only, and a pick fills the field',
        (tester) async {
      _seed([_row('s', 'Stage', _stagenet), _row('m', 'Alice', _mainnet)]);
      await tester.pumpWidget(_scoped(const SendPilotScreen()));
      await _settle(tester);
      expect(find.byKey(const Key('send-book')), findsOneWidget);
      await tester.tap(find.byKey(const Key('send-book')));
      await _settle(tester);
      expect(find.byType(AddressBookPicker), findsOneWidget);
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Stage'), findsNothing,
          reason: 'a stagenet address cannot be paid from mainnet');
      await tester.tap(find.byKey(const ValueKey('pick m')));
      await _settle(tester);
      expect(find.byType(AddressBookPicker), findsNothing);
      expect(_recipient(tester), _mainnet);
      await _tearDownTree(tester);
    });

    testWidgets('says when the network has no saved address, and closes '
        'empty', (tester) async {
      _seed([_row('s', 'Stage', _stagenet)]);
      await tester.pumpWidget(_scoped(const SendPilotScreen()));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('send-book')));
      await _settle(tester);
      expect(find.textContaining('No saved addresses on Mainnet'),
          findsOneWidget);
      await tester.tap(find.byKey(const Key('picker-close')));
      await _settle(tester);
      expect(find.byType(AddressBookPicker), findsNothing);
      expect(_recipient(tester), isEmpty);
      await _tearDownTree(tester);
    });
  });

  group('the SENT screen', () {
    testWidgets('offers to save a recipient the book does not hold, and the '
        'offer goes once it is saved', (tester) async {
      final wallet = _SendingNotifier(_wallet(SoqNetwork.mainnet));
      await tester.pumpWidget(_scoped(const SendPilotScreen(), wallet: wallet));
      await _settle(tester);
      await tester.enterText(find.byType(TextField).at(0), '1');
      await tester.enterText(find.byType(TextField).at(1), _mainnet);
      await tester.pump();
      await tester.tap(find.text('SEND SOQ'));
      // The credential, the signing phase, the broadcast and the SENT
      // screen's scale-in.
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(wallet.sent, [(_mainnet, 1.0)]);
      expect(find.text('SENT'), findsOneWidget);
      expect(find.byKey(const Key('send-save-recipient')), findsOneWidget);

      await tester.tap(find.byKey(const Key('send-save-recipient')));
      await _settle(tester);
      expect(find.text('SAVE AN ADDRESS'), findsOneWidget);
      expect(
          tester
              .widget<TextField>(find.descendant(
                  of: find.byKey(const Key('entry-address')),
                  matching: find.byType(TextField)))
              .controller!
              .text,
          _mainnet,
          reason: 'the address the transaction carried, filled in');
      await tester.enterText(find.byKey(const Key('entry-name')), 'Alice');
      await tester.tap(find.byKey(const ValueKey('dialog confirm')));
      await _settle(tester);
      expect(find.text('Alice saved'), findsOneWidget);
      expect(find.byKey(const Key('send-save-recipient')), findsNothing,
          reason: 'the book holds it now');
      expect(_stored().single['address'], _mainnet);
      await _tearDownTree(tester);
    });

    testWidgets('makes no offer for a recipient already in the book',
        (tester) async {
      _seed([_row('m', 'Alice', _mainnet)]);
      final wallet = _SendingNotifier(_wallet(SoqNetwork.mainnet));
      await tester.pumpWidget(_scoped(const SendPilotScreen(), wallet: wallet));
      await _settle(tester);
      await tester.enterText(find.byType(TextField).at(0), '1');
      await tester.enterText(find.byType(TextField).at(1), _mainnet);
      await tester.pump();
      await tester.tap(find.text('SEND SOQ'));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('SENT'), findsOneWidget);
      expect(find.byKey(const Key('send-save-recipient')), findsNothing);
      await _tearDownTree(tester);
    });
  });

  group('the Field Manual', () {
    test('has an address book article and names the book icon on Send', () {
      final article = guideArticleById('address-book');
      expect(article, isNotNull);
      expect(article!.sections.any((s) => s.steps.any((t) => t.contains('SAVE AN ADDRESS'))),
          isTrue);
      final send = guideArticleById('send')!;
      expect(send.sections.any((s) => s.steps.any((t) => t.contains('book icon'))),
          isTrue);
    });
  });
}
