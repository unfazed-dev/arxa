import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../channel/params.dart' show resolveColorToArgb;
import '../components/tab_bar.dart' show CNTabBarRouteObserver;
import '../utils/modal_hide_mixin.dart';

/// A native iOS text field with Liquid Glass styling, for use as a real form
/// input (not a search affordance).
///
/// Backed by `UITextField` via SwiftUI hosted in a `UiKitView` (iOS 26+ renders
/// `.glassEffect(.regular, in: .capsule)`; below iOS 26 a `Color(.systemGray6)`
/// capsule). On macOS it hosts the same SwiftUI field via `AppKitView`. This is
/// the primitive [AppBoxKitNativeTextField] wraps on its Liquid Glass tier.
///
/// **Two-way controller** (the gap [CNSearchBar] leaves open): pass a
/// [TextEditingController] and it stays in sync both ways — programmatic
/// `controller.text = …` is forwarded to the native field via `setText`, and
/// every native keystroke writes back into the controller, so reads after the
/// field loses focus (form submission) return the current value. A reentrancy
/// guard breaks the would-be echo loop.
///
/// **Keyboard** — `keyboardType` is honored on the plain (non-secure) tier;
/// secure fields (passwords) intentionally do not set a keyboard type so iOS
/// uses the default (which is correct for secure entry).
///
/// **Modal z-order** — includes [autoHideOnModal] (Issue #53): when a modal
/// sheet is presented above this widget's host route, the native platform view
/// is torn down so its pixels don't bleed through the sheet's scrim. Requires
/// `CNTabBarRouteObserver()` registered in the app's `navigatorObservers`
/// (same contract as [CNSearchBar]).
class CNTextField extends StatefulWidget {
  /// Creates a native Liquid Glass text field. See the class doc for the
  /// two-way controller contract and the modal-hide behavior.
  const CNTextField({
    super.key,
    this.controller,
    this.placeholder,
    this.obscureText = false,
    this.keyboardType,
    this.autofocus = false,
    this.onChanged,
    this.onSubmitted,
    this.onFocusChanged,
    this.tint,
    this.textColor,
    this.placeholderColor,
    this.autoHideOnModal = true,
    this.preferFlutterTier = false,
  });

  /// Owns the input text. Two-way synced: programmatic writes forward to the
  /// native field; native keystrokes write back. `null` creates an internal
  /// controller (not retrievable — pass one if you need to read `.text`).
  final TextEditingController? controller;

  /// Placeholder shown when the field is empty.
  final String? placeholder;

  /// `true` → `SecureField` (passwords / OTP). Disables the inline clear button.
  final bool obscureText;

  /// Keyboard type. Applied on the plain tier only.
  final TextInputType? keyboardType;

  /// Autofocus on appearance.
  final bool autofocus;

  /// Fired on every keystroke with the current text.
  final ValueChanged<String>? onChanged;

  /// Fired on submit (return key).
  final ValueChanged<String>? onSubmitted;

  /// Fired when focus enters/leaves the field.
  final ValueChanged<bool>? onFocusChanged;

  /// Accent / caret / clear-button tint (ARGB resolved from context).
  final Color? tint;

  /// Text color (nil → `.primary`).
  final Color? textColor;

  /// Placeholder color (nil → `.secondary`).
  final Color? placeholderColor;

  /// See class doc. Mirrors [CNSearchBar.autoHideOnModal].
  final bool autoHideOnModal;

  /// LOCAL PATCH #6: tier-split demotion (see button.dart PATCH #4).
  /// Forces the Flutter fallback tier even where the native field is
  /// available; hosts set this when the field lives under a Scrollable.
  final bool preferFlutterTier;

  @override
  State<CNTextField> createState() => _CNTextFieldState();
}

/// Standard iOS single-line field height. The platform view (and its
/// pre-creation `SizedBox.expand()` placeholder inside [UiKitView]) sizes to
/// `constraints.biggest`, so the widget MUST own a bounded height or it blows
/// up with "given an infinite size" inside any unbounded-height parent
/// (Column under a scroll view) — same contract as [CNSearchBar.expandedHeight].
const double _kFieldHeight = 44.0;

