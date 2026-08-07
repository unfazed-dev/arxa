import 'package:appbox_kit_motion/appbox_kit_motion.dart';

/// The motion demo's spec presets, in segmented-control order — [spec] is
/// the kit preset itself; the viewmodel applies the master switch on top.
enum ShowcaseMotionPreset {
  standard('Standard', AppBoxKitMotionSpec.standard),
  subtle('Subtle', AppBoxKitMotionSpec.subtle),
  energetic('Energetic', AppBoxKitMotionSpec.energetic);

  const ShowcaseMotionPreset(this.label, this.spec);

  /// Segment label.
  final String label;

  /// The preset spec (before the demo's enabled toggle is applied).
  final AppBoxKitMotionSpec spec;
}
