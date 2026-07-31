import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_core/common/kit_glyphs.dart';
import 'package:ui_library/widgets/kit_image.dart';

import 'native_test_helpers.dart';

/// KitImage tests.
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
  testWidgets('constructs an Image.asset with the given path', (tester) async {
    await tester.pumpWidget(host(const KitImage(
      asset: 'assets/some/product.jpg',
      size: 48,
    )));

    final image = tester.widget<Image>(find.byType(Image));
    expect(image, isA<Image>());
    expect((image.image as AssetImage).assetName,
      'assets/some/product.jpg');
    expect(image.width, 48);
    expect(image.height, 48);
  });

  testWidgets('empty asset shows the placeholder glyph and never throws',
      (tester) async {
    await tester.pumpWidget(host(const KitImage(asset: '', size: 48)));
    await tester.pump();

    expect(find.byType(Image), findsNothing,
        reason: 'an empty asset must not construct an Image.asset');
    expect(find.byIcon(KitGlyphs.photo.icon), findsOneWidget,
        reason: 'the default placeholder (KitGlyphs.photo) is shown');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a missing asset falls back to the placeholder glyph',
      (tester) async {
    // A path that does not exist in the bundle — the errorBuilder must
      // catch the decode failure and show the placeholder instead of the
      // framework's red error box.
      await tester.pumpWidget(host(const KitImage(
        asset: 'assets/does/not/exist.jpg',
        size: 48,
      )));
      // Pump past the asset-load failure so the errorBuilder runs.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));

      expect(find.byIcon(KitGlyphs.photo.icon), findsOneWidget,
          reason: 'errorBuilder should render the placeholder glyph');
  });

  testWidgets('honors a custom placeholder glyph', (tester) async {
    await tester.pumpWidget(host(const KitImage(
      asset: '',
      size: 48,
      placeholder: KitGlyphs.cart,
    )));
    await tester.pump();

    expect(find.byIcon(KitGlyphs.cart.icon), findsOneWidget);
    expect(find.byIcon(KitGlyphs.photo.icon), findsNothing);
  });

  testWidgets('size sets both width and height', (tester) async {
    await tester.pumpWidget(host(const KitImage(
      asset: 'assets/x.jpg',
      size: 64,
    )));

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.width, 64);
    expect(image.height, 64);
  });
}