class _CNTextFieldState extends State<CNTextField>
    with ModalHideMixin<CNTextField> {
  @override
  bool get autoHideOnModal => widget.autoHideOnModal;

  @override
  MethodChannel? get platformViewChannel => _channel;

  MethodChannel? _channel;

  late TextEditingController _controller;
  bool _ownsController = false;

  /// Reentrancy guard for the two-way controller sync. Set while applying a
  /// native-originated text change to the Dart controller, so the controller's
  /// listener doesn't echo it back to native via `setText`.
  bool _suppressControllerEcho = false;

  /// Last brightness pushed to native, so a theme flip sends exactly one
  /// `setBrightness` and a rebuild for any other reason sends none.
  bool? _lastIsDark;

  /// Deliberately the same expression used for the `isDark` creation param
  /// below — if the two ever disagree the sync either misfires or never fires.
  bool get _isDark => Theme.of(context).brightness == Brightness.dark;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TextEditingController();
    _ownsController = widget.controller == null;
    _controller.addListener(_onControllerChanged);
    CNTabBarRouteObserver.anyModalDepth.addListener(_onAnyModalDepthChanged);
    _onAnyModalDepthChanged();
  }

  /// The native field pins its own appearance with
  /// `container.overrideUserInterfaceStyle`, which makes it immune to the
  /// window's trait collection by design — so an app-level theme flip can only
  /// reach it through this channel call. `Theme.of(context)` registers an
  /// inherited-widget dependency, so this fires on every theme change.
  ///
  /// Without it the field keeps its creation-time appearance forever and only
  /// corrects itself when the platform view happens to be recreated (which is
  /// why the stale appearance looked like a *delay* while navigating rather
  /// than a permanent bug).
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncBrightnessIfNeeded();
  }

  Future<void> _syncBrightnessIfNeeded() async {
    // Read the theme FIRST, before any bail-out. `_isDark` resolves through an
    // inherited widget, so this read is what registers this State's dependency
    // on Theme/CupertinoTheme. Returning early on a null channel — which is the
    // normal state on the first `didChangeDependencies`, and for the whole
    // `PlatformViewGuard` delay in debug — skipped the read, so no dependency
    // was ever registered and `didChangeDependencies` never fired again for an
    // in-app theme change. The view then stayed at its creation-time appearance
    // until something else happened to rebuild it. Same fix, and the same
    // reasoning, as `glass_button_group.dart:184-189`.
    final bool isDark = _isDark;
    final channel = _channel;
    if (channel == null) return;
    if (_lastIsDark == isDark) return;
    _lastIsDark = isDark;
    await channel.invokeMethod('setBrightness', {'isDark': isDark});
  }

  @override
  void didUpdateWidget(covariant CNTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      _controller.removeListener(_onControllerChanged);
      if (_ownsController) _controller.dispose();
      _controller = widget.controller ?? TextEditingController();
      _ownsController = widget.controller == null;
      _controller.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    if (_ownsController) _controller.dispose();
    CNTabBarRouteObserver.anyModalDepth.removeListener(_onAnyModalDepthChanged);
    // Unmounting while focused never delivers a `focusChanged(false)`, so
    // clear the pointer here or it dangles at a dead platform view.
    if (identical(CNTextFieldFocus._current, _channel)) {
      CNTextFieldFocus._current = null;
    }
    super.dispose();
  }

  /// Dart controller → native. Fires when the host sets `controller.text`
  /// programmatically (autofill, reset, validation clear). Guarded against the
  /// native→Dart echo (we set the guard in `_onTextChanged` before mutating).
  void _onControllerChanged() {
    if (_suppressControllerEcho) return;
    _channel?.invokeMethod('setText', {'text': _controller.text});
  }

  /// Modal-depth listener stub (ModalHideMixin drives the hide via
  /// `maybeHiddenPlaceholder`; this listener is the registration the mixin
  /// requires so it re-evaluates when a modal opens).
  void _onAnyModalDepthChanged() {
    // ModalHideMixin reads anyModalDepth in build via maybeHiddenPlaceholder.
    if (mounted) setState(() {});
  }

  void _onPlatformViewCreated(int id) {
    final ch = MethodChannel('CNTextField_$id');
    _channel = ch;
    ch.setMethodCallHandler(_onMethodCall);
    // Seed the brightness baseline to what the creation params just carried, so
    // the first `didChangeDependencies` after creation is a no-op rather than a
    // redundant channel round-trip.
    _lastIsDark = _isDark;
    // Push the initial text so native and Dart agree from frame one (covers the
    // case where the controller was constructed with non-empty text).
    if (_controller.text.isNotEmpty) {
      ch.invokeMethod('setText', {'text': _controller.text});
    }
  }

  Future<dynamic> _onMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'textChanged':
        final text = (call.arguments['text'] as String?) ?? '';
        if (_controller.text != text) {
          // Native → Dart. Suppress the echo so _onControllerChanged doesn't
          // bounce this back to native as a setText (would loop / fight the
          // cursor).
          _suppressControllerEcho = true;
          _controller.value = TextEditingValue(
            text: text,
            selection: TextSelection.collapsed(offset: text.length),
          );
          _suppressControllerEcho = false;
        }
        widget.onChanged?.call(text);
        break;
      case 'submitted':
        widget.onSubmitted?.call((call.arguments['text'] as String?) ?? '');
        break;
      case 'focusChanged':
        final bool focused = (call.arguments['focused'] as bool?) ?? false;
        // Record which native field holds the keyboard, so an app-level
        // "tap outside to dismiss" can reach it. A CNTextField is a platform
        // view with no FocusNode, so Flutter's focus system does not know it
        // exists and `FocusManager.primaryFocus?.unfocus()` cannot close its
        // keyboard — see [CNTextFieldFocus].
        if (focused) {
          CNTextFieldFocus._current = _channel;
        } else if (identical(CNTextFieldFocus._current, _channel)) {
          CNTextFieldFocus._current = null;
        }
        widget.onFocusChanged?.call(focused);
        break;
    }
    return null;
  }

  /// Maps [TextInputType] → the string the Swift side expects
  /// (`TextModel.uiKeyboardType`).
  String _keyboardTypeString() {
    final t = widget.keyboardType;
    if (t == TextInputType.number) return 'number';
    if (t == TextInputType.phone) return 'phone';
    if (t == TextInputType.emailAddress) return 'emailAddress';
    if (t == TextInputType.url) return 'url';
    return 'default';
  }

  @override
  Widget build(BuildContext context) {
    // Liquid Glass is iOS 26+ / macOS 26+ only. Below that, the native SwiftUI
    // field still renders a `systemGray6` capsule — so the platform view is
    // valid on all iOS/macOS. The kit wrapper decides whether to use this tier
    // or the Material fallback; this widget always builds the native field.
    // LOCAL PATCH #6: tier-split demotion (see button.dart PATCH #4).
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS) &&
        !widget.preferFlutterTier) {
      final hidden = maybeHiddenPlaceholder(height: _kFieldHeight);
      if (hidden != null) return hidden;

      const viewType = 'CNTextField';
      final creationParams = <String, dynamic>{
        'text': _controller.text,
        'placeholder': widget.placeholder ?? '',
        'isSecure': widget.obscureText,
        'autofocus': widget.autofocus,
        'keyboardType': _keyboardTypeString(),
        'tint': resolveColorToArgb(widget.tint, context),
        'textColor': resolveColorToArgb(widget.textColor, context),
        'placeholderColor': resolveColorToArgb(widget.placeholderColor, context),
        'isDark': _isDark,
      };

      final platformView = defaultTargetPlatform == TargetPlatform.iOS
          ? UiKitView(
              viewType: viewType,
              creationParams: creationParams,
              creationParamsCodec: const StandardMessageCodec(),
              onPlatformViewCreated: _onPlatformViewCreated,
            )
          : AppKitView(
              viewType: viewType,
              creationParams: creationParams,
              creationParamsCodec: const StandardMessageCodec(),
              onPlatformViewCreated: _onPlatformViewCreated,
            );

      // Bounded height is mandatory: UiKitView/AppKitView (and the
      // SizedBox.expand placeholder Flutter builds before the native view is
      // created) size to constraints.biggest.
      return wrapWithModalInteractionGuard(
        SizedBox(height: _kFieldHeight, child: platformView),
      );
    }

    // Non-Apple — should not be reached (the kit wrapper gates this). Render a
    // Material fallback defensively rather than throwing, so a misconfigured
    // host still gets a usable field.
    return TextField(
      controller: _controller,
      decoration: InputDecoration(hintText: widget.placeholder),
      obscureText: widget.obscureText,
      keyboardType: widget.keyboardType,
      autofocus: widget.autofocus,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
    );
  }
}

