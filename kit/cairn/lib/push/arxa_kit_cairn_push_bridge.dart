/// The push bridge (ADR-0037): cairn push sits BEHIND the kit/notifications
/// seam. The bridge consumes `ArxaKitNotificationsService.tokenStream` /
/// `currentToken()` and hands each token to cairn's `registerPushToken` —
/// no Firebase/APNs type ever crosses into the kit; the provider rail
/// (Firebase init, native wiring, the background-isolate handler, the VAPID
/// web leg) is app-side, per the README's push section.
///
/// Lifecycle (mirrors the atlet pilot checklist):
/// - [attach] after EVERY engine start: the SDK deregisters session-registered
///   tokens on `signOut()`, so each new session must re-register. The backend
///   attaches at initialize when `ARXA_CAIRN_PUSH=true`.
/// - Refresh re-registers: `tokenStream` emits on rotation.
/// - [CairnPushTokenException] is non-fatal: logged, retried on the next
///   attach/refresh.
/// - [detach] only stops forwarding — deregistration is the SDK sign-out
///   hook's job, never this class's.
///
/// Doorbell semantics: push is a hint, sync is the transport. The bridge
/// registers WHERE to knock; row data always arrives over the sync
/// connection.
library;

import 'dart:async';

import 'package:cairn_flutter/cairn_flutter.dart';
import 'package:arxa_kit_notifications/arxa_kit_notifications.dart';

class ArxaKitCairnPushBridge {
  /// [register] is normally `CairnDatabase.registerPushToken`, bound by the
  /// backend after open (injectable so the whole flow tests without a
  /// server). [log] defaults to a no-op so tests and release builds stay
  /// quiet; wire `debugPrint` in development.
  ArxaKitCairnPushBridge({
    required this.notifications,
    required this.register,
    void Function(String message)? log,
  }) : _log = log ?? _noop;

  final ArxaKitNotificationsService notifications;

  /// `CairnDatabase.registerPushToken(platform, token)` — cairn validates the
  /// platform set ({fcm, apns, webpush}) and throws [CairnPushTokenException]
  /// on a non-204.
  final Future<void> Function(String platform, String token) register;

  final void Function(String message) _log;

  StreamSubscription<ArxaKitPushToken>? _sub;

  static void _noop(String _) {}

  /// cairn's wire platform for a kit push provider. `unknown` throws — the
  /// bridge skips such tokens before ever calling this (see [_forward]).
  static String platformFor(ArxaKitPushProvider provider) => switch (provider) {
        ArxaKitPushProvider.apns => 'apns',
        ArxaKitPushProvider.fcm => 'fcm',
        ArxaKitPushProvider.unknown => throw ArgumentError.value(
            provider,
            'provider',
            'no cairn platform mapping — the token is skipped',
          ),
      };

  /// Registers the currently-held token (if any) and forwards every future
  /// refresh. Idempotent: re-attaching replaces the subscription.
  ///
  /// The current-token probe is bounded: some providers only resolve after
  /// the OS's remote-registration callback fires, which iOS can defer or
  /// throttle indefinitely — an unbounded await here would wedge the whole
  /// data-layer boot (initialize awaits attach). A hung answer degrades to
  /// null and the [tokenStream] subscription carries the registration
  /// whenever the token does arrive.
  Future<void> attach() async {
    await _sub?.cancel();
    _sub = notifications.tokenStream.listen(
      (token) => unawaited(_forward(token)),
    );
    final current = await notifications
        .currentToken()
        .timeout(const Duration(seconds: 5), onTimeout: () => null);
    if (current != null) await _forward(current);
  }

  /// Stops forwarding. Token DEREGISTRATION is deliberately absent — the
  /// SDK's sign-out hook owns it (ADR-0037 §3).
  Future<void> detach() async {
    await _sub?.cancel();
    _sub = null;
  }

  Future<void> _forward(ArxaKitPushToken token) async {
    if (token.provider == ArxaKitPushProvider.unknown) {
      _log('ArxaKitCairnPushBridge: skipping token with unknown provider — '
          'no cairn platform mapping');
      return;
    }
    try {
      await register(platformFor(token.provider), token.value);
    } on CairnPushTokenException catch (e) {
      // Non-fatal: registration retries on the next attach()/token refresh
      // (atlet's observed contract — a stranded device re-registers next time).
      _log('ArxaKitCairnPushBridge: registerPushToken failed (retries on the '
          'next attach/refresh): $e');
    }
  }
}
