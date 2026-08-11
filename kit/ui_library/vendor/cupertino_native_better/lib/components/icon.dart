import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../channel/params.dart';
import '../style/sf_symbol.dart';
import '../utils/icon_renderer.dart';
import '../utils/theme_helper.dart';
import '../utils/platform_view_guard.dart';
import 'async_resolution_state.dart';

/// A platform-rendered SF Symbol icon, custom image asset, or IconData.
///
/// Renders an `SFSymbol` on iOS/macOS using native APIs for best fidelity,
/// displays a custom image asset, or renders IconData.
class CNIcon extends StatefulWidget {
  /// Creates a platform-rendered SF Symbol icon.
  const CNIcon({
    super.key,
    this.symbol,
    this.imageAsset,
    this.customIcon,
    this.size,
    this.color,
    this.mode,
    this.gradient,
    this.height,
  }) : assert(
         symbol != null || imageAsset != null || customIcon != null,
         'At least one of symbol, imageAsset, or customIcon must be provided',
       );

  /// The SF Symbol to render.
  /// Priority: [imageAsset] > [customIcon] > [symbol]
  final CNSymbol? symbol;

  /// Custom image asset (SVG, PNG, etc.) to render.
  /// If provided, this takes precedence over [symbol] and [customIcon].
  final CNImageAsset? imageAsset;

  /// Optional custom icon from CupertinoIcons, Icons, or any IconData.
  /// If provided, this takes precedence over [symbol] but not [imageAsset].
  final IconData? customIcon;

  /// Overrides the symbol's size.
  final double? size;

  /// Overrides the symbol's color for monochrome/hierarchical modes.
  final Color? color;

  /// Overrides the rendering mode.
  final CNSymbolRenderingMode? mode;

  /// Whether to enable the system gradient when available.
  final bool? gradient;

  /// Optional fixed height; defaults to the icon's size.
  final double? height;

  @override
  State<CNIcon> createState() => _CNIconState();
}

