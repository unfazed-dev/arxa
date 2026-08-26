import 'arxa_kit_payment_method.dart';

/// The outcome of a payment request. Sealed with four cases so callers must
/// handle every branch — the distinctions are load-bearing:
///
/// * [ArxaKitPaymentSuccess] — a token was minted. Nothing is charged yet; hand the
///   token to your server / PSP to capture.
/// * [ArxaKitPaymentCancelled] — the user dismissed the sheet. Not an error; show
///   nothing.
/// * [ArxaKitPaymentDeclined] — the payment method itself was rejected (expired card,
///   insufficient funds, risk block). Distinct from [ArxaKitPaymentError] because the
///   user should retry with a different method, not report a bug. Apple/Google
///   Pay rarely surface this client-side (declines usually happen at capture),
///   but the pluggable Stripe/PayPal providers and the fake do.
/// * [ArxaKitPaymentError] — something broke (misconfiguration, network, plugin
///   exception). The user cannot fix it by retrying.
sealed class ArxaKitPaymentResult {
  const ArxaKitPaymentResult();
}

/// A wallet token was produced. [token] is the raw token payload to forward to
/// your payment processor (JSON-encoded for Apple/Google Pay). [raw] is the
/// full plugin result map for providers that need more than the token.
final class ArxaKitPaymentSuccess extends ArxaKitPaymentResult {
  final String token;
  final ArxaKitPaymentMethod method;
  final Map<String, dynamic> raw;

  const ArxaKitPaymentSuccess({
    required this.token,
    required this.method,
    this.raw = const {},
  });
}

/// The user dismissed the payment sheet before completing.
final class ArxaKitPaymentCancelled extends ArxaKitPaymentResult {
  const ArxaKitPaymentCancelled();
}

/// The payment instrument was rejected. [reason] is a provider-supplied,
/// human-readable string when available.
final class ArxaKitPaymentDeclined extends ArxaKitPaymentResult {
  final String? reason;

  const ArxaKitPaymentDeclined({this.reason});
}

/// The request failed for a non-user reason. [cause] retains the underlying
/// exception so callers can log it without importing any provider SDK.
final class ArxaKitPaymentError extends ArxaKitPaymentResult {
  final String message;
  final Object? cause;

  const ArxaKitPaymentError(this.message, {this.cause});

  @override
  String toString() => 'ArxaKitPaymentError($message)';
}
