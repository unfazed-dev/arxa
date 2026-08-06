/// Snackbar variants the kit emits for its auto-process notifications
/// (AppBoxKitAction loading / success / error / warning). The kit owns the vocabulary
/// AND the default presentation — [setupAppBoxKitSnackbars] registers a SnackbarConfig
/// for each variant using the kit palette. AppBoxKitActionConfig's snackbar-type
/// fields are `dynamic`, so a call site may pass a host enum variant (with a
/// matching registered config) to override.
enum AppBoxKitSnackbarType {
  appBoxKitAutoProcessInfo,
  appBoxKitAutoProcessSuccess,
  appBoxKitAutoProcessError,
  appBoxKitAutoProcessWarning,
}
