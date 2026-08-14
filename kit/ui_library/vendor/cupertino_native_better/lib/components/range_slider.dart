import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import '../channel/params.dart';
import '../utils/theme_helper.dart';
import '../utils/modal_hide_mixin.dart';

/// Controller for a [CNRangeSlider], allowing imperative changes to the native
/// range view (programmatic [setValues], [setRange], [setEnabled]).
class CNRangeSliderController {
  MethodChannel? _channel;

  void _attach(MethodChannel channel) => _channel = channel;
  void _detach() => _channel = null;

  /// Sets both thumbs. [RangeValues.start] is the low thumb, [.end] the high
  /// thumb. When [animated] is true, animates to the new values.
  Future<void> setValues(RangeValues values, {bool animated = false}) async {
    final channel = _channel;
    if (channel == null) return;
    await channel.invokeMethod('setValues', {
      'lowValue': values.start,
      'highValue': values.end,
      'animated': animated,
    });
  }

  /// Sets the valid [min] / [max] of the range.
  Future<void> setRange({required double min, required double max}) async {
    final channel = _channel;
    if (channel == null) return;
    await channel.invokeMethod('setRange', {'min': min, 'max': max});
  }

  /// Enables or disables user interaction on both thumbs.
  Future<void> setEnabled(bool enabled) async {
    final channel = _channel;
    if (channel == null) return;
    await channel.invokeMethod('setEnabled', {'enabled': enabled});
  }
}

/// A native two-thumb range slider.
///
/// On iOS this embeds a single platform view containing **two real `UISlider`
/// thumbs** over a natively-drawn combined track. Because the thumbs are
/// genuine `UISlider` controls — the native container routes each touch to the
/// nearer thumb — iOS 26 auto-applies Liquid Glass and fires it on press,
/// identical to a standalone [CNSlider]. UIKit has no two-thumb slider, so this
/// is the only way to get *native* glass on a range control. Other platforms
/// fall back to a Material [RangeSlider].
///
/// The public surface mirrors [CNSlider]: [values], [onChanged] (required
/// non-null), [min], [max], [enabled], tint colors, and an optional
/// [controller]. Pass `enabled: false` (or a host no-op) to disable.
class CNRangeSlider extends StatefulWidget {
  /// Creates a native range slider.
  const CNRangeSlider({
    super.key,
    required this.values,
    required this.onChanged,
    this.min = 0.0,
    this.max = 1.0,
    this.enabled = true,
    this.controller,
    this.height = 44.0,
    this.color,
    this.thumbColor,
    this.trackColor,
    this.trackBackgroundColor,
    this.autoHideOnModal = true,
    this.preferFlutterTier = false,
  });

  /// Current selection. [RangeValues.start] is the low thumb, [.end] the high.
  final RangeValues values;

  /// Callback when the selection changes due to user interaction.
  final ValueChanged<RangeValues> onChanged;

  /// Minimum value (inclusive). Defaults to 0.0.
  final double min;

  /// Maximum value (inclusive). Defaults to 1.0.
  final double max;

  /// Whether the control is interactive.
  final bool enabled;

  /// Optional controller to imperatively interact with the native view.
  final CNRangeSliderController? controller;

  /// Visual height of the embedded platform view.
  final double height;

  /// General accent/tint color (fallback for the active track).
  final Color? color;

  /// Explicit thumb color; if null, the native default.
  final Color? thumbColor;

  /// Explicit active (low→high) track color.
  final Color? trackColor;

  /// Explicit inactive track color.
  final Color? trackBackgroundColor;

  /// When true (default), destroys the native view's PlatformView while a modal
  /// sheet is presented above this widget's host route (Issue #53 z-order bleed).
  final bool autoHideOnModal;

  /// LOCAL PATCH #6: tier-split demotion (see button.dart PATCH #4).
  /// Forces the Flutter fallback tier even where native glass is available;
  /// hosts set this when the range slider lives under a Scrollable.
  final bool preferFlutterTier;

  @override
  State<CNRangeSlider> createState() => _CNRangeSliderState();
}

