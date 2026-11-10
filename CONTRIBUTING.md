# Contributing to SoquShield

SoquShield is the self-custodial wallet for Soqucoin, a Layer 1 network based on Dogecoin Core with post-quantum signatures. The app on Google Play and the App Store is built from this repository and from nowhere else.

## How a change lands

1. Work on a branch and open a pull request as a draft. Copilot reviews it at open.
2. Answer every review thread with the fixing commit or with the reason the finding does not hold, then resolve the thread.
3. The checks pass: `flutter analyze`, `flutter test`, the store scripts' tests, the store-copy check and gitleaks.
4. Mark the pull request ready. One approving review is required, and the owner of the GitHub account merges.
5. Nobody pushes to `main`, force-pushes, or merges their own pull request.

One pull request per change. A change to key handling, signing, the transaction builder, backups, authentication or a network path is security relevant and travels alone. Its pull request body opens with a threat and state pass written before the first line of code: what a wrong, stale or hostile input can do, and the proof that the amount a person approved on the review screen is the only amount the transaction carries.

## Commit messages

A commit message describes the change in ten lines or fewer. It names no person and carries no AI attribution trailer or footer.

## What the app is

- Non-custodial. Keys are generated and held on the device. No part of the app or its services holds anyone's money or can move it.
- No wallet runs on a server. The app talks to public nodes and indexers, and every host it names is on the allowlist in `test/lite_scope_test.dart`, which the test suite enforces.
- Every transaction is signed with ML-DSA-44 (FIPS 204). No other signature scheme enters the signing path.
- Soqucoin is described as based on Dogecoin Core. The word fork is not used.
- Stagenet shows no money figure. A price shown beside a mainnet amount is a reading of a public market feed: the SOQ amount is what the transaction carries, and no chart, no change figure and no portfolio framing appear anywhere.

## Public text

The listing text under `android/fastlane/metadata` and `ios/fastlane/metadata`, the TestFlight description under `store-assets`, the release notes and the README are read by the public. They state what is true on the day they are published: no price, no market figure, no claim about the network's future. Short sentences, no em dashes. Mainnet has run since 13 October 2026, and the store-copy check refuses the wording of the pre-launch builds.

## Releases

`pubspec.yaml` carries `version: major.minor.patch+build`. The build number rises on every upload, because both stores reject a repeated one. A merge to `main` builds the app and uploads it to TestFlight and to the Play internal track. A tag `v<version>-build<build>` on `main` promotes that build to production after the approval step. The same tag builds the Android APK from the tagged commit and, after the same approval step, publishes it on the GitHub Releases page with its SHA-256, once `scripts/apk_release.py` has found the certificate of every earlier APK in the built file. The tag names a commit on `main` whose testing upload has finished and whose build Apple has processed. Before the tag, the App Store version for the marketing version exists (the iOS `metadata` lane creates it from the listing text, or it is created in App Store Connect) and the release notes are written. Before an upload, the device drive under `integration_test` runs on an iOS simulator and on an Android emulator, and the pull request names the run. Release signing material and store credentials live in the repository's Actions secrets and in a local `~/.soqushield-release.env` (see `fastlane.env.example`), and nowhere in the tree.

## Reading

- `README.md`: the build from source and the layout.
- `test/lite_scope_test.dart`: the route table, the QR payload and the host allowlist.
- `ios/fastlane/Fastfile` and `android/fastlane/Fastfile`: the lanes.
- `scripts/`: the App Store Connect and Play Console tools and their tests.
- `.github/workflows/`: the checks and the release workflow.