/// Reaches the keyboard raised by a [CNTextField].
///
/// A [CNTextField] is a `UiKitView` wrapping a SwiftUI `TextField`; focus lives
/// in the native `@FocusState`, and the widget deliberately carries **no**
/// [FocusNode]. So `FocusManager.instance.primaryFocus?.unfocus()` — the whole
/// basis of every "tap outside to dismiss" recipe — has nothing to unfocus and
/// silently leaves the keyboard up.
///
/// The native side has always had the lever (`case "unfocus"` →
/// `focusBinding.relinquish()` in `CupertinoTextFieldPlatformView.swift`); it
/// was simply never called from Dart. This is that call.
///
/// **One variable, not a registry.** Only one field can hold the keyboard, so
/// tracking the focused one is a single nullable pointer maintained by the
/// `focusChanged` callback the native side already sends. There is no
/// collection to iterate, nothing to leak, and no listeners — [dismiss] is a
/// plain method call, so it cannot notify anything mid-build.
class CNTextFieldFocus {
  CNTextFieldFocus._();

  /// Channel of the [CNTextField] currently holding the keyboard, or null.
  static MethodChannel? _current;

  /// Whether a native field currently holds the keyboard.
  static bool get hasFocus => _current != null;

  /// Asks the focused native field to resign first responder, closing the
  /// keyboard. A no-op when no [CNTextField] is focused, so callers may fire
  /// it unconditionally alongside Flutter's own unfocus.
  static Future<void> dismiss() async {
    final MethodChannel? channel = _current;
    if (channel == null) return;
    _current = null;
    await channel.invokeMethod('unfocus');
  }

  /// Test seam: drop the tracked field without touching a platform channel.
  @visibleForTesting
  static void debugReset() => _current = null;

  /// Test seam: stand in for a focused native field. A [CNTextField] wraps a
  /// `UiKitView`, which cannot be mounted in a headless test, so the only way
  /// to exercise the dismissal path is to supply the channel directly.
  @visibleForTesting
  static void debugSetCurrent(MethodChannel channel) => _current = channel;
}
