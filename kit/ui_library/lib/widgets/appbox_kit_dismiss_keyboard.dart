import 'package:cupertino_native_better/cupertino_native_better.dart'
    show CNTextFieldFocus;
import 'package:flutter/widgets.dart';

/// Tap anywhere outside a text field to dismiss the keyboard, installed once
/// for a whole app.
///
/// Wrap the app **above** its router/`MaterialApp` so every shell, route and
/// nested navigator inherits it:
///
/// ```dart
/// runApp(const AppBoxKitDismissKeyboard(child: MyApp()));
/// ```
///
/// ## Why a widget and not just an extension
///
/// An `extension on BuildContext` can only dismiss when something calls it —
/// it cannot install behaviour. App-wide interception needs a widget in the
/// tree above the routes. Both ship here: this widget is the "apply once in
/// `main`" lever, and [AppBoxKitKeyboardX.dismissKeyboard] is the imperative
/// call for handlers that need it explicitly (a submit button, a route change).
///
/// ## Why both unfocus paths
///
/// Every published recipe for this is `FocusManager.instance.primaryFocus
/// ?.unfocus()`. That covers Flutter-rendered fields and **silently fails**
/// for the kit's native tier: a `CNTextField` is a platform view whose focus
/// lives in SwiftUI's `@FocusState`, with no [FocusNode] in the Flutter tree
/// for `primaryFocus` to return. So this also calls [CNTextFieldFocus.dismiss],
/// which reaches the focused native field over its own channel. Both are
/// no-ops when nothing is focused, so firing them unconditionally is safe.
///
/// ## Why [Listener], not [GestureDetector]
///
/// A `GestureDetector` competes in the gesture arena: it must wait to see
/// whether a competing recognizer (a scroll, a button, a slider drag) claims
/// the gesture, and an ancestor that wins the arena swallows the tap so the
/// keyboard stays up. `Listener.onPointerDown` observes the raw pointer
/// *before* arena resolution — it never competes, never wins, and never
/// prevents the widget under the finger from receiving its own tap. Dismissing
/// on pointer-down also matches the platform: iOS closes the keyboard as the
/// finger lands, not on release.
///
/// The trade is that a scroll gesture also dismisses, since a drag begins with
/// a pointer-down. That matches `ScrollViewKeyboardDismissBehavior.onDrag`,
/// which is the same choice Flutter's own scrollables offer.
class AppBoxKitDismissKeyboard extends StatelessWidget {
  const AppBoxKitDismissKeyboard({
    super.key,
    required this.child,
    this.enabled = true,
  });

  final Widget child;

  /// Set false to suspend dismissal (e.g. a screen driving focus itself).
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return Listener(
      // `deferToChild` and NOT `opaque`: this listener must not add a hit-test
      // target of its own. It sits above the entire app, so an opaque box here
      // would make every miss — including taps on inert background — register,
      // and more importantly would claim the whole screen in hit testing.
      // Pointer events still arrive for anything the child does hit.
      behavior: HitTestBehavior.deferToChild,
      onPointerDown: (_) => appBoxKitDismissKeyboard(),
      child: child,
    );
  }
}

/// Dismisses the keyboard on both tiers, whichever is up.
///
/// Safe to call when nothing is focused. Prefer the [BuildContext] extension
/// ([AppBoxKitKeyboardX.dismissKeyboard]) at call sites that have a context;
/// this bare function exists for the ones that do not.
void appBoxKitDismissKeyboard() {
  // Flutter-rendered fields (Material tier, TextFieldM3E, any host TextField).
  final FocusNode? focused = FocusManager.instance.primaryFocus;
  if (focused != null && focused.hasPrimaryFocus) focused.unfocus();
  // Native tier — invisible to the line above; see the class docs.
  CNTextFieldFocus.dismiss();
}

/// Imperative keyboard dismissal from any [BuildContext].
extension AppBoxKitKeyboardX on BuildContext {
  /// Closes the keyboard, whichever tier raised it.
  ///
  /// ```dart
  /// onPressed: () {
  ///   context.dismissKeyboard();
  ///   submit();
  /// }
  /// ```
  void dismissKeyboard() => appBoxKitDismissKeyboard();
}
