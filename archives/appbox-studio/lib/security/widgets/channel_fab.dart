import 'package:flutter/material.dart';

import 'package:appbox_studio/l10n/app_localizations.dart';

import '../channel/channel_state.dart';
import '../config/companion_config.dart';

/// A floating, draggable button that rides above the prototype WebView and
/// carries the **channel state** (live / reconnecting / dead) as its own
/// affordance — never whether the WebView painted (§15).
///
/// Constraints honoured (12.10):
///  - Edge-docked / minimised: it occludes by definition, so a drag snaps to
///    the nearest horizontal edge and a double-tap shrinks it out of the way.
///  - Never over the home indicator: vertical clamp reserves
///    [CompanionConfig.fabHomeIndicatorKeepout] at the bottom edge.
///  - Gesture capture scoped to the FAB: only this widget's hit region
///    intercepts — the overlay that hosts it is fully transparent to touches
///    elsewhere, so the WebView owns every other touch.
class ChannelFab extends StatefulWidget {
  const ChannelFab({
    super.key,
    required this.state,
    required this.config,
    this.onStop,
    this.onBack,
    this.positionNotifier,
  });

  /// The channel state to display. Bound to [PrototypeChannelService.current].
  final ChannelState state;

  /// Insets and keepouts (R3 — from config, never literals).
  final CompanionConfig config;

  /// "Stop server" — halts the desktop prototype server and drops the session.
  final VoidCallback? onStop;

  /// Back to the companion home (pair / pipeline controls).
  final VoidCallback? onBack;

  /// Optional observability hook for tests — the FAB drives this with its
  /// current centre position so a test can assert clamping without poking
  /// private state.
  final ValueNotifier<Offset>? positionNotifier;

  @override
  State<ChannelFab> createState() => _ChannelFabState();
}

class _ChannelFabState extends State<ChannelFab> {
  static const double _radius = 28.0;
  bool _expanded = false;
  bool _minimized = false;
  Offset? _position; // centre, in the overlay's coordinate space

  Offset _resolvePosition(Size size) {
    final pos = _position ??
        Offset(
          size.width - _radius - widget.config.fabEdgeDockInset,
          // Default parked at the right edge, clear of the home indicator.
          size.height - _radius - widget.config.fabHomeIndicatorKeepout,
        );
    return _clamp(pos, size);
  }

  Offset _clamp(Offset pos, Size size) {
    final minX = _radius + widget.config.fabEdgeDockInset;
    final maxX = size.width - _radius - widget.config.fabEdgeDockInset;
    final minY = _radius + widget.config.fabEdgeDockInset;
    final maxY =
        size.height - _radius - widget.config.fabHomeIndicatorKeepout;
    return Offset(
      pos.dx.clamp(minX, maxX == minX ? minX : maxX),
      pos.dy.clamp(minY, maxY == minY ? minY : maxY),
    );
  }

  void _onPanUpdate(DragUpdateDetails details, Size size) {
    setState(() {
      _position = _clamp((_position ?? _resolvePosition(size)) + details.delta,
          size);
      widget.positionNotifier?.value = _position!;
    });
  }

  void _onPanEnd(DragEndDetails _, Size size) {
    // Edge-dock: snap to the nearer horizontal edge so the FAB tucks away
    // rather than floating mid-content.
    final pos = _position ?? _resolvePosition(size);
    final midX = size.width / 2;
    final snapped = Offset(pos.dx < midX ? _radius + widget.config.fabEdgeDockInset
        : size.width - _radius - widget.config.fabEdgeDockInset, pos.dy);
    setState(() {
      _position = _clamp(snapped, size);
      widget.positionNotifier?.value = _position!;
    });
  }

  @override
  Widget build(BuildContext context) {
    final spec = _ChannelSpec.of(widget.state, AppLocalizations.of(context));
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        if (_position == null) {
          // Initialise notifier + cached position on first layout.
          _position = _resolvePosition(size);
          widget.positionNotifier?.value = _position!;
        }
        final scale = _minimized ? widget.config.fabMinimizedScale : 1.0;
        return Stack(
          // The overlay itself must not eat touches meant for the WebView —
          // only positioned children with their own hit regions intercept.
          children: [
            Positioned(
              left: _position!.dx - _radius,
              top: _position!.dy - _radius,
              child: Transform.scale(
                scale: scale,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: (d) => _onPanUpdate(d, size),
                  onPanEnd: (d) => _onPanEnd(d, size),
                  onTap: () => setState(() => _expanded = !_expanded),
                  onDoubleTapDown: (_) {},
                  onDoubleTap: () => setState(() => _minimized = !_minimized),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (_expanded) _expandedControls(spec),
                      _fabButton(spec),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _fabButton(_ChannelSpec spec) {
    return Container(
      width: _radius * 2,
      height: _radius * 2,
      decoration: BoxDecoration(
        color: spec.color,
        shape: BoxShape.circle,
        boxShadow: const [
          BoxShadow(color: Color(0x66000000), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(spec.icon, color: Colors.white, size: _radius),
          // Reconnecting pulses to read as "trying", dead shows nothing extra.
          if (widget.state == ChannelState.reconnecting)
            const SizedBox(
              width: _radius * 2,
              height: _radius * 2,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white70,
              ),
            ),
        ],
      ),
    );
  }

  Widget _expandedControls(_ChannelSpec spec) {
    final l10n = AppLocalizations.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8, right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: const Color(0xF01C1C1E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _controlButton(Icons.power_settings_new, l10n.channelStop, spec, widget.onStop),
          Container(width: 1, height: 24, color: Colors.white24),
          _controlButton(Icons.arrow_back, l10n.channelBack, spec, widget.onBack),
        ],
      ),
    );
  }

  Widget _controlButton(
      IconData icon, String label, _ChannelSpec spec, VoidCallback? onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(height: 2),
            Text(label,
                style: const TextStyle(color: Colors.white, fontSize: 10)),
          ],
        ),
      ),
    );
  }
}

/// Maps a [ChannelState] to the visual the FAB shows. Kept as a private value
/// type so the mapping is testable in one place and the widget reads it.
/// Labels come from [AppLocalizations], so instances are built per-build.
class _ChannelSpec {
  final Color color;
  final IconData icon;
  final String label;
  const _ChannelSpec({required this.color, required this.icon, required this.label});

  static _ChannelSpec of(ChannelState s, AppLocalizations l10n) {
    return switch (s) {
      ChannelState.live => _ChannelSpec(
          color: const Color(0xFF34C759), icon: Icons.bolt, label: l10n.channelLive),
      ChannelState.reconnecting => _ChannelSpec(
          color: const Color(0xFFFFCC00), icon: Icons.sync, label: l10n.channelReconnecting),
      ChannelState.dead => _ChannelSpec(
          color: const Color(0xFFFF3B30), icon: Icons.warning, label: l10n.channelDead),
    };
  }
}
