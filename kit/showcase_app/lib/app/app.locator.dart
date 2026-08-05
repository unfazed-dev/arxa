// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// **************************************************************************
// StackedLocatorGenerator
// **************************************************************************

// ignore_for_file: public_member_api_docs, implementation_imports, depend_on_referenced_packages

import 'package:appbox_kit_core/extensions/kit_selectable_extension.dart';
import 'package:appbox_kit_core/services/error/kit_error_service.dart';
import 'package:appbox_kit_core/services/theme/kit_theme_service.dart';
import 'package:appbox_kit_haptics/src/kit_haptic_service.dart';
import 'package:stacked_services/src/bottom_sheet/bottom_sheet_service.dart';
import 'package:stacked_services/src/dialog/dialog_service.dart';
import 'package:stacked_services/src/navigation/router_service.dart';
import 'package:stacked_services/src/snackbar/snackbar_service.dart';
import 'package:stacked_shared/stacked_shared.dart';
import 'package:talker/src/talker.dart';
import 'package:ui_library/extensions/kit_overlay_extension.dart';
import 'package:ui_library/services/navigation/kit_navigation_controller_service.dart';
import 'package:ui_library/services/notifications/kit_notification_service.dart';
import 'package:ui_library/services/sheet/kit_bottom_sheet_service.dart';

import '../services/adapters/showcase_notes_media_service.dart';
import '../services/facades/showcase_notes_facade.dart';
import '../services/repositories/showcase_notes_repository.dart';
import 'app.router.dart';

final locator = StackedLocator.instance;

Future<void> setupLocator(
    {String? environment,
    EnvironmentFilter? environmentFilter,
    StackedRouterWeb? stackedRouter}) async {
// Register environments
  locator.registerEnvironment(
      environment: environment, environmentFilter: environmentFilter);

// Register dependencies
  locator
      .registerLazySingleton<BottomSheetService>(() => KitBottomSheetService());
  locator.registerLazySingleton(() => DialogService());
  locator.registerLazySingleton(() => RouterService());
  locator.registerLazySingleton(() => SnackbarService());
  locator.registerLazySingleton(() => Talker());
  locator.registerLazySingleton(() => KitErrorService());
  locator.registerLazySingleton(() => KitNotificationService());
  locator.registerLazySingleton(() => KitHapticService());
  locator.registerLazySingleton(() => KitThemeService());
  locator.registerLazySingleton(() => KitNavigationControllerService());
  locator.registerLazySingleton(() => KitOverlayService());
  locator.registerLazySingleton(() => KitSelectableService());
  locator.registerLazySingleton(() => ShowcaseNotesRepository());
  locator.registerLazySingleton(() => ShowcaseNotesFacade());
  locator.registerLazySingleton(() => ShowcaseNotesMediaService());
  if (stackedRouter == null) {
    throw Exception(
        'Stacked is building to use the Router (Navigator 2.0) navigation but no stackedRouter is supplied. Pass the stackedRouter to the setupLocator function in main.dart');
  }

  locator<RouterService>().setRouter(stackedRouter);
}
