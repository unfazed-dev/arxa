import 'dart:ui' show Color;

import 'package:mocktail/mocktail.dart';
import 'package:rxdart/rxdart.dart';
import 'package:talker_flutter/talker_flutter.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart'
    show AppBoxKitErrorService, AppBoxKitNotificationService;
import 'package:appbox_kit_ui_library/appbox_kit_testing.dart';
import 'package:appbox_kit_showcase_app/app/app.locator.dart';
import 'package:stacked_services/stacked_services.dart';
import 'package:appbox_kit_showcase_app/services/showcase_notes_services/facades/showcase_notes_facade_service.dart';
import 'package:appbox_kit_showcase_app/services/showcase_notes_services/adapters/showcase_notes_media_adapter_service.dart';
// @stacked-import

/// mocktail mocks — no codegen (behavior-TDD canon: mocktail only).
class MockRouterService extends Mock implements RouterService {}

class MockBottomSheetService extends Mock implements BottomSheetService {}

class MockDialogService extends Mock implements DialogService {}

class MockShowcaseNotesFacadeService extends Mock
    implements ShowcaseNotesFacadeService {}

class MockShowcaseNotesMediaAdapterService extends Mock
    implements ShowcaseNotesMediaAdapterService {}

void registerServices() {
  // Fallbacks for the `any(named:)` matchers in the bottom-sheet stub below —
  // registered once here so consuming files don't repeat them per file.
  registerFallbackValue(const Color(0x00000000));
  registerFallbackValue(Duration.zero);
  getAndRegisterRouterService();
  getAndRegisterBottomSheetService();
  getAndRegisterDialogService();
  getAndRegisterShowcaseNotesFacadeService();
  getAndRegisterShowcaseNotesMediaAdapterService();
// @stacked-mock-register
}

/// Registers the services an `AppBoxKitAction` chain lazily resolves from the
/// locator — real [Talker], real [AppBoxKitErrorService], and the kit's
/// scriptable [FakeAppBoxKitNotificationService] — so viewmodel tests can
/// execute REAL action chains (error snackbars land on the fake, where the
/// test can assert them) instead of mocking the chain away.
void registerAppBoxKitActionServices() {
  _removeRegistrationIfExists<Talker>();
  locator.registerLazySingleton<Talker>(() => Talker());
  _removeRegistrationIfExists<AppBoxKitErrorService>();
  locator.registerLazySingleton<AppBoxKitErrorService>(
      () => AppBoxKitErrorService());
  _removeRegistrationIfExists<AppBoxKitNotificationService>();
  locator.registerLazySingleton<AppBoxKitNotificationService>(
      () => FakeAppBoxKitNotificationService());
}

/// Seeded [BehaviorSubject] for the stream-first VMs — stub facade streams
/// (`session$`, `overview$`, `note$`, `recording$`, …) with the subject's
/// stream so tests get the seed synchronously on subscribe and can push later
/// events (sign-out, edits) through the same subject:
/// ```dart
/// final session = seededSubject<AppBoxKitAuthSession?>(null);
/// when(() => facade.session$).thenAnswer((_) => session.stream);
/// ```
/// Assert the FULL sequence including the seed (canon streams rules) — never
/// silently drop it.
BehaviorSubject<T> seededSubject<T>(T seed) => BehaviorSubject<T>.seeded(seed);

MockRouterService getAndRegisterRouterService() {
  _removeRegistrationIfExists<RouterService>();
  final service = MockRouterService();
  locator.registerSingleton<RouterService>(service);
  return service;
}

MockBottomSheetService getAndRegisterBottomSheetService<T>({
  SheetResponse<T>? showCustomSheetResponse,
}) {
  _removeRegistrationIfExists<BottomSheetService>();
  final service = MockBottomSheetService();

  when(
    () => service.showCustomSheet<T, T>(
      enableDrag: any(named: 'enableDrag'),
      enterBottomSheetDuration: any(named: 'enterBottomSheetDuration'),
      exitBottomSheetDuration: any(named: 'exitBottomSheetDuration'),
      ignoreSafeArea: any(named: 'ignoreSafeArea'),
      isScrollControlled: any(named: 'isScrollControlled'),
      barrierDismissible: any(named: 'barrierDismissible'),
      additionalButtonTitle: any(named: 'additionalButtonTitle'),
      variant: any(named: 'variant'),
      title: any(named: 'title'),
      hasImage: any(named: 'hasImage'),
      imageUrl: any(named: 'imageUrl'),
      showIconInMainButton: any(named: 'showIconInMainButton'),
      mainButtonTitle: any(named: 'mainButtonTitle'),
      showIconInSecondaryButton: any(named: 'showIconInSecondaryButton'),
      secondaryButtonTitle: any(named: 'secondaryButtonTitle'),
      showIconInAdditionalButton: any(named: 'showIconInAdditionalButton'),
      takesInput: any(named: 'takesInput'),
      barrierColor: any(named: 'barrierColor'),
      barrierLabel: any(named: 'barrierLabel'),
      // Kept so calls still passing the legacy param match the stub; drop
      // when stacked_services removes it.
      // ignore: deprecated_member_use
      customData: any(named: 'customData'),
      data: any(named: 'data'),
      description: any(named: 'description'),
    ),
  ).thenAnswer(
    (_) => Future.value(showCustomSheetResponse ?? SheetResponse<T>()),
  );

  locator.registerSingleton<BottomSheetService>(service);
  return service;
}

MockDialogService getAndRegisterDialogService() {
  _removeRegistrationIfExists<DialogService>();
  final service = MockDialogService();
  locator.registerSingleton<DialogService>(service);
  return service;
}

MockShowcaseNotesFacadeService getAndRegisterShowcaseNotesFacadeService() {
  _removeRegistrationIfExists<ShowcaseNotesFacadeService>();
  final service = MockShowcaseNotesFacadeService();
  locator.registerSingleton<ShowcaseNotesFacadeService>(service);
  return service;
}

MockShowcaseNotesMediaAdapterService
    getAndRegisterShowcaseNotesMediaAdapterService() {
  _removeRegistrationIfExists<ShowcaseNotesMediaAdapterService>();
  final service = MockShowcaseNotesMediaAdapterService();
  locator.registerSingleton<ShowcaseNotesMediaAdapterService>(service);
  return service;
}
// @stacked-mock-create

void _removeRegistrationIfExists<T extends Object>() {
  if (locator.isRegistered<T>()) {
    locator.unregister<T>();
  }
}
