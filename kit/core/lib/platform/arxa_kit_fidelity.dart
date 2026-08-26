import 'package:flutter/foundation.dart' show kDebugMode, visibleForTesting;

import 'arxa_kit_platform.dart';

/// App-level design-fidelity mode (QF-1…QF-4, fidelity-mode-config.md §2).
///
/// One of `flutter | mix | native`, declared per build target by the
/// scaffolder via `--dart-define=ARXA_FIDELITY=<mode>` and read here as a
/// compile-time const so `flutter` mode tree-shakes every native branch
/// (advisor 2026-08-14: only const environment values participate in const
/// conditionals; a runtime static ships all native wiring regardless).
enum ArxaKitFidelityMode {
  /// Pure Flutter-drawn tiers everywhere; native branches tree-shaken.
  /// Sanctioned law exception "app fidelity mode" (QF-4) — NOT the banned
  /// one-switch blanket demotion when declared at scaffold time.
  flutter,

  /// Default. Native chrome where capability exists, Flutter tier elsewhere;
  /// per-widget `preferFlutterTier` still wins locally.
  mix,

  /// Native chrome required. Missing capability is an error, never a silent
  /// fallback (QF-1) — one deterministic [FidelityViolation] at app-root
  /// init via [ArxaKitFidelity.validateAtRoot] (QF-1 amendment: throw
  /// site moved from first-gate-evaluation to root init).
  native,
}

/// Thrown (debug AND release) when a `native`-fidelity app runs on a target
/// without native chrome capability, or the `ARXA_FIDELITY` define is not
/// a recognized mode.
class FidelityViolation extends Error {
  FidelityViolation(this.message);

  final String message;

  @override
  String toString() => 'FidelityViolation: $message';
}

/// Single source of truth for the declared fidelity mode.
///
/// Widgets never read this directly — they gate on
/// [ArxaKitPlatform.supportsNativeChrome] (and friends), which compose
/// [allowsNative] with raw capability. The generated app root calls
/// [validateAtRoot] once in `main()`.
class ArxaKitFidelity {
  ArxaKitFidelity._();

  static const String _raw =
      String.fromEnvironment('ARXA_FIDELITY', defaultValue: 'mix');

  /// The mode declared at build time. Unrecognized raw values resolve to
  /// [ArxaKitFidelityMode.mix] here so const evaluation stays total;
  /// [validateAtRoot] is what rejects them loudly.
  static const ArxaKitFidelityMode declared = _raw == 'flutter'
      ? ArxaKitFidelityMode.flutter
      : _raw == 'native'
          ? ArxaKitFidelityMode.native
          : ArxaKitFidelityMode.mix;

  /// Test-only override (kDebugMode-guarded so release builds fold [mode]
  /// to the const [declared] and tree-shaking is preserved). Set in `setUp`,
  /// clear with [reset] in `tearDown`.
  @visibleForTesting
  static ArxaKitFidelityMode? debugOverride;

  /// Clear the test override.
  @visibleForTesting
  static void reset() => debugOverride = null;

  /// Effective mode: const [declared] in release; overridable in debug/tests.
  static ArxaKitFidelityMode get mode {
    if (kDebugMode) {
      final forced = debugOverride;
      if (forced != null) return forced;
    }
    return declared;
  }

  /// False only in `flutter` mode — the tree-shaking clamp composed into
  /// every [ArxaKitPlatform] `supports*` getter.
  static bool get allowsNative => mode != ArxaKitFidelityMode.flutter;

  /// True only in `native` mode (error-not-fallback semantics).
  static bool get strict => mode == ArxaKitFidelityMode.native;

  /// Pure mapping from a raw define string; throws [FidelityViolation] on
  /// unrecognized input. Kept as a testable pure function (the const
  /// [declared] path cannot be flipped by tests).
  static ArxaKitFidelityMode parse(String raw) {
    switch (raw) {
      case 'flutter':
        return ArxaKitFidelityMode.flutter;
      case 'mix':
        return ArxaKitFidelityMode.mix;
      case 'native':
        return ArxaKitFidelityMode.native;
      default:
        throw FidelityViolation(
          'unrecognized ARXA_FIDELITY "$raw" — expected flutter|mix|native',
        );
    }
  }

  /// The single strict-mode fail-fast (QF-1 as amended): called once by the
  /// generated app root in `main()`. Throws [FidelityViolation] (debug AND
  /// release) if the define is unrecognized, or if `native` fidelity is
  /// declared on a target with no native chrome capability. One
  /// deterministic crash point with one stack trace — never a lazy
  /// first-gate release throw.
  static void validateAtRoot() {
    parse(kDebugMode && debugOverride != null
        ? debugOverride!.name
        : _raw); // throws on unrecognized define
    if (strict && !ArxaKitPlatform.nativeChromeCapability) {
      throw FidelityViolation(
        'fidelity "native" declared but this target has no native chrome '
        'capability (need iOS 26+ Liquid Glass or Android Compose M3E) — '
        'declare "mix" or "flutter" for this target in arxa.config',
      );
    }
  }
}
