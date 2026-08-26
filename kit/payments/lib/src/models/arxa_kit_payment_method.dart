/// The wallet a payment runs through. Native-first: Apple/Google Pay through
/// the `pay` plugin; [payPal] arrived with its provider (web approval, no
/// native sheet). Keep this enum the single source of truth so
/// `canPay(method)` stays exhaustive.
enum ArxaKitPaymentMethod {
  applePay,
  googlePay,

  /// PayPal web checkout (Orders v2 approval redirect) — served only by
  /// [ArxaKitPayPalPaymentsProvider]; the native provider never reports it.
  payPal,
}

extension ArxaKitPaymentMethodX on ArxaKitPaymentMethod {
  /// The wire id used in payment-profile JSON (`"provider"` field) and by the
  /// `pay` plugin's `PayProvider`. Kept here so nothing downstream hard-codes
  /// the string.
  String get wireId => switch (this) {
        ArxaKitPaymentMethod.applePay => 'apple_pay',
        ArxaKitPaymentMethod.googlePay => 'google_pay',
        ArxaKitPaymentMethod.payPal => 'paypal',
      };
}
