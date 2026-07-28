import '../channel/channel_state.dart';
import '../channel/prototype_channel_service.dart';
import 'last_render_store.dart';

/// Owns one prototype serving session: receives the desktop's ready-line
/// payload (the P09 contract), serves the render to [renderStore], and starts
/// the heartbeat on [channel].
///
/// This is the seam between "the desktop delivered a URL over the channel" and
/// the two stores that must stay independent: the render the WebView holds, and
/// the channel state the FAB holds. Stopping a session drops both — but a dead
/// server mid-session drops only the channel state; the render persists (that
/// asymmetry is the feature, see [LastRenderStore]).
class PrototypeSession {
  PrototypeSession({required this.channel, required this.renderStore});

  final PrototypeChannelService channel;
  final LastRenderStore renderStore;

  bool _active = false;
  bool get isActive => _active;

  /// Accept a ready-line payload from the paired channel. Returns true if it
  /// was the prototype-ready signal and a session started.
  ///
  /// On a new serve the render store updates (the WebView loads the new URL)
  /// and the heartbeat begins against it. The FAB reads the channel, never the
  /// render store.
  Future<bool> handleReadyLine(Map<String, dynamic> payload) async {
    final ready = ReadyLine.tryParse(payload);
    if (ready == null) return false;
    renderStore.serve(ready.url);
    await channel.start(ready.url);
    _active = true;
    return true;
  }

  /// Stop the session: halt the heartbeat and drop the render. Used when the
  /// user leaves the prototype view or commands "stop server".
  Future<void> stop() async {
    _active = false;
    await channel.stop();
    renderStore.clear();
  }

  /// The channel state the FAB should display right now.
  ChannelState get channelState => channel.current;
}
