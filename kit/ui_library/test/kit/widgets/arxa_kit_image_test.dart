import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:arxa_kit_core/common/arxa_kit_glyphs.dart';
import 'package:arxa_kit_ui_library/widgets/arxa_kit_image.dart';

import 'arxa_kit_native_test_helpers.dart';

/// ArxaKitImage tests.
///
/// The kit ships **no bundled image asset**, so the happy-path decode (real
/// `Image.asset` rendering a frame) is exercised in the host app's tests,
/// where host assets are bundled. These widget tests cover what the kit can
/// verify standalone:
/// - construction wiring (the `Image.asset` is constructed with the path),
/// - the empty-asset fallback (placeholder glyph shown, no crash),
/// - the load-error fallback (`errorBuilder` → placeholder glyph), and
/// - the custom-placeholder + radius parameters.
void main() {
  testWidgets(
      'kit.ui-library.image — constructs an Image.asset with the given path',
      (tester) async {
    await tester.pumpWidget(host(const ArxaKitImage(
      asset: 'assets/some/product.jpg',
      size: 48,
    )));

    final image = tester.widget<Image>(find.byType(Image));
    expect(image, isA<Image>());
    expect((image.image as AssetImage).assetName, 'assets/some/product.jpg');
    expect(image.width, 48);
    expect(image.height, 48);
  });

  testWidgets(
      'kit.ui-library.image — empty asset shows the placeholder glyph and never throws',
      (tester) async {
    await tester.pumpWidget(host(const ArxaKitImage(asset: '', size: 48)));
    await tester.pump();

    expect(find.byType(Image), findsNothing,
        reason: 'an empty asset must not construct an Image.asset');
    expect(find.byIcon(ArxaKitGlyphs.photo.icon), findsOneWidget,
        reason: 'the default placeholder (ArxaKitGlyphs.photo) is shown');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'kit.ui-library.image — a missing asset falls back to the placeholder glyph',
      (tester) async {
    // A path that does not exist in the bundle — the errorBuilder must
    // catch the decode failure and show the placeholder instead of the
    // framework's red error box.
    await tester.pumpWidget(host(const ArxaKitImage(
      asset: 'assets/does/not/exist.jpg',
      size: 48,
    )));
    // Pump past the asset-load failure so the errorBuilder runs.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));

    expect(find.byIcon(ArxaKitGlyphs.photo.icon), findsOneWidget,
        reason: 'errorBuilder should render the placeholder glyph');
  });

  testWidgets('kit.ui-library.image — honors a custom placeholder glyph',
      (tester) async {
    await tester.pumpWidget(host(const ArxaKitImage(
      asset: '',
      size: 48,
      placeholder: ArxaKitGlyphs.cart,
    )));
    await tester.pump();

    expect(find.byIcon(ArxaKitGlyphs.cart.icon), findsOneWidget);
    expect(find.byIcon(ArxaKitGlyphs.photo.icon), findsNothing);
  });

  testWidgets('kit.ui-library.image — size sets both width and height',
      (tester) async {
    await tester.pumpWidget(host(const ArxaKitImage(
      asset: 'assets/x.jpg',
      size: 64,
    )));

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.width, 64);
    expect(image.height, 64);
  });
}
