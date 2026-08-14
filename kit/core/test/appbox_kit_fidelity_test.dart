import 'package:appbox_kit_core/appbox_kit_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() {
    AppBoxKitFidelity.reset();
    AppBoxKitPlatform.reset();
  });

  AppBoxKitPlatformOverride ios26() =>
      const AppBoxKitPlatformOverride(isIOS: true, iosMajor: 26);
  AppBoxKitPlatformOverride noNative() =>
      const AppBoxKitPlatformOverride(isIOS: false, isAndroid: false);

  group('parse (pure)', () {
    test('maps the three modes', () {
      expect(AppBoxKitFidelity.parse('flutter'), AppBoxKitFidelityMode.flutter);
      expect(AppBoxKitFidelity.parse('mix'), AppBoxKitFidelityMode.mix);
      expect(AppBoxKitFidelity.parse('native'), AppBoxKitFidelityMode.native);
    });

    test('throws FidelityViolation on unrecognized raw', () {
      expect(
        () => AppBoxKitFidelity.parse('hybrid'),
        throwsA(isA<FidelityViolation>()),
      );
    });
  });

  group('defaults', () {
    test('no define + no override => mix, allowsNative, not strict', () {
      expect(AppBoxKitFidelity.mode, AppBoxKitFidelityMode.mix);
      expect(AppBoxKitFidelity.allowsNative, isTrue);
      expect(AppBoxKitFidelity.strict, isFalse);
    });
  });

  group('flutter mode clamps supports*', () {
    test('supports* false even where capability is real', () {
      AppBoxKitPlatform.override = ios26();
      expect(AppBoxKitPlatform.supportsLiquidGlass, isTrue); // mix baseline
      AppBoxKitFidelity.debugOverride = AppBoxKitFidelityMode.flutter;
      expect(AppBoxKitPlatform.supportsLiquidGlass, isFalse);
      expect(AppBoxKitPlatform.supportsNativeChrome, isFalse);
      // raw capability is untouched by policy
      expect(AppBoxKitPlatform.nativeChromeCapability, isTrue);
      expect(AppBoxKitPlatform.liquidGlassCapability, isTrue);
    });
  });

  group('mix mode follows capability', () {
    test('capability present', () {
      AppBoxKitFidelity.debugOverride = AppBoxKitFidelityMode.mix;
      AppBoxKitPlatform.override = ios26();
      expect(AppBoxKitPlatform.supportsNativeChrome, isTrue);
    });

    test('capability absent', () {
      AppBoxKitFidelity.debugOverride = AppBoxKitFidelityMode.mix;
      AppBoxKitPlatform.override = noNative();
      expect(AppBoxKitPlatform.supportsNativeChrome, isFalse);
    });
  });

  group('native mode (QF-1 as amended)', () {
    test('validateAtRoot passes with capability', () {
      AppBoxKitFidelity.debugOverride = AppBoxKitFidelityMode.native;
      AppBoxKitPlatform.override = ios26();
      expect(AppBoxKitFidelity.validateAtRoot, returnsNormally);
      expect(AppBoxKitPlatform.supportsNativeChrome, isTrue);
    });

    test('validateAtRoot throws FidelityViolation without capability', () {
      AppBoxKitFidelity.debugOverride = AppBoxKitFidelityMode.native;
      AppBoxKitPlatform.override = noNative();
      expect(
        AppBoxKitFidelity.validateAtRoot,
        throwsA(isA<FidelityViolation>()),
      );
    });

    test('debug-only per-gate backstop fires if root validation skipped', () {
      AppBoxKitFidelity.debugOverride = AppBoxKitFidelityMode.native;
      AppBoxKitPlatform.override = noNative();
      expect(
        () => AppBoxKitPlatform.supportsNativeChrome,
        throwsA(isA<FidelityViolation>()),
      );
    });
  });

  group('state hygiene', () {
    test('reset restores declared mode', () {
      AppBoxKitFidelity.debugOverride = AppBoxKitFidelityMode.flutter;
      AppBoxKitFidelity.reset();
      expect(AppBoxKitFidelity.mode, AppBoxKitFidelity.declared);
    });
  });
}
