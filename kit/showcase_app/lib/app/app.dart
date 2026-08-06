import 'package:appbox_kit_showcase_app/ui/bottom_sheets/showcase_notice_sheet/showcase_notice_sheet.dart';
import 'package:appbox_kit_showcase_app/ui/dialogs/showcase_info_alert_dialog/showcase_info_alert_dialog.dart';
import 'package:appbox_kit_showcase_app/ui/dialogs/showcase_confirm_dialog/showcase_confirm_dialog.dart';
import 'package:appbox_kit_showcase_app/ui/dialogs/showcase_text_input_dialog/showcase_text_input_dialog.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_unknown_shell/showcase_unknown_shell_view.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_unknown_shell/showcase_unknown/showcase_unknown_view.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_startup_shell/showcase_startup_shell_view.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_startup_shell/showcase_startup/showcase_startup_view.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_application_shell/showcase_application_shell_view.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_home_shell/showcase_home_shell_view.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_home_shell/showcase_home/showcase_home_view.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_search_shell/showcase_search_shell_view.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_search_shell/showcase_search/showcase_search_view.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_profile_shell/showcase_profile_shell_view.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_profile_shell/showcase_profile/showcase_profile_view.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_profile_shell/showcase_motion/showcase_motion_view.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_profile_shell/showcase_maps/showcase_maps_view.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_profile_shell/showcase_components/showcase_components_view.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_notes_shell/showcase_notes_shell_view.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_notes_shell/showcase_notes/showcase_notes_view.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_notes_shell/showcase_notes_folder/showcase_notes_folder_view.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_notes_shell/showcase_note_editor/showcase_note_editor_view.dart';
import 'package:stacked/stacked_annotations.dart';
import 'package:stacked_services/stacked_services.dart';
import 'package:talker_flutter/talker_flutter.dart';
import 'package:appbox_kit_haptics/appbox_kit_haptics.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';
import 'package:appbox_kit_showcase_app/services/showcase_notes_services/repositories/showcase_notes_repository_service.dart';
import 'package:appbox_kit_showcase_app/services/showcase_notes_services/facades/showcase_notes_facade_service.dart';
import 'package:appbox_kit_showcase_app/services/showcase_notes_services/adapters/showcase_notes_media_adapter_service.dart';
// @stacked-import

@StackedApp(
  routes: [
    // Shell-per-tab (navigator2): ShowcaseApplicationShellView hosts four tab stacks in a
    // StackedTabsRouter (IndexedStack — every stack stays alive). Each tab file
    // defines both a `*ShellView` router outlet and its leaf view. Ported from
    // the source showcase; names/paths must match ShowcaseApplicationShellView.tabs.
    AdaptiveRoute(page: ShowcaseStartupShellView, initial: true, children: [
      AdaptiveRoute(page: ShowcaseStartupView, path: '', initial: true),
    ]),

    AdaptiveRoute(page: ShowcaseApplicationShellView, path: '/', children: [
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
        // appbox_kit_motion showcase — AdaptiveRoute on purpose: the demo's
        // route-driven AppBoxKitMotionScope rides the native push animation and the
        // iOS swipe-back scrub (same rationale as the note editor below).
        AdaptiveRoute(page: ShowcaseMotionView, path: 'motion'),
        // appbox_kit_maps showcase — OpenStreetMap by default (no key),
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
    // AppBoxKitBottomSheetService presents stacked sheets through appBoxKitShowNativeSheet
    // (CNBottomSheet on iOS, M3 modal sheet on Android) — registered as the
    // base type so every BottomSheetService call site stays untouched.
    LazySingleton(classType: AppBoxKitBottomSheetService, asType: BottomSheetService),
    LazySingleton(classType: DialogService),
    LazySingleton(classType: RouterService),
    LazySingleton(classType: SnackbarService),

    // Kit services — registration lives in the app, decoupled from the kit.
    LazySingleton(classType: Talker),
    LazySingleton(classType: AppBoxKitErrorService),
    LazySingleton(classType: AppBoxKitNotificationService),
    LazySingleton(classType: AppBoxKitHapticService),
    LazySingleton(classType: AppBoxKitThemeService),
    LazySingleton(classType: AppBoxKitNavigationControllerService),
    LazySingleton(classType: AppBoxKitOverlayService),
    LazySingleton(classType: AppBoxKitSelectableService),
    // Data layer (appbox_kit_data layering): the Notes Repository — the
    // notes-domain gateway over the kit's AppBoxKitRepository<ShowcaseNoteModel>/<ShowcaseNoteFolderModel> —
    // then the Facade, the only layer viewmodels talk to.
    LazySingleton(classType: ShowcaseNotesRepositoryService),
    LazySingleton(classType: ShowcaseNotesFacadeService),
    LazySingleton(classType: ShowcaseNotesMediaAdapterService),
// @stacked-service
  ],
  bottomsheets: [
    StackedBottomsheet(classType: ShowcaseNoticeSheet),
    // @stacked-bottom-sheet
  ],
  dialogs: [
    StackedDialog(classType: ShowcaseInfoAlertDialog),
    StackedDialog(classType: ShowcaseConfirmDialog),
    StackedDialog(classType: ShowcaseTextInputDialog),
    // @stacked-dialog
  ],
)
class App {}
