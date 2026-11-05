# SoquShield

The self-custodial wallet for Soqucoin. The app on Google Play and the App Store
is built from this repository and from nowhere else.

Read `CONTRIBUTING.md` for the full rules and `ONBOARDING.md` for the setup. This
file is the short form a coding assistant needs before it writes a line.

## Invariants

- Non-custodial. Keys are generated and held on the device. No part of the app or
  its services holds anyone's money or can move it.
- No wallet runs on a server. The app talks to public nodes and indexers. Every
  host it names is on the allowlist in `test/lite_scope_test.dart`, which the
  suite enforces. Adding a host means adding it there first.
- Every transaction is signed with ML-DSA-44 (FIPS 204). No other signature
  scheme enters the signing path.
- Soqucoin is described as based on Dogecoin Core. The word fork is not used.
- Amounts, fees and coin selection stay in koinu. Nothing the wallet does is
  derived from a price.
- Stagenet shows no money figure and makes no price request.

## The price line

- The app reads the company's cached route. It never calls CoinGecko itself.
- The dollar line is opt-in in Settings and off by default.
- It shows the source and the age of the rate.
- No 24-hour change figure and no chart. No portfolio framing anywhere.

## How a change lands

1. One pull request per change. A change to key handling, signing, the
   transaction builder, backups, authentication or a network path is security
   relevant and travels alone.
2. A security-relevant pull request body opens with a threat and state pass: what
   a wrong, stale or hostile input can do, and the proof that the amount a person
   approved on the review screen is the only amount the transaction carries.
3. Open as a draft (`gh pr create --draft`). Copilot reviews at open.
4. Answer every review thread with the fixing commit or the reason the finding
   does not hold, then resolve it, before marking the pull request ready.
5. The checks pass: `flutter analyze`, `flutter test`, the store scripts' tests,
   the store-copy check and gitleaks.
6. One approving review is required and the account holder merges. Nobody pushes
   to `main`, force-pushes, or merges their own pull request.

## Commit messages

Ten lines or fewer. No person named. No AI attribution trailer or footer.

## Public text

`README.md`, the listing text under `android/fastlane/metadata` and
`ios/fastlane/metadata`, the TestFlight description under `store-assets`, and the
release notes are read by the public. They state what is true on the day they are
published: no price, no market figure, no claim about the network's future. Short
sentences, no em dashes. Mainnet has run since 13 October 2026, and
`.github/scripts/check-store-copy.py` refuses the wording of the pre-launch
builds.

## Releases

`pubspec.yaml` carries `version: major.minor.patch+build`. The build number rises
on every upload. A merge to `main` uploads to TestFlight and the Play internal
track. A tag `v<version>-build<build>` promotes that build to production after the
approval step. Before an upload, `integration_test/real_flow_test.dart` runs on an
iOS simulator and on an Android emulator, and the pull request names the run.

Signing material and store credentials live in the repository's Actions secrets
and in a local `~/.soqushield-release.env`, and nowhere in the tree.

## Build

```sh
flutter pub get
sh native/dilithium/build_cli_dylib.sh    # once: the host library the tests load
flutter analyze
flutter test
```
