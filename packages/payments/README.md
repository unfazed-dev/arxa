# stacked_kit_payments

Native-first payments for `stacked_kit` apps. **Apple Pay + Google Pay** run
through Google's first-party [`pay`](https://pub.dev/packages/pay) plugin
(PassKit / Google Pay API) — the wallet the user already trusts, no third-party
SDK in the hot path. A pluggable provider port keeps Stripe / PayPal one file
away.

- **Version:** 0.1.0 · `publish_to: 'none'` · Dart `>=3.0.3 <4.0.0`
- **Depends on:** `pay ^3.3.0` only. **No** dependency on `stacked_kit`,
  `stacked`, or `stacked_services`.
- **Platforms:** Android + iOS (the `pay` plugin supports no others).

## Scope

**In (implemented):**
- `KitPaymentsService` port — `canPay(method)` + `requestPayment(config, items)`.
- `PayPaymentsProvider` — the native Apple/Google Pay backend over `pay`.
- Pluggable `KitPaymentsProviderRegistry` so backends are swappable.
- Typed sealed `PaymentResult`: `PaymentSuccess` · `PaymentCancelled` ·
  `PaymentDeclined` · `PaymentError`.
- `KitPayButton` — per-platform wallet button; `pay`'s `ApplePayButton` /
  `GooglePayButton` are re-exported for direct use.
- Scriptable fakes (`testing.dart`).

**Stubs (phase-later, `UnimplementedError` + TODO):**
- `StripePaymentsProvider` — `flutter_stripe` (`PlatformPay` + `PaymentSheet`).
- `PayPalPaymentsProvider` — Braintree / Orders v2 redirect flow.

**Non-goals:** server-side capture, PSP integration, storing cards, refunds,
subscriptions. This package mints a wallet token and hands it back — capturing
it is your server's job.

## Usage

```dart
import 'package:stacked_kit_payments/stacked_kit_payments.dart';

final payments = DefaultKitPaymentsService.native(
  applePay: const ApplePayConfig.fromAsset('assets/apple_pay_config.json'),
  googlePay: const GooglePayConfig.fromAsset('assets/google_pay_config.json'),
);

if (await payments.canPay(KitPaymentMethod.applePay)) {
  final result = await payments.requestPayment(
    config: const ApplePayConfig.fromAsset('assets/apple_pay_config.json'),
    items: const [KitPaymentItem(label: 'Total', amount: '99.99')],
  );
  switch (result) {
    case PaymentSuccess(:final token):   // forward token to your server / PSP
    case PaymentCancelled():             // user dismissed — do nothing
    case PaymentDeclined(:final reason): // retry with another method
    case PaymentError(:final message):   // log; not user-fixable
  }
}
```

Or drop in the button directly:

```dart
KitPayButton(
  applePay: const ApplePayConfig.fromAsset('assets/apple_pay_config.json'),
  googlePay: const GooglePayConfig.fromAsset('assets/google_pay_config.json'),
  items: const [KitPaymentItem(label: 'Total', amount: '99.99')],
  onResult: (result) { /* same switch as above */ },
);
```

## Payment profiles

Config follows the `pay` convention: a JSON document per wallet, supplied
inline (`ApplePayConfig.fromJson`) or from a Flutter asset
(`ApplePayConfig.fromAsset`). Copy the samples in [`example/`](example/) into
your host app's `assets/` and edit the merchant identifiers:

- `example/apple_pay_config.json` — `PKPaymentRequest`-shaped.
- `example/google_pay_config.json` — Google Pay API request object (`TEST`
  environment; switch to `PRODUCTION` when live).

Native setup (merchant identifier, entitlement, processing certificate for
Apple; Business Console + gateway for Google) is per the
[`pay` getting-started guide](https://pub.dev/packages/pay).

## Testing

```dart
import 'package:stacked_kit_payments/testing.dart';

final payments = FakeKitPaymentsService(
  canPayByMethod: {KitPaymentMethod.applePay: true},
  results: [
    PaymentSuccess(token: 't', method: KitPaymentMethod.applePay),
    const PaymentCancelled(),
    const PaymentDeclined(reason: 'insufficient funds'),
    const PaymentError('network'),
  ],
);
```

Named factories cover the common single-outcome cases:
`FakeKitPaymentsService.alwaysSucceeds()`, `.alwaysCancels()`,
`.alwaysDeclined()`, `.alwaysErrors()`. `FakePaymentsProvider` exercises the
registry/routing layer directly.

## Phase

Phase 1 (this package): native wallets + provider seam + fakes. Stripe / PayPal
providers and any server-capture seam are later phases. Workspace wiring
(path deps, showcase swap) is handled by a downstream reconciliation pass.
