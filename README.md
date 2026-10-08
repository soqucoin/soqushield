# SoquShield

SoquShield is the self-custodial wallet for Soqucoin, a Layer 1 network built on post-quantum cryptography. Keys are generated and held on the device, and every transaction is signed on the device with ML-DSA-44 (FIPS 204), using the node's own C implementation through FFI. Soqucoin Labs never holds your funds and cannot move them.

This repository is the source of the app on Google Play and TestFlight. The current release is 2.4.1 (build 25).

## What the app does

- Create a wallet, or restore one from its 24 words
- Back it up: the recovery phrase, and an encrypted `.soqbackup` file
- Show the address as text or as a QR code
- Send and receive SOQ with post-quantum signatures
- Activity: the wallet's history, rebuilt from the chain after a restore
- Network: the chain's block clock and public figures, and SOQUPOOL's published figures
- The Field Manual: the in-app user guide, no account needed

## Networks

A new wallet is created on Mainnet; balances and sending on Mainnet open at mainnet launch. Stagenet, the public test network, is one tap away in Settings for practising with test coins.

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

Flutter 3.41 (Dart 3.11), Xcode with CocoaPods for iOS, the Android SDK and NDK for Android, and a C compiler. The ML-DSA-44 library is compiled from `native/dilithium` by the native-assets build hook in `hook/build.dart`; nothing is downloaded at build time.

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
├── providers/      wallet, auth, session, network stats
├── services/       key derivation, secure storage, backup, RPC, ElectrumX balance,
│                   UTXO tracking, transaction builder, history, network weather
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
