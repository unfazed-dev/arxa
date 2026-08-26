/// arxa_kit_payments — native-first payments for arxa_kit apps.
///
/// Apple Pay + Google Pay through Google's first-party `pay` plugin, behind a
/// pluggable [ArxaKitPaymentsProvider] port so Stripe / PayPal backends slot in
/// later without changing call sites. Talk to [ArxaKitPaymentsService]; branch on
/// the sealed [ArxaKitPaymentResult].
library;

// The pay plugin's button widgets + their style/type enums, re-exported so
// hosts never import `package:pay` directly.
export 'package:pay/pay.dart'
    show
        ApplePayButton,
        GooglePayButton,
        RawApplePayButton,
        RawGooglePayButton,
        ApplePayButtonStyle,
        ApplePayButtonType,
        GooglePayButtonType;

// Models
export 'src/models/arxa_kit_payment_config.dart';
export 'src/models/arxa_kit_payment_item.dart';
export 'src/models/arxa_kit_payment_method.dart';
export 'src/models/arxa_kit_payment_result.dart';

// Service (the port hosts depend on)
export 'src/service/arxa_kit_payments_service.dart';

// Providers — the native one plus Stripe (PaymentSheet) and PayPal (Orders
// v2 web checkout); ArxaKitSeedPaymentsProvider is a pure-Dart fake for tests/demos.
export 'src/providers/arxa_kit_payments_provider.dart';
export 'src/providers/native/arxa_kit_pay_payments_provider.dart';
export 'src/providers/seed/arxa_kit_seed_payments_provider.dart';
export 'src/providers/stripe/arxa_kit_stripe_payments_provider.dart';
export 'src/providers/paypal/arxa_kit_paypal_payments_provider.dart';

// Widgets
export 'src/widgets/arxa_kit_pay_button.dart';
