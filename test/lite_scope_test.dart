// Lite mainnet build: the scope pins.
//
// Each test here fails on the full app and passes on the lite build. They pin
// the route table, the landing route after splash and after unlock, the receive
// QR payload, the welcome screen's two actions, the surfaces the home, settings,
// shell and drawer no longer carry, the Field Manual's categories and copy, the
// hosts a string literal under lib/ may name (and no other, and no IPv4
// literal anywhere under lib/), the absence of every removed scheme,
// dependency and screen from the source tree, and the release version.

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:soqushield/app_version.dart';
import 'package:soqushield/guide/guide_content.dart';
import 'package:soqushield/models/wallet_keys.dart';
import 'package:soqushield/providers/auth_provider.dart';
import 'package:soqushield/providers/network_provider.dart';
import 'package:soqushield/providers/session_provider.dart';
import 'package:soqushield/providers/wallet_provider.dart';
import 'package:soqushield/router.dart';
import 'package:soqushield/screens/auth/welcome_pilot_screen.dart';
import 'package:soqushield/screens/home/home_pilot_screen.dart';
import 'package:soqushield/screens/receive/receive_pilot_screen.dart';
import 'package:soqushield/screens/send/send_pilot_screen.dart';
import 'package:soqushield/screens/settings/settings_pilot_screen.dart';
import 'package:soqushield/screens/shell.dart';

import 'lite_test_support.dart';

const _mainnetAddress =
    'sq1p3j6nd46xrh8vl8ac86x8sm4dlynv95ckpyn5y4d46kte8js05k2qarf5vn';
const _stagenetAddress =
    'ssq1p3j6nd46xrh8vl8ac86x8sm4dlynv95ckpyn5y4d46kte8js05k2qvft6ee';

/// Every network host a string literal under lib/ may name. The source-tree
/// test reads every string literal (comments skipped, escapes decoded,
/// adjacent literals joined, the literals inside an interpolation read),
/// takes each dotted name in it whole, whatever its last label, and refuses
/// any that is not on this list or a file the tree names; it also refuses
/// any IPv4 literal anywhere under lib/. So a removed feature's endpoint
/// cannot creep back under any top-level domain and no infrastructure
/// address sits in the tree. A name assembled from pieces at run time is
/// not seen.
const _allowedHosts = {
  'mainnet-api.soqu.org',
  'mainnet-rpc.soqu.org',
  'staging-rpc.soqu.org',
  'electrum.soqu.org',
  'soqushield-api.research-c26.workers.dev',
  'api.soqupool.com',
  'discord.gg',
};

/// The few files the app names by name in a string literal: the native
/// library under its three forms, its build script, an asset. A `.dart`
/// name is a file when it is a library URI or a relative import that
/// resolves ([_knownFile]); a last label alone tells nothing, since `.sh`,
/// `.so` and `.dev` are top-level domains too.
const _knownFiles = {
  'build_cli_dylib.sh',
  'dilithium_soq.framework',
  'libdilithium_soq.dylib',
  'libdilithium_soq.so',
  'soqucoin_logo.png',
};

/// Whether dotted [name], found in [literal] in the file at [path], is a
/// file and not a host: one of [_knownFiles], or a `.dart` name in a
/// `package:` or `dart:` URI or in a relative import that resolves from the
/// file's directory. A name under a scheme is a host whatever its label.
bool _knownFile(String path, String literal, String name) {
  if (literal.contains('://')) return false;
  if (_knownFiles.contains(name)) return true;
  if (!name.endsWith('.dart')) return false;
  if (literal.startsWith('package:') || literal.startsWith('dart:')) {
    return true;
  }
  if (!literal.toLowerCase().endsWith(name)) return false;
  return File.fromUri(File(path).parent.uri.resolve(literal)).existsSync();
}

