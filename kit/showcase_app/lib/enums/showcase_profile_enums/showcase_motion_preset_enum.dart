import 'package:arxa_kit_motion/arxa_kit_motion.dart';

/// The motion demo's spec presets, in segmented-control order — [spec] is
/// the kit preset itself; the viewmodel applies the master switch on top.
enum ShowcaseMotionPreset {
  standard('Standard', ArxaKitMotionSpec.standard),
  subtle('Subtle', ArxaKitMotionSpec.subtle),
  energetic('Energetic', ArxaKitMotionSpec.energetic);

  const ShowcaseMotionPreset(this.label, this.spec);

  /// Segment label.
  final String label;

  /// The preset spec (before the demo's enabled toggle is applied).
  final ArxaKitMotionSpec spec;
}
