import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_showcase_app/app/app.locator.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_profile_shell/showcase_motion/showcase_motion_viewmodel.dart';

void main() {
  group('ShowcaseMotionViewModel', () {
    tearDown(() => locator.reset());

    test(
        'profile-and-gallery-demos.gallery.view-the-motion-demo — '
        'the default spec is the standard preset with motion enabled', () {
      // given
      final vm = ShowcaseMotionViewModel();
      // when (nothing — the demo opens on the default spec)
      final spec = vm.spec;
      // then
      expect(spec.enabled, isTrue);
      expect(spec.staggerFraction, 0.06);
      expect(spec.offset, const Offset(0, 0.08));
      expect(spec.scale, 1.0);
    });

    test(
        'profile-and-gallery-demos.gallery.view-the-motion-demo — '
        'setPreset + setEnabled derive the spec through copyWith(enabled:)',
        () {
      // given
      final vm = ShowcaseMotionViewModel();
      // when
      vm.setPreset(2); // Energetic
      vm.setEnabled(false);
      // then — the energetic knobs survive, the master switch wins
      expect(vm.spec.enabled, isFalse);
      expect(vm.spec.staggerFraction, 0.09);
      expect(vm.spec.offset, const Offset(0, 0.12));
      expect(vm.spec.scale, 0.96);
    });
  });
}
