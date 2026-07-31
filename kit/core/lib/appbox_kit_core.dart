/// appbox_kit — a reusable Stacked MVVM toolkit.
///
/// One-stop import for the kit's public surface:
/// ```dart
/// import 'package:appbox_kit_core/appbox_kit_core.dart';
/// ```
///
/// Ships a generic default Material 3 design system (KitColors / KitDarkColors
/// + kitLightTheme / kitDarkTheme) any Stacked app can use as-is or override,
/// and manages its own snackbar presentation (KitSnackbarType / setupKitSnackbars).
/// Not included (source-app-specific): widgets, supabase services, navbar enum.
library;

// --- Locator (decoupled: resolves the app's StackedLocator singleton) ---
export 'kit_locator.dart';

// --- Platform detection (native-chrome gating) ---
export 'platform/kit_platform.dart';

// --- Native-chrome widgets (adaptive: Liquid Glass / Compose M3 / Flutter fallback) ---
// Controls
// Actions (+ shared menu primitive)
// Feedback
// Bars
// Surfaces

// --- Common: design tokens + theme + UI helpers ---
export 'common/kit_app_constants.dart';
export 'common/kit_glyphs.dart';
export 'common/kit_glyphs_lucide.dart';
export 'common/kit_colors.dart';
export 'common/kit_ui_helpers.dart';

// --- Enums ---
export 'enums/kit_app_common_enum.dart';
export 'enums/kit_icon_position.dart';

// --- Extensions ---
export 'extensions/kit_dismiss_keyboard_extension.dart';
export 'extensions/kit_to_title_case_extension.dart';
export 'extensions/kit_hover_extensions.dart';
export 'extensions/kit_selectable_extension.dart';

// --- Services ---
export 'services/error/kit_error_service.dart';
export 'services/theme/kit_theme_service.dart';

// --- Utils ---
export 'utils/kit_time_utils.dart';
export 'utils/formatters/email_input_formatter.dart';
export 'utils/formatters/mobile_number_input_formatter.dart';
export 'utils/formatters/mobile_aus_input_formatter.dart';
export 'utils/formatters/otp_code_input_formatter.dart';
export 'utils/mouse_transforms/fill_on_hover.dart';
export 'utils/mouse_transforms/outline_on_hover.dart';
export 'utils/mouse_transforms/scale_on_hover.dart';
export 'utils/mouse_transforms/translate_on_hover.dart';

// --- KitAction (fluent operation API + snackbar vocabulary/presentation) ---
