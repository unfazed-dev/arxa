// Cold-start tap drain + requestId dedupe for the raw-APNs backend
// (D68 phone leg follow-up). The 'arxa/apns' channel is mocked via
// TestDefaultBinaryMessengerBinding; native→Dart 'event' calls are
// delivered with handlePlatformMessage, exactly as the platform would.
import 'package:arxa_studio_mobile/services/apns_notifications_backend.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('arxa/apns');
  final codec = const StandardMethodCodec();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  // canned responses for Dart→native calls; default null (pendingTap absent).
  Object? Function(MethodCall)? dartToNative;
  Future<Object?>? handler(MethodCall call) async => dartToNative?.call(call);

  setUp(() {
    dartToNative = null;
    messenger.setMockMethodCallHandler(channel, handler);
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
  });

  /// Delivers a native→Dart message on the channel (as the Runner side does).
  Future<void> deliverEvent(Map<String, dynamic> args) async {
    final data = codec.encodeMethodCall(MethodCall('event', args));
    messenger.handlePlatformMessage(channel.name, data, (_) {});
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }

  Future<List<Map<String, dynamic>>> collectTaps(
    ApnsNotificationsBackend backend,
    Future<void> Function() action,
  ) async {
    final taps = <Map<String, dynamic>>[];
    final sub = backend.taps.listen(taps.add);
    await action();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    return taps;
  }

  test('constructor drains a canned pendingTap and emits on taps', () async {
    dartToNative = (call) =>
        call.method == 'pendingTap'
            ? <String, dynamic>{'type': 'tap', 'requestId': 'r1', 'title': 'Buzz'}
            : null;

    final backend = ApnsNotificationsBackend();
    addTearDown(backend.dispose);
    final taps = await collectTaps(
        backend, () async => Future<void>.delayed(Duration.zero));

    expect(taps, hasLength(1));
    expect(taps.single['requestId'], 'r1');
  });

  test('null pendingTap emits nothing on taps', () async {
    dartToNative = (call) => call.method == 'pendingTap' ? null : null;

    final backend = ApnsNotificationsBackend();
    addTearDown(backend.dispose);
    final taps = await collectTaps(
        backend, () async => Future<void>.delayed(Duration.zero));

    expect(taps, isEmpty);
  });

  test('dedupe: same requestId twice emits once (drain + live event)', () async {
    dartToNative = (call) =>
        call.method == 'pendingTap'
            ? <String, dynamic>{'type': 'tap', 'requestId': 'r1'}
            : null;

    final backend = ApnsNotificationsBackend();
    addTearDown(backend.dispose);
    final taps = <Map<String, dynamic>>[];
    final sub = backend.taps.listen(taps.add);
    // Let the constructor's drain land first, then the live 'event' racing
    // in with the SAME notification id — only one emission may survive.
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    await deliverEvent(<String, dynamic>{'type': 'tap', 'requestId': 'r1'});
    await sub.cancel();

    expect(taps, hasLength(1));
    expect(taps.single['requestId'], 'r1');
  });

  test('distinct requestIds both emit', () async {
    dartToNative = (call) =>
        call.method == 'pendingTap'
            ? <String, dynamic>{'type': 'tap', 'requestId': 'r1'}
            : null;

    final backend = ApnsNotificationsBackend();
    addTearDown(backend.dispose);
    final taps = <Map<String, dynamic>>[];
    final sub = backend.taps.listen(taps.add);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    await deliverEvent(<String, dynamic>{'type': 'tap', 'requestId': 'r2'});
    await sub.cancel();

    expect(taps.map((t) => t['requestId']), ['r1', 'r2']);
  });
}
