/// appbox_kit_payments — native-first payments for appbox_kit apps.
///
/// Apple Pay + Google Pay through Google's first-party `pay` plugin, behind a
/// pluggable [KitPaymentsProvider] port so Stripe / PayPal backends slot in
/// later without changing call sites. Talk to [KitPaymentsService]; branch on
/// the sealed [PaymentResult].
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
export 'src/models/kit_payment_config.dart';
export 'src/models/kit_payment_item.dart';
export 'src/models/kit_payment_method.dart';
export 'src/models/payment_result.dart';

// Service (the port hosts depend on)
export 'src/service/kit_payments_service.dart';

// Providers — the native one plus Stripe (PaymentSheet) and PayPal (Orders
// v2 web checkout); SeedPaymentsProvider is a pure-Dart fake for tests/demos.
export 'src/providers/kit_payments_provider.dart';
export 'src/providers/native/pay_payments_provider.dart';
export 'src/providers/seed/seed_payments_provider.dart';
export 'src/providers/stripe/stripe_payments_provider.dart';
export 'src/providers/paypal/paypal_payments_provider.dart';

// Widgets
export 'src/widgets/kit_pay_button.dart';