/// A dotted name, read whole: labels of letters, digits, underscores and
/// hyphens, at least one dot, a last label of letters only. A name may
/// follow a dot (what is left after a blanked interpolation) but never a
/// label character, so a longer name is never read as its own suffix.
final _dottedName = RegExp(
    r'(?<![a-z0-9_-])[a-z0-9_-]+(?:\.[a-z0-9_-]+)*\.[a-z]{2,}(?![a-z0-9_.-])');
final _ipv4Pattern = RegExp(r'\b[0-9]{1,3}(?:\.[0-9]{1,3}){3}\b');
final _identifierChar = RegExp(r'[A-Za-z0-9_]');

/// The bodies of the string literals in Dart [source]: comments skipped,
/// escapes decoded, adjacent literals joined as the compiler joins them, an
/// interpolation blanked and the literals inside it read on their own, raw
/// and triple-quoted strings read.
List<String> stringLiterals(String source) {
  final out = <String>[];
  var i = 0;
  while (i < source.length) {
    final afterComment = _skipComment(source, i);
    if (afterComment != i) {
      i = afterComment;
      continue;
    }
    if (_literalAt(source, i) == null) {
      i++;
      continue;
    }
    final buf = StringBuffer();
    while (true) {
      i = _readLiteral(source, i, buf, out);
      final next = _skipSpaceAndComments(source, i);
      if (_literalAt(source, next) == null) break;
      i = next;
    }
    out.add(buf.toString());
  }
  return out;
}

/// The index after the comment opening at [i], or [i] when none does.
int _skipComment(String s, int i) {
  if (s.startsWith('//', i)) {
    final j = s.indexOf('\n', i);
    return j < 0 ? s.length : j + 1;
  }
  if (s.startsWith('/*', i)) {
    final j = s.indexOf('*/', i + 2);
    return j < 0 ? s.length : j + 2;
  }
  return i;
}

int _skipSpaceAndComments(String s, int i) {
  while (i < s.length) {
    final j = _skipComment(s, i);
    if (j != i) {
      i = j;
    } else if (s[i].trim().isEmpty) {
      i++;
    } else {
      break;
    }
  }
  return i;
}

/// The literal opening at [i]: its quote (`'`, `"` or the triple form) and
/// whether it is raw; null when no literal opens there.
(String, bool)? _literalAt(String s, int i) {
  var raw = false;
  if (i + 1 < s.length && s[i] == 'r' && (s[i + 1] == "'" || s[i + 1] == '"')) {
    raw = true;
    i++;
  }
  if (i >= s.length || (s[i] != "'" && s[i] != '"')) return null;
  final q = s.startsWith(s[i] * 3, i) ? s[i] * 3 : s[i];
  return (q, raw);
}

/// Reads the literal opening at [i] into [buf], escapes decoded and
/// interpolations blanked (the literals inside one are added to [out]),
/// and returns the index after its closing quote.
int _readLiteral(String s, int i, StringBuffer buf, List<String> out) {
  final (q, raw) = _literalAt(s, i)!;
  i += (raw ? 1 : 0) + q.length;
  while (i < s.length && !s.startsWith(q, i)) {
    final ch = s[i];
    if (!raw && ch == r'\') {
      final (text, next) = _escape(s, i);
      buf.write(text);
      i = next;
    } else if (!raw && ch == r'$') {
      if (i + 1 < s.length && s[i + 1] == '{') {
        final end = _closingBrace(s, i + 1);
        out.addAll(stringLiterals(s.substring(i + 2, end)));
        i = end + 1;
      } else {
        i++;
        while (i < s.length && _identifierChar.hasMatch(s[i])) {
          i++;
        }
      }
      buf.write(' ');
    } else {
      buf.write(ch);
      i++;
    }
  }
  return i + q.length;
}

/// The index of the brace closing the one at [open], by depth; the end of
/// [s] when none does.
int _closingBrace(String s, int open) {
  var depth = 0;
  for (var i = open; i < s.length; i++) {
    if (s[i] == '{') depth++;
    if (s[i] == '}' && --depth == 0) return i;
  }
  return s.length;
}

