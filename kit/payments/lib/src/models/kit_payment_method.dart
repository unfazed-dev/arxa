/// The wallet a payment runs through. Native-first: only the two the `pay`
/// plugin implements today. Additional rails (card, PayPal balance) arrive
/// with their provider stubs and get their own members then — keep this enum
/// the single source of truth so `canPay(method)` stays exhaustive.
enum KitPaymentMethod {
  applePay,
  googlePay,
}

extension KitPaymentMethodX on KitPaymentMethod {
  /// The wire id used in payment-profile JSON (`"provider"` field) and by the
  /// `pay` plugin's `PayProvider`. Kept here so nothing downstream hard-codes
  /// the string.
  String get wireId => switch (this) {
        KitPaymentMethod.applePay => 'apple_pay',
        KitPaymentMethod.googlePay => 'google_pay',
      };
}
