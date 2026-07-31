/// Snackbar variants the kit emits for its auto-process notifications
/// (KitAction loading / success / error / warning). The kit owns the vocabulary
/// AND the default presentation — [setupKitSnackbars] registers a SnackbarConfig
/// for each variant using the kit palette. KitActionConfig's snackbar-type
/// fields are `dynamic`, so a call site may pass a host enum variant (with a
/// matching registered config) to override.
enum KitSnackbarType {
  kitAutoProcessInfo,
  kitAutoProcessSuccess,
  kitAutoProcessError,
  kitAutoProcessWarning,
}
