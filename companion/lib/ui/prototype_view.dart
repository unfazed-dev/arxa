import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../channel/channel_state.dart';
import '../config/companion_config.dart';
import '../prototype/last_render_store.dart';
import '../prototype/prototype_session.dart';
import '../widgets/channel_fab.dart';

/// Fullscreen prototype surface: a WebView at true device width with the
/// [ChannelFab] riding above it.
///
/// The WebView loads the URL the desktop served (from [LastRenderStore]) once
/// and keeps the last render even after the server dies — a browser does not
/// blank a loaded page when its origin goes away. The FAB reads the channel
/// state independently, so a dead server shows a stale render while the FAB
/// reads DEAD. That is the property §15 exists to guarantee.
///
/// Safe-area insets (12.11): a WebView is a platform view and does not inherit
/// Flutter's [SafeArea] — verified explicitly via [MediaQuery] padding and
/// folded into the FAB's keepout, never assumed.
class PrototypeView extends StatefulWidget {
  const PrototypeView({
    super.key,
    required this.session,
    required this.config,
    this.onExit,
  });

  final PrototypeSession session;
  final CompanionConfig config;
  final VoidCallback? onExit;

  @override
  State<PrototypeView> createState() => _PrototypeViewState();
}

class _PrototypeViewState extends State<PrototypeView> {
  late final WebViewController _web;
  ChannelState _fabState = ChannelState.reconnecting;
  String? _renderedUrl;
  StreamSubscription<ChannelState>? _channelSub;

  @override
  void initState() {
    super.initState();
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        // The WebView owns its own page; we only react to a NEW serve, never
        // to channel death (a dead server must leave the render in place).
        onPageFinished: (_) {},
      ));
    // Bind FAB state to the channel.
    _channelSub = widget.session.channel.states.listen((s) {
      if (mounted) setState(() => _fabState = s);
    });
    // Load whatever render is current and follow new serves.
    final store = widget.session.renderStore;
    store.addListener(_onRender);
    _onRender();
  }

  void _onRender() {
    final url = widget.session.renderStore.lastUrl;
    if (url != null && url != _renderedUrl) {
      _renderedUrl = url;
      _web.loadRequest(Uri.parse(url));
    }
  }

  @override
  void dispose() {
    _channelSub?.cancel();
    widget.session.renderStore.removeListener(_onRender);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 12.11 — verify safe-area insets explicitly. The WebView is a platform
    // view and won't pick up Flutter's SafeArea; the FAB keepout must be at
    // least the real bottom inset so it never parks over the home indicator.
    final mediaQuery = MediaQuery.of(context);
    final effectiveKeepout =
        widget.config.fabHomeIndicatorKeepout < mediaQuery.padding.bottom
            ? mediaQuery.padding.bottom
            : widget.config.fabHomeIndicatorKeepout;
    assert(
      effectiveKeepout >= mediaQuery.padding.bottom,
      'FAB keepout must respect the real bottom safe-area inset',
    );

    return Scaffold(
      // No app bar — the prototype is the whole screen at true device width.
      body: Stack(
        children: [
          // The WebView fills the screen; only the FAB below intercepts touch.
          Positioned.fill(child: WebViewWidget(controller: _web)),
          Positioned.fill(
            child: ChannelFab(
              state: _fabState,
              config: widget.config,
              onStop: () async {
                await widget.session.stop();
                widget.onExit?.call();
              },
              onBack: widget.onExit,
            ),
          ),
        ],
      ),
    );
  }
}
