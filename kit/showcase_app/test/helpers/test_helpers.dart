import 'package:mocktail/mocktail.dart';
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart';
import 'package:arxa_kit_ui_library/arxa_kit_testing.dart';
import 'package:arxa_kit_showcase_app/app/app.locator.dart';
import 'package:arxa_kit_showcase_app/services/showcase_notes_services/facades/showcase_notes_facade_service.dart';
import 'package:arxa_kit_showcase_app/services/showcase_notes_services/adapters/showcase_notes_media_adapter_service.dart';
// @stacked-import

/// mocktail mocks — no codegen (behavior-TDD canon: mocktail only).
class MockRouterService extends Mock implements RouterService {}

class MockShowcaseNotesFacadeService extends Mock
    implements ShowcaseNotesFacadeService {}

class MockShowcaseNotesMediaAdapterService extends Mock
    implements ShowcaseNotesMediaAdapterService {}

void registerServices() {
  getAndRegisterRouterService();
  getAndRegisterShowcaseNotesFacadeService();
  getAndRegisterShowcaseNotesMediaAdapterService();
// @stacked-mock-register
}

/// Registers the services an `ArxaKitAction` chain lazily resolves from the
/// locator — the kit's UI services (Talker backs ArxaKitErrorService
/// logging), the real [ArxaKitErrorService], and the kit's scriptable
/// [FakeArxaKitNotificationService] — so viewmodel tests can execute REAL
/// action chains (error snackbars land on the fake, where the test can assert
/// them) instead of mocking the chain away. Confirm/prompt paths set
/// `confirmResult`/`promptResult` on the fake.
void registerArxaKitActionServices() {
  // Talker isn't re-exported by the kit barrel; the kit's own setup
  // registers it (plus the stacked Dialog/Snackbar/BottomSheet bases —
  // SnackbarService doubles as the idempotency check).
  if (!locator.isRegistered<SnackbarService>()) setupArxaKitUiServices();
  _removeRegistrationIfExists<ArxaKitErrorService>();
  locator.registerLazySingleton<ArxaKitErrorService>(
      () => ArxaKitErrorService());
  _removeRegistrationIfExists<ArxaKitNotificationService>();
  locator.registerLazySingleton<ArxaKitNotificationService>(
      () => FakeArxaKitNotificationService());
}

/// Seeded [BehaviorSubject] for the stream-first VMs — stub facade streams
/// (`session$`, `overview$`, `note$`, `recording$`, …) with the subject's
/// stream so tests get the seed synchronously on subscribe and can push later
/// events (sign-out, edits) through the same subject:
/// ```dart
/// final session = seededSubject<ArxaKitAuthSession?>(null);
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
