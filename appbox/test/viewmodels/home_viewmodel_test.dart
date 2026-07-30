import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:appbox/app/app.bottomsheets.dart';
import 'package:appbox/app/app.locator.dart';
import 'package:appbox/l10n/app_localizations_en.dart';
import 'package:appbox/ui/views/home/home_viewmodel.dart';

import '../helpers/test_helpers.dart';

void main() {
  HomeViewModel getModel() => HomeViewModel();
  final en = AppLocalizationsEn();

  group('HomeViewmodelTest -', () {
    setUp(() => registerServices());
    tearDown(() => locator.reset());

    group('incrementCounter -', () {
      test('When called once should return  Counter is: 1', () {
        final model = getModel();
        model.incrementCounter();
        expect(model.counterLabel, 'Counter is: 1');
      });
    });

    group('showBottomSheet -', () {
      test(
        'When called, should show custom bottom sheet using notice variant',
        () {
          final bottomSheetService = getAndRegisterBottomSheetService();

          final model = getModel();
          model.showBottomSheet();
          verify(
            bottomSheetService.showCustomSheet(
              variant: BottomSheetType.notice,
              title: en.homeBottomSheetTitle,
              description: en.homeBottomSheetDescription,
            ),
          );
        },
      );
    });
  });
}
