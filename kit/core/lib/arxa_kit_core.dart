/// arxa_kit — a reusable Stacked MVVM toolkit.
///
/// One-stop import for the kit's public surface:
/// ```dart
/// import 'package:arxa_kit_core/arxa_kit_core.dart';
/// ```
///
/// Ships a generic default Material 3 design system (ArxaKitColors / ArxaKitDarkColors
/// + arxaKitLightTheme / arxaKitDarkTheme) any Stacked app can use as-is or override,
/// and manages its own snackbar presentation (ArxaKitSnackbarType / setupArxaKitSnackbars).
/// Not included (source-app-specific): widgets, supabase services, navbar enum.
library;

// --- Locator (decoupled: resolves the app's StackedLocator singleton) ---
export 'arxa_kit_locator.dart';

// --- Platform detection (native-chrome gating) ---
export 'platform/arxa_kit_platform.dart';
export 'platform/arxa_kit_fidelity.dart';

// --- Native-chrome widgets (adaptive: Liquid Glass / Compose M3 / Flutter fallback) ---
// Controls
// Actions (+ shared menu primitive)
// Feedback
// Bars
// Surfaces

// --- Common: design tokens + theme + UI helpers ---
export 'common/arxa_kit_app_constants.dart';
export 'common/arxa_kit_glyphs.dart';
export 'common/arxa_kit_glyphs_lucide.dart';
export 'common/arxa_kit_colors.dart';
export 'common/arxa_kit_fonts.dart';
export 'common/arxa_kit_ui_helpers.dart';

// --- Inspect identity (Q12): the emit-time (screenId, surfaceId, anatomyNodeId) triple ---
export 'common/arxa_kit_inspect_attrs.dart';

// --- Enums ---
export 'enums/arxa_kit_app_common_enum.dart';
export 'enums/arxa_kit_icon_position.dart';

// --- Extensions ---
export 'extensions/arxa_kit_dismiss_keyboard_extension.dart';
export 'extensions/arxa_kit_to_title_case_extension.dart';
export 'extensions/arxa_kit_hover_extensions.dart';
export 'extensions/arxa_kit_selectable_extension.dart';

// --- Services ---
export 'services/error/arxa_kit_error_service.dart';
export 'services/theme/arxa_kit_theme_service.dart';

// --- Utils ---
export 'utils/arxa_kit_time_utils.dart';
export 'utils/formatters/arxa_kit_email_input_formatter.dart';
export 'utils/formatters/arxa_kit_mobile_number_input_formatter.dart';
export 'utils/formatters/arxa_kit_mobile_aus_input_formatter.dart';
export 'utils/formatters/arxa_kit_otp_code_input_formatter.dart';
export 'utils/mouse_transforms/arxa_kit_fill_on_hover.dart';
export 'utils/mouse_transforms/arxa_kit_outline_on_hover.dart';
export 'utils/mouse_transforms/arxa_kit_scale_on_hover.dart';
export 'utils/mouse_transforms/arxa_kit_translate_on_hover.dart';

// --- ArxaKitAction (fluent operation API + snackbar vocabulary/presentation) ---
