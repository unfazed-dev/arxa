# arxa_kit_payments

Native-first payments for `arxa_kit` apps. **Apple Pay + Google Pay** run
through Google's first-party [`pay`](https://pub.dev/packages/pay) plugin
(PassKit / Google Pay API) — the wallet the user already trusts, no third-party
SDK in the hot path. A pluggable provider port keeps Stripe / PayPal one file
away.

- **Version:** 0.1.0 · `publish_to: 'none'` · Dart `>=3.8.1 <4.0.0` · Flutter `>=3.41.0`
- **Depends on:** `pay ^3.3.0`, `flutter_stripe ^13.1.0`,
  `flutter_web_auth_2 ^5.0.3`. **No** dependency on `arxa_kit`,
  `stacked`, or `stacked_services`.
- **Platforms:** Android + iOS (the `pay` plugin supports no others).

## Scope

**In (implemented):**
- `ArxaKitPaymentsService` port — `canPay(method)` + `requestPayment(config, items)`.
- `ArxaKitPayPaymentsProvider` — the native Apple/Google Pay backend over `pay`.
- `ArxaKitStripePaymentsProvider` — Stripe PaymentSheet (card entry + Apple Pay /
  Google Pay + 3DS) over `flutter_stripe`. PaymentIntent creation stays
  server-side behind the `ArxaKitStripeBackend` port; the app sees only the
  client secret. `googlePayTestEnv` auto-follows `pk_test_` keys.
- `ArxaKitPayPalPaymentsProvider` — PayPal Orders v2 web checkout. Order
  create/capture stay server-side behind the `ArxaKitPayPalBackend` port; the
  buyer approves in an in-app browser via `flutter_web_auth_2`
  (ASWebAuthenticationSession / Chrome Auth Tab) with a deep-link return.
- Pluggable `ArxaKitPaymentsProviderRegistry` so backends are swappable.
- Typed sealed `ArxaKitPaymentResult`: `ArxaKitPaymentSuccess` · `ArxaKitPaymentCancelled` ·
  `ArxaKitPaymentDeclined` · `ArxaKitPaymentError`.
- `ArxaKitPayButton` — per-platform wallet button; `pay`'s `ApplePayButton` /
  `GooglePayButton` are re-exported for direct use.
- Scriptable fakes (`arxa_kit_testing.dart`).

**Non-goals:** server-side capture implementation (the kit defines the
backend ports; your server implements them), storing cards, refunds,
subscriptions. The Stripe/PayPal providers mint/confirm a payment and hand
back the intent/capture id — capturing is your server's job.

## Usage

```dart
import 'package:arxa_kit_payments/arxa_kit_payments.dart';

final payments = DefaultArxaKitPaymentsService.native(
  applePay: const ArxaKitApplePayConfig.fromAsset('assets/apple_pay_config.json'),
  googlePay: const ArxaKitGooglePayConfig.fromAsset('assets/google_pay_config.json'),
);

if (await payments.canPay(ArxaKitPaymentMethod.applePay)) {
  final result = await payments.requestPayment(
    config: const ArxaKitApplePayConfig.fromAsset('assets/apple_pay_config.json'),
    items: const [ArxaKitPaymentItem(label: 'Total', amount: '99.99')],
  );
  switch (result) {
    case ArxaKitPaymentSuccess(:final token):   // forward token to your server / PSP
    case ArxaKitPaymentCancelled():             // user dismissed — do nothing
    case ArxaKitPaymentDeclined(:final reason): // retry with another method
    case ArxaKitPaymentError(:final message):   // log; not user-fixable
  }
}
```

Stripe and PayPal plug into the same registry — the secret-bearing calls live
behind backend ports your server implements:

```dart
final payments = DefaultArxaKitPaymentsService(
  ArxaKitPaymentsProviderRegistry([
    ArxaKitPayPaymentsProvider(applePayConfig: applePay, googlePayConfig: googlePay),
    ArxaKitStripePaymentsProvider(
      publishableKey: 'pk_test_…',            // pk_live_… in production
      merchantIdentifier: 'merchant.com.example.app', // enables Apple Pay
      backend: MyStripeBackend(),             // implements ArxaKitStripeBackend
    ),
    ArxaKitPayPalPaymentsProvider(
      backend: MyPayPalBackend(),             // implements ArxaKitPayPalBackend
      callbackUrlScheme: 'com.example.app',   // registered deep-link scheme
    ),
  ]),
);

// PayPal routes via its own config (currency is per-order):
final result = await payments.requestPayment(
  config: const ArxaKitPayPalConfig(currencyCode: 'EUR'),
  items: const [ArxaKitPaymentItem(label: 'Total', amount: '49.99')],
);
```

`ArxaKitStripeBackend.createPaymentIntent` wraps your server's PaymentIntent
endpoint (secret key server-side; returns the client secret).
`ArxaKitPayPalBackend.createOrder` / `.captureOrder` wrap Orders v2
create/capture; PayPal must redirect approvals to
`<callbackUrlScheme>://paypalpay`.

Or drop in the button directly:

```dart
ArxaKitPayButton(
  applePay: const ArxaKitApplePayConfig.fromAsset('assets/apple_pay_config.json'),
  googlePay: const ArxaKitGooglePayConfig.fromAsset('assets/google_pay_config.json'),
  items: const [ArxaKitPaymentItem(label: 'Total', amount: '99.99')],
  onResult: (result) { /* same switch as above */ },
);
```

## Payment profiles

Config follows the `pay` convention: a JSON document per wallet, supplied
inline (`ArxaKitApplePayConfig.fromJson`) or from a Flutter asset
(`ArxaKitApplePayConfig.fromAsset`). Copy the samples in [`example/`](example/) into
your host app's `assets/` and edit the merchant identifiers:

- `example/apple_pay_config.json` — `PKPaymentRequest`-shaped.
- `example/google_pay_config.json` — Google Pay API request object (`TEST`
  environment; switch to `PRODUCTION` when live).

Native setup (merchant identifier, entitlement, processing certificate for
Apple; Business Console + gateway for Google) is per the
[`pay` getting-started guide](https://pub.dev/packages/pay).

## Testing

```dart
import 'package:arxa_kit_payments/arxa_kit_testing.dart';

final payments = FakeArxaKitPaymentsService(
  canPayByMethod: {ArxaKitPaymentMethod.applePay: true},
  results: [
    ArxaKitPaymentSuccess(token: 't', method: ArxaKitPaymentMethod.applePay),
    const ArxaKitPaymentCancelled(),
    const ArxaKitPaymentDeclined(reason: 'insufficient funds'),
    const ArxaKitPaymentError('network'),
  ],
);
```

Named factories cover the common single-outcome cases:
`FakeArxaKitPaymentsService.alwaysSucceeds()`, `.alwaysCancels()`,
`.alwaysDeclined()`, `.alwaysErrors()`. `FakeArxaKitPaymentsProvider` exercises the
registry/routing layer directly.

## Phase

Stripe and PayPal providers are implemented (PaymentSheet / Orders v2 web
checkout); both keep their secret-bearing calls behind backend ports. Unit
tests run at the mocked Port/gateway boundary — no device needed. Simulator
smoke (real keys, sandbox accounts) is a later pass. Workspace wiring
(path deps, showcase swap) is handled by a downstream reconciliation pass.
