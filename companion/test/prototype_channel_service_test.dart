import 'dart:async';
import 'dart:io';

import 'package:app_box_companion/channel/channel_state.dart';
import 'package:app_box_companion/channel/prototype_channel_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_config.dart';

/// The heartbeat on the paired channel — plan-09 done-when #5.
///
/// Uses a REAL [HttpServer] (not a mock): start it, point the channel service
/// at it, assert LIVE; shut the server down, assert the service reaches DEAD.
/// This is the liveness signal the FAB carries, independent of any WebView.
void main() {
  late HttpServer server;
  late PrototypeChannelService channel;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) {
      request.response
        ..statusCode = HttpStatus.ok
        ..write('<html><body>prototype</body></html>');
      request.response.close();
    });
    channel = PrototypeChannelService(config: testConfig());
  });

  tearDown(() async {
    channel.dispose();
    await server.close(force: true);
  });

  String urlOf(HttpServer s) => 'http://${s.address.host}:${s.port}/';

  test('heartbeats a live server to LIVE', () async {
    final live = await _waitForState(
      channel,
      ChannelState.live,
      startUrl: urlOf(server),
    );
    expect(live, isTrue, reason: 'a live server must reach LIVE');
    expect(channel.current, ChannelState.live);
  });

  test('reaches DEAD after the server is killed (P09 #5)', () async {
    await _waitForState(channel, ChannelState.live, startUrl: urlOf(server));

    // THE KILL — the negative event the heartbeat exists to detect.
    final killAt = DateTime.now();
    await server.close(force: true);

    final reachedDead = await _waitForState(channel, ChannelState.dead);
    expect(reachedDead, isTrue, reason: 'a killed server must flip to DEAD');

    // Bounded time-to-dead: within a heartbeat window, not minutes.
    final cfg = testConfig();
    final bound = cfg.deadAfterFailures * cfg.heartbeatInterval.inMilliseconds
        + cfg.heartbeatTimeout.inMilliseconds + 500 /* slack */;
    expect(
      DateTime.now().difference(killAt).inMilliseconds,
      lessThan(bound),
      reason: 'DEAD must arrive within deadAfterFailures × heartbeatInterval',
    );
  });

  test('a failing channel reads RECONNECTING before DEAD (transient grace)',
      () async {
    // Nothing listens on this OS-assigned-then-closed port: every heartbeat
    // fails. With deadAfterFailures = 2, the first failure reads RECONNECTING
    // (not DEAD) — the grace that stops a single dropped packet reading as a
    // dead server during a client demo.
    final sink = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final deadPort = sink.port;
    await sink.close(force: true);
    final deadUrl = 'http://${InternetAddress.loopbackIPv4.host}:$deadPort/';

    final seen = <ChannelState>[];
    await channel.start(deadUrl);
    final sub = channel.states.listen(seen.add);

    // Wait long enough for the heartbeat to fail past the threshold.
    await Future<void>.delayed(
        testConfig().heartbeatInterval * (testConfig().deadAfterFailures + 1));
    await sub.cancel();

    expect(seen, contains(ChannelState.reconnecting),
        reason: 'a transient failure must read RECONNECTING');
    expect(seen, contains(ChannelState.dead),
        reason: 'a persistent failure must eventually read DEAD');
    expect(
      seen.indexOf(ChannelState.reconnecting) < seen.indexOf(ChannelState.dead),
      true,
      reason: 'RECONNECTING must precede DEAD',
    );
  });
}

/// Drives [service] to a target state. Starts the heartbeat against [startUrl]
/// unless [alreadyStarted]. Returns true if [target] was seen before a 2s cap.
Future<bool> _waitForState(
  PrototypeChannelService service,
  ChannelState target, {
  String? startUrl,
  bool alreadyStarted = false,
}) async {
  if (!alreadyStarted && startUrl != null) {
    await service.start(startUrl);
  }
  if (service.current == target) return true;
  final completer = Completer<bool>();
  late StreamSubscription sub;
  sub = service.states.listen((s) {
    if (s == target && !completer.isCompleted) {
      completer.complete(true);
    }
  });
  Future<void>.delayed(const Duration(seconds: 2)).then((_) {
    if (!completer.isCompleted) completer.complete(false);
  });
  final result = await completer.future;
  await sub.cancel();
  return result;
}
