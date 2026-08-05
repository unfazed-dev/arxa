import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:appbox_kit_showcase_app/app/app.locator.dart';
import 'package:stacked_services/stacked_services.dart';
import 'package:appbox_kit_showcase_app/services/showcase_notes_services/facades/showcase_notes_facade_service.dart';
import 'package:appbox_kit_showcase_app/services/showcase_notes_services/adapters/showcase_notes_media_adapter_service.dart';
// @stacked-import

import 'test_helpers.mocks.dart';

@GenerateMocks(
  [],
  customMocks: [
    MockSpec<RouterService>(onMissingStub: OnMissingStub.returnDefault),
    MockSpec<BottomSheetService>(onMissingStub: OnMissingStub.returnDefault),
    MockSpec<DialogService>(onMissingStub: OnMissingStub.returnDefault),
    MockSpec<ShowcaseNotesFacadeService>(onMissingStub: OnMissingStub.returnDefault),
    MockSpec<ShowcaseNotesMediaAdapterService>(onMissingStub: OnMissingStub.returnDefault),
// @stacked-mock-spec
  ],
)
void registerServices() {
  getAndRegisterRouterService();
  getAndRegisterBottomSheetService();
  getAndRegisterDialogService();
  getAndRegisterShowcaseNotesFacadeService();
  getAndRegisterShowcaseNotesMediaAdapterService();
// @stacked-mock-register
}

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
    service.showCustomSheet<T, T>(
      enableDrag: anyNamed('enableDrag'),
      enterBottomSheetDuration: anyNamed('enterBottomSheetDuration'),
      exitBottomSheetDuration: anyNamed('exitBottomSheetDuration'),
      ignoreSafeArea: anyNamed('ignoreSafeArea'),
      isScrollControlled: anyNamed('isScrollControlled'),
      barrierDismissible: anyNamed('barrierDismissible'),
      additionalButtonTitle: anyNamed('additionalButtonTitle'),
      variant: anyNamed('variant'),
      title: anyNamed('title'),
      hasImage: anyNamed('hasImage'),
      imageUrl: anyNamed('imageUrl'),
      showIconInMainButton: anyNamed('showIconInMainButton'),
      mainButtonTitle: anyNamed('mainButtonTitle'),
      showIconInSecondaryButton: anyNamed('showIconInSecondaryButton'),
      secondaryButtonTitle: anyNamed('secondaryButtonTitle'),
      showIconInAdditionalButton: anyNamed('showIconInAdditionalButton'),
      takesInput: anyNamed('takesInput'),
      barrierColor: anyNamed('barrierColor'),
      barrierLabel: anyNamed('barrierLabel'),
      customData: anyNamed('customData'),
      data: anyNamed('data'),
      description: anyNamed('description'),
    ),
  ).thenAnswer(
    (realInvocation) =>
        Future.value(showCustomSheetResponse ?? SheetResponse<T>()),
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

MockShowcaseNotesMediaAdapterService getAndRegisterShowcaseNotesMediaAdapterService() {
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
