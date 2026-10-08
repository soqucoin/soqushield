/// Single source of truth for the displayed app version.
///
/// Must match the `version:` line in pubspec.yaml (build metadata excluded) —
/// a drift test in test/mainnet_readiness_test.dart enforces this.
const String kAppVersion = 'v2.4.1';
