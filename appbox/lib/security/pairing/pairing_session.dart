import 'dart:math';
import 'dart:typed_data';

/// The desktop's pairing session (12.4 — the QR-relay defense).
///
/// This is the nonce + device lifecycle that makes a captured QR useless to an
/// attacker. It is a PURE STATE MACHINE: every transition takes the current
/// `now`, so the logic is fully deterministic and unit-testable with an injected
/// clock. The desktop wires real [Timer]s around [rotate] and [sweepIdle]; the
/// security logic itself owns no timers (a timer would hide the expiry math from
/// the test that proves it fires).
///
/// The three relay defenses, mapped:
///   - **rotate**      : the QR nonce changes every `qrRotation`. A photo of the
///                       QR is stale within that window.
///   - **single-use**  : [consume] accepts ONLY the current nonce, once. A replay
///                       (the same QR scanned twice, or a relayed capture) is the
///                       second use → rejected.
///   - **idle expiry** : a paired device idle for `sessionIdleTimeout` is dropped
///                       by [sweepIdle]; [touch] resets the idle clock.
/// Plus a revocable device list ([revoke]) and the human confirm gate
/// ([confirm] — the desktop dialog naming the device, which the builder wires to
/// the UI; this module only records the decision).
///
/// Pairing is LAN-local with no cloud relay (12.5). This module enforces none of
/// that — the absence of a relay is a topology property, not a check — but the
/// nonce lifecycle is what makes "no relay" safe rather than merely unfeatured.
class PairingSession {
  PairingSession({
    required this._qrRotation,
    required this._sessionIdleTimeout,
    required this._now,
    String Function()? nonceSource,
  }) : _nonceSource = nonceSource ?? _defaultNonceSource {
    rotate(_now()); // mint the first nonce immediately (never an empty session)
  }

  final Duration _qrRotation;
  final Duration _sessionIdleTimeout;
  final DateTime Function() _now;
  final String Function() _nonceSource;

  late String _currentNonce;
  late DateTime _currentNonceIssuedAt;
  String? _consumedNonce; // the nonce a companion already used — a replay target

  final Map<String, _Device> _devices = {}; // id -> device

  /// The nonce the desktop's QR should carry right now. Callers re-read this on
  /// the rotation cadence; it only changes when [rotate] advances it.
  String get currentNonce => _currentNonce;

  /// True iff [currentNonce] is past its rotation window (the desktop should call
  /// [rotate]). Exposed so the UI can render "refreshing…" precisely when stale.
  bool isNonceStale(DateTime at) =>
      at.difference(_currentNonceIssuedAt) >= _qrRotation;

  /// Advance to a fresh nonce. The previous nonce is forgotten (not retained as
  /// consumed — a nonce older than the rotation window is already useless; only
  /// the JUST-consumed one needs replay protection, held in [_consumedNonce]).
  String rotate(DateTime at) {
    _currentNonce = _nonceSource();
    _currentNonceIssuedAt = at;
    return _currentNonce;
  }

  /// A companion scanned a QR and presented [nonce] for [deviceName].
  ///
  /// Returns a [PairingRequest] the desktop shows in its confirm dialog, or
  /// `null` if the nonce is invalid. A nonce is valid iff it is the CURRENT nonce
  /// AND it has not already been consumed (single-use). An expired/replayed nonce
  /// is rejected here, before any trust is granted.
  ///
  /// [deviceName] is what the human confirms against (12.4 "naming the device") —
  /// the companion supplies it from its own device name, so a pairing attempt
  /// from an unexpected name is visible at the dialog.
  PairingRequest? consume(String nonce, String deviceName, DateTime at) {
    if (nonce != _currentNonce) return null; // expired or never-issued
    if (_consumedNonce == nonce) return null; // single-use: already consumed (replay)
    _consumedNonce = nonce;
    final id = _deviceId();
    final req = PairingRequest(id: id, deviceName: deviceName, requestedAt: at);
    _devices[id] = _Device(
      name: deviceName,
      state: DeviceState.pending,
      lastActiveAt: at,
    );
    return req;
  }

  /// Human approved the confirm dialog for [id]. Moves the device to paired.
  /// A pending device that is not confirmed idles out via [sweepIdle].
  void confirm(String id) {
    final d = _devices[id];
    if (d == null || d.state != DeviceState.pending) return;
    _devices[id] = _Device(
      name: d.name,
      state: DeviceState.paired,
      lastActiveAt: _now(),
    );
  }

  /// Mark activity for a paired device (resets the idle-expiry clock).
  void touch(String id) {
    final d = _devices[id];
    if (d == null || d.state != DeviceState.paired) return;
    _devices[id] = _Device(
      name: d.name,
      state: DeviceState.paired,
      lastActiveAt: _now(),
    );
  }

  /// Revoke a paired device (12.4 revocable list). The device is dropped
  /// immediately — the desktop's confirm dialog and the companion's session both
  /// see it gone. Returns true if a device was actually revoked.
  bool revoke(String id) => _devices.remove(id) != null;

  /// Drop every device (pending or paired) idle past [sessionIdleTimeout]. The
  /// desktop calls this on a sweep timer. Returns the ids dropped (for the UI).
  List<String> sweepIdle(DateTime at) {
    final dropped = <String>[];
    final cutoff = at.subtract(_sessionIdleTimeout);
    _devices.removeWhere((id, d) {
      if (d.lastActiveAt.isBefore(cutoff)) {
        dropped.add(id);
        return true;
      }
      return false;
    });
    return dropped;
  }

  /// The currently-paired device ids (for the desktop's device list UI).
  List<DeviceRecord> get pairedDevices => _devices.entries
      .where((e) => e.value.state == DeviceState.paired)
      .map((e) => DeviceRecord(id: e.key, name: e.value.name))
      .toList(growable: false);

  int get deviceCount => _devices.length;

  static final _rand = Random.secure();
  static String _defaultNonceSource() {
    final bytes = Uint8List(16);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = _rand.nextInt(256);
    }
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  int _nextId = 0;
  String _deviceId() => 'dev-${(_nextId++).toString().padLeft(4, '0')}';
}

enum DeviceState { pending, paired }

class _Device {
  const _Device({
    required this.name,
    required this.state,
    required this.lastActiveAt,
  });
  final String name;
  final DeviceState state;
  final DateTime lastActiveAt;
}

/// A pending pairing the desktop's confirm dialog shows (12.4).
class PairingRequest {
  const PairingRequest({
    required this.id,
    required this.deviceName,
    required this.requestedAt,
  });
  final String id;
  final String deviceName;
  final DateTime requestedAt;
}

/// A paired device in the desktop's revocable list.
class DeviceRecord {
  const DeviceRecord({required this.id, required this.name});
  final String id;
  final String name;
}
