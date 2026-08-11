import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import '../channel/params.dart';
import '../utils/version_detector.dart';
import '../utils/theme_helper.dart';
import '../utils/modal_hide_mixin.dart';

/// Controller for a [CNSwitch] that allows imperative updates from Dart
/// to the underlying native UISwitch/NSSwitch instance.
class CNSwitchController {
  MethodChannel? _channel;

  void _attach(MethodChannel channel) {
    _channel = channel;
  }

  void _detach() {
    _channel = null;
  }

  /// Sets the switch [value]. When [animated] is true the change is animated
  /// on the native control.
  Future<void> setValue(bool value, {bool animated = false}) async {
    final channel = _channel;
    if (channel == null) return;
    await channel.invokeMethod('setValue', {
      'value': value,
      'animated': animated,
    });
  }

  /// Enables or disables user interaction on the native switch.
  Future<void> setEnabled(bool enabled) async {
    final channel = _channel;
    if (channel == null) return;
    await channel.invokeMethod('setEnabled', {'enabled': enabled});
  }
}

/// A Cupertino-native switch rendered by the host platform.
///
/// On iOS/macOS this uses a platform view to embed UISwitch/NSSwitch, and
/// falls back to Flutter's [Switch] on unsupported platforms.
class CNSwitch extends StatefulWidget {
  /// Creates a Cupertino-native switch.
  const CNSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.controller,
    this.height = 44.0,
    this.color,
    this.autoHideOnModal = true,
    this.semanticLabel,
  });

  /// Whether the switch is on.
  final bool value;

  /// Whether the control is interactive.
  final bool enabled;

  /// Callback invoked when the user toggles the value.
  final ValueChanged<bool> onChanged;

  /// Optional controller to imperatively control the native view.
  final CNSwitchController? controller;

  /// Visual height of the embedded platform view.
  final double height;

  /// Optional tint color to apply to the switch.
  final Color? color;

  /// When true (default), destroys the native switch's PlatformView while a
  /// modal sheet is presented above this widget's host route. Prevents the
  /// iOS hybrid-composition z-order bleed (Issue #53) where the host-page
  /// PlatformView's pixels leak through a sheet that also contains a
  /// PlatformView (CN-widget). Requires `CNTabBarRouteObserver()` to be
  /// registered in the app's `navigatorObservers`. No effect on non-iOS or
  /// iOS < 26 (Flutter fallback path).
  final bool autoHideOnModal;

  /// Accessibility label for the switch. On the native path it is forwarded
  /// to the platform view (surfaced as the UISwitch/NSSwitch VoiceOver
  /// label via the visually-hidden Toggle title); on Flutter fallback paths
  /// it wraps the switch in a [Semantics] node. Without it, iOS exposes the
  /// native switch as an **unlabeled** AX element.
  final String? semanticLabel;

  @override
  State<CNSwitch> createState() => _CNSwitchState();
}

class _CNSwitchState extends State<CNSwitch> with ModalHideMixin<CNSwitch> {
  @override
  bool get autoHideOnModal => widget.autoHideOnModal;

  @override
  MethodChannel? get platformViewChannel => _channel;

  MethodChannel? _channel;

  bool? _lastValue;
  bool? _lastEnabled;
  bool? _lastIsDark;
  int? _lastTint;
  String? _lastSemanticLabel;
  bool get _isDark => ThemeHelper.isDark(context);

  CNSwitchController? _internalController;

  CNSwitchController get _controller =>
      widget.controller ?? (_internalController ??= CNSwitchController());

