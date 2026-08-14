import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

import '../channel/params.dart';
import '../style/button_data.dart';
import '../style/button_style.dart';
import '../style/sf_symbol.dart';
import '../utils/icon_renderer.dart';
import '../utils/modal_hide_mixin.dart';
import '../utils/theme_helper.dart';
import '../utils/cn_trace.dart';
import '../utils/version_detector.dart';
import 'async_resolution_state.dart';
import 'glass_button_group.dart';
import 'icon.dart';

/// Base type for entries in a [CNPopupMenuButton] menu.
abstract class CNPopupMenuEntry {
  /// Const constructor for subclasses.
  const CNPopupMenuEntry();
}

/// A selectable item in a popup menu.
class CNPopupMenuItem extends CNPopupMenuEntry {
  /// Creates a selectable popup menu item.
  const CNPopupMenuItem({
    required this.label,
    this.icon,
    this.customIcon,
    this.imageAsset,
    this.iconColor,
    this.enabled = true,
    this.checked = false,
    this.isDestructive = false,
  });

  /// Display label for the item.
  final String label;

  /// Optional SF Symbol shown before the label.
  /// Priority: [imageAsset] > [customIcon] > [icon]
  final CNSymbol? icon;

  /// Optional custom icon from CupertinoIcons, Icons, or any IconData.
  /// If provided, this takes precedence over [icon] but not [imageAsset].
  final IconData? customIcon;

  /// Optional image asset (SVG, PNG, etc.) shown before the label.
  /// If provided, this takes precedence over [icon] and [customIcon].
  final CNImageAsset? imageAsset;

  /// Optional color for custom icons. This applies a tint color to the custom icon.
  /// For SF Symbols, use the [icon]'s color parameter instead.
  final Color? iconColor;

  /// Whether the item can be selected.
  final bool enabled;

  /// Whether the item shows a checkmark (selected/active state).
  final bool checked;

  /// Marks the item as destructive (e.g. "Delete", "Logout", "Remove").
  ///
  /// On iOS 14+ this applies `UIMenuElement.Attributes.destructive` so the
  /// LABEL renders in the system red destructive color (not just the icon).
  /// On iOS < 26 fallback (CupertinoActionSheet) the entry uses
  /// `isDestructiveAction: true`. On iOS 13 legacy UIAlertController fallback
  /// the action uses `.destructive` style.
  final bool isDestructive;
}

/// A visual divider between popup menu items.
class CNPopupMenuDivider extends CNPopupMenuEntry {
  /// Creates a visual divider between items.
  const CNPopupMenuDivider();
}

// Reusable style enum for buttons across widgets (popup menu, future CNButton, ...)

/// A Cupertino-native popup menu button.
///
/// On iOS/macOS this embeds a native popup button and shows a native menu.
class CNPopupMenuButton extends StatefulWidget {
  /// Creates a text-labeled popup menu button.
  const CNPopupMenuButton({
    super.key,
    required this.buttonLabel,
    required this.items,
    required this.onSelected,
    this.tint,
    this.height = 32.0,
    this.shrinkWrap = false,
    this.buttonStyle = CNButtonStyle.plain,
    this.preserveTopToBottomOrder = false,
    this.autoHideOnModal = false,
    this.preferFlutterTier = false,
  }) : buttonIcon = null,
       buttonCustomIcon = null,
       buttonCustomIconColor = null,
       buttonImageAsset = null,
       width = null,
       round = false;

  /// Creates a round, icon-only popup menu button.
  CNPopupMenuButton.icon({
    super.key,
    this.buttonIcon,
    this.buttonCustomIcon,
    this.buttonCustomIconColor,
    this.buttonImageAsset,
    required this.items,
    required this.onSelected,
    this.tint,
    double size = 44.0, // button diameter (width = height)
    this.buttonStyle = CNButtonStyle.glass,
    this.preserveTopToBottomOrder = false,
    this.autoHideOnModal = false,
    this.preferFlutterTier = false,
  }) : buttonLabel = null,
       round = true,
       width = size,
       height = size,
       shrinkWrap = false,
       super() {
    assert(
      buttonIcon != null ||
          buttonCustomIcon != null ||
          buttonImageAsset != null,
      'At least one of buttonIcon, buttonCustomIcon, or buttonImageAsset must be provided',
    );
  }

  /// Text for the button (null when using [buttonIcon]).
  final String? buttonLabel; // null in icon mode
  /// Icon for the button (non-null in icon mode).
  /// Priority: [buttonImageAsset] > [buttonCustomIcon] > [buttonIcon]
  final CNSymbol? buttonIcon; // non-null in icon mode
  /// Optional custom icon from CupertinoIcons, Icons, or any IconData for the button.
  /// If provided, this takes precedence over [buttonIcon] but not [buttonImageAsset].
  final IconData? buttonCustomIcon;

  /// Optional color for the [buttonCustomIcon].
  ///
  /// When provided, the custom icon is rendered with this color.
  /// Defaults to white when not specified (suitable for glass-style buttons).
  /// Has no effect on [buttonIcon] (SF Symbol) or [buttonImageAsset].
  final Color? buttonCustomIconColor;

  /// Optional image asset (SVG, PNG, etc.) for the button icon.
  /// If provided, this takes precedence over [buttonIcon] and [buttonCustomIcon].
  final CNImageAsset? buttonImageAsset;
  // Fixed size (width = height) when in icon mode.
  /// Fixed width in icon mode; otherwise computed/intrinsic.
  final double? width;

