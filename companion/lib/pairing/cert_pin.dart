import 'dart:typed_data';

import 'fingerprint.dart';
import 'qr_payload.dart';

/// The companion's certificate-pin check (12.3 — the MITM defense).
///
/// After scanning the QR, the companion holds the desktop's pinned fingerprint
/// (the SPKI SHA-256 the desktop embedded in the payload). On the TLS handshake,
/// it reads the server's presented cert, extracts the SPKI DER, and accepts the
/// channel ONLY iff [Fingerprint.ofSpki] of that DER [Fingerprint.matches] the
/// pin.
///
/// What this stops: a LAN MITM or a relay that terminates TLS on its OWN key
/// presents a cert whose SPKI differs from the pin → [validate] returns
/// [PinResult.mismatch] → the companion refuses to trust the channel, whatever
/// the host/port. The pin is over the KEY, so a legitimately-issued cert for the
/// same host but a different key still fails (the whole point of key pinning).
///
/// What this does NOT stop: the QR-phishing shape (an attacker shows a victim a
/// fake QR pointing at the attacker's server, with the attacker's own fp). That
/// is defeated by the nonce lifecycle + the human confirm dialog naming the
/// device — see [PairingSession] and 12.4. This class is the transport-layer
/// pin; [PairingSession] is the human-layer defense. Both are required.
class CertPin {
  /// The fingerprint the companion pinned from the QR payload.
  final String pinnedFingerprint;

  CertPin(this.pinnedFingerprint);

  /// Build a pin from a scanned QR payload (the usual path).
  factory CertPin.fromPayload(QrPayload payload) =>
      CertPin(payload.fingerprint);

  /// Validate a presented cert's SPKI DER against the pin.
  ///
  /// [presentedSpkiDer] is the SubjectPublicKeyInfo bytes extracted from the
  /// server's leaf cert during the handshake (the desktop's TLS stack exposes
  /// this; extracting it is the device layer — the companion hooks
  /// `SecureSocket`'s `onBadCertificate`/`supportedProtocols` to capture the DER,
  /// then calls here). This method is the pure decision.
  PinResult validate(Uint8List presentedSpkiDer) {
    final presented = Fingerprint.ofSpki(presentedSpkiDer);
    if (Fingerprint.matches(pinnedFingerprint, presented)) {
      return const PinResult.ok();
    }
    return PinResult.mismatch(pinned: pinnedFingerprint, presented: presented);
  }
}

/// The outcome of a pin check. Never a bare bool — a mismatch must carry the two
/// fingerprints so the UI can show the human what differed (and a log/audit can
/// record the attempt without exposing the key material itself).
class PinResult {
  final bool accepted;
  final String? pinned;
  final String? presented;

  const PinResult.ok()
      : accepted = true,
        pinned = null,
        presented = null;

  const PinResult.mismatch({required this.pinned, required this.presented})
      : accepted = false;

  bool get isMismatch => !accepted;
}
