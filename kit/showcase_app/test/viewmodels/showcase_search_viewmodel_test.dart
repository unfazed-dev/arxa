import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_showcase_app/app/app.locator.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_search_shell/showcase_search/showcase_search_viewmodel.dart';

// No intake story maps to the search-filters demo surface (map.json has no
// search-demo story — `search-and-attachments.search.*` covers the notes text
// search, a different feature), so these names carry behavior sentences only.
void main() {
  group('ShowcaseSearchViewModel', () {
    tearDown(() => locator.reset());

    test('setRadius moves the radius filter and notifies the view', () {
      // given
      final vm = ShowcaseSearchViewModel();
      var notifications = 0;
      vm.addListener(() => notifications++);
      // when
      vm.setRadius(0.8);
      // then
      expect(vm.radius, 0.8);
      expect(notifications, 1);
    });

    test('setPrice moves the price range as a pair and notifies once', () {
      // given
      final vm = ShowcaseSearchViewModel();
      var notifications = 0;
      vm.addListener(() => notifications++);
      // when
      vm.setPrice(0.1, 0.4);
      // then
      expect(vm.priceStart, 0.1);
      expect(vm.priceEnd, 0.4);
      expect(notifications, 1);
    });

    test('setOpenNow flips the open-now filter from its closed default', () {
      // given
      final vm = ShowcaseSearchViewModel();
      expect(vm.openNow, isFalse);
      // when
      vm.setOpenNow(true);
      // then
      expect(vm.openNow, isTrue);
    });

    test('setOutdoor flips the outdoor filter from its on default', () {
      // given
      final vm = ShowcaseSearchViewModel();
      expect(vm.outdoor, isTrue);
      // when
      vm.setOutdoor(false);
      // then
      expect(vm.outdoor, isFalse);
    });
  });
}
