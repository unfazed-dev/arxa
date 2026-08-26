import 'package:arxa_kit_showcase_app/ui/views/showcase_unknown_shell/showcase_unknown_shell_view.dart';
import 'package:arxa_kit_showcase_app/ui/views/showcase_unknown_shell/showcase_unknown/showcase_unknown_view.dart';
import 'package:arxa_kit_showcase_app/ui/views/showcase_startup_shell/showcase_startup_shell_view.dart';
import 'package:arxa_kit_showcase_app/ui/views/showcase_startup_shell/showcase_startup/showcase_startup_view.dart';
import 'package:arxa_kit_showcase_app/ui/views/showcase_application_hub/showcase_application_hub_view.dart';
import 'package:arxa_kit_showcase_app/ui/views/showcase_home_shell/showcase_home_shell_view.dart';
import 'package:arxa_kit_showcase_app/ui/views/showcase_home_shell/showcase_home/showcase_home_view.dart';
import 'package:arxa_kit_showcase_app/ui/views/showcase_search_shell/showcase_search_shell_view.dart';
import 'package:arxa_kit_showcase_app/ui/views/showcase_search_shell/showcase_search/showcase_search_view.dart';
import 'package:arxa_kit_showcase_app/ui/views/showcase_profile_shell/showcase_profile_shell_view.dart';
import 'package:arxa_kit_showcase_app/ui/views/showcase_profile_shell/showcase_profile/showcase_profile_view.dart';
import 'package:arxa_kit_showcase_app/ui/views/showcase_profile_shell/showcase_motion/showcase_motion_view.dart';
import 'package:arxa_kit_showcase_app/ui/views/showcase_profile_shell/showcase_maps/showcase_maps_view.dart';
import 'package:arxa_kit_showcase_app/ui/views/showcase_profile_shell/showcase_components/showcase_components_view.dart';
import 'package:arxa_kit_showcase_app/ui/views/showcase_notes_shell/showcase_notes_shell_view.dart';
import 'package:arxa_kit_showcase_app/ui/views/showcase_notes_shell/showcase_notes/showcase_notes_view.dart';
import 'package:arxa_kit_showcase_app/ui/views/showcase_notes_shell/showcase_notes_folder/showcase_notes_folder_view.dart';
import 'package:arxa_kit_showcase_app/ui/views/showcase_notes_shell/showcase_note_editor/showcase_note_editor_view.dart';
import 'package:arxa_kit_haptics/arxa_kit_haptics.dart';
import 'package:arxa_kit_media/arxa_kit_media.dart';
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart';
import 'package:arxa_kit_showcase_app/services/showcase_notes_services/repositories/showcase_notes_repository_service.dart';
import 'package:arxa_kit_showcase_app/services/showcase_notes_services/facades/showcase_notes_facade_service.dart';
import 'package:arxa_kit_showcase_app/services/showcase_notes_services/adapters/showcase_notes_media_adapter_service.dart';
// @stacked-import

@StackedApp(
  routes: [
    // Shell-per-tab (navigator2): ShowcaseApplicationHubView hosts four tab stacks in a
    // StackedTabsRouter (IndexedStack — every stack stays alive). Each tab file
    // defines both a `*ShellView` router outlet and its leaf view. Ported from
    // the source showcase; names/paths must match ShowcaseApplicationHubView.tabs.
    AdaptiveRoute(page: ShowcaseStartupShellView, initial: true, children: [
      AdaptiveRoute(page: ShowcaseStartupView, path: '', initial: true),
    ]),

    AdaptiveRoute(page: ShowcaseApplicationHubView, path: '/', children: [
      AdaptiveRoute(
          page: ShowcaseHomeShellView,
          path: 'home',
          initial: true,
          children: [
            AdaptiveRoute(page: ShowcaseHomeView, path: '', initial: true),
          ]),
      AdaptiveRoute(page: ShowcaseSearchShellView, path: 'search', children: [
        AdaptiveRoute(page: ShowcaseSearchView, path: '', initial: true),
      ]),
      AdaptiveRoute(page: ShowcaseProfileShellView, path: 'profile', children: [
        AdaptiveRoute(page: ShowcaseProfileView, path: '', initial: true),
        // arxa_kit_motion showcase — AdaptiveRoute on purpose: the demo's
        // route-driven ArxaKitMotionScope rides the native push animation and the
        // iOS swipe-back scrub (same rationale as the note editor below).
        AdaptiveRoute(page: ShowcaseMotionView, path: 'motion'),
        // arxa_kit_maps showcase — OpenStreetMap by default (no key),
        // Mapbox raster tiles when MAPBOX_PUBLIC_TOKEN is dart-defined.
        AdaptiveRoute(page: ShowcaseMapsView, path: 'maps'),
        // ADR 0011 video-parity components — same AdaptiveRoute rationale as
        // the motion demo above.
        AdaptiveRoute(page: ShowcaseComponentsView, path: 'components'),
      ]),
      AdaptiveRoute(page: ShowcaseNotesShellView, path: 'notes', children: [
        AdaptiveRoute(page: ShowcaseNotesView, path: '', initial: true),
        AdaptiveRoute(page: ShowcaseNotesFolderView, path: 'folder/:id'),
        // Kept as AdaptiveRoute deliberately: in stacked 3.5.0 AdaptiveRoute
        // has no transitionsBuilder (only CustomRoute does), and swapping to
        // CustomRoute would trade away the platform-native push animation
        // AND iOS interactive swipe-back for a fixed PageRouteBuilder.
        // Adaptive already animates: Cupertino slide on iOS, zoom on Android.
        AdaptiveRoute(page: ShowcaseNoteEditorView, path: 'note/:id'),
      ]),
    ]),

    // @stacked-route
    AdaptiveRoute(page: ShowcaseUnknownShellView, path: '/404', children: [
      AdaptiveRoute(page: ShowcaseUnknownView, path: '', initial: true),
    ]),

    /// When none of the above routes match, redirect to ShowcaseUnknownView
    RedirectRoute(path: '*', redirectTo: '/404'),
  ],
  dependencies: [
    // DialogService / SnackbarService / BottomSheetService / Talker are
    // registered by setupArxaKitUiServices() (called from main) — kit-owned.
    LazySingleton(classType: RouterService),

    // Kit services — registration lives in the app, decoupled from the kit.
    LazySingleton(classType: ArxaKitErrorService),
    LazySingleton(classType: ArxaKitNotificationService),
    LazySingleton(classType: ArxaKitHapticService),
    LazySingleton(classType: ArxaKitThemeService),
    LazySingleton(classType: ArxaKitNavigationControllerService),
    LazySingleton(classType: ArxaKitOverlayService),
    LazySingleton(classType: ArxaKitSelectableService),
    // Data layer (arxa_kit_data layering): the Notes Repository — the
    // notes-domain gateway over the kit's ArxaKitRepository<ShowcaseNoteModel>/<ShowcaseNoteFolderModel> —
    // then the Facade, the only layer viewmodels talk to.
    // Kit media — the audio recorder behind the composer's hold-to-record
    // (record plugin → AVAudioRecorder/AudioRecord). Registered under its
    // interface so tests swap in the kit's scriptable fake; the notes shell
    // default-constructs its own instance inside the media adapter.
    LazySingleton(
      classType: ArxaKitRecordAudioRecorderService,
      asType: ArxaKitAudioRecorderService,
    ),
    LazySingleton(classType: ShowcaseNotesRepositoryService),
    LazySingleton(classType: ShowcaseNotesFacadeService),
    LazySingleton(classType: ShowcaseNotesMediaAdapterService),
// @stacked-service
  ],
)
class App {}
