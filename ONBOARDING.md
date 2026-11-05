# SoquShield developer onboarding

## Toolchain

- Flutter 3.41 stable (Dart 3.11), Xcode 26 with CocoaPods, the Android SDK with the NDK, a C compiler and Python 3.
- fastlane 2.236 or later for the store lanes.
- The `gh` command line, signed in to the GitHub account that holds write access on `soqucoin/soqushield`.

## First build

```sh
git clone https://github.com/soqucoin/soqushield.git
cd soqushield
flutter pub get
sh native/dilithium/build_cli_dylib.sh    # the host ML-DSA-44 library the test suite loads
flutter analyze
flutter test
flutter build apk --debug
```

A release build refuses without `android/key.properties` and the keystore it names. Release signing happens in the repository's workflow, so a developer machine builds debug variants.

## The device drive

`integration_test/real_flow_test.dart` drives the real app against the live endpoints: every flow on an iOS simulator and on an Android emulator. Run it before an upload and name the run in the pull request.

```sh
flutter test integration_test/real_flow_test.dart -d "iPhone 16 Pro Max"
flutter test integration_test/real_flow_test.dart -d emulator-5554
```

## The coding seat

A coding assistant reads a context file at the checkout root, under the name its vendor chose. Create it from the rules in `CONTRIBUTING.md`, in your own first pull request. Turn off the setting that adds an AI co-author trailer to commits. For the seat in use here that is `"includeCoAuthoredBy": false` in the user settings file.

The habits beyond the settings: pull requests open as drafts (`gh pr create --draft`), every review thread is answered and resolved before the pull request is marked ready, and the owner merges.

## Store consoles

- App Store Connect: an invitation to the team with access to SoquShield at the App Manager role and the certificates permission. The lanes and the scripts take a team API key, generated for you by the account holder under Users and Access, Integrations, Team Keys, at the App Manager role. An individual key has no issuer id and signs a different token, which the scripts do not produce yet.
- Google Play Console: an invitation with app-level access to SoquShield. For the scripts, a service account in your own Google Cloud project, invited to the Play Console with the same app permissions.
- Fill `~/.soqushield-release.env` from `fastlane.env.example` with your own key id, issuer id, key path and service-account path. `python3 scripts/play_status.py` and `python3 scripts/asc.py get '/v1/apps/6759628525/builds?limit=3'` confirm the access.

No keystore, certificate or key file passes between machines. The release workflow signs with material the account owner holds in the repository's secrets.

## Where things are decided

- `CONTRIBUTING.md`: the rules a change follows and what the app is.
- `test/lite_scope_test.dart`: the host allowlist and the route table.
- `.github/workflows/checks.yml` and `release.yml`: what runs on a pull request, a merge and a tag.
