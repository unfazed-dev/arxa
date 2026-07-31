import 'dart:io' show Platform;

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Single source of truth for host platform + native-chrome capability gating.
///
/// Pure Dart; safe on web (every `dart:io` [Platform] read is guarded by
/// [kIsWeb]). Native-chrome widgets (Liquid Glass iOS 26, Compose M3 Android)
/// route through [supportsNativeChrome] so the choice lives in one testable
/// place — mirrors the validated starling `supportsNative` gate.
class KitPlatform {
  KitPlatform._();

  /// Test override (set in `setUp`, clear with [reset] in `tearDown`) — also
  /// used at runtime to force a tier where no native one exists (e.g. web).
  static KitPlatformOverride? override;

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
  /// iOS 26+ renders real Liquid Glass via standard UIKit hosted in a platform view.
  static bool get supportsLiquidGlass => isIOS && iosMajor >= 26;

  /// Android hosts Jetpack Compose Material 3 / M3-Expressive via a platform view.
  static bool get supportsComposeM3E => isAndroid;

  /// Any real native chrome is renderable on this platform.
  static bool get supportsNativeChrome =>
      supportsLiquidGlass || supportsComposeM3E;

  // --- widget-tree platform (Cupertino-vs-Material fallback choice) ---
  static TargetPlatform get targetPlatform =>
      override?._targetPlatform ?? defaultTargetPlatform;
}

bool get _hostIsDesktop =>
    Platform.isMacOS || Platform.isWindows || Platform.isLinux;

/// Test override for [KitPlatform]: force identity, iOS major version, and/or
/// the widget-tree [TargetPlatform]. All fields optional.
class KitPlatformOverride {
  const KitPlatformOverride({
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
enum KitTier { native, fallback }
