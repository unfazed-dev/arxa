import 'package:arxa_kit_core/arxa_kit_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() {
    ArxaKitFidelity.reset();
    ArxaKitPlatform.reset();
  });

  ArxaKitPlatformOverride ios26() =>
      const ArxaKitPlatformOverride(isIOS: true, iosMajor: 26);
  ArxaKitPlatformOverride noNative() =>
      const ArxaKitPlatformOverride(isIOS: false, isAndroid: false);

  group('parse (pure)', () {
    test('maps the three modes', () {
      expect(ArxaKitFidelity.parse('flutter'), ArxaKitFidelityMode.flutter);
      expect(ArxaKitFidelity.parse('mix'), ArxaKitFidelityMode.mix);
      expect(ArxaKitFidelity.parse('native'), ArxaKitFidelityMode.native);
    });

    test('throws FidelityViolation on unrecognized raw', () {
      expect(
        () => ArxaKitFidelity.parse('hybrid'),
        throwsA(isA<FidelityViolation>()),
      );
    });
  });

  group('defaults', () {
    test('no define + no override => mix, allowsNative, not strict', () {
      expect(ArxaKitFidelity.mode, ArxaKitFidelityMode.mix);
      expect(ArxaKitFidelity.allowsNative, isTrue);
      expect(ArxaKitFidelity.strict, isFalse);
    });
  });

  group('flutter mode clamps supports*', () {
    test('supports* false even where capability is real', () {
      ArxaKitPlatform.override = ios26();
      expect(ArxaKitPlatform.supportsLiquidGlass, isTrue); // mix baseline
      ArxaKitFidelity.debugOverride = ArxaKitFidelityMode.flutter;
      expect(ArxaKitPlatform.supportsLiquidGlass, isFalse);
      expect(ArxaKitPlatform.supportsNativeChrome, isFalse);
      // raw capability is untouched by policy
      expect(ArxaKitPlatform.nativeChromeCapability, isTrue);
      expect(ArxaKitPlatform.liquidGlassCapability, isTrue);
    });
  });

  group('mix mode follows capability', () {
    test('capability present', () {
      ArxaKitFidelity.debugOverride = ArxaKitFidelityMode.mix;
      ArxaKitPlatform.override = ios26();
      expect(ArxaKitPlatform.supportsNativeChrome, isTrue);
    });

    test('capability absent', () {
      ArxaKitFidelity.debugOverride = ArxaKitFidelityMode.mix;
      ArxaKitPlatform.override = noNative();
      expect(ArxaKitPlatform.supportsNativeChrome, isFalse);
    });
  });

  group('native mode (QF-1 as amended)', () {
    test('validateAtRoot passes with capability', () {
      ArxaKitFidelity.debugOverride = ArxaKitFidelityMode.native;
      ArxaKitPlatform.override = ios26();
      expect(ArxaKitFidelity.validateAtRoot, returnsNormally);
      expect(ArxaKitPlatform.supportsNativeChrome, isTrue);
    });

    test('validateAtRoot throws FidelityViolation without capability', () {
      ArxaKitFidelity.debugOverride = ArxaKitFidelityMode.native;
      ArxaKitPlatform.override = noNative();
      expect(
        ArxaKitFidelity.validateAtRoot,
        throwsA(isA<FidelityViolation>()),
      );
    });

    test('debug-only per-gate backstop fires if root validation skipped', () {
      ArxaKitFidelity.debugOverride = ArxaKitFidelityMode.native;
      ArxaKitPlatform.override = noNative();
      expect(
        () => ArxaKitPlatform.supportsNativeChrome,
        throwsA(isA<FidelityViolation>()),
      );
    });
  });

  group('state hygiene', () {
    test('reset restores declared mode', () {
      ArxaKitFidelity.debugOverride = ArxaKitFidelityMode.flutter;
      ArxaKitFidelity.reset();
      expect(ArxaKitFidelity.mode, ArxaKitFidelity.declared);
    });
  });
}