  /// Whether this is the round icon variant.
  final bool round; // internal: text=false, icon=true
  /// Entries that populate the popup menu.
  final List<CNPopupMenuEntry> items;

  /// Called with the selected index when the user makes a selection.
  final ValueChanged<int> onSelected;

  /// Tint color for the control.
  final Color? tint;

  /// Control height; icon mode uses diameter semantics.
  final double height;

  /// If true, sizes the control to its intrinsic width.
  final bool shrinkWrap;

  /// Visual style to apply to the button.
  final CNButtonStyle buttonStyle;

  /// When true, items maintain top-to-bottom order even when menu opens upward.
  ///
  /// By default (false), iOS native behavior keeps the first item closest to
  /// the button. When the menu opens upward, this means item 1 appears at the
  /// bottom. Set to true to always display items 1,2,3,4 from top to bottom.
  final bool preserveTopToBottomOrder;

  /// When true (default), destroys the native popup menu's PlatformView while a
  /// modal sheet is presented above this widget's host route. Fixes the
  /// iOS hybrid-composition z-order bleed (Issue #53) where a host-page
  /// CN-widget's pixels leak through a sheet that also contains a CN-widget.
  /// Requires `CNTabBarRouteObserver()` to be registered in the app's
  /// `navigatorObservers`. No effect on iOS < 26 / non-iOS (Flutter fallback).
  final bool autoHideOnModal;

  /// LOCAL PATCH #6: tier-split demotion (see button.dart PATCH #4).
  /// Forces the Flutter fallback tier even where native glass is available;
  /// hosts set this when the popup menu lives under a Scrollable.
  final bool preferFlutterTier;

  /// Whether this instance is configured as an icon button variant.
  bool get isIconButton =>
      buttonIcon != null ||
      buttonCustomIcon != null ||
      buttonImageAsset != null;

  @override
  State<CNPopupMenuButton> createState() => _CNPopupMenuButtonState();
}