  Color? get _effectiveColor =>
      widget.color ?? ThemeHelper.getPrimaryColor(context);

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    _controller._detach();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant CNSwitch oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncPropsToNativeIfNeeded();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncBrightnessIfNeeded();
  }

  @override
  Widget build(BuildContext context) {
    // Check if we should use native platform view
    final isIOSOrMacOS =
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
    final shouldUseNative =
        isIOSOrMacOS && PlatformVersion.shouldUseNativeGlass;

    // Fallback to Flutter widgets for non-iOS/macOS or iOS/macOS < 26
    if (!shouldUseNative) {
      // For non-iOS/macOS, use Material Switch
      if (!isIOSOrMacOS) {
        return _withSemantics(
          SizedBox(
            height: widget.height,
            child: Switch(
              value: widget.value,
              onChanged: widget.enabled ? widget.onChanged : null,
            ),
          ),
        );
      }

      // For iOS/macOS < 26, use CupertinoSwitch
      return _withSemantics(
        SizedBox(
          height: widget.height,
          child: CupertinoSwitch(
            value: widget.value,
            onChanged: widget.enabled ? widget.onChanged : null,
            activeTrackColor: _effectiveColor,
          ),
        ),
      );
    }

    const viewType = 'CupertinoNativeSwitch';
    // Platform views expand to the biggest size in unconstrained axes.
    // When placed in a Row, width can be unconstrained which would cause
    // the platform view to try to expand to Infinity. Provide a finite
    // width based on the native switch aspect ratio to avoid layout
    // assertions in such cases.
    double estimatedWidthFor(double height) {
      // Approximate iOS UISwitch size is 51x31pt => ~1.645 aspect ratio.
      const ratio = 51.0 / 31.0;
      return height * ratio;
    }

    final double width = estimatedWidthFor(widget.height);

    // Issue #53 fix: when a modal is presented above our host route, destroy
    // the native UISwitch to remove its PlatformView from the shared iOS
    // PlatformView container. Otherwise hybrid-composition z-order desyncs
    // with the sheet's PlatformView during drag, causing visual bleed.
    final hidden = maybeHiddenPlaceholder(height: widget.height, width: width);
    if (hidden != null) return hidden;

    final creationParams = <String, dynamic>{
      'value': widget.value,
      'enabled': widget.enabled,
      'isDark': _isDark,
      'style': encodeStyle(context, tint: _effectiveColor),
      if (widget.semanticLabel != null)
        'accessibilityLabel': widget.semanticLabel,
    };

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return wrapWithModalInteractionGuard(
        ClipRect(
          child: SizedBox(
            height: widget.height,
            width: width,
            child: UiKitView(
              viewType: viewType,
              creationParamsCodec: const StandardMessageCodec(),
              creationParams: creationParams,
              onPlatformViewCreated: _onPlatformViewCreated,
              gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
                Factory<HorizontalDragGestureRecognizer>(
                  () => HorizontalDragGestureRecognizer(),
                ),
                Factory<TapGestureRecognizer>(() => TapGestureRecognizer()),
              },
            ),
          ),
        ),
      );
    }

    // macOS
    return ClipRect(
      child: SizedBox(
        height: widget.height,
        width: width,
        child: AppKitView(
          viewType: viewType,
          creationParamsCodec: const StandardMessageCodec(),
          creationParams: creationParams,
          onPlatformViewCreated: _onPlatformViewCreated,
          gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
            Factory<HorizontalDragGestureRecognizer>(
              () => HorizontalDragGestureRecognizer(),
            ),
            Factory<TapGestureRecognizer>(() => TapGestureRecognizer()),
          },
        ),
      ),
    );
  }

  /// Wraps Flutter-fallback switches in a labeled [Semantics] node. The
  /// native platform-view path is NOT wrapped — the native AX node carries
  /// the label itself (avoids a duplicated VoiceOver announcement).
  Widget _withSemantics(Widget child) => widget.semanticLabel == null
      ? child
      : Semantics(label: widget.semanticLabel, container: true, child: child);

  void _onPlatformViewCreated(int id) {
    final channel = MethodChannel('CupertinoNativeSwitch_$id');
    _channel = channel;
    _controller._attach(channel);
    channel.setMethodCallHandler(_onMethodCall);
    _cacheCurrentProps();
    _syncBrightnessIfNeeded();
  }

  Future<dynamic> _onMethodCall(MethodCall call) async {
    if (call.method == 'valueChanged') {
      final args = call.arguments as Map?;
      final value = args?['value'] as bool?;
      if (value != null) {
        widget.onChanged(value);
        _lastValue = value;
      }
    }
    return null;
  }

  void _cacheCurrentProps() {
    _lastValue = widget.value;
    _lastEnabled = widget.enabled;
    _lastIsDark = _isDark;
    _lastTint = resolveColorToArgb(_effectiveColor, context);
    _lastSemanticLabel = widget.semanticLabel;
  }

  Future<void> _syncPropsToNativeIfNeeded() async {
    final channel = _channel;
    if (channel == null) return;

    // Resolve theme-dependent values before awaiting.
    final int? tint = resolveColorToArgb(_effectiveColor, context);

    if (_lastEnabled != widget.enabled) {
      await channel.invokeMethod('setEnabled', {'enabled': widget.enabled});
      _lastEnabled = widget.enabled;
    }

    if (_lastValue != widget.value) {
      await channel.invokeMethod('setValue', {
        'value': widget.value,
        'animated': false,
      });
      _lastValue = widget.value;
    }

    // Style updates (e.g., tint color)
    if (_lastTint != tint && tint != null) {
      await channel.invokeMethod('setStyle', {'tint': tint});
      _lastTint = tint;
    }

    if (_lastSemanticLabel != widget.semanticLabel) {
      await channel.invokeMethod('setAccessibilityLabel', {
        'label': widget.semanticLabel,
      });
      _lastSemanticLabel = widget.semanticLabel;
    }
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
    final int? tint = resolveColorToArgb(_effectiveColor, context);

    if (_lastIsDark != isDark) {
      await channel.invokeMethod('setBrightness', {'isDark': isDark});
      _lastIsDark = isDark;
    }

    if (_lastTint != tint && tint != null) {
      await channel.invokeMethod('setStyle', {'tint': tint});
      _lastTint = tint;
    }
  }
}
