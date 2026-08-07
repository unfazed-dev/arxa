import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_showcase_app/app/app.locator.dart';
import 'package:appbox_kit_showcase_app/enums/showcase_profile_enums/enums.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_profile_shell/showcase_profile/showcase_profile_viewmodel.dart';


void main() {
  group('ShowcaseProfileViewModel', () {
    tearDown(() => locator.reset());

    test(
        'profile-and-gallery-demos.profile.view-the-profile-surface — '
        'switching the rail selects the matching section and notifies the view',
        () {
      // given
      final vm = ShowcaseProfileViewModel();
      var notifications = 0;
      vm.addListener(() => notifications++);
      expect(vm.rail, ShowcaseProfileRail.account);
      // when
      vm.setRailIndex(2);
      // then
      expect(vm.railIndex, 2);
      expect(vm.rail, ShowcaseProfileRail.alerts);
      expect(notifications, 1);
    });
  });
}
