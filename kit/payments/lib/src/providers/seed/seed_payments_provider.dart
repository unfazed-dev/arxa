import '../../models/kit_payment_config.dart';
import '../../models/kit_payment_item.dart';
import '../../models/kit_payment_method.dart';
import '../../models/payment_result.dart';
import '../kit_payments_provider.dart';

/// The deterministic behaviour a [SeedPaymentsProvider] fakes for each
/// request. Sealed (mirroring [PaymentResult] / [KitPaymentConfig]) so the
/// `switch` in [SeedPaymentsProvider.requestPayment] stays exhaustive and the
/// compiler catches any new profile.
///
/// Pure data — no wallet SDK, no platform calls. The point is to make every
/// payment outcome, including the sad paths that are hard to reproduce on a
/// real device, scriptable in CI.
sealed class SeedPaymentProfile {
  const SeedPaymentProfile();
}

/// [SeedPaymentsProvider.requestPayment] resolves immediately with
/// [PaymentSuccess]. The default profile.
final class SeedSucceed extends SeedPaymentProfile {
  const SeedSucceed();
}

/// [requestPayment] resolves immediately with [PaymentDeclined]. Set [reason]
/// to surface a provider-style message (insufficient funds, risk block, …) —
/// the same [PaymentDeclined] shape the Stripe / PayPal providers will emit on
/// a funding failure.
final class SeedDecline extends SeedPaymentProfile {
  final String? reason;
  const SeedDecline({this.reason});
}

/// [requestPayment] resolves immediately with [PaymentCancelled] — the shape
/// the native [PayPaymentsProvider] returns when the user dismisses the sheet.
final class SeedCancel extends SeedPaymentProfile {
  const SeedCancel();
}

/// [requestPayment] awaits [duration] then resolves with [PaymentError] — the
/// honest mapping of a timed-out wallet operation onto the kit's existing
/// vocabulary (a timeout is an error, not a decline and not a cancel). Tests
/// control the duration; the default is intentionally short so suites stay
/// fast.
final class SeedTimeout extends SeedPaymentProfile {
  final Duration duration;
  const SeedTimeout([this.duration = const Duration(milliseconds: 10)]);
}

/// A deterministic, pure-Dart [KitPaymentsProvider] for tests and demos.
///
/// Implements the exact provider contract the native [PayPaymentsProvider]
/// does (same `id` / `supportedMethods` / `canPay` / `requestPayment` shape)
/// so it plugs into [KitPaymentsProviderRegistry] and
/// [DefaultKitPaymentsService] unchanged — no call site or service code
/// differs. No `pay` / Stripe / PayPal SDK is touched; the outcome of every
/// request is decided entirely by the current [profile].
///
/// The [profile] is mutable at runtime so a single provider can flip mid-suite
/// (e.g. succeed for the happy path, then decline for the retry path) without
/// re-registering. Defaults to [SeedSucceed] and supports both wallets so the
/// common case needs no configuration.
class SeedPaymentsProvider implements KitPaymentsProvider {
  final Set<KitPaymentMethod> _supportedMethods;

  SeedPaymentsProvider({
    this.profile = const SeedSucceed(),
    Set<KitPaymentMethod> supportedMethods = const {
      KitPaymentMethod.applePay,
      KitPaymentMethod.googlePay,
    },
  }) : _supportedMethods = Set.of(supportedMethods);

  @override
  String get id => 'seed';

  @override
  Set<KitPaymentMethod> get supportedMethods => Set.of(_supportedMethods);

  /// The profile that decides the next [requestPayment] result. Mutable so
  /// tests can flip the outcome between calls without re-registering.
  SeedPaymentProfile profile;

  @override
  Future<bool> canPay(KitPaymentMethod method) async =>
      _supportedMethods.contains(method);

  @override
  Future<PaymentResult> requestPayment({
    required KitPaymentConfig config,
    required List<KitPaymentItem> items,
  }) async {
    final active = profile;
    return switch (active) {
      SeedSucceed() => PaymentSuccess(
          token: 'seed_token_${config.method.wireId}',
          method: config.method,
          raw: const {'provider': 'seed', 'profile': 'succeed'},
        ),
      SeedDecline(:final reason) => PaymentDeclined(reason: reason),
      SeedCancel() => const PaymentCancelled(),
      SeedTimeout(:final duration) => await Future<PaymentResult>.delayed(
          duration,
          () => const PaymentError('Seed payment timed out'),
        ),
    };
  }
}
