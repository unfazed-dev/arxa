import 'package:stacked_services/stacked_services.dart';
import 'package:talker_flutter/talker_flutter.dart';

import 'package:appbox_kit_core/appbox_kit_locator.dart';

import 'sheet/appbox_kit_bottom_sheet_service.dart';

/// Registers the stacked UI services every kit app needs — call once from
/// `main()` after `setupLocator()`, before `setupAppBoxKitSnackbars()`.
///
/// Registration lives in the kit so app code never imports `stacked_services`
/// or `talker_flutter`: [DialogService] and [SnackbarService] are the stacked
/// base services, [BottomSheetService] resolves to [AppBoxKitBottomSheetService]
/// (registered as the base type, so stacked sheet call sites present through
/// `appBoxKitShowSheet` untouched), and [Talker] backs AppBoxKitAction /
/// AppBoxKitErrorService logging.
void setupAppBoxKitUiServices() {
  appBoxKitLocator
    ..registerLazySingleton(() => DialogService())
    ..registerLazySingleton(() => SnackbarService())
    ..registerLazySingleton<BottomSheetService>(
        () => AppBoxKitBottomSheetService())
    ..registerLazySingleton(() => Talker());
}
