import 'kit_payment_method.dart';

/// The outcome of a payment request. Sealed with four cases so callers must
/// handle every branch — the distinctions are load-bearing:
///
/// * [PaymentSuccess] — a token was minted. Nothing is charged yet; hand the
///   token to your server / PSP to capture.
/// * [PaymentCancelled] — the user dismissed the sheet. Not an error; show
///   nothing.
/// * [PaymentDeclined] — the payment method itself was rejected (expired card,
///   insufficient funds, risk block). Distinct from [PaymentError] because the
///   user should retry with a different method, not report a bug. Apple/Google
///   Pay rarely surface this client-side (declines usually happen at capture),
///   but the pluggable Stripe/PayPal providers and the fake do.
/// * [PaymentError] — something broke (misconfiguration, network, plugin
///   exception). The user cannot fix it by retrying.
sealed class PaymentResult {
  const PaymentResult();
}

/// A wallet token was produced. [token] is the raw token payload to forward to
/// your payment processor (JSON-encoded for Apple/Google Pay). [raw] is the
/// full plugin result map for providers that need more than the token.
final class PaymentSuccess extends PaymentResult {
  final String token;
  final KitPaymentMethod method;
  final Map<String, dynamic> raw;

  const PaymentSuccess({
    required this.token,
    required this.method,
    this.raw = const {},
  });
}

/// The user dismissed the payment sheet before completing.
final class PaymentCancelled extends PaymentResult {
  const PaymentCancelled();
}

/// The payment instrument was rejected. [reason] is a provider-supplied,
/// human-readable string when available.
final class PaymentDeclined extends PaymentResult {
  final String? reason;

  const PaymentDeclined({this.reason});
}

/// The request failed for a non-user reason. [cause] retains the underlying
/// exception so callers can log it without importing any provider SDK.
final class PaymentError extends PaymentResult {
  final String message;
  final Object? cause;

  const PaymentError(this.message, {this.cause});

  @override
  String toString() => 'PaymentError($message)';
}
