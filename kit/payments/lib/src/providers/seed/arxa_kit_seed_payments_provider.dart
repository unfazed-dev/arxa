import '../../models/arxa_kit_payment_config.dart';
import '../../models/arxa_kit_payment_item.dart';
import '../../models/arxa_kit_payment_method.dart';
import '../../models/arxa_kit_payment_result.dart';
import '../arxa_kit_payments_provider.dart';

/// The deterministic behaviour a [ArxaKitSeedPaymentsProvider] fakes for each
/// request. Sealed (mirroring [ArxaKitPaymentResult] / [ArxaKitPaymentConfig]) so the
/// `switch` in [ArxaKitSeedPaymentsProvider.requestPayment] stays exhaustive and the
/// compiler catches any new profile.
///
/// Pure data — no wallet SDK, no platform calls. The point is to make every
/// payment outcome, including the sad paths that are hard to reproduce on a
/// real device, scriptable in CI.
sealed class ArxaKitSeedPaymentProfile {
  const ArxaKitSeedPaymentProfile();
}

/// [ArxaKitSeedPaymentsProvider.requestPayment] resolves immediately with
/// [ArxaKitPaymentSuccess]. The default profile.
final class ArxaKitSeedSucceed extends ArxaKitSeedPaymentProfile {
  const ArxaKitSeedSucceed();
}

/// [requestPayment] resolves immediately with [ArxaKitPaymentDeclined]. Set [reason]
/// to surface a provider-style message (insufficient funds, risk block, …) —
/// the same [ArxaKitPaymentDeclined] shape the Stripe / PayPal providers will emit on
/// a funding failure.
final class ArxaKitSeedDecline extends ArxaKitSeedPaymentProfile {
  final String? reason;
  const ArxaKitSeedDecline({this.reason});
}

/// [requestPayment] resolves immediately with [ArxaKitPaymentCancelled] — the shape
/// the native [ArxaKitPayPaymentsProvider] returns when the user dismisses the sheet.
final class ArxaKitSeedCancel extends ArxaKitSeedPaymentProfile {
  const ArxaKitSeedCancel();
}

/// [requestPayment] awaits [duration] then resolves with [ArxaKitPaymentError] — the
/// honest mapping of a timed-out wallet operation onto the kit's existing
/// vocabulary (a timeout is an error, not a decline and not a cancel). Tests
/// control the duration; the default is intentionally short so suites stay
/// fast.
final class ArxaKitSeedTimeout extends ArxaKitSeedPaymentProfile {
  final Duration duration;
  const ArxaKitSeedTimeout([this.duration = const Duration(milliseconds: 10)]);
}

/// A deterministic, pure-Dart [ArxaKitPaymentsProvider] for tests and demos.
///
/// Implements the exact provider contract the native [ArxaKitPayPaymentsProvider]
/// does (same `id` / `supportedMethods` / `canPay` / `requestPayment` shape)
/// so it plugs into [ArxaKitPaymentsProviderRegistry] and
/// [DefaultArxaKitPaymentsService] unchanged — no call site or service code
/// differs. No `pay` / Stripe / PayPal SDK is touched; the outcome of every
/// request is decided entirely by the current [profile].
///
/// The [profile] is mutable at runtime so a single provider can flip mid-suite
/// (e.g. succeed for the happy path, then decline for the retry path) without
/// re-registering. Defaults to [ArxaKitSeedSucceed] and supports both wallets so the
/// common case needs no configuration.
class ArxaKitSeedPaymentsProvider implements ArxaKitPaymentsProvider {
  final Set<ArxaKitPaymentMethod> _supportedMethods;

  ArxaKitSeedPaymentsProvider({
    this.profile = const ArxaKitSeedSucceed(),
    Set<ArxaKitPaymentMethod> supportedMethods = const {
      ArxaKitPaymentMethod.applePay,
      ArxaKitPaymentMethod.googlePay,
    },
  }) : _supportedMethods = Set.of(supportedMethods);

  @override
  String get id => 'seed';

  @override
  Set<ArxaKitPaymentMethod> get supportedMethods => Set.of(_supportedMethods);

  /// The profile that decides the next [requestPayment] result. Mutable so
  /// tests can flip the outcome between calls without re-registering.
  ArxaKitSeedPaymentProfile profile;

  @override
  Future<bool> canPay(ArxaKitPaymentMethod method) async =>
      _supportedMethods.contains(method);

  @override
  Future<ArxaKitPaymentResult> requestPayment({
    required ArxaKitPaymentConfig config,
    required List<ArxaKitPaymentItem> items,
  }) async {
    final active = profile;
    return switch (active) {
      ArxaKitSeedSucceed() => ArxaKitPaymentSuccess(
          token: 'seed_token_${config.method.wireId}',
          method: config.method,
          raw: const {'provider': 'seed', 'profile': 'succeed'},
        ),
      ArxaKitSeedDecline(:final reason) => ArxaKitPaymentDeclined(reason: reason),
      ArxaKitSeedCancel() => const ArxaKitPaymentCancelled(),
      ArxaKitSeedTimeout(:final duration) => await Future<ArxaKitPaymentResult>.delayed(
          duration,
          () => const ArxaKitPaymentError('Seed payment timed out'),
        ),
    };
  }
}
