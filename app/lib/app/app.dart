import 'package:app_box/services/auth_harness_service.dart';
import 'package:app_box/services/config_service.dart';
import 'package:app_box/services/credential_service.dart';
import 'package:app_box/services/gate_service.dart';
import 'package:app_box/services/kit_inventory_service.dart';
import 'package:app_box/services/licence_service.dart';
import 'package:app_box/services/launch_service.dart';
import 'package:app_box/services/mcp/mcp_registry.dart';
import 'package:app_box/services/pipeline_runner_service.dart';
import 'package:app_box/services/intake_runner_service.dart';
import 'package:app_box/services/projects_service.dart';
import 'package:app_box/ui/bottom_sheets/notice/notice_sheet.dart';
import 'package:app_box/ui/dialogs/info_alert/info_alert_dialog.dart';
import 'package:app_box/ui/views/app_shell/app_shell_view.dart';
import 'package:app_box/ui/views/build/build_approve/build_approve_view.dart';
import 'package:app_box/ui/views/build/build_finding/build_finding_view.dart';
import 'package:app_box/ui/views/build/build_run/build_run_view.dart';
import 'package:app_box/ui/views/chat/chat_home/chat_home_view.dart';
import 'package:app_box/ui/views/design/design_approve/design_approve_view.dart';
import 'package:app_box/ui/views/design/design_directions/design_directions_view.dart';
import 'package:app_box/ui/views/design/design_surface/design_surface_view.dart';
import 'package:app_box/ui/views/intake/intake_wizard/intake_wizard_view.dart';
import 'package:app_box/ui/views/projects/projects_home/projects_home_view.dart';
import 'package:app_box/ui/views/projects/projects_new/projects_new_view.dart';
import 'package:app_box/ui/views/settings/settings_credentials/settings_credentials_view.dart';
import 'package:app_box/ui/views/settings/settings_devices/settings_devices_view.dart';
import 'package:app_box/ui/views/settings/settings_kits/settings_kits_view.dart';
import 'package:app_box/ui/views/ship/ship_confirm/ship_confirm_view.dart';
import 'package:app_box/ui/views/ship/ship_targets/ship_targets_view.dart';
import 'package:app_box/ui/views/showcase_startup/showcase_startup_view.dart';
import 'package:app_box/ui/views/showcase_unknown/showcase_unknown_view.dart';
import 'package:stacked/stacked_annotations.dart';
import 'package:stacked_services/stacked_services.dart';
import 'package:talker_flutter/talker_flutter.dart';
import 'package:stacked_kit_haptics/stacked_kit_haptics.dart';
import 'package:ui_library/ui_library.dart';
// @stacked-import

@StackedApp(
  routes: [
    // Boot splash → AppShellView, the desktop sidebar host for the 14 product
    // surfaces (brief §4). The dogfood target is macOS desktop.
    AdaptiveRoute(page: ShowcaseStartupView, initial: true),

    AdaptiveRoute(page: AppShellView, path: '/', children: [
      // projects
      AdaptiveRoute(page: ProjectsHomeView, path: 'projects', initial: true),
      AdaptiveRoute(page: ProjectsNewView, path: 'projects/new'),
      // intake (10.5) — the wizard drives the ONE elicitation engine
      AdaptiveRoute(page: IntakeWizardView, path: 'intake/wizard'),
      // design (gate 1 = design.approve)
      AdaptiveRoute(page: DesignDirectionsView, path: 'design'),
      AdaptiveRoute(page: DesignSurfaceView, path: 'design/surface'),
      AdaptiveRoute(page: DesignApproveView, path: 'design/approve'),
      // build (gate 2 = build.approve)
      AdaptiveRoute(page: BuildRunView, path: 'build'),
      AdaptiveRoute(page: BuildFindingView, path: 'build/finding'),
      AdaptiveRoute(page: BuildApproveView, path: 'build/approve'),
      // ship (gate 3 = ship.confirm — the triple)
      AdaptiveRoute(page: ShipTargetsView, path: 'ship'),
      AdaptiveRoute(page: ShipConfirmView, path: 'ship/confirm'),
      // chat (MCP client)
      AdaptiveRoute(page: ChatHomeView, path: 'chat'),
      // settings
      AdaptiveRoute(page: SettingsCredentialsView, path: 'settings'),
      AdaptiveRoute(page: SettingsDevicesView, path: 'settings/devices'),
      AdaptiveRoute(page: SettingsKitsView, path: 'settings/kits'),
    ]),

    // @stacked-route
    AdaptiveRoute(page: ShowcaseUnknownView, path: '/404'),

    /// When none of the above routes match, redirect to ShowcaseUnknownView
    RedirectRoute(path: '*', redirectTo: '/404'),
  ],
  dependencies: [
    // KitBottomSheetService presents stacked sheets through kitShowNativeSheet
    // — registered as the base type so every BottomSheetService call site stays
    // untouched.
    LazySingleton(classType: KitBottomSheetService, asType: BottomSheetService),
    LazySingleton(classType: DialogService),
    LazySingleton(classType: RouterService),
    LazySingleton(classType: SnackbarService),

    // Kit services — registration lives in the app, decoupled from the kit.
    LazySingleton(classType: Talker),
    LazySingleton(classType: KitErrorService),
    LazySingleton(classType: KitNotificationService),
    LazySingleton(classType: KitHapticService),
    LazySingleton(classType: KitThemeService),
    LazySingleton(classType: KitNavigationControllerService),
    LazySingleton(classType: KitOverlayService),
    LazySingleton(classType: KitSelectableService),

    // app_box services.
    LazySingleton(classType: ConfigService),
    LazySingleton(classType: CredentialService),
    LazySingleton(classType: LicenceService),
    LazySingleton(classType: GateService),
    LazySingleton(classType: KitInventoryService),
    LazySingleton(classType: ProjectsService),
    LazySingleton(classType: PipelineRunnerService),
    LazySingleton(classType: IntakeRunnerService),
    LazySingleton(classType: AuthHarnessService),
    LazySingleton(classType: LaunchService),
    LazySingleton(classType: McpRegistry),
// @stacked-service
  ],
  bottomsheets: [
    StackedBottomsheet(classType: NoticeSheet),
    // @stacked-bottom-sheet
  ],
  dialogs: [
    StackedDialog(classType: InfoAlertDialog),
    // @stacked-dialog
  ],
)
class App {}
