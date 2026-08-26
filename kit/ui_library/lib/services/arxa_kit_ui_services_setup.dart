import 'package:stacked_services/stacked_services.dart';
import 'package:talker_flutter/talker_flutter.dart';

import 'package:arxa_kit_core/arxa_kit_locator.dart';

import 'sheet/arxa_kit_bottom_sheet_service.dart';

/// Registers the stacked UI services every kit app needs — call once from
/// `main()` after `setupLocator()`, before `setupArxaKitSnackbars()`.
///
/// Registration lives in the kit so app code never imports `stacked_services`
/// or `talker_flutter`: [DialogService] and [SnackbarService] are the stacked
/// base services, [BottomSheetService] resolves to [ArxaKitBottomSheetService]
/// (registered as the base type, so stacked sheet call sites present through
/// `arxaKitShowSheet` untouched), and [Talker] backs ArxaKitAction /
/// ArxaKitErrorService logging.
void setupArxaKitUiServices() {
  arxaKitLocator
    ..registerLazySingleton(() => DialogService())
    ..registerLazySingleton(() => SnackbarService())
    ..registerLazySingleton<BottomSheetService>(
        () => ArxaKitBottomSheetService())
    ..registerLazySingleton(() => Talker());
}
