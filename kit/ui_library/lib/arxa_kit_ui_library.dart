/// ui_library — Stacked kit UI tier.
///
/// Kit* adaptive port widgets, the UI-coupled services (navigation / sheet /
/// notifications), and the overlay + component plumbing that host them.
/// Re-exports [arxa_kit_core] so a consumer needs a single import for the
/// full kit surface (widgets here + tokens / platform / arxaKitLocator / error &
/// theme services in core). Dependency edge is ui_library -> core only.
library;

// Core non-UI surface — re-exported for one-import consumers.
export 'package:arxa_kit_core/arxa_kit_core.dart';

// The arxa-mandated MVVM framework — re-exported so apps never declare
// stacked/rxdart in their own pubspec (the kit pins the versions once).
export 'package:stacked/stacked.dart';
export 'package:stacked/stacked_annotations.dart';
export 'package:rxdart/rxdart.dart'
    show
        BehaviorSubject,
        ValueStream,
        Rx,
        SwitchMapExtension,
        StartWithExtension,
        ConnectableStreamExtensions;

// The stacked_services types an app legitimately touches: registrations and
// its own snackbar palette config. Dialogs/sheets/toasts themselves go
// through ArxaKitNotificationService's verbs — apps never call the stacked
// dialog/sheet services directly.
export 'package:stacked_services/stacked_services.dart'
    show
        RouterService,
        SnackbarService,
        SnackbarConfig,
        SnackPosition,
        StackedService;

export 'services/arxa_kit_ui_services_setup.dart';
export 'widgets/arxa_kit_lazy_indexed_stack.dart';
export 'widgets/arxa_kit_directional_tab_transition.dart';
export 'widgets/arxa_kit_tab_switch_transition.dart';
export 'widgets/arxa_kit_animated_tab_stack.dart';
export 'widgets/arxa_kit_tab_bar.dart';
export 'widgets/arxa_kit_bottom_nav_scaffold.dart';
export 'widgets/arxa_kit_pressable.dart';
export 'widgets/arxa_kit_native_button.dart';
export 'widgets/arxa_kit_native_segmented_control.dart';
export 'widgets/arxa_kit_native_chrome_gate.dart';
export 'widgets/arxa_kit_scroll_occlusion_gate.dart';
export 'widgets/arxa_kit_scroll_edge_effect.dart';
export 'widgets/arxa_kit_edge_aware_list_view.dart';
export 'widgets/arxa_kit_native_switch.dart';
export 'widgets/arxa_kit_native_slider.dart';
export 'widgets/arxa_kit_native_range_slider.dart';
export 'widgets/arxa_kit_native_icon_button.dart';
export 'widgets/arxa_kit_input_tap_behavior.dart';
export 'widgets/arxa_kit_native_input_bar.dart';
export 'widgets/arxa_kit_opaque_bar_base.dart';
export 'widgets/arxa_kit_dismiss_keyboard.dart';
export 'widgets/arxa_kit_menu_item.dart';
export 'widgets/arxa_kit_native_fab.dart';
export 'widgets/arxa_kit_native_fab_menu.dart';
export 'widgets/arxa_kit_native_popup_menu.dart';
export 'widgets/arxa_kit_native_split_button.dart';
export 'widgets/arxa_kit_native_loading_indicator.dart';
export 'widgets/arxa_kit_native_progress.dart';
export 'widgets/arxa_kit_native_search_bar.dart';
export 'widgets/arxa_kit_native_textfield.dart';
export 'widgets/arxa_kit_chrome_scaffold.dart';
export 'widgets/arxa_kit_native_app_bar.dart';
export 'widgets/arxa_kit_native_floating_bar.dart';
export 'widgets/arxa_kit_native_sliver_app_bar.dart';
export 'widgets/arxa_kit_native_toolbar.dart';
export 'widgets/arxa_kit_native_navigation_rail.dart';
export 'widgets/arxa_kit_glass_card.dart';
export 'widgets/arxa_kit_glass_warmup.dart';
export 'widgets/arxa_kit_frosted_surface.dart';
export 'widgets/arxa_kit_glass_luminance.dart';
export 'widgets/arxa_kit_image.dart';
export 'widgets/arxa_kit_markdown.dart';
export 'widgets/arxa_kit_code_block.dart';
export 'widgets/arxa_kit_svg.dart';
export 'widgets/arxa_kit_list_section.dart';
export 'widgets/arxa_kit_list_tile.dart';
export 'widgets/arxa_kit_drawer.dart';
export 'widgets/arxa_kit_chip.dart';
export 'widgets/arxa_kit_chip_carousel.dart';
export 'widgets/arxa_kit_native_sheet.dart';
export 'widgets/arxa_kit_native_dialog.dart';
export 'widgets/arxa_kit_stream_builder.dart';
export 'enums/arxa_kit_widgets_enum.dart';
export 'enums/arxa_kit_native_component.dart';
export 'extensions/arxa_kit_overlay_extension.dart';
export 'services/notifications/arxa_kit_notification_service.dart';
export 'services/navigation/arxa_kit_navigation_controller_service.dart';
export 'services/navigation/arxa_kit_platform_pages.dart';
export 'services/sheet/arxa_kit_bottom_sheet_service.dart';
export 'utils/arxa_kit_native_overlay.dart';

// Native transition occlusion — the NavigatorObserver that suppresses every
// native glass surface's Liquid Glass effect during route transitions (push,
// pop, and — with the kit's gesture-aware fork — the interactive back-swipe),
// so a hybrid-composition platform view can't leak over the sliding routes.
// Register it in the app router's navigatorObservers (see NATIVE_COMPONENTS.md
// "Route-transition occlusion"). CNTransitionHelper is the manual begin/end
// API for custom/non-Navigator transitions.
export 'package:cupertino_native_better/cupertino_native.dart'
    show CNTransitionObserver, CNTransitionHelper, CNTabBarRouteObserver;
// The native-tier focus tracker — hosts and integration tests observe CN
// keyboard state through it (a CNTextField has no Flutter FocusNode).
export 'package:cupertino_native_better/cupertino_native_better.dart'
    show CNTextFieldFocus;

// --- ArxaKitAction (fluent operation API + snackbar vocabulary) ---
export 'utils/kit_action/arxa_kit_action.dart';
export 'utils/kit_action/arxa_kit_action_hub.dart'; // SPIKE — @experimental
export 'utils/arxa_kit_action_owner.dart';
export 'utils/arxa_kit_view_model.dart';
export 'utils/kit_action/arxa_kit_snackbar_type.dart';
export 'utils/kit_action/arxa_kit_snackbar_setup.dart';
