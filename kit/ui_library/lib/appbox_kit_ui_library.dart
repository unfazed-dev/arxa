/// ui_library — Stacked kit UI tier.
///
/// Kit* adaptive port widgets, the UI-coupled services (navigation / sheet /
/// notifications), and the overlay + component plumbing that host them.
/// Re-exports [appbox_kit_core] so a consumer needs a single import for the
/// full kit surface (widgets here + tokens / platform / appBoxKitLocator / error &
/// theme services in core). Dependency edge is ui_library -> core only.
library;

// Core non-UI surface — re-exported for one-import consumers.
export 'package:appbox_kit_core/appbox_kit_core.dart';

export 'widgets/appbox_kit_lazy_indexed_stack.dart';
export 'widgets/appbox_kit_directional_tab_transition.dart';
export 'widgets/appbox_kit_tab_switch_transition.dart';
export 'widgets/appbox_kit_animated_tab_stack.dart';
export 'widgets/appbox_kit_tab_bar.dart';
export 'widgets/appbox_kit_bottom_nav_scaffold.dart';
export 'widgets/appbox_kit_native_button.dart';
export 'widgets/appbox_kit_native_segmented_control.dart';
export 'widgets/appbox_kit_native_chrome_gate.dart';
export 'widgets/appbox_kit_scroll_occlusion_gate.dart';
export 'widgets/appbox_kit_scroll_edge_effect.dart';
export 'widgets/appbox_kit_native_switch.dart';
export 'widgets/appbox_kit_native_slider.dart';
export 'widgets/appbox_kit_native_range_slider.dart';
export 'widgets/appbox_kit_native_icon_button.dart';
export 'widgets/appbox_kit_native_input_bar.dart';
export 'widgets/appbox_kit_menu_item.dart';
export 'widgets/appbox_kit_native_fab.dart';
export 'widgets/appbox_kit_native_fab_menu.dart';
export 'widgets/appbox_kit_native_popup_menu.dart';
export 'widgets/appbox_kit_native_split_button.dart';
export 'widgets/appbox_kit_native_loading_indicator.dart';
export 'widgets/appbox_kit_native_progress.dart';
export 'widgets/appbox_kit_native_search_bar.dart';
export 'widgets/appbox_kit_native_textfield.dart';
export 'widgets/appbox_kit_native_app_bar.dart';
export 'widgets/appbox_kit_native_sliver_app_bar.dart';
export 'widgets/appbox_kit_native_toolbar.dart';
export 'widgets/appbox_kit_native_navigation_rail.dart';
export 'widgets/appbox_kit_glass_card.dart';
export 'widgets/appbox_kit_frosted_surface.dart';
export 'widgets/appbox_kit_image.dart';
export 'widgets/appbox_kit_markdown.dart';
export 'widgets/appbox_kit_code_block.dart';
export 'widgets/appbox_kit_svg.dart';
export 'widgets/appbox_kit_list_section.dart';
export 'widgets/appbox_kit_list_tile.dart';
export 'widgets/appbox_kit_drawer.dart';
export 'widgets/appbox_kit_chip.dart';
export 'widgets/appbox_kit_chip_carousel.dart';
export 'widgets/appbox_kit_native_sheet.dart';
export 'widgets/appbox_kit_native_dialog.dart';
export 'widgets/appbox_kit_stream_builder.dart';
export 'enums/appbox_kit_widgets_enum.dart';
export 'enums/appbox_kit_native_component.dart';
export 'extensions/appbox_kit_overlay_extension.dart';
export 'services/notifications/appbox_kit_notification_service.dart';
export 'services/navigation/appbox_kit_navigation_controller_service.dart';
export 'services/navigation/appbox_kit_platform_pages.dart';
export 'services/sheet/appbox_kit_bottom_sheet_service.dart';
export 'utils/appbox_kit_native_overlay.dart';

// Native transition occlusion — the NavigatorObserver that suppresses every
// native glass surface's Liquid Glass effect during route transitions (push,
// pop, and — with the kit's gesture-aware fork — the interactive back-swipe),
// so a hybrid-composition platform view can't leak over the sliding routes.
// Register it in the app router's navigatorObservers (see NATIVE_COMPONENTS.md
// "Route-transition occlusion"). CNTransitionHelper is the manual begin/end
// API for custom/non-Navigator transitions.
export 'package:cupertino_native_better/cupertino_native.dart'
    show CNTransitionObserver, CNTransitionHelper;

// --- AppBoxKitAction (fluent operation API + snackbar vocabulary) ---
export 'utils/kit_action/appbox_kit_action.dart';
export 'utils/kit_action/appbox_kit_action_bus.dart'; // SPIKE — @experimental
export 'utils/appbox_kit_action_owner.dart';
export 'utils/appbox_kit_view_model.dart';
export 'utils/kit_action/appbox_kit_snackbar_type.dart';
export 'utils/kit_action/appbox_kit_snackbar_setup.dart';
