import 'dart:async';
import 'dart:io';

import 'package:appbox/security/channel/channel_state.dart';
import 'package:appbox/security/channel/prototype_channel_service.dart';
import 'package:appbox/security/prototype/last_render_store.dart';
import 'package:appbox/security/prototype/prototype_session.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_config.dart';

/// Plan-12 done-when #3 / §15 — the property this feature exists to guarantee:
///
///   Killing the desktop server flips the FAB to DEAD within one heartbeat,
///   while the WebView still shows the last render.
///
/// Proof strategy (no device, no mock): a REAL [HttpServer] stands in for the
/// desktop prototype server. A [PrototypeSession] receives the ready-line
/// payload (the P09 contract), serves the render and starts the heartbeat.
/// We assert LIVE + a render on screen. Then we KILL the server (the negative
/// event) and assert the channel reaches DEAD while the render store is
/// UNCHANGED — the WebView keeps the last page; only the FAB moved.
void main() {
  late HttpServer server;
  late PrototypeSession session;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) {
      request.response
        ..statusCode = HttpStatus.ok
        ..write('<html><body>prototype render</body></html>');
      request.response.close();
    });
    session = PrototypeSession(
      channel: PrototypeChannelService(config: testConfig()),
      renderStore: LastRenderStore(),
    );
  });

  tearDown(() async {
    await session.stop();
    await server.close(force: true);
  });

  Map<String, dynamic> readyPayload(String url) => {
        'tag': 'app-box-prototype-ready',
        'url': url,
        'port': server.port,
        'host': server.address.host,
      };

  test('FAB goes DEAD while the WebView keeps the last render', () async {
    final url = 'http://${server.address.host}:${server.port}/';

    // 1. The desktop delivers the ready-line over the channel.
    final started = await session.handleReadyLine(readyPayload(url));
    expect(started, true);

    // 2. Heartbeat reaches LIVE; the WebView has a render to show.
    await _waitForChannel(session.channel, ChannelState.live);
    expect(session.channelState, ChannelState.live);
    expect(session.renderStore.hasRender, true);
    expect(session.renderStore.lastUrl, url);
    final renderLoadedAt = session.renderStore.loadedAt;

    // 3. THE KILL — the desktop server is gone.
    await server.close(force: true);

    // 4. The FAB's channel state flips to DEAD ...
    final dead = await _waitForChannel(session.channel, ChannelState.dead);
    expect(dead, true, reason: 'the killed server must flip the FAB to DEAD');
    expect(session.channelState, ChannelState.dead);

    // 5. ... while the WebView STILL shows the last render. The kill must not
    //    have cleared the render store — a browser keeps a loaded page when its
    //    origin dies, and that stale render is exactly the failure the FAB
    //    exists to flag.
    expect(session.renderStore.lastUrl, url,
        reason: 'the render must persist after the kill');
    expect(session.renderStore.loadedAt, renderLoadedAt,
        reason: 'no new render is loaded on channel death');
    expect(session.renderStore.hasRender, true);
  });

  test('a stale render on a DEAD channel is the lie the FAB exposes', () async {
    // This is the negative-case framing: the channel says DEAD but the screen
    // shows content. The FAB must read DEAD (from the heartbeat), not infer
    // liveness from the render that is still on screen.
    final url = 'http://${server.address.host}:${server.port}/';
    await session.handleReadyLine(readyPayload(url));
    await _waitForChannel(session.channel, ChannelState.live);

    await server.close(force: true);
    await _waitForChannel(session.channel, ChannelState.dead);

    // The dangerous combination: DEAD channel, non-null render. The FAB carries
    // the channel truth; the render is stale.
    expect(session.channelState, ChannelState.dead);
    expect(session.renderStore.lastUrl, isNotNull);
  });
}

Future<bool> _waitForChannel(
  PrototypeChannelService channel,
  ChannelState target, {
  Duration cap = const Duration(seconds: 3),
}) async {
  if (channel.current == target) return true;
  final completer = Completer<bool>();
  late StreamSubscription sub;
  sub = channel.states.listen((s) {
    if (s == target && !completer.isCompleted) completer.complete(true);
  });
  Future<void>.delayed(cap).then((_) {
    if (!completer.isCompleted) completer.complete(false);
  });
  final result = await completer.future;
  await sub.cancel();
  return result;
}
