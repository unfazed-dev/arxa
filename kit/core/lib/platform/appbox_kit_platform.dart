import 'dart:io' show Platform;

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

import 'appbox_kit_fidelity.dart';

/// Single source of truth for host platform + native-chrome capability gating.
///
/// Pure Dart; safe on web (every `dart:io` [Platform] read is guarded by
/// [kIsWeb]). Native-chrome widgets (Liquid Glass iOS 26, Compose M3 Android)
/// route through [supportsNativeChrome] so the choice lives in one testable
/// place — mirrors the validated starling `supportsNative` gate.
class AppBoxKitPlatform {
  AppBoxKitPlatform._();

  /// Test override (set in `setUp`, clear with [reset] in `tearDown`) — also
  /// used at runtime to force a tier where no native one exists (e.g. web).
  static AppBoxKitPlatformOverride? override;

  /// Clear the test override.
  static void reset() => override = null;

  // --- identity ---
  static bool get isWeb => kIsWeb;

  static bool get isIOS {
    final forced = override?._isIOS;
    if (forced != null) return forced;
    if (kIsWeb) return false;
    return Platform.isIOS;
  }

  static bool get isAndroid {
    final forced = override?._isAndroid;
    if (forced != null) return forced;
    if (kIsWeb) return false;
    return Platform.isAndroid;
  }

  static bool get isDesktop => !isWeb && !isIOS && !isAndroid && _hostIsDesktop;

  /// iOS or Android (a real mobile OS behind a platform view).
  static bool get isMobileNative => isIOS || isAndroid;

  /// Major OS version on iOS. `0` off-iOS.
  // ponytail: regex on Platform.operatingSystemVersion — sync + dependency-free,
  // but fragile to Apple reformatting the string. Upgrade path: device_info_plus
  // .systemVersion if this ever mis-parses in the field.
  static int get iosMajor {
    final forced = override?._iosMajor;
    if (forced != null) return forced;
    if (!isIOS) return 0;
    final m = RegExp(r'\d+').firstMatch(Platform.operatingSystemVersion);
    return int.tryParse(m?.group(0) ?? '') ?? 0;
  }

  // --- native-chrome capability (the tier-1 gate) ---
  // Raw capability (pre-fidelity-policy). Used only by
  // AppBoxKitFidelity.validateAtRoot and the debug assert below; widgets
  // gate on the supports* getters, which compose the app fidelity mode.

  /// Raw: iOS 26+ renders real Liquid Glass via standard UIKit hosted in a
  /// platform view.
  static bool get liquidGlassCapability => isIOS && iosMajor >= 26;

  /// Raw: Android hosts Jetpack Compose Material 3 / M3-Expressive via a
  /// platform view.
  static bool get composeM3ECapability => isAndroid;

  /// Raw: any real native chrome is renderable on this platform.
  static bool get nativeChromeCapability =>
      liquidGlassCapability || composeM3ECapability;

  /// Capability ∧ fidelity policy: `flutter` mode clamps this false
  /// everywhere (const-foldable — native branches tree-shake).
  static bool get supportsLiquidGlass =>
      AppBoxKitFidelity.allowsNative && liquidGlassCapability;

  /// Capability ∧ fidelity policy.
  static bool get supportsComposeM3E =>
      AppBoxKitFidelity.allowsNative && composeM3ECapability;

  /// Any native chrome renderable AND allowed by the declared fidelity mode.
  static bool get supportsNativeChrome {
    // QF-1 amendment: strict-mode release throw lives at root init only;
    // this per-gate check is the debug-only backstop in the shared helper.
    assert(() {
      if (AppBoxKitFidelity.strict && !nativeChromeCapability) {
        throw FidelityViolation(
          'native fidelity with no native chrome capability reached a tier '
          'gate — AppBoxKitFidelity.validateAtRoot() was not called at app '
          'root, or the target config is wrong',
        );
      }
      return true;
    }());
    return supportsLiquidGlass || supportsComposeM3E;
  }

  // --- widget-tree platform (Cupertino-vs-Material fallback choice) ---
  static TargetPlatform get targetPlatform =>
      override?._targetPlatform ?? defaultTargetPlatform;
}

bool get _hostIsDesktop =>
    Platform.isMacOS || Platform.isWindows || Platform.isLinux;

/// Test override for [AppBoxKitPlatform]: force identity, iOS major version, and/or
/// the widget-tree [TargetPlatform]. All fields optional.
class AppBoxKitPlatformOverride {
  const AppBoxKitPlatformOverride({
    bool? isIOS,
    bool? isAndroid,
    int? iosMajor,
    TargetPlatform? targetPlatform,
  })  : _isIOS = isIOS,
        _isAndroid = isAndroid,
        _iosMajor = iosMajor,
        _targetPlatform = targetPlatform;

  final bool? _isIOS;
  final bool? _isAndroid;
  final int? _iosMajor;
  final TargetPlatform? _targetPlatform;
}

/// Render tier resolved per native-chrome widget.
enum AppBoxKitTier { native, fallback }