/// The text the Dart escape at [i] (its backslash) stands for and the index
/// after it: `\n` `\r` `\t` `\b` `\f` `\v`, `\xHH`, `\uHHHH`, `\u{H..}`, and
/// `\c` for any other `c`. A compile-time escape is how a host would hide
/// from a scan that read the source and not the value.
(String, int) _escape(String s, int i) {
  final c = i + 1 < s.length ? s[i + 1] : '';
  String fromHex(String hex) {
    final code = int.tryParse(hex, radix: 16);
    return code == null ? ' ' : String.fromCharCode(code);
  }

  switch (c) {
    case 'n':
      return ('\n', i + 2);
    case 'r':
      return ('\r', i + 2);
    case 't':
      return ('\t', i + 2);
    case 'b':
      return ('\b', i + 2);
    case 'f':
      return ('\f', i + 2);
    case 'v':
      return ('\v', i + 2);
    case 'x':
      final end = math.min(i + 4, s.length);
      return (fromHex(s.substring(i + 2, end)), end);
    case 'u':
      if (i + 2 < s.length && s[i + 2] == '{') {
        var close = s.indexOf('}', i + 3);
        if (close < 0) close = s.length;
        return (fromHex(s.substring(i + 3, close)), math.min(close + 1, s.length));
      }
      final end = math.min(i + 6, s.length);
      return (fromHex(s.substring(i + 2, end)), end);
    default:
      return (c, i + 2);
  }
}

/// Each dotted name in the string literals of [dart], lowercased, with the
/// literal that carries it.
List<(String, String)> literalNames(String dart) => [
      for (final literal in stringLiterals(dart))
        for (final m in _dottedName.allMatches(literal.toLowerCase()))
          (literal, m.group(0)!),
    ];

/// The dotted names in the string literals of [dart], lowercased.
List<String> dottedNames(String dart) => literalNames(dart)
    .map((e) => e.$2)
    .toList();

/// Packages that leave with the removed features.
const _removedPackages = [
  'soqushield_sdk',
  'sign_in_with_apple',
  'google_sign_in',
  'solana',
  'cryptography',
  'fl_chart',
  'video_player',
  'hive',
  'dio',
];

/// Screens, providers and services that leave the tree.
const _removedFiles = [
  'lib/screens/lightning/pay_pilot_screen.dart',
  'lib/screens/lightning/lightning_screen.dart',
  'lib/screens/swap/swap_pilot_screen.dart',
  'lib/screens/bridge/bridge_pilot_screen.dart',
  'lib/screens/privacy/privacy_pilot_screen.dart',
  'lib/screens/stablecoin/usdsoq_pilot_screen.dart',
  'lib/screens/sns/sns_names_screen.dart',
  'lib/screens/sns/sns_register_screen.dart',
  'lib/screens/network/network_pilot_screen.dart',
  'lib/screens/lab/intel_pilot_screen.dart',
  'lib/screens/utxo/utxo_screen.dart',
  'lib/screens/quests/quests_screen.dart',
  'lib/screens/shop/shop_screen.dart',
  'lib/screens/home/home_screen.dart',
  'lib/screens/send/send_screen.dart',
  'lib/screens/receive/receive_screen.dart',
  'lib/screens/settings/settings_screen.dart',
  'lib/screens/auth/welcome_screen.dart',
  'lib/screens/auth/lock_screen.dart',
  'lib/screens/splash_screen.dart',
  'lib/services/signer_service.dart',
  'lib/services/sns_service.dart',
  'lib/services/faucet_service.dart',
  'lib/services/solana_service.dart',
  'lib/services/social_auth_service.dart',
  'lib/services/bridge_service.dart',
  'lib/services/vault_bridge_service.dart',
  'lib/services/usdsoq_gateway_service.dart',
  'lib/services/confidential_tx_builder.dart',
  'lib/services/client_privacy_service.dart',
  'lib/services/lightning_channel_service.dart',
  'lib/providers/lightning_channel_provider.dart',
  'lib/providers/privacy_provider.dart',
  'lib/providers/usdsoq_provider.dart',
  'lib/providers/quest_provider.dart',
  'lib/providers/activation_provider.dart',
  'lib/crypto/latticebp_ffi.dart',
];