class _CNRangeSliderState extends State<CNRangeSlider>
    with ModalHideMixin<CNRangeSlider> {
  @override
  bool get autoHideOnModal => widget.autoHideOnModal;

  @override
  MethodChannel? get platformViewChannel => _channel;

  MethodChannel? _channel;
  CNRangeSliderController? _internalController;
  CNRangeSliderController get _controller =>
      widget.controller ?? (_internalController ??= CNRangeSliderController());

  double? _lastLow, _lastHigh, _lastMin, _lastMax;
  bool? _lastEnabled, _lastIsDark;
  int? _lastThumbTint, _lastTrackTint, _lastTrackBgTint;

  bool get _isDark => ThemeHelper.isDark(context);
  Color? get _effectiveTrackTint =>
      widget.trackColor ?? widget.color ?? ThemeHelper.getPrimaryColor(context);
  Color? get _effectiveThumbTint => widget.thumbColor;
  Color? get _effectiveTrackBgTint => widget.trackBackgroundColor;

  @override
  Widget build(BuildContext context) {
    const viewType = 'CupertinoNativeRangeSlider';

    final hidden =
        maybeHiddenPlaceholder(height: widget.height, width: double.infinity);
    if (hidden != null) return hidden;

    final creationParams = <String, dynamic>{
      'min': widget.min,
      'max': widget.max,
      'lowValue': widget.values.start,
      'highValue': widget.values.end,
      'enabled': widget.enabled,
      'isDark': _isDark,
      'style': encodeStyle(
        context,
        trackTint: _effectiveTrackTint,
        thumbTint: _effectiveThumbTint,
        trackBackgroundTint: _effectiveTrackBgTint,
      ),
    };

    // LOCAL PATCH #6: tier-split demotion (see button.dart PATCH #4).
    if (defaultTargetPlatform == TargetPlatform.iOS &&
        !widget.preferFlutterTier) {
      return wrapWithModalInteractionGuard(
        ClipRect(
          child: SizedBox(
            height: widget.height,
            width: double.infinity,
            child: UiKitView(
              viewType: viewType,
              creationParamsCodec: const StandardMessageCodec(),
              creationParams: creationParams,
              onPlatformViewCreated: _onPlatformViewCreated,
              // Forward horizontal drags and taps to the native view so the
              // UISlider thumbs receive the press (→ Liquid Glass) and it works
              // inside Flutter scroll views.
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

    // Non-iOS (incl. macOS): no native range view is provided → Material fallback.
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: RangeSlider(
        values: widget.values,
        min: widget.min,
        max: widget.max,
        onChanged: widget.enabled ? widget.onChanged : null,
      ),
    );
  }

  void _onPlatformViewCreated(int id) {
    final channel = MethodChannel('CupertinoNativeRangeSlider_$id');
    _channel = channel;
    _controller._attach(channel);
    channel.setMethodCallHandler(_onMethodCall);
    _cacheCurrentProps();
    _syncBrightnessIfNeeded();
  }

  Future<dynamic> _onMethodCall(MethodCall call) async {
    if (call.method == 'valuesChanged') {
      final args = call.arguments as Map?;
      final lo = (args?['lowValue'] as num?)?.toDouble();
      final hi = (args?['highValue'] as num?)?.toDouble();
      if (lo != null && hi != null) {
        final v = RangeValues(lo, hi);
        widget.onChanged(v);
        _lastLow = lo;
        _lastHigh = hi;
      }
    }
    return null;
  }

  void _cacheCurrentProps() {
    _lastLow = widget.values.start;
    _lastHigh = widget.values.end;
    _lastMin = widget.min;
    _lastMax = widget.max;
    _lastEnabled = widget.enabled;
    _lastIsDark = _isDark;
    _lastThumbTint = resolveColorToArgb(_effectiveThumbTint, context);
    _lastTrackTint = resolveColorToArgb(_effectiveTrackTint, context);
    _lastTrackBgTint = resolveColorToArgb(_effectiveTrackBgTint, context);
  }

  Future<void> _syncPropsToNativeIfNeeded() async {
    final channel = _channel;
    if (channel == null) return;
    final int? thumb = resolveColorToArgb(_effectiveThumbTint, context);
    final int? track = resolveColorToArgb(_effectiveTrackTint, context);
    final int? trackBg = resolveColorToArgb(_effectiveTrackBgTint, context);

    if (_lastMin != widget.min || _lastMax != widget.max) {
      await channel.invokeMethod('setRange', {'min': widget.min, 'max': widget.max});
      _lastMin = widget.min;
      _lastMax = widget.max;
    }
    if (_lastEnabled != widget.enabled) {
      await channel.invokeMethod('setEnabled', {'enabled': widget.enabled});
      _lastEnabled = widget.enabled;
    }
    final lo = widget.values.start.clamp(widget.min, widget.max).toDouble();
    final hi = widget.values.end.clamp(widget.min, widget.max).toDouble();
    if (_lastLow != lo || _lastHigh != hi) {
      await channel.invokeMethod('setValues', {'lowValue': lo, 'highValue': hi});
      _lastLow = lo;
      _lastHigh = hi;
    }
    final styleUpdate = <String, dynamic>{};
    if (_lastThumbTint != thumb && thumb != null) {
      styleUpdate['thumbTint'] = thumb;
      _lastThumbTint = thumb;
    }
    if (_lastTrackTint != track && track != null) {
      styleUpdate['trackTint'] = track;
      _lastTrackTint = track;
    }
    if (_lastTrackBgTint != trackBg && trackBg != null) {
      styleUpdate['trackBackgroundTint'] = trackBg;
      _lastTrackBgTint = trackBg;
    }
    if (styleUpdate.isNotEmpty) {
      await channel.invokeMethod('setStyle', styleUpdate);
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
    if (_lastIsDark != isDark) {
      await channel.invokeMethod('setBrightness', {'isDark': isDark});
      _lastIsDark = isDark;
    }
  }

  @override
  void didUpdateWidget(covariant CNRangeSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncPropsToNativeIfNeeded();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncBrightnessIfNeeded();
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    _controller._detach();
    super.dispose();
  }
}
