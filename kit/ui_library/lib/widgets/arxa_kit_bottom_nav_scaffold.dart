import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'arxa_kit_lazy_indexed_stack.dart';
import 'arxa_kit_native_floating_bar.dart';
import 'arxa_kit_tab_bar.dart';

/// Fully-automated bottom-nav scaffold: owns the active index, lays out the tab
/// views in a lazy [ArxaKitLazyIndexedStack], and mounts the adaptive
/// [ArxaKitNativeTabBar]. Sets `extendBody: true` itself so a native Liquid Glass
/// bar samples the body beneath it — the host supplies only tabs + views.
///
/// ```dart
/// ArxaKitBottomNavScaffold(
///   tabs: const [ArxaKitTab(icon: Icons.home, label: 'Home'), ArxaKitTab(...)],
///   views: [(c) => const HomeView(), (c) => const ShopView()],
/// )
/// ```
/// Fixes FAB placement under `Scaffold(extendBody: true)` (flutter#145680).
///
/// `extendBody` injects the measured bottom-bar height into the body's
/// MediaQuery *padding* (scroll clearance works), but Flutter's
/// `FloatingActionButtonLocation` lifts FABs by *viewPadding*, which
/// extendBody leaves at the raw device inset — so nested Scaffolds park their
/// FABs behind the floating bar. Mirroring the injected padding into
/// viewPadding lifts every descendant FAB clear of the bar
/// (endFloat margin = bar height + 16).
///
/// Wrap the *body* of any `Scaffold(extendBody: true, bottomNavigationBar: …)`
/// that hosts nested Scaffolds with FABs. [ArxaKitBottomNavScaffold] applies it
/// automatically.
class ArxaKitExtendBodyFabLift extends StatelessWidget {
  const ArxaKitExtendBodyFabLift({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final lift = math.max(mq.viewPadding.bottom, mq.padding.bottom);
    return MediaQuery(
      data: mq.copyWith(
        viewPadding: mq.viewPadding.copyWith(bottom: lift),
      ),
      child: child,
    );
  }
}

class ArxaKitBottomNavScaffold extends StatefulWidget {
  const ArxaKitBottomNavScaffold({
    super.key,
    required this.tabs,
    required this.views,
    this.initialIndex = 0,
    this.onTabChanged,
    this.native,
    this.appBar,
    this.floatingActionButton,
    this.bottomEdgeScrim = true,
  }) : assert(
          views.length == tabs.length,
          'views must match tabs (one builder per tab)',
        );

  final List<ArxaKitTab> tabs;
  final List<WidgetBuilder> views;
  final int initialIndex;
  final ValueChanged<int>? onTabChanged;

  /// Forwarded to [ArxaKitNativeTabBar]; null = auto-tier.
  final bool? native;
  final PreferredSizeWidget? appBar;
  final Widget? floatingActionButton;

  /// Bottom-edge dissolve under the bar ([ArxaKitBottomEdgeScrim]) — the
  /// counterpart of the top chrome's status-bar scrim, ON by default at both
  /// edges by design. The per-child scroll edge effect is inert on the glass
  /// tier, so without this scrolled content hard-clips at the physical bottom
  /// edge (device clip 18-50).
  final bool bottomEdgeScrim;

  @override
  State<ArxaKitBottomNavScaffold> createState() =>
      _KitBottomNavScaffoldState();
}

class _KitBottomNavScaffoldState extends State<ArxaKitBottomNavScaffold> {
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.tabs.isEmpty
        ? 0
        : widget.initialIndex.clamp(0, widget.tabs.length - 1).toInt();
  }

  void _onTap(int i) {
    if (i == _index) return;
    setState(() => _index = i);
    widget.onTabChanged?.call(i);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody:
          true, // required: native glass samples the body beneath the bar
      appBar: widget.appBar,
      floatingActionButton: widget.floatingActionButton,
      // Scrim host OUTSIDE the FabLift: the scrim sizes its opaque band from
      // the RAW device inset (`viewPadding.bottom`), which the FabLift raises
      // to the full bar clearance for its subtree.
      body: ArxaKitBottomEdgeScrimHost(
        enabled: widget.bottomEdgeScrim,
        child: ArxaKitExtendBodyFabLift(
          child:
              ArxaKitLazyIndexedStack(index: _index, builders: widget.views),
        ),
      ),
      bottomNavigationBar: ArxaKitNativeTabBar(
        tabs: widget.tabs,
        currentIndex: _index,
        onTap: _onTap,
        native: widget.native,
      ),
    );
  }
}
