import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'appbox_kit_lazy_indexed_stack.dart';
import 'appbox_kit_tab_bar.dart';

/// Fully-automated bottom-nav scaffold: owns the active index, lays out the tab
/// views in a lazy [AppBoxKitLazyIndexedStack], and mounts the adaptive
/// [AppBoxKitNativeTabBar]. Sets `extendBody: true` itself so a native Liquid Glass
/// bar samples the body beneath it — the host supplies only tabs + views.
///
/// ```dart
/// AppBoxKitBottomNavScaffold(
///   tabs: const [AppBoxKitTab(icon: Icons.home, label: 'Home'), AppBoxKitTab(...)],
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
/// that hosts nested Scaffolds with FABs. [AppBoxKitBottomNavScaffold] applies it
/// automatically.
class AppBoxKitExtendBodyFabLift extends StatelessWidget {
  const AppBoxKitExtendBodyFabLift({super.key, required this.child});

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

class AppBoxKitBottomNavScaffold extends StatefulWidget {
  const AppBoxKitBottomNavScaffold({
    super.key,
    required this.tabs,
    required this.views,
    this.initialIndex = 0,
    this.onTabChanged,
    this.native,
    this.appBar,
    this.floatingActionButton,
  }) : assert(
          views.length == tabs.length,
          'views must match tabs (one builder per tab)',
        );

  final List<AppBoxKitTab> tabs;
  final List<WidgetBuilder> views;
  final int initialIndex;
  final ValueChanged<int>? onTabChanged;

  /// Forwarded to [AppBoxKitNativeTabBar]; null = auto-tier.
  final bool? native;
  final PreferredSizeWidget? appBar;
  final Widget? floatingActionButton;

  @override
  State<AppBoxKitBottomNavScaffold> createState() => _KitBottomNavScaffoldState();
}

class _KitBottomNavScaffoldState extends State<AppBoxKitBottomNavScaffold> {
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
      body: AppBoxKitExtendBodyFabLift(
        child: AppBoxKitLazyIndexedStack(index: _index, builders: widget.views),
      ),
      bottomNavigationBar: AppBoxKitNativeTabBar(
        tabs: widget.tabs,
        currentIndex: _index,
        onTap: _onTap,
        native: widget.native,
      ),
    );
  }
}