class _CNPopupMenuButtonState extends State<CNPopupMenuButton>
    with
        ModalHideMixin<CNPopupMenuButton>,
        AsyncResolutionState<CNPopupMenuButton, Map<String, dynamic>> {
  @override
  bool get autoHideOnModal => widget.autoHideOnModal;

  @override
  MethodChannel? get platformViewChannel => _channel;

  MethodChannel? _channel;
  bool? _lastIsDark;
  int? _lastTint;
  String? _lastTitle;
  String? _lastIconName;
  double? _lastIconSize;
  int? _lastIconColor;
  double? _intrinsicWidth;
  CNButtonStyle? _lastStyle;
  Offset? _downPosition;
  bool _pressed = false;

  // Issue #29 halo containment: clip native view while enclosing route is
  // animating. Modal-up containment is now handled by ModalHideMixin
  // (maybeHiddenPlaceholder + native setInteractive); the legacy modal trigger
  // was removed to avoid double-firing visual blink.
  Animation<double>? _secondaryRouteAnim;

  bool get _isDark => ThemeHelper.isDark(context);
  Color? get _effectiveTint =>
      widget.tint ?? ThemeHelper.getPrimaryColor(context);

  @override
  void didUpdateWidget(covariant CNPopupMenuButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    syncResolution();
    _syncPropsToNativeIfNeeded();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // First resolution happens here, not in initState: _prepareCreationParams
    // reads inherited widgets (encodeStyle, resolveColorToArgb, _isDark),
    // which initState forbids. syncResolution is keyed, so unrelated
    // dependency changes are no-ops.
    syncResolution();
    _attachSecondaryRouteAnim();
    _syncBrightnessIfNeeded();
  }

  @override
  void dispose() {
    _secondaryRouteAnim?.removeListener(_onSecondaryRouteAnimChanged);
    _secondaryRouteAnim = null;
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  void _attachSecondaryRouteAnim() {
    final route = ModalRoute.of(context);
    final newAnim = route?.secondaryAnimation;
    if (identical(newAnim, _secondaryRouteAnim)) return;
    _secondaryRouteAnim?.removeListener(_onSecondaryRouteAnimChanged);
    _secondaryRouteAnim = newAnim;
    _secondaryRouteAnim?.addListener(_onSecondaryRouteAnimChanged);
    _onSecondaryRouteAnimChanged();
  }

  void _onSecondaryRouteAnimChanged() {
    _pushContainmentIfNeeded();
  }

  void _pushContainmentIfNeeded() {
    final anim = _secondaryRouteAnim;
    final animating =
        anim?.status == AnimationStatus.forward ||
        anim?.status == AnimationStatus.reverse;
    final active = animating;
    final ch = _channel;
    if (ch == null) return;
    ch.invokeMethod('setTransitioning', {'active': active}).catchError((_) {});
  }

  /// Returns a hide-placeholder wrapped in a LayoutBuilder that reproduces
  /// the live build's width formula, or null when the widget should render
  /// normally. Mirrors the width logic in [_buildNativePopupMenu]'s
  /// LayoutBuilder so the slot has identical dimensions whether or not the
  /// native platform view is currently mounted (prevents surrounding text
  /// from creeping into the slot during the hide/show transition).
  Widget? _maybeHiddenWithLiveDimensions() {
    // Probe with widget-level dimensions: if not hidden, return null so the
    // caller proceeds with the normal build.
    final probe = maybeHiddenPlaceholder(
      height: widget.height,
      width: widget.width,
    );
    if (probe == null) return null;
    return LayoutBuilder(
      builder: (context, constraints) {
        final hasBoundedWidth = constraints.hasBoundedWidth;
        final preferIntrinsic = widget.shrinkWrap || !hasBoundedWidth;
        double? width;
        if (widget.isIconButton) {
          // Fixed circle size for icon buttons (matches live build).
          width = widget.width ?? widget.height;
        } else if (preferIntrinsic) {
          // Match the live build's intrinsic-width fallback (80.0).
          width = _intrinsicWidth ?? 80.0;
        } else if (hasBoundedWidth && constraints.maxWidth.isFinite) {
          // Live build passes null width so SizedBox fills the parent's
          // bounded width. Mirror that explicitly so the placeholder reserves
          // the same footprint instead of collapsing to 0.
          width = constraints.maxWidth;
        }
        return maybeHiddenPlaceholder(height: widget.height, width: width) ??
            SizedBox(height: widget.height, width: width);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Check if we should use native platform view
    final isIOSOrMacOS =
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
    // LOCAL PATCH #6: tier-split demotion (see button.dart PATCH #4).
    final shouldUseNative = isIOSOrMacOS &&
        PlatformVersion.shouldUseNativeGlass &&
        !widget.preferFlutterTier;

    // Fallback to Flutter widgets for non-iOS/macOS or iOS/macOS < 26
    if (!shouldUseNative) {
      // For both non-iOS/macOS and iOS/macOS < 26, use CupertinoActionSheet
      return _buildCupertinoFallback(context);
    }

    // iOS 26 menu-chrome reroute: a `showsMenuAsPrimaryAction` UIButton's
    // popup chrome does NOT re-derive its appearance per presentation —
    // measured on device (10-40 clip) it renders with the PREVIOUS
    // presentation's traits: light menus in dark mode, dark menus in light
    // mode, always exactly one presentation behind (FB13391355-class; no
    // public lever reaches the cached presentation). The SwiftUI `Menu`
    // inside CNGlassButtonGroup — the Send split button's construction —
    // resolves `.environment(\.colorScheme)` fresh at every presentation
    // and followed the app theme in both directions in the same clip.
    // Group-compatible glass icon triggers therefore route through a
    // one-button group; feature-rich configurations keep the UIKit path
    // with the documented caveat.
    if (_canUseGlassGroupTrigger) {
      return _buildAsGlassGroup(context);
    }

    // Issue #53 fix: when a modal is presented above our host route, destroy
    // the native popup menu's PlatformView so it's removed from the shared
    // iOS PlatformView container.
    //
    // Compute the placeholder width using the SAME formula the live build
    // uses inside its LayoutBuilder so the surrounding layout does not
    // reflow during hide/show (text creeping into the gap, etc.).
    final hiddenWrapper = _maybeHiddenWithLiveDimensions();
    if (hiddenWrapper != null) return hiddenWrapper;

    // Priority: imageAsset > customIcon > icon

    // Resolution is hoisted into the State (see AsyncResolutionState), so
    // build() is synchronous. This collapses what used to be a *nested* pair
    // of FutureBuilders — an outer one for `_renderCustomIcons` and an inner
    // one that awaited `_buildNativePopupMenu` (which itself awaited
    // `resolveIconSource` for the button asset and every menu asset). Both
    // layers restarted on every parent rebuild. Same shape tab_bar.dart
    // already adopted: all async work in one prepare step, build() sync.
    final creationParams = resolvedValue;
    if (creationParams == null) {
      // Genuine first load only: resolvedValue is never cleared once a
      // resolution has landed, so a re-resolve keeps the last-good menu on
      // screen instead of flashing this placeholder.
      return SizedBox(height: widget.height, width: widget.width);
    }
    return _buildNativePopupMenu(context, creationParams);
  }

  /// Whether any icon on the button or in the menu needs rasterizing or asset
  /// resolution. When false, [_prepareCreationParams] skips
  /// [_renderCustomIcons] entirely — matching the pre-refactor branch that
  /// only mounted the icon-rendering FutureBuilder in that case.
  bool get _hasIconsNeedingRender =>
      widget.buttonCustomIcon != null ||
      widget.buttonImageAsset != null ||
      widget.items.any(
        (e) =>
            e is CNPopupMenuItem &&
            (e.customIcon != null || e.imageAsset != null),
      );

  /// Digest of everything that affects **platform view creation**.
  ///
  /// Reproduced verbatim from the pre-refactor `viewKey`, deliberately: this
  /// controls when the native view is destroyed and re-created, and widening
  /// it (e.g. adding `checked`) would re-create the view on a checkmark
  /// toggle that `setItems` already pushes live — trading this fix for a new
  /// flicker.
  String get _viewKeyString {
    final buttonIconKey =
        '${widget.buttonLabel}_${widget.buttonIcon?.name}_${widget.buttonImageAsset?.assetPath}_${widget.buttonImageAsset?.imageData?.length ?? 0}_${widget.buttonCustomIcon?.hashCode ?? 0}';
    final itemsKey = widget.items
        .map((e) {
          if (e is CNPopupMenuItem) {
            return '${e.label}_${e.icon?.name}_${e.imageAsset?.assetPath}_${e.imageAsset?.imageData?.length ?? 0}_${e.customIcon?.hashCode ?? 0}';
          }
          return 'divider';
        })
        .join('|');
    return 'popupMenu_'
        '$buttonIconKey|'
        '$itemsKey|'
        '${widget.buttonStyle.name}_'
        '${widget.height}_'
        '${widget.width}_'
        '${widget.tint?.toARGB32()}_'
        '${widget.buttonCustomIconColor?.toARGB32()}_'
        '$_isDark';
  }

  /// Value-equal digest of every input [_prepareCreationParams] reads.
  ///
  /// Superset of [_viewKeyString] and of the old outer icon-FutureBuilder key
  /// (which additionally tracked `iconColor`), plus the per-item flags that
  /// feed the params arrays. Broader than the view key on purpose: a change
  /// here re-resolves the params without necessarily re-creating the view.
  @override
  Object? resolutionKey() {
    final itemFlags = widget.items
        .map(
          (e) => e is CNPopupMenuItem
              ? '${e.iconColor?.toARGB32() ?? 0}_${e.enabled}_${e.checked}'
                    '_${e.isDestructive}'
              : 'divider',
        )
        .join('|');
    return '$_viewKeyString||$itemFlags';
  }

  @override
  Future<Map<String, dynamic>?> resolveValue() => _prepareCreationParams();

  Future<Map<String, dynamic>> _renderCustomIcons(BuildContext context) async {
    Uint8List? buttonIconBytes;
    final menuIconBytes = <Uint8List?>[];

    // Handle button icon - imageAsset takes precedence over customIcon
    if (widget.buttonImageAsset != null) {
      // ImageAsset doesn't need async rendering, it's already data
      buttonIconBytes = null; // Will be handled in _buildNativePopupMenu
    } else if (widget.buttonCustomIcon != null) {
      // Divergence (Stage 2): button custom-icon default color is white
      // (glass-style buttons), vs. CupertinoColors.label for per-item icons
      // below.
      final source = await resolveIconSource(
        customIcon: widget.buttonCustomIcon,
        customIconSize: widget.buttonIcon?.size ?? 20.0,
        customIconColor: widget.buttonCustomIconColor ?? CupertinoColors.white,
      );
      buttonIconBytes = source is IconSourceBytes ? source.bytes : null;
    }

    // Handle menu item icons - imageAsset takes precedence over customIcon
    for (final e in widget.items) {
      if (e is CNPopupMenuDivider) {
        menuIconBytes.add(null);
      } else if (e is CNPopupMenuItem) {
        if (e.imageAsset != null) {
          // ImageAsset doesn't need async rendering, it's already data
          menuIconBytes.add(null); // Will be handled in _buildNativePopupMenu
        } else if (e.customIcon != null) {
          // Divergence (Stage 2): per-item custom-icon default color is
          // CupertinoColors.label, vs. white for the button face above.
          final source = await resolveIconSource(
            customIcon: e.customIcon,
            customIconSize: e.icon?.size ?? 20.0,
            customIconColor: e.iconColor ?? CupertinoColors.label,
          );
          menuIconBytes.add(source is IconSourceBytes ? source.bytes : null);
        } else {
          menuIconBytes.add(null);
        }
      }
    }

    return {'buttonIconBytes': buttonIconBytes, 'menuIconBytes': menuIconBytes};
  }

  /// Prepares every creation param for the native platform view.
  ///
  /// All async work (icon rasterization, asset path + format resolution)
  /// happens here, guarded by the generation token in [AsyncResolutionState].
  /// The result is cached so [build] can construct the platform view
  /// synchronously — this is what stops a parent rebuild from restarting the
  /// whole resolution. Mirrors `_prepareCreationParams` in tab_bar.dart.
  ///
  /// Returns `null` if the State unmounted mid-resolution; the caller keeps
  /// the last-good params in that case.
  Future<Map<String, dynamic>?> _prepareCreationParams() async {
    // Render custom icons first, and only when something actually needs it.
    final customIconData = _hasIconsNeedingRender
        ? await _renderCustomIcons(context)
        : null;
    if (!mounted) return null;

    // Capture all context-derived values before any further async operations
    final capturedIsDark = _isDark;
    final capturedStyle = encodeStyle(context, tint: _effectiveTint);
    final capturedButtonIconColor = resolveColorToArgb(
      widget.buttonImageAsset?.color ??
          widget.buttonCustomIconColor ??
          widget.buttonIcon?.color,
      context,
    );
    final capturedButtonPaletteColors = widget.buttonIcon?.paletteColors
        ?.map((c) => resolveColorToArgb(c, context))
        .toList();
    // Pre-capture menu item colors
    final capturedMenuItemColors = <int?>[];
    final capturedMenuItemIconColors = <int?>[];
    final capturedMenuItemPalettes = <List<int?>?>[];
    for (final item in widget.items) {
      if (item is CNPopupMenuItem) {
        capturedMenuItemIconColors.add(
          resolveColorToArgb(item.iconColor, context),
        );
        capturedMenuItemColors.add(
          resolveColorToArgb(
            item.imageAsset?.color ?? item.icon?.color,
            context,
          ),
        );
        capturedMenuItemPalettes.add(
          item.icon?.paletteColors
              ?.map((c) => resolveColorToArgb(c, context))
              .toList(),
        );
      } else {
        capturedMenuItemIconColors.add(null);
        capturedMenuItemColors.add(null);
        capturedMenuItemPalettes.add(null);
      }
    }

    // Resolve button image asset (path + format) if present.
    // Divergence (Stage 2): the isNotEmpty guard previously here is dropped
    // so this matches the per-item pattern below (unconditional
    // resolveIconSource whenever imageAsset != null) — the asset path
    // resolver falls back to the original (possibly empty) path when no
    // resolution-specific asset is found, so wire values are unchanged.
    IconSourceAsset? resolvedButtonAsset;
    if (widget.buttonImageAsset != null) {
      resolvedButtonAsset =
          await resolveIconSource(
                assetPath: widget.buttonImageAsset!.assetPath,
                assetImageData: widget.buttonImageAsset!.imageData,
                assetFormat: widget.buttonImageAsset!.imageFormat,
              )
              as IconSourceAsset;
    }
    if (!mounted) return null;

    // Resolve menu item image assets (path + format) concurrently
    final resolvedMenuAssets = await Future.wait(
      widget.items.map((e) async {
        if (e is CNPopupMenuItem && e.imageAsset != null) {
          return await resolveIconSource(
                assetPath: e.imageAsset!.assetPath,
                assetImageData: e.imageAsset!.imageData,
                assetFormat: e.imageAsset!.imageFormat,
              )
              as IconSourceAsset;
        }
        return null;
      }),
    );
    if (!mounted) return null;

    final buttonIconBytes = customIconData?['buttonIconBytes'] as Uint8List?;
    final menuIconBytes =
        customIconData?['menuIconBytes'] as List<Uint8List?>? ?? [];

    // Flatten entries into parallel arrays for the platform view.
    final labels = <String>[];
    final symbols = <String>[];
    final customIconBytesArray = <Uint8List?>[];
    final customIconColors = <int?>[];
    final imageAssetPaths = <String>[];
    final imageAssetData = <Uint8List?>[];
    final imageAssetFormats = <String>[];
    final isDivider = <bool>[];
    final enabled = <bool>[];
    final checked = <bool>[];
    final isDestructive = <bool>[];
    final sizes = <double?>[];
    final colors = <int?>[];
    final modes = <String?>[];
    final palettes = <List<int?>?>[];
    final gradients = <bool?>[];

    var menuIconIndex = 0;
    for (var i = 0; i < widget.items.length; i++) {
      final e = widget.items[i];
      if (e is CNPopupMenuDivider) {
        labels.add('');
        symbols.add('');
        customIconBytesArray.add(null);
        customIconColors.add(null);
        imageAssetPaths.add('');
        imageAssetData.add(null);
        imageAssetFormats.add('');
        isDivider.add(true);
        enabled.add(false);
        checked.add(false);
        isDestructive.add(false);
        sizes.add(null);
        colors.add(null);
        modes.add(null);
        palettes.add(null);
        gradients.add(null);
      } else if (e is CNPopupMenuItem) {
        labels.add(e.label);
        symbols.add(e.icon?.name ?? '');
        customIconBytesArray.add(
          menuIconIndex < menuIconBytes.length
              ? menuIconBytes[menuIconIndex]
              : null,
        );
        customIconColors.add(capturedMenuItemIconColors[i]);

        // Handle imageAsset for menu items
        if (e.imageAsset != null) {
          // Use pre-resolved asset source (path + format).
          final resolvedAsset = resolvedMenuAssets[i]!;
          imageAssetPaths.add(resolvedAsset.resolvedPath);
          imageAssetData.add(e.imageAsset!.imageData);
          imageAssetFormats.add(resolvedAsset.format ?? '');
        } else {
          imageAssetPaths.add('');
          imageAssetData.add(null);
          imageAssetFormats.add('');
        }

        isDivider.add(false);
        enabled.add(e.enabled);
        checked.add(e.checked);
        isDestructive.add(e.isDestructive);
        sizes.add(e.imageAsset?.size ?? e.icon?.size);
        colors.add(capturedMenuItemColors[i]);
        modes.add(e.imageAsset?.mode?.name ?? e.icon?.mode?.name);
        palettes.add(capturedMenuItemPalettes[i]);
        gradients.add(e.imageAsset?.gradient ?? e.icon?.gradient);
        menuIconIndex++;
      }
    }

    final creationParams = <String, dynamic>{
      if (widget.buttonLabel != null) 'buttonTitle': widget.buttonLabel,
      'buttonCustomIconBytes': ?buttonIconBytes,
      if (widget.buttonImageAsset != null) ...{
        // Use resolved asset path
        'buttonAssetPath': ?resolvedButtonAsset?.resolvedPath,
        if (widget.buttonImageAsset!.imageData != null)
          'buttonImageData': widget.buttonImageAsset!.imageData,
        // Format resolved by resolveIconSource above (uses resolved path).
        'buttonImageFormat': resolvedButtonAsset?.format,
      },
      if (widget.buttonIcon != null) 'buttonIconName': widget.buttonIcon!.name,
      'buttonIconSize':
          widget.buttonImageAsset?.size ?? widget.buttonIcon?.size ?? 20.0,
      'buttonIconColor': ?capturedButtonIconColor,
      if (widget.isIconButton) 'round': true,
      'buttonStyle': widget.buttonStyle.name,
      'labels': labels,
      'sfSymbols': symbols,
      'customIconBytes': customIconBytesArray,
      'customIconColors': customIconColors,
      'imageAssetPaths': imageAssetPaths,
      'imageAssetData': imageAssetData,
      'imageAssetFormats': imageAssetFormats,
      'isDivider': isDivider,
      'enabled': enabled,
      'checked': checked,
      'isDestructive': isDestructive,
      'sfSymbolSizes': sizes,
      'sfSymbolColors': colors,
      'sfSymbolRenderingModes': modes,
      'sfSymbolPaletteColors': palettes,
      'sfSymbolGradientEnabled': gradients,
      'isDark': capturedIsDark,
      'style': capturedStyle,
      if (widget.buttonIcon?.mode != null)
        'buttonIconRenderingMode': widget.buttonIcon!.mode!.name,
      'buttonIconPaletteColors': ?capturedButtonPaletteColors,
      if (widget.buttonIcon?.gradient != null)
        'buttonIconGradientEnabled': widget.buttonIcon!.gradient,
      'preserveTopToBottomOrder': widget.preserveTopToBottomOrder,
    };

    return creationParams;
  }

  /// Builds the native platform view from already-resolved [creationParams].
  ///
  /// Fully synchronous: everything that needed an `await` was done in
  /// [_prepareCreationParams].
  Widget _buildNativePopupMenu(
    BuildContext context,
    Map<String, dynamic> creationParams,
  ) {
    const viewType = 'CupertinoNativePopupMenuButton';

    // Create a comprehensive key that includes all parameters affecting
    // platform view creation. Unchanged from before the refactor.
    final viewKey = ValueKey(_viewKeyString);

    final platformView = defaultTargetPlatform == TargetPlatform.iOS
        ? UiKitView(
            key: viewKey,
            viewType: viewType,
            creationParams: creationParams,
            creationParamsCodec: const StandardMessageCodec(),
            onPlatformViewCreated: _onCreated,
            gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
              Factory<TapGestureRecognizer>(() => TapGestureRecognizer()),
            },
          )
        : AppKitView(
            key: viewKey,
            viewType: viewType,
            creationParams: creationParams,
            creationParamsCodec: const StandardMessageCodec(),
            onPlatformViewCreated: _onCreated,
            gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
              Factory<TapGestureRecognizer>(() => TapGestureRecognizer()),
            },
          );

    return wrapWithModalInteractionGuard(
      LayoutBuilder(
        builder: (context, constraints) {
          final hasBoundedWidth = constraints.hasBoundedWidth;
          // If shrinkWrap or width is unbounded (e.g. inside a Row), prefer intrinsic width.
          final preferIntrinsic = widget.shrinkWrap || !hasBoundedWidth;
          double? width;
          if (widget.isIconButton) {
            // Fixed circle size for icon buttons
            width = widget.width ?? widget.height;
          } else if (preferIntrinsic) {
            width = _intrinsicWidth ?? 80.0;
          }
          return Listener(
            onPointerDown: (e) {
              _downPosition = e.position;
              _setPressed(true);
            },
            onPointerMove: (e) {
              final start = _downPosition;
              if (start != null && _pressed) {
                final moved = (e.position - start).distance;
                if (moved > kTouchSlop) {
                  _setPressed(false);
                }
              }
            },
            onPointerUp: (_) {
              _setPressed(false);
              _downPosition = null;
            },
            onPointerCancel: (_) {
              _setPressed(false);
              _downPosition = null;
            },
            child: ClipRect(
              child: SizedBox(
                height: widget.height,
                width: width,
                child: platformView,
              ),
            ),
          );
        },
      ),
    );
  }

  void _onCreated(int id) {
    final ch = MethodChannel('CupertinoNativePopupMenuButton_$id');
    _channel = ch;
    ch.setMethodCallHandler(_onMethodCall);
    _lastTint = resolveColorToArgb(_effectiveTint, context);
    _lastIsDark = _isDark;
    _lastTitle = widget.buttonLabel;
    _lastIconName = widget.buttonIcon?.name;
    _lastIconSize = widget.buttonIcon?.size;
    _lastIconColor = resolveColorToArgb(widget.buttonIcon?.color, context);
    _lastStyle = widget.buttonStyle;
    if (!widget.isIconButton) {
      _requestIntrinsicSize();
    }
  }

  Future<dynamic> _onMethodCall(MethodCall call) async {
    if (call.method == 'itemSelected') {
      final args = call.arguments as Map?;
      final idx = (args?['index'] as num?)?.toInt();
      if (idx != null) widget.onSelected(idx);
    }
    return null;
  }

  Future<void> _requestIntrinsicSize() async {
    final ch = _channel;
    if (ch == null) return;
    try {
      final size = await ch.invokeMethod<Map>('getIntrinsicSize');
      final w = (size?['width'] as num?)?.toDouble();
      if (w != null && mounted) {
        setState(() => _intrinsicWidth = w);
      }
    } catch (_) {}
  }

  Future<void> _syncPropsToNativeIfNeeded() async {
    final ch = _channel;
    if (ch == null) return;
    // Prepare popup items upfront to avoid using BuildContext after awaits.
    final updLabels = <String>[];
    final updSymbols = <String>[];
    final updIsDivider = <bool>[];
    final updEnabled = <bool>[];
    final updChecked = <bool>[];
    final updIsDestructive = <bool>[];
    final updSizes = <double?>[];
    final updColors = <int?>[];
    final updModes = <String?>[];
    final updPalettes = <List<int?>?>[];
    final updGradients = <bool?>[];
    final updImageAssetPaths = <String>[];
    final updImageAssetData = <Uint8List?>[];
    for (final e in widget.items) {
      if (e is CNPopupMenuDivider) {
        updLabels.add('');
        updSymbols.add('');
        updIsDivider.add(true);
        updEnabled.add(false);
        updChecked.add(false);
        updIsDestructive.add(false);
        updSizes.add(null);
        updColors.add(null);
        updModes.add(null);
        updPalettes.add(null);
        updGradients.add(null);
        updImageAssetPaths.add('');
        updImageAssetData.add(null);
      } else if (e is CNPopupMenuItem) {
        updLabels.add(e.label);
        updSymbols.add(e.icon?.name ?? '');
        updIsDivider.add(false);
        updEnabled.add(e.enabled);
        updChecked.add(e.checked);
        updIsDestructive.add(e.isDestructive);
        updSizes.add(e.imageAsset?.size ?? e.icon?.size);
        updColors.add(
          resolveColorToArgb(e.imageAsset?.color ?? e.icon?.color, context),
        );
        updModes.add(e.imageAsset?.mode?.name ?? e.icon?.mode?.name);
        updPalettes.add(
          e.icon?.paletteColors
              ?.map((c) => resolveColorToArgb(c, context))
              .toList(),
        );
        updGradients.add(e.imageAsset?.gradient ?? e.icon?.gradient);

        // Handle imageAsset for menu items. Path/data only here — format
        // resolution is deferred below (after all BuildContext-dependent
        // captures) so this loop stays await-free, preserving the
        // "prepare popup items upfront to avoid using BuildContext after
        // awaits" invariant this function was already written around.
        updImageAssetPaths.add(e.imageAsset?.assetPath ?? '');
        updImageAssetData.add(e.imageAsset?.imageData);
      }
    }
    // Capture context-dependent values before any awaits
    final tint = resolveColorToArgb(_effectiveTint, context);
    final preIconName = widget.buttonIcon?.name;
    final preIconSize = widget.buttonIcon?.size;
    final preIconColor = resolveColorToArgb(widget.buttonIcon?.color, context);

    // Divergence (Stage 2): this call path does not resolve the asset for
    // device pixel ratio (pre-existing behavior — the path sent to native
    // here is always the raw, unresolved asset path from the loop above).
    // Only the format is taken from resolveIconSource; the resolved path
    // it also computes is discarded to preserve the raw path.
    final updImageAssetFormats = await Future.wait(
      widget.items.map((e) async {
        if (e is CNPopupMenuItem && e.imageAsset != null) {
          final source =
              await resolveIconSource(
                    assetPath: e.imageAsset!.assetPath,
                    assetImageData: e.imageAsset!.imageData,
                    assetFormat: e.imageAsset!.imageFormat,
                  )
                  as IconSourceAsset;
          return source.format ?? '';
        }
        return '';
      }),
    );
    if (!mounted) return;
    if (_lastTint != tint && tint != null) {
      await ch.invokeMethod('setStyle', {'tint': tint});
      _lastTint = tint;
    }
    if (_lastStyle != widget.buttonStyle) {
      await ch.invokeMethod('setStyle', {
        'buttonStyle': widget.buttonStyle.name,
      });
      _lastStyle = widget.buttonStyle;
    }
    if (_lastTitle != widget.buttonLabel && widget.buttonLabel != null) {
      await ch.invokeMethod('setButtonTitle', {'title': widget.buttonLabel});
      _lastTitle = widget.buttonLabel;
      _requestIntrinsicSize();
    }

    if (widget.isIconButton) {
      final iconName = preIconName;
      final iconSize = preIconSize;
      final iconColor = preIconColor;
      final updates = <String, dynamic>{};

      // Handle button imageAsset (takes precedence over SF Symbol)
      if (widget.buttonImageAsset != null) {
        // Resolve asset path + format based on device pixel ratio
        final source =
            await resolveIconSource(
                  assetPath: widget.buttonImageAsset!.assetPath,
                  assetImageData: widget.buttonImageAsset!.imageData,
                  assetFormat: widget.buttonImageAsset!.imageFormat,
                )
                as IconSourceAsset;
        updates['buttonAssetPath'] = source.resolvedPath;
        updates['buttonImageData'] = widget.buttonImageAsset!.imageData;
        updates['buttonImageFormat'] = source.format;
        updates['buttonIconSize'] = widget.buttonImageAsset!.size;
        if (widget.buttonImageAsset!.color != null) {
          if (mounted) {
            updates['buttonIconColor'] = resolveColorToArgb(
              widget.buttonImageAsset!.color,
              context,
            );
          }
        }
        if (widget.buttonImageAsset!.mode != null) {
          updates['buttonIconRenderingMode'] =
              widget.buttonImageAsset!.mode!.name;
        }
        if (widget.buttonImageAsset!.gradient != null) {
          updates['buttonIconGradientEnabled'] =
              widget.buttonImageAsset!.gradient;
        }
      } else {
        // Fallback to SF Symbol
        if (_lastIconName != iconName && iconName != null) {
          updates['buttonIconName'] = iconName;
          _lastIconName = iconName;
        }
        if (_lastIconSize != iconSize && iconSize != null) {
          updates['buttonIconSize'] = iconSize;
          _lastIconSize = iconSize;
        }
        if (_lastIconColor != iconColor && iconColor != null) {
          updates['buttonIconColor'] = iconColor;
          _lastIconColor = iconColor;
        }
        if (widget.buttonIcon?.mode != null) {
          updates['buttonIconRenderingMode'] = widget.buttonIcon!.mode!.name;
        }
        if (widget.buttonIcon?.paletteColors != null) {
          updates['buttonIconPaletteColors'] = widget.buttonIcon!.paletteColors!
              .map((c) => resolveColorToArgb(c, context))
              .toList();
        }
        if (widget.buttonIcon?.gradient != null) {
          updates['buttonIconGradientEnabled'] = widget.buttonIcon!.gradient;
        }
      }

      if (updates.isNotEmpty) {
        await ch.invokeMethod('setButtonIcon', updates);
      }
    }

    await ch.invokeMethod('setItems', {
      'labels': updLabels,
      'sfSymbols': updSymbols,
      'isDivider': updIsDivider,
      'enabled': updEnabled,
      'checked': updChecked,
      'isDestructive': updIsDestructive,
      'sfSymbolSizes': updSizes,
      'sfSymbolColors': updColors,
      'sfSymbolRenderingModes': updModes,
      'sfSymbolPaletteColors': updPalettes,
      'sfSymbolGradientEnabled': updGradients,
      'imageAssetPaths': updImageAssetPaths,
      'imageAssetData': updImageAssetData,
      'imageAssetFormats': updImageAssetFormats,
    });
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
    final ch = _channel;
    if (ch == null) return;
    // Capture values before awaiting
    final tint = resolveColorToArgb(_effectiveTint, context);
    if (_lastIsDark != isDark) {
      await cnTracedSetBrightness(ch, 'CNPopupMenuButton', isDark);
      _lastIsDark = isDark;
    }
    if (_lastTint != tint && tint != null) {
      await ch.invokeMethod('setStyle', {'tint': tint});
      _lastTint = tint;
    }
  }

  Future<void> _setPressed(bool pressed) async {
    final ch = _channel;
    if (ch == null) return;
    if (_pressed == pressed) return;
    _pressed = pressed;
    try {
      await ch.invokeMethod('setPressed', {'pressed': pressed});
    } catch (_) {}
  }

  /// Whether this configuration can take the [CNGlassButtonGroup] route (see
  /// the reroute in `build`). The group's popup segment is icon-trigger-only
  /// and supports label/SF-Symbol/custom-icon items with a destructive flag —
  /// anything richer keeps the UIKit button.
  bool get _canUseGlassGroupTrigger {
    if (widget.buttonLabel != null) return false; // group popups are icon-only
    // prominentGlass would silently degrade to .regular in the group — keep
    // the real thing on the UIKit path.
    if (widget.buttonStyle != CNButtonStyle.glass) return false;
    if (widget.preserveTopToBottomOrder) return false; // UIKit-only ordering
    if (widget.buttonCustomIconColor != null) {
      return false; // the group has no custom trigger-icon tint
    }
    for (final e in widget.items) {
      if (e is! CNPopupMenuItem) return false; // dividers
      if (!e.enabled || e.checked) return false; // no per-item state in group
      // Per-item tint/asset icons and colored symbols have no group mapping.
      if (e.iconColor != null || e.imageAsset != null) return false;
      if (e.icon?.color != null) return false;
    }
    return true;
  }

  /// The glass icon trigger as a one-button [CNGlassButtonGroup] — the same
  /// SwiftUI `Menu` construction as the Send split button's chevron half,
  /// whose popup chrome follows the in-app theme on every presentation.
  Widget _buildAsGlassGroup(BuildContext context) {
    // .icon sets width = height = size; the group sizes by icon + padding
    // with a minHeight, so the padding is what makes the capsule a circle.
    final diameter = widget.height;
    final iconSize = widget.buttonIcon?.size ?? 20.0;
    final pad = diameter > iconSize ? (diameter - iconSize) / 2 : 0.0;
    // The group's slot math is `count * 44 + 6` wide — pin the diameter so
    // a 56pt FAB isn't compressed by the default 44pt estimate.
    return SizedBox(
      width: diameter,
      height: diameter,
      child: CNGlassButtonGroup(
        buttons: [
          CNButtonData.popup(
            icon: widget.buttonIcon,
            customIcon: widget.buttonCustomIcon,
            imageAsset: widget.buttonImageAsset,
            popupItems: [
              for (final e in widget.items.cast<CNPopupMenuItem>())
                CNButtonDataPopupItem(
                  label: e.label,
                  // Name-only mapping: per-item symbol size/color are not
                  // expressible in the group (guarded above).
                  sfSymbol: e.icon?.name,
                  customIcon: e.icon == null ? e.customIcon : null,
                  isDestructive: e.isDestructive,
                ),
            ],
            onMenuSelected: widget.onSelected,
            tint: widget.tint,
            config: CNButtonDataConfig(
              style: CNButtonStyle.glass,
              minHeight: diameter,
              padding: EdgeInsets.all(pad),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCupertinoFallback(BuildContext context) {
    // For iOS/macOS < 26 and non-iOS/macOS, use CupertinoActionSheet
    return SizedBox(
      height: widget.height,
      width: widget.isIconButton && widget.round
          ? (widget.width ?? widget.height)
          : null,
      child: CupertinoButton(
        padding: widget.isIconButton
            ? const EdgeInsets.all(4)
            : const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        onPressed: () async {
          final selected = await showCupertinoModalPopup<int>(
            context: context,
            builder: (ctx) {
              return CupertinoActionSheet(
                title: widget.buttonLabel != null
                    ? Text(widget.buttonLabel!)
                    : null,
                actions: [
                  for (var i = 0; i < widget.items.length; i++)
                    if (widget.items[i] is CNPopupMenuItem)
                      CupertinoActionSheetAction(
                        onPressed: () => Navigator.of(ctx).pop(i),
                        isDestructiveAction:
                            (widget.items[i] as CNPopupMenuItem).isDestructive,
                        child: Text((widget.items[i] as CNPopupMenuItem).label),
                      )
                    else
                      const SizedBox(height: 8),
                ],
                cancelButton: CupertinoActionSheetAction(
                  onPressed: () => Navigator.of(ctx).pop(),
                  isDefaultAction: true,
                  child: const Text('Cancel'),
                ),
              );
            },
          );
          if (selected != null) widget.onSelected(selected);
        },
        child: widget.isIconButton
            ? (widget.buttonIcon != null
                  ? CNIcon(
                      symbol: widget.buttonIcon,
                      size: widget.buttonIcon!.size,
                      color: widget.buttonIcon!.color,
                    )
                  : const SizedBox.shrink())
            : Text(widget.buttonLabel ?? ''),
      ),
    );
  }
}