/// Every route path the lite app serves, and no other.
const _liteRoutes = {
  '/splash',
  '/welcome',
  '/lock',
  '/create-account',
  '/seed-backup',
  '/seed-restore',
  '/risk-disclosure',
  '/',
  '/send',
  '/activity',
  '/network',
  '/receive',
  '/settings',
  '/guide',
  '/guide/:id',
};

Set<String> _routePaths(List<RouteBase> routes) {
  final out = <String>{};
  for (final r in routes) {
    if (r is GoRoute) out.add(r.path);
    out.addAll(_routePaths(r.routes));
  }
  return out;
}

WalletState _wallet(SoqNetwork network, String address) => WalletState(
      balance: 0,
      keys: WalletKeys(
        publicKey: Uint8List(WalletKeys.pubKeySize),
        address: address,
        derivationPath: "m/44'/21329'/0'/0/0",
        accountIndex: 0,
        createdAt: DateTime(2026, 1, 1),
      ),
      network: network,
      backupConfirmed: true,
      isInitialized: true,
      isLoading: false,
    );

/// The app's providers mocked around [wallet]: authenticated, device auth
/// succeeds, the session arms no timer. [extra] adds overrides (the chain
/// poll, for instance); [auth] substitutes the device-auth fake.
Widget _scoped(WalletState wallet, Widget child,
        {List<dynamic> extra = const [], FakeAuthService? auth}) =>
    ProviderScope(
      overrides: [
        authProvider.overrideWith(() => MockAuthNotifier(AuthStatus.authenticated)),
        authServiceProvider.overrideWithValue(auth ?? FakeAuthService()),
        sessionProvider.overrideWith(MockSessionNotifier.new),
        walletProvider.overrideWith(() => MockWalletNotifier(wallet)),
        ...extra,
      ],
      child: child,
    );

/// Replace the tree so every provider is disposed, then drain the timers the
/// kept screens arm (the 30-second chain poll, the splash delays).
Future<void> _tearDownTree(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
  await tester.pump(const Duration(minutes: 1));
}

