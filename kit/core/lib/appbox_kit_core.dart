/// appbox_kit — a reusable Stacked MVVM toolkit.
///
/// One-stop import for the kit's public surface:
/// ```dart
/// import 'package:appbox_kit_core/appbox_kit_core.dart';
/// ```
///
/// Ships a generic default Material 3 design system (AppBoxKitColors / AppBoxKitDarkColors
/// + appBoxKitLightTheme / appBoxKitDarkTheme) any Stacked app can use as-is or override,
/// and manages its own snackbar presentation (AppBoxKitSnackbarType / setupAppBoxKitSnackbars).
/// Not included (source-app-specific): widgets, supabase services, navbar enum.
library;

// --- Locator (decoupled: resolves the app's StackedLocator singleton) ---
export 'appbox_kit_locator.dart';

// --- Platform detection (native-chrome gating) ---
export 'platform/appbox_kit_platform.dart';

// --- Native-chrome widgets (adaptive: Liquid Glass / Compose M3 / Flutter fallback) ---
// Controls
// Actions (+ shared menu primitive)
// Feedback
// Bars
// Surfaces

// --- Common: design tokens + theme + UI helpers ---
export 'common/appbox_kit_app_constants.dart';
export 'common/appbox_kit_glyphs.dart';
export 'common/appbox_kit_glyphs_lucide.dart';
export 'common/appbox_kit_colors.dart';
export 'common/appbox_kit_fonts.dart';
export 'common/appbox_kit_ui_helpers.dart';

// --- Enums ---
export 'enums/appbox_kit_app_common_enum.dart';
export 'enums/appbox_kit_icon_position.dart';

// --- Extensions ---
export 'extensions/appbox_kit_dismiss_keyboard_extension.dart';
export 'extensions/appbox_kit_to_title_case_extension.dart';
export 'extensions/appbox_kit_hover_extensions.dart';
export 'extensions/appbox_kit_selectable_extension.dart';

// --- Services ---
export 'services/error/appbox_kit_error_service.dart';
export 'services/theme/appbox_kit_theme_service.dart';

// --- Utils ---
export 'utils/appbox_kit_time_utils.dart';
export 'utils/formatters/appbox_kit_email_input_formatter.dart';
export 'utils/formatters/appbox_kit_mobile_number_input_formatter.dart';
export 'utils/formatters/appbox_kit_mobile_aus_input_formatter.dart';
export 'utils/formatters/appbox_kit_otp_code_input_formatter.dart';
export 'utils/mouse_transforms/appbox_kit_fill_on_hover.dart';
export 'utils/mouse_transforms/appbox_kit_outline_on_hover.dart';
export 'utils/mouse_transforms/appbox_kit_scale_on_hover.dart';
export 'utils/mouse_transforms/appbox_kit_translate_on_hover.dart';

// --- AppBoxKitAction (fluent operation API + snackbar vocabulary/presentation) ---