class _CNIconState extends State<CNIcon>
    with AsyncResolutionState<CNIcon, IconSource> {
  MethodChannel? _channel;
  bool? _lastIsDark;
  String? _lastName;
  double? _lastSize;
  int? _lastColor;
  String? _lastMode;
  bool? _lastGradient;

  bool get _isDark => ThemeHelper.isDark(context);

  @override
  void initState() {
    super.initState();
    if (!PlatformViewGuard.isReady) {
      PlatformViewGuard.ensureScheduled();
      PlatformViewGuard.readyNotifier.addListener(_onPlatformViewGuardReady);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // First resolution happens here, not in initState: resolveValue may read
    // inherited widgets, which initState forbids. syncResolution is keyed, so
    // unrelated dependency changes are no-ops.
    syncResolution();
    _syncBrightnessIfNeeded();
  }

  @override
  void didUpdateWidget(covariant CNIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    syncResolution();
    _syncPropsToNativeIfNeeded();
  }

  /// Rasterization size for the [CNIcon.customIcon] branch.
  ///
  /// Divergence (Stage 2): sources from `widget.symbol?.size` (not
  /// `widget.imageAsset?.size`) — mirrors the placeholder divergence in
  /// [build].
  double get _customIconSize => widget.size ?? widget.symbol?.size ?? 24.0;

  @override
  Object? resolutionKey() {
    // Priority: imageAsset > customIcon > symbol. The symbol branch needs no
    // async resolution at all, hence the null.
    if (widget.imageAsset != null) {
      final asset = widget.imageAsset!;
      return ('asset', asset.assetPath, asset.imageData, asset.imageFormat);
    }
    if (widget.customIcon != null) {
      return ('custom', widget.customIcon, _customIconSize);
    }
    return null;
  }

  @override
  Future<IconSource?> resolveValue() {
    if (widget.imageAsset != null) {
      return resolveIconSource(
        assetPath: widget.imageAsset!.assetPath,
        assetImageData: widget.imageAsset!.imageData,
        assetFormat: widget.imageAsset!.imageFormat,
      );
    }
    return resolveIconSource(
      customIcon: widget.customIcon,
      customIconSize: _customIconSize,
    );
  }

  @override
  void dispose() {
    PlatformViewGuard.readyNotifier.removeListener(_onPlatformViewGuardReady);
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  void _onPlatformViewGuardReady() {
    if (!mounted) return;
    PlatformViewGuard.readyNotifier.removeListener(_onPlatformViewGuardReady);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // LOCAL PATCH #4: widget SELECTION gates on defaultTargetPlatform (which
    // honors debugDefaultTargetPlatformOverride, so tests and previews get a
    // deterministic tier) plus the package's own flutter-test probe — never
    // dart:io Platform. Under `flutter test` on a macOS host,
    // PlatformVersion.supportsSFSymbols (Platform.isIOS || Platform.isMacOS)
    // evaluates TRUE because dart:io reflects the test HOST, so CNIcon built
    // an AppKitView and crashed with MissingPluginException. Real-device
    // selection is unchanged: defaultTargetPlatform is iOS/macOS exactly
    // where dart:io reported iOS/macOS. Revert when upstreamed.
    final shouldUseNative =
        !kIsWeb &&
        !PlatformViewGuard.isTestEnvironment &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS);

    if (!shouldUseNative) {
      return _buildFlutterIcon(context);
    }

    if (!PlatformViewGuard.isReady) {
      PlatformViewGuard.ensureScheduled();
      return _buildFlutterIcon(context);
    }

    // Priority: imageAsset > customIcon > symbol

    // Handle image asset (highest priority)
    if (widget.imageAsset != null) {
      // Resolution is hoisted into the State (see AsyncResolutionState), so
      // build() is synchronous and a parent rebuild no longer restarts it.
      // The type test doubles as a branch check: after a switch from the
      // customIcon branch the cached value is still IconSourceBytes until the
      // new resolution lands.
      final resolved = resolvedValue;
      if (resolved is! IconSourceAsset) {
        // Divergence (Stage 2): asset branch placeholder sizes off
        // widget.imageAsset?.size, not widget.symbol?.size.
        final defaultSize = widget.size ?? (widget.imageAsset?.size ?? 24.0);
        return SizedBox(
          width: defaultSize,
          height: widget.height ?? defaultSize,
        );
      }
      // Create a new CNImageAsset with the resolved path/format.
      final resolvedImageAsset = CNImageAsset(
        resolved.resolvedPath,
        size: widget.imageAsset!.size,
        color: widget.imageAsset!.color,
        imageFormat: resolved.format,
        imageData: widget.imageAsset!.imageData,
        mode: widget.imageAsset!.mode,
        gradient: widget.imageAsset!.gradient,
      );
      return _buildNativeIcon(context, imageAsset: resolvedImageAsset);
    }

    // Handle custom icon (medium priority)
    if (widget.customIcon != null) {
      final iconSize = _customIconSize;
      final resolved = resolvedValue;
      if (resolved is! IconSourceBytes) {
        // Divergence (Stage 2): customIcon branch placeholder sizes off
        // widget.symbol?.size, not widget.imageAsset?.size.
        return SizedBox(width: iconSize, height: widget.height ?? iconSize);
      }
      return _buildNativeIcon(context, customIconBytes: resolved.bytes);
    }

    // Handle SF Symbol (lowest priority)
    return _buildNativeIcon(context, customIconBytes: null);
  }

  Widget _buildNativeIcon(
    BuildContext context, {
    Uint8List? customIconBytes,
    CNImageAsset? imageAsset,
  }) {
    const viewType = 'CupertinoNativeIcon';

    // Determine which source to use and build parameters accordingly
    String name = '';
    Uint8List? imageData;
    String? imageFormat;
    String? assetPath;
    double size = 24.0;
    Color? color;
    CNSymbolRenderingMode? mode;
    bool? gradient;
    List<Color>? paletteColors;

    if (imageAsset != null) {
      // Image asset takes precedence. imageFormat was already resolved (and
      // format-detected, if needed) by resolveIconSource at the call site.
      assetPath = imageAsset.assetPath;
      imageData = imageAsset.imageData;
      imageFormat = imageAsset.imageFormat;
      size = widget.size ?? imageAsset.size;
      color = widget.color ?? imageAsset.color;
      mode = widget.mode ?? imageAsset.mode;
      gradient = widget.gradient ?? imageAsset.gradient;
    } else if (customIconBytes != null) {
      // Custom icon bytes
      imageData = customIconBytes;
      imageFormat = 'png'; // IconData is rendered as PNG
      size = widget.size ?? widget.symbol?.size ?? 24.0;
      color = widget.color ?? widget.symbol?.color;
      mode = widget.mode ?? widget.symbol?.mode;
      gradient = widget.gradient ?? widget.symbol?.gradient;
      paletteColors = widget.symbol?.paletteColors;
    } else if (widget.symbol != null) {
      // SF Symbol
      name = widget.symbol!.name;
      size = widget.size ?? widget.symbol!.size;
      color = widget.color ?? widget.symbol!.color;
      mode = widget.mode ?? widget.symbol!.mode;
      gradient = widget.gradient ?? widget.symbol!.gradient;
      paletteColors = widget.symbol!.paletteColors;
    }

    final creationParams = <String, dynamic>{
      'name': name,
      'assetPath': ?assetPath,
      'imageData': ?imageData,
      'imageFormat': ?imageFormat,
      'isDark': _isDark,
      'style': <String, dynamic>{
        'iconSize': size,
        if (color != null) 'iconColor': resolveColorToArgb(color, context),
        if (mode != null) 'iconRenderingMode': mode.name,
        if (gradient != null) 'iconGradientEnabled': gradient == true,
        if (paletteColors != null)
          'iconPaletteColors': paletteColors
              .map((c) => resolveColorToArgb(c, context))
              .toList(),
      },
    };

    final platformView = defaultTargetPlatform == TargetPlatform.iOS
        ? UiKitView(
            viewType: viewType,
            creationParamsCodec: const StandardMessageCodec(),
            creationParams: creationParams,
            onPlatformViewCreated: _onPlatformViewCreated,
          )
        : AppKitView(
            viewType: viewType,
            creationParamsCodec: const StandardMessageCodec(),
            creationParams: creationParams,
            onPlatformViewCreated: _onPlatformViewCreated,
          );

    // Ensure the platform view always has finite constraints
    final fallbackSize =
        widget.size ?? (imageAsset?.size ?? widget.symbol?.size ?? 24.0);
    final h = widget.height ?? fallbackSize;
    final w = fallbackSize;
    return ClipRect(
      child: SizedBox(width: w, height: h, child: platformView),
    );
  }

  void _onPlatformViewCreated(int id) {
    _channel = MethodChannel('CupertinoNativeIcon_$id')
      ..setMethodCallHandler(_onMethodCall);
    _cacheCurrentProps();
    _syncBrightnessIfNeeded();
    // No intrinsic measurement needed.
  }

  Future<dynamic> _onMethodCall(MethodCall call) async {
    return null;
  }

  void _cacheCurrentProps() {
    _lastIsDark = _isDark;

    // Determine current source and cache accordingly
    if (widget.imageAsset != null) {
      _lastName = widget.imageAsset!.assetPath;
      _lastSize = widget.size ?? widget.imageAsset!.size;
      _lastColor = resolveColorToArgb(
        widget.color ?? widget.imageAsset!.color,
        context,
      );
      _lastMode = (widget.mode ?? widget.imageAsset!.mode)?.name;
      _lastGradient = widget.gradient ?? widget.imageAsset!.gradient;
    } else if (widget.symbol != null) {
      _lastName = widget.symbol!.name;
      _lastSize = widget.size ?? widget.symbol!.size;
      _lastColor = resolveColorToArgb(
        widget.color ?? widget.symbol!.color,
        context,
      );
      _lastMode = (widget.mode ?? widget.symbol!.mode)?.name;
      _lastGradient = widget.gradient ?? widget.symbol!.gradient;
    } else {
      // Custom icon case
      _lastName = '';
      _lastSize = widget.size ?? 24.0;
      _lastColor = resolveColorToArgb(widget.color, context);
      _lastMode = widget.mode?.name;
      _lastGradient = widget.gradient;
    }
  }

  Future<void> _syncPropsToNativeIfNeeded() async {
    final channel = _channel;
    if (channel == null) return;

    // Determine current source and resolve values
    String name = '';
    double size = 24.0;
    int? color;
    String? mode;
    bool? gradient;
    // Resolved once below when widget.imageAsset != null; reused for both
    // the setSymbol and setStyle payloads so format is only detected once.
    IconSourceAsset? resolvedAssetSource;

    if (widget.imageAsset != null) {
      // Resolve asset path based on device pixel ratio
      resolvedAssetSource =
          await resolveIconSource(
                assetPath: widget.imageAsset!.assetPath,
                assetImageData: widget.imageAsset!.imageData,
                assetFormat: widget.imageAsset!.imageFormat,
              )
              as IconSourceAsset;
      if (!mounted) return;

      name = resolvedAssetSource.resolvedPath;
      size = widget.size ?? widget.imageAsset!.size;
      color = resolveColorToArgb(
        widget.color ?? widget.imageAsset!.color,
        context,
      );
      mode = (widget.mode ?? widget.imageAsset!.mode)?.name;
      gradient = widget.gradient ?? widget.imageAsset!.gradient;
    } else if (widget.symbol != null) {
      name = widget.symbol!.name;
      size = widget.size ?? widget.symbol!.size;
      color = resolveColorToArgb(widget.color ?? widget.symbol!.color, context);
      mode = (widget.mode ?? widget.symbol!.mode)?.name;
      gradient = widget.gradient ?? widget.symbol!.gradient;
    } else {
      // Custom icon case
      size = widget.size ?? 24.0;
      color = resolveColorToArgb(widget.color, context);
      mode = widget.mode?.name;
      gradient = widget.gradient;
    }

    if (_lastName != name) {
      final symbolArgs = <String, dynamic>{'name': name};

      // Add imageAsset properties if using imageAsset
      if (widget.imageAsset != null) {
        symbolArgs['assetPath'] = widget.imageAsset!.assetPath;
        symbolArgs['imageData'] = widget.imageAsset!.imageData;
        symbolArgs['imageFormat'] = resolvedAssetSource?.format;
      }

      await channel.invokeMethod('setSymbol', symbolArgs);
      _lastName = name;
    }

    // Track if any style properties changed
    bool hasStyleChanges = false;
    final style = <String, dynamic>{};

    if (_lastSize != size) {
      style['iconSize'] = size;
      _lastSize = size;
      hasStyleChanges = true;
    }
    if (_lastColor != color) {
      if (color != null) {
        style['iconColor'] = color;
      }
      _lastColor = color;
      hasStyleChanges = true;
    }
    if (_lastMode != mode) {
      if (mode != null) {
        style['iconRenderingMode'] = mode;
      }
      _lastMode = mode;
      hasStyleChanges = true;
    }
    if (_lastGradient != gradient) {
      if (gradient != null) {
        style['iconGradientEnabled'] = gradient;
      }
      _lastGradient = gradient;
      hasStyleChanges = true;
    }

    // If any style changed, include the icon source to prevent disappearing icons
    if (hasStyleChanges) {
      // Add imageAsset properties if using imageAsset
      if (widget.imageAsset != null) {
        style['assetPath'] = widget.imageAsset!.assetPath;
        style['imageData'] = widget.imageAsset!.imageData;
        style['imageFormat'] = resolvedAssetSource?.format;
      } else if (widget.symbol != null) {
        // Include the symbol name so native side knows what to render
        style['name'] = widget.symbol!.name;
      }
    }

    if (style.isNotEmpty) {
      await channel.invokeMethod('setStyle', style);
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

  Widget _buildFlutterIcon(BuildContext context) {
    // For fallback, use Flutter Icon widget
    Widget? iconWidget;

    if (widget.imageAsset != null) {
      // For image assets in fallback, use a placeholder
      iconWidget = Icon(
        CupertinoIcons.circle_fill,
        size: widget.imageAsset!.size,
        color: widget.imageAsset!.color ?? widget.color,
      );
    } else if (widget.customIcon != null) {
      iconWidget = Icon(
        widget.customIcon,
        size: widget.size ?? widget.symbol?.size ?? 24.0,
        color: widget.color,
      );
    } else if (widget.symbol != null) {
      // For SF Symbols, use a placeholder Cupertino icon
      iconWidget = Icon(
        CupertinoIcons.circle_fill,
        size: widget.size ?? widget.symbol!.size,
        color: widget.color ?? widget.symbol?.color,
      );
    } else {
      // Fallback to a generic icon
      iconWidget = Icon(
        CupertinoIcons.circle_fill,
        size: widget.size ?? 24.0,
        color: widget.color,
      );
    }

    final h = widget.height ?? widget.size ?? 24.0;
    final w = widget.size ?? 24.0;
    return SizedBox(width: w, height: h, child: iconWidget);
  }
}
