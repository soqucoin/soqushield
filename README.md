# SoquShield

SoquShield is the self-custodial wallet for Soqucoin, a Layer 1 network built on post-quantum cryptography. Keys are generated and held on the device, and every transaction is signed on the device with ML-DSA-44 (FIPS 204), using the node's own C implementation through FFI. Soqucoin Labs never holds your funds and cannot move them.

This repository is the source of the app on Google Play and TestFlight. The current release is 2.4.1 (build 25).

## What the app does

- Create a wallet, or restore one from its 24 words
- Back it up: the recovery phrase, and an encrypted `.soqbackup` file (AES-256-GCM under an Argon2id-derived key)
- Show the address as text or as a QR code
- Send and receive SOQ with post-quantum signatures
- The value of a balance, an amount being sent, and each row of history, in any of 22 currencies
- Hide every amount with one tap, and choose whether the screen may be captured
- Activity: the wallet's history, rebuilt from the chain after a restore
- Network: the chain's block clock and public figures, and SOQUPOOL's published figures
- The Field Manual: the in-app user guide, no account needed

## Networks

A new wallet is created on Mainnet; balances and sending on Mainnet open at mainnet launch. Stagenet, the public test network, is one tap away in Settings for practising with test coins.

## Price and currency

Mainnet balances carry a money figure, read from CoinGecko's public [SOQ listing](https://www.coingecko.com/en/coins/soqucoin) every five minutes in whichever of the 22 currencies you pick in Settings. It is a public read with no key and no account, and the app sends nothing but the coin id and a currency code — no address, no balance. Nothing the wallet *does* is derived from it: amounts, fees and coin selection stay in koinu, and a price the app cannot read is simply not shown rather than falling back to `0.00`.

Stagenet shows no money figure and makes no price request at all: tSOQ is a test coin with no market, and a real number beside it would be read as real money.

## Privacy controls

**Hide balances** replaces every amount — the holdings readout, the asset row, the money figure and the Activity rows — with dots. Tap the balance on the Wallet screen, or use the switch in Settings. It persists: hide it to hand someone your phone and it stays hidden across tabs and restarts.

**Screen capture** is blocked by default. On Android that is `FLAG_SECURE`, which also blocks screen recording and casting — the live channel a remote-support scam needs. You can allow it in Settings if you want to share a balance or a receive code. On iOS no app can block a screenshot, so the setting governs the blur over the app in the app switcher, and the Settings copy says so.

Either way the recovery-phrase screens override the setting and protect themselves while visible: a phrase screenshotted once lives in the camera roll, and from there in whatever cloud backs it up.

## Get the app

- Google Play: https://play.google.com/store/apps/details?id=org.soqu.soqushield
- Android APK: the [Releases](https://github.com/soqucoin/soqushield/releases) page. Every release lists the SHA-256 of its APK, and every APK is signed with the same key, so a release installs over the previous one.
- iOS: [TestFlight](https://testflight.apple.com/join/tTUHeFmY)

To check a downloaded APK:

```sh
shasum -a 256 soqushield-v2.4.1-build25.apk
apksigner verify --print-certs soqushield-v2.4.1-build25.apk
```

The signing certificate's SHA-256 digest is `f274e1a60220ff095f9a4451cd0ac956450e9a0e3b619d44c1da10058830ede5`.

## Build from source

Flutter 3.41 (Dart 3.11), Xcode with CocoaPods for iOS (minimum deployment target 15.0 — Xcode 15 and later refuse to build a simulator slice below it), the Android SDK and NDK for Android (minSdk 24), and a C compiler. The ML-DSA-44 library is compiled from `native/dilithium` by the native-assets build hook in `hook/build.dart`; nothing is downloaded at build time.

```sh
flutter pub get
sh native/dilithium/build_cli_dylib.sh    # once: the host library the test suite loads
flutter analyze
flutter test
flutter build apk --debug                 # a release build refuses without a keystore named in android/key.properties
```

## Layout

```
lib/
├── main.dart, router.dart, app_version.dart
├── screens/        splash, auth (welcome, create, lock, seed backup, seed restore,
│                   risk disclosure), home, send, receive, activity, network,
│                   settings, guide, shell
├── providers/      wallet, auth, session, network stats, price, display prefs
├── services/       key derivation, secure storage, backup, RPC, ElectrumX balance,
│                   UTXO tracking, transaction builder, history, network weather,
│                   price, screen capture
├── crypto/         the Dilithium FFI binding, XMSS/WOTS (the backup format)
├── guide/          the Field Manual content
└── theme/          the instrument language, figures, motion, colours
test/               unit and widget tests, including the key-derivation known-answer vectors
integration_test/   simulator drives of the real app
native/dilithium/   the node's ML-DSA-44 C sources
hook/               the native-assets build hook
android/, ios/      the platform projects
```

`test/derivation_kat_test.dart` pins the key derivation to the vectors the node produces, so the same 24 words give the same address in the app, in the node and in the SOQUPOOL console.

## License

MIT License. Copyright © 2026 Soqucoin Labs Inc.
