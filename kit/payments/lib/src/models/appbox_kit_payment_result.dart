import 'appbox_kit_payment_method.dart';

/// The outcome of a payment request. Sealed with four cases so callers must
/// handle every branch — the distinctions are load-bearing:
///
/// * [AppBoxKitPaymentSuccess] — a token was minted. Nothing is charged yet; hand the
///   token to your server / PSP to capture.
/// * [AppBoxKitPaymentCancelled] — the user dismissed the sheet. Not an error; show
///   nothing.
/// * [AppBoxKitPaymentDeclined] — the payment method itself was rejected (expired card,
///   insufficient funds, risk block). Distinct from [AppBoxKitPaymentError] because the
///   user should retry with a different method, not report a bug. Apple/Google
///   Pay rarely surface this client-side (declines usually happen at capture),
///   but the pluggable Stripe/PayPal providers and the fake do.
/// * [AppBoxKitPaymentError] — something broke (misconfiguration, network, plugin
///   exception). The user cannot fix it by retrying.
sealed class AppBoxKitPaymentResult {
  const AppBoxKitPaymentResult();
}

/// A wallet token was produced. [token] is the raw token payload to forward to
/// your payment processor (JSON-encoded for Apple/Google Pay). [raw] is the
/// full plugin result map for providers that need more than the token.
final class AppBoxKitPaymentSuccess extends AppBoxKitPaymentResult {
  final String token;
  final AppBoxKitPaymentMethod method;
  final Map<String, dynamic> raw;

  const AppBoxKitPaymentSuccess({
    required this.token,
    required this.method,
    this.raw = const {},
  });
}

/// The user dismissed the payment sheet before completing.
final class AppBoxKitPaymentCancelled extends AppBoxKitPaymentResult {
  const AppBoxKitPaymentCancelled();
}

/// The payment instrument was rejected. [reason] is a provider-supplied,
/// human-readable string when available.
final class AppBoxKitPaymentDeclined extends AppBoxKitPaymentResult {
  final String? reason;

  const AppBoxKitPaymentDeclined({this.reason});
}

/// The request failed for a non-user reason. [cause] retains the underlying
/// exception so callers can log it without importing any provider SDK.
final class AppBoxKitPaymentError extends AppBoxKitPaymentResult {
  final String message;
  final Object? cause;

  const AppBoxKitPaymentError(this.message, {this.cause});

  @override
  String toString() => 'AppBoxKitPaymentError($message)';
}
