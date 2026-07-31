// ═══════════════════════════════════════════════════════════════════════════════
// KitAction v2.0 - Notification Type Enum
// ═══════════════════════════════════════════════════════════════════════════════
//
// 📖 Technical Specification: docs/kit_action_technical_specification.md
//    - Section 5.2: Notification Types (lines 858-927)
//    - Section 11.1: Glossary (lines 2055-2060)
//
// NEW in v2.0: Flexible notification rendering for different UI contexts.
// ═══════════════════════════════════════════════════════════════════════════════

/// Defines how notifications should be displayed to the user
///
/// KitAction supports multiple notification types for loading, success, and error states:
/// - **snackbar**: Standard bottom notification bar (default)
/// - **dialog**: Full modal dialog with overlay
/// - **bottomSheet**: Bottom sheet that slides up
/// - **none**: No notification displayed
///
/// 📖 **Specification:** See Section 5.2 (lines 858-927) for usage patterns
enum NotificationType {
  /// Display notification as a snackbar at the bottom of the screen
  snackbar,

  /// Display notification as a modal dialog with overlay
  dialog,

  /// Display notification as a bottom sheet sliding from bottom
  bottomSheet,

  /// Do not display any notification
  none,
}
