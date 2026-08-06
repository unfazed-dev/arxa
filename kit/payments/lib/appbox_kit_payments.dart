/// appbox_kit_payments — native-first payments for appbox_kit apps.
///
/// Apple Pay + Google Pay through Google's first-party `pay` plugin, behind a
/// pluggable [AppBoxKitPaymentsProvider] port so Stripe / PayPal backends slot in
/// later without changing call sites. Talk to [AppBoxKitPaymentsService]; branch on
/// the sealed [AppBoxKitPaymentResult].
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
export 'src/models/appbox_kit_payment_config.dart';
export 'src/models/appbox_kit_payment_item.dart';
export 'src/models/appbox_kit_payment_method.dart';
export 'src/models/appbox_kit_payment_result.dart';

// Service (the port hosts depend on)
export 'src/service/appbox_kit_payments_service.dart';

// Providers — the native one plus Stripe (PaymentSheet) and PayPal (Orders
// v2 web checkout); AppBoxKitSeedPaymentsProvider is a pure-Dart fake for tests/demos.
export 'src/providers/appbox_kit_payments_provider.dart';
export 'src/providers/native/appbox_kit_pay_payments_provider.dart';
export 'src/providers/seed/appbox_kit_seed_payments_provider.dart';
export 'src/providers/stripe/appbox_kit_stripe_payments_provider.dart';
export 'src/providers/paypal/appbox_kit_paypal_payments_provider.dart';

// Widgets
export 'src/widgets/appbox_kit_pay_button.dart';