String _read(String path) => File(path).readAsStringSync();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    installSecureStorageMock();
    SharedPreferences.setMockInitialValues({});
  });

  group('routes', () {
    test('the router serves exactly the lite routes', () {
      expect(_routePaths(router.configuration.routes), _liteRoutes);
    });

    testWidgets('splash lands an authenticated wallet on the wallet home',
        (tester) async {
      router.go('/splash');
      await tester.pumpWidget(_scoped(_wallet(SoqNetwork.mainnet, _mainnetAddress), MaterialApp.router(routerConfig: router)));
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(router.routerDelegate.currentConfiguration.uri.path, '/');
      await _tearDownTree(tester);
    });

    testWidgets('unlock lands on the wallet home', (tester) async {
      router.go('/lock');
      await tester.pumpWidget(_scoped(_wallet(SoqNetwork.mainnet, _mainnetAddress), MaterialApp.router(routerConfig: router)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(router.routerDelegate.currentConfiguration.uri.path, '/');
      await _tearDownTree(tester);
    });
  });

  group('receive', () {
    testWidgets('the QR encodes the bare address and the screen takes no input',
        (tester) async {
      await tester.pumpWidget(_scoped(_wallet(SoqNetwork.mainnet, _mainnetAddress), const MaterialApp(home: ReceivePilotScreen())));
      await tester.pump();
      // The screen's own QR wrapper carries the payload it hands qr_flutter.
      expect(tester.widget<ReceiveQr>(find.byType(ReceiveQr)).data, _mainnetAddress);
      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.textContaining('payment request'), findsNothing);
    });
  });

  group('welcome', () {
    testWidgets('offers create and restore and no sign-in', (tester) async {
      await tester.pumpWidget(_scoped(const WalletState(), const MaterialApp(home: WelcomePilotScreen())));
      await tester.pump();
      expect(find.text('CREATE A WALLET'), findsOneWidget);
      expect(find.text('I ALREADY HAVE A WALLET'), findsOneWidget);
      expect(find.text('APPLE'), findsNothing);
      expect(find.text('GOOGLE'), findsNothing);
      expect(find.text('OR'), findsNothing);
    });
  });

  group('home', () {
    testWidgets('reads OFFLINE while the node does not answer', (tester) async {
      // The real chain poll against the test binding's HTTP client, which
      // answers 400 to everything: a failed poll must render OFFLINE.
      await tester.pumpWidget(_scoped(_wallet(SoqNetwork.mainnet, _mainnetAddress), const MaterialApp(home: HomePilotScreen())));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('SOQUCOIN · ML-DSA-44 · OFFLINE'), findsOneWidget);
      expect(find.textContaining('LIVE'), findsNothing);
      await _tearDownTree(tester);
    });

    testWidgets('reads LIVE when the node answers', (tester) async {
      await tester.pumpWidget(_scoped(
        _wallet(SoqNetwork.mainnet, _mainnetAddress),
        const MaterialApp(home: HomePilotScreen()),
        extra: [
          networkStatsProvider.overrideWith((ref) => const AsyncData(
              NetworkStats(blocks: 1234, peers: 8, reachable: true))),
        ],
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('SOQUCOIN · ML-DSA-44 · LIVE'), findsOneWidget);
      expect(find.text('SOQUCOIN · ML-DSA-44 · OFFLINE'), findsNothing);
      await _tearDownTree(tester);
    });

    testWidgets('carries send and receive and none of the removed surfaces',
        (tester) async {
      await tester.pumpWidget(_scoped(_wallet(SoqNetwork.mainnet, _mainnetAddress), const MaterialApp(home: HomePilotScreen())));
      await tester.pump();
      expect(find.text('SEND'), findsOneWidget);
      expect(find.text('RECEIVE'), findsOneWidget);
      for (final gone in ['SWAP', 'BRIDGE', 'PRIVATE', 'VISIBLE', 'USDSOQ', 'Bridged']) {
        expect(find.text(gone), findsNothing, reason: '$gone must be gone');
      }
      await _tearDownTree(tester);
    });
  });

  group('send', () {
    testWidgets('refuses before the device credential while the chain has no height',
        (tester) async {
      // A cached balance with no chain tip since boot (the mainnet case before
      // re-homing, or any network that has not answered): the send must stop
      // before asking for the credential.
      final auth = FakeAuthService();
      await tester.pumpWidget(_scoped(
        _wallet(SoqNetwork.mainnet, _mainnetAddress).copyWith(balance: 5),
        const MaterialApp(home: SendPilotScreen()),
        auth: auth,
      ));
      await tester.pump();
      await tester.enterText(find.byType(TextField).at(0), '1');
      await tester.enterText(find.byType(TextField).at(1), _mainnetAddress);
      await tester.pump();
      await tester.tap(find.text('SEND SOQ'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(auth.prompts, 0, reason: 'no credential prompt before the chain answers');
      expect(find.text('Waiting for the network'), findsOneWidget);
      await _tearDownTree(tester);
    });

    testWidgets('asks for the device credential once the chain has a height',
        (tester) async {
      final auth = FakeAuthService();
      await tester.pumpWidget(_scoped(
        _wallet(SoqNetwork.mainnet, _mainnetAddress).copyWith(balance: 5, blockHeight: 100),
        const MaterialApp(home: SendPilotScreen()),
        auth: auth,
      ));
      await tester.pump();
      await tester.enterText(find.byType(TextField).at(0), '1');
      await tester.enterText(find.byType(TextField).at(1), _mainnetAddress);
      await tester.pump();
      await tester.tap(find.text('SEND SOQ'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(auth.prompts, 1);
      await _tearDownTree(tester);
    });
  });

  group('settings', () {
    testWidgets('keeps security, backup, network and danger and drops the rest',
        (tester) async {
      // A stagenet wallet: on the full app that is where the faucet row shows.
      tester.view.physicalSize = const Size(430, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_scoped(_wallet(SoqNetwork.stagenet, _stagenetAddress), const MaterialApp(home: SettingsPilotScreen())));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      for (final kept in ['SECURITY', 'BACKUP & KEYS', 'NETWORK', 'ABOUT', 'DANGER ZONE',
          'Recovery phrase', 'Encrypted backup', 'Wipe wallet', 'SOQ address']) {
        expect(find.text(kept), findsOneWidget, reason: '$kept must stay');
      }
      for (final gone in ['PRIVACY', 'PROTOCOL', 'Faucet', 'Privacy dashboard', 'Coin control',
          'View key', 'Solana address']) {
        expect(find.text(gone), findsNothing, reason: '$gone must be gone');
      }
      expect(find.textContaining('window'), findsNothing,
          reason: 'the network note names no migration window');
      await _tearDownTree(tester);
    });
  });

  group('shell and drawer', () {
    testWidgets('the bar has no Pay tab and the drawer no removed destinations',
        (tester) async {
      router.go('/');
      await tester.pumpWidget(_scoped(_wallet(SoqNetwork.mainnet, _mainnetAddress), MaterialApp.router(routerConfig: router)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Wallet'), findsOneWidget);
      expect(find.text('Activity'), findsOneWidget);
      expect(find.text('Network'), findsOneWidget, reason: 'the weather tab');
      expect(find.text('More'), findsOneWidget);
      expect(find.text('Pay'), findsNothing);

      AppShell.scaffoldKey.currentState!.openDrawer();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      for (final kept in ['Help', 'Settings']) {
        expect(find.text(kept), findsOneWidget, reason: '$kept must stay');
      }
      // The Network tab replaces the drawer's observatory entry; the rest stay gone.
      for (final gone in ['History', 'Intel', 'Names (SNS)', 'SOQ-TEC Terminal', 'Block Explorer']) {
        expect(find.text(gone), findsNothing, reason: '$gone must be gone');
      }
      await _tearDownTree(tester);
    });
  });

  group('field manual', () {
    test('is trimmed to three categories', () {
      expect(guideCategories.map((c) => c.label).toList(),
          ['GETTING STARTED', 'EVERYDAY USE', 'STAY SAFE']);
    });

    test('names no removed feature and no launch date, and says when send opens', () {
      final text = <String>[];
      for (final c in guideCategories) {
        for (final a in c.articles) {
          text..add(a.title)..add(a.tagline);
          for (final s in a.sections) {
            text..add(s.heading ?? '')..add(s.body ?? '')..add(s.note ?? '')..addAll(s.steps);
          }
        }
      }
      final all = text.join('\n');
      final lower = all.toLowerCase();
      for (final term in ['usdsoq', 'swap', '.soq', 'pay tab', 'channel', 'faucet',
          'lightning', 'apple', 'google', 'coin control', 'stagenet beta', 'this beta']) {
        expect(lower, isNot(contains(term)), reason: '"$term" names a removed feature');
      }
      expect(lower, contains('opens at mainnet launch'));
      final dated = RegExp(
          r'\b(20\d\d|january|february|march|april|may|june|july|august|september|october|november|december)\b');
      expect(dated.hasMatch(lower), isFalse, reason: 'the manual names no date');
    });
  });

  group('source tree', () {
    test('every dotted name in a string literal under lib/ is an allowed host '
        'or a file the tree names; no IPv4 literal, pay scheme or SDK import '
        'anywhere under lib/', () {
      final files = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));
      for (final f in files) {
        final src = _read(f.path);
        for (final (literal, name) in literalNames(src)) {
          if (_knownFile(f.path, literal, name)) continue;
          expect(_allowedHosts, contains(name),
              reason: '${f.path} names $name, which is not on the allowlist');
        }
        expect(_ipv4Pattern.hasMatch(src), isFalse, reason: '${f.path} carries an IPv4 literal');
        expect(src, isNot(contains('soqushield://')), reason: '${f.path} still builds the pay link');
        expect(src, isNot(contains('package:soqushield_sdk')), reason: '${f.path} still imports the SDK');
      }
    });

    test('the literal scan reads a name whole under any last label, skips '
        'comments, decodes escapes, joins adjacent literals, reads the '
        'literals inside an interpolation, tells a file from a host by where '
        'it is named, catches an address literal, and reads every allowed '
        'host back', () {
      // The attacks: a removed host under an unlisted top-level domain, an
      // allowed host as the prefix or the suffix of a longer name, a host
      // that differs in case, a host in a comment, a host spelled with a
      // compile-time escape, a host split over adjacent literals, a host in
      // a literal inside an interpolation, a host after an interpolation, a
      // host under a file-name label, an infrastructure address.
      expect(dottedNames("final u = 'https://pump.fun/x';"), ['pump.fun']);
      expect(dottedNames("Uri.https('mainnet-api.soqu.org.attacker.xyz', '/')"),
          ['mainnet-api.soqu.org.attacker.xyz']);
      expect(dottedNames("'https://evil_host.mainnet-api.soqu.org/'"),
          ['evil_host.mainnet-api.soqu.org']);
      expect(dottedNames("'Relay.Example.ORG'"), ['relay.example.org']);
      expect(dottedNames("// see docs.flutter.dev\nfinal x = 1;"), isEmpty,
          reason: 'a comment is not a literal');
      expect(dottedNames("/* docs.flutter.dev */ final x = 'a.bc';"), ['a.bc']);
      const bs = r'\'; // one backslash, for a fixture spelled with an escape
      expect(dottedNames("'https://pump${bs}u002efun'"), ['pump.fun'],
          reason: 'a four-digit unicode escape is decoded');
      expect(dottedNames(r"'https://pump\u{2e}fun'"), ['pump.fun'],
          reason: 'a braced unicode escape is decoded');
      expect(dottedNames(r"'https://pump\x2efun'"), ['pump.fun'],
          reason: 'a hex escape is decoded');
      expect(dottedNames(r"'pump\nfun.xyz'"), ['fun.xyz'],
          reason: 'a newline escape ends a name');
      expect(dottedNames("'pump' '.fun'"), ['pump.fun'],
          reason: 'adjacent literals are the one string the compiler makes');
      expect(dottedNames("'pump' // a comment\n    '.fun'"), ['pump.fun'],
          reason: 'adjacent over a line and a comment too');
      expect(dottedNames("'pump' + '.fun'"), isEmpty,
          reason: 'a run-time join is not seen, as the allowlist says');
      expect(dottedNames(r"'${a}pump.fun'"), ['pump.fun'],
          reason: 'what follows an interpolation is still read');
      expect(dottedNames(r"'$a.pump.fun'"), ['pump.fun'],
          reason: 'what follows a bare interpolation and a dot is read');
      expect(dottedNames(r"'${'pump.fun'}'"), ['pump.fun'],
          reason: 'a literal inside an interpolation is read on its own');
      expect(dottedNames(r"'${f('pump' '.fun')}'"), ['pump.fun'],
          reason: 'adjacent literals inside an interpolation too');
      expect(dottedNames(r"'it\'s api.soqupool.com'"), ['api.soqupool.com'],
          reason: 'an escaped quote does not end the literal');
      expect(dottedNames("r'a${bs}u002eb.cd'"), ['u002eb.cd'],
          reason: 'a raw literal has no escapes: the backslash and the u stay text');
      expect(dottedNames('"x" + "y.dart" + r"z.png"'), ['y.dart', 'z.png']);
      // A file is told from a host by where it is named, not by its label.
      expect(_knownFile('lib/main.dart', 'router.dart', 'router.dart'), isTrue,
          reason: 'a relative import that resolves');
      expect(_knownFile('lib/main.dart', 'package:flutter/material.dart', 'material.dart'),
          isTrue, reason: 'a library URI');
      expect(_knownFile('lib/main.dart', 'nowhere.dart', 'nowhere.dart'), isFalse,
          reason: 'an import that resolves to no file');
      expect(_knownFile('lib/main.dart', 'https://attacker.sh', 'attacker.sh'), isFalse,
          reason: 'a host under a file-name label');
      expect(_knownFile('lib/main.dart', 'attacker.so', 'attacker.so'), isFalse);
      expect(_knownFile('lib/main.dart', 'native/dilithium/build_cli_dylib.sh',
              'build_cli_dylib.sh'), isTrue, reason: 'a file the tree names');
      expect(_knownFile('lib/main.dart', 'https://build_cli_dylib.sh/', 'build_cli_dylib.sh'),
          isFalse, reason: 'a known file name under a scheme is a host');
      expect(_ipv4Pattern.hasMatch("const origin = '203.0.113.7';"), isTrue);
      expect(_ipv4Pattern.hasMatch('version 2.5.0+26'), isFalse);
      for (final host in _allowedHosts) {
        expect(dottedNames("'https://$host/x'"), [host],
            reason: '$host is read back whole');
      }
    });

    test('the pool API host is named only by the weather service', () {
      final files = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart') && !f.path.endsWith('lib/services/weather_service.dart'));
      for (final f in files) {
        expect(_read(f.path), isNot(contains('soqupool.com')),
            reason: '${f.path} names the pool host; only the weather service reads it');
      }
    });

    test('declares none of the removed packages', () {
      final pubspec = _read('pubspec.yaml');
      for (final p in _removedPackages) {
        expect(RegExp('^\\s+$p:', multiLine: true).hasMatch(pubspec), isFalse,
            reason: 'pubspec still declares $p');
      }
    });

    test('has none of the removed screens, providers and services', () {
      for (final path in _removedFiles) {
        expect(File(path).existsSync(), isFalse, reason: '$path must be deleted');
      }
    });

    test('ios/ and android/ carry none of the removed library, pods, scheme or plugins', () {
      const exts = {'xcconfig', 'plist', 'pbxproj', 'lock', 'kts', 'gradle', 'xml',
          'entitlements', 'json', 'swift', 'kt', 'properties', 'yaml', 'yml', 'rb', 'md',
          'txt', 'h', 'm', 'xcprivacy', 'pro', 'xcscheme', 'storyboard', 'xcworkspacedata',
          'java'};
      // Build state is gitignored and not source; the gradle lock files under
      // android/.gradle/ are binary and would fail the UTF-8 read.
      const skip = ['/Pods/', '/build/', '/.gradle/', '/.symlinks/', '/Flutter/ephemeral/'];
      final files = [Directory('ios'), Directory('android')]
          .expand((d) => d.listSync(recursive: true))
          .whereType<File>()
          .where((f) => !skip.any(f.path.contains))
          .where((f) =>
              exts.contains(f.path.split('.').last) ||
              f.path.endsWith('Podfile') ||
              f.path.endsWith('Fastfile') ||
              f.path.endsWith('Appfile'));
      expect(files, isNotEmpty);
      for (final f in files) {
        final lower = _read(f.path).toLowerCase();
        for (final term in ['latticebp', 'google_sign_in', 'sign_in_with_apple', 'gidclientid',
            'applesignin', 'googleusercontent', 'soqushield_sdk', 'video_player', 'google_fonts']) {
          expect(lower, isNot(contains(term)), reason: '${f.path} still names $term');
        }
      }
    });
  });

  group('version', () {
    test('is the lite release', () {
      expect(kAppVersion, 'v2.4.1');
      expect(RegExp(r'^version:\s*2\.4\.1\+25\s*$', multiLine: true).hasMatch(_read('pubspec.yaml')),
          isTrue, reason: 'pubspec version must be 2.4.1+25, the build with the Network cards and the Send fit');
    });
  });
}
