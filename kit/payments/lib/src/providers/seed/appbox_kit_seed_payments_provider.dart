import '../../models/appbox_kit_payment_config.dart';
import '../../models/appbox_kit_payment_item.dart';
import '../../models/appbox_kit_payment_method.dart';
import '../../models/appbox_kit_payment_result.dart';
import '../appbox_kit_payments_provider.dart';

/// The deterministic behaviour a [AppBoxKitSeedPaymentsProvider] fakes for each
/// request. Sealed (mirroring [AppBoxKitPaymentResult] / [AppBoxKitPaymentConfig]) so the
/// `switch` in [AppBoxKitSeedPaymentsProvider.requestPayment] stays exhaustive and the
/// compiler catches any new profile.
///
/// Pure data — no wallet SDK, no platform calls. The point is to make every
/// payment outcome, including the sad paths that are hard to reproduce on a
/// real device, scriptable in CI.
sealed class AppBoxKitSeedPaymentProfile {
  const AppBoxKitSeedPaymentProfile();
}

/// [AppBoxKitSeedPaymentsProvider.requestPayment] resolves immediately with
/// [AppBoxKitPaymentSuccess]. The default profile.
final class AppBoxKitSeedSucceed extends AppBoxKitSeedPaymentProfile {
  const AppBoxKitSeedSucceed();
}

/// [requestPayment] resolves immediately with [AppBoxKitPaymentDeclined]. Set [reason]
/// to surface a provider-style message (insufficient funds, risk block, …) —
/// the same [AppBoxKitPaymentDeclined] shape the Stripe / PayPal providers will emit on
/// a funding failure.
final class AppBoxKitSeedDecline extends AppBoxKitSeedPaymentProfile {
  final String? reason;
  const AppBoxKitSeedDecline({this.reason});
}

/// [requestPayment] resolves immediately with [AppBoxKitPaymentCancelled] — the shape
/// the native [AppBoxKitPayPaymentsProvider] returns when the user dismisses the sheet.
final class AppBoxKitSeedCancel extends AppBoxKitSeedPaymentProfile {
  const AppBoxKitSeedCancel();
}

/// [requestPayment] awaits [duration] then resolves with [AppBoxKitPaymentError] — the
/// honest mapping of a timed-out wallet operation onto the kit's existing
/// vocabulary (a timeout is an error, not a decline and not a cancel). Tests
/// control the duration; the default is intentionally short so suites stay
/// fast.
final class AppBoxKitSeedTimeout extends AppBoxKitSeedPaymentProfile {
  final Duration duration;
  const AppBoxKitSeedTimeout([this.duration = const Duration(milliseconds: 10)]);
}

/// A deterministic, pure-Dart [AppBoxKitPaymentsProvider] for tests and demos.
///
/// Implements the exact provider contract the native [AppBoxKitPayPaymentsProvider]
/// does (same `id` / `supportedMethods` / `canPay` / `requestPayment` shape)
/// so it plugs into [AppBoxKitPaymentsProviderRegistry] and
/// [DefaultAppBoxKitPaymentsService] unchanged — no call site or service code
/// differs. No `pay` / Stripe / PayPal SDK is touched; the outcome of every
/// request is decided entirely by the current [profile].
///
/// The [profile] is mutable at runtime so a single provider can flip mid-suite
/// (e.g. succeed for the happy path, then decline for the retry path) without
/// re-registering. Defaults to [AppBoxKitSeedSucceed] and supports both wallets so the
/// common case needs no configuration.
class AppBoxKitSeedPaymentsProvider implements AppBoxKitPaymentsProvider {
  final Set<AppBoxKitPaymentMethod> _supportedMethods;

  AppBoxKitSeedPaymentsProvider({
    this.profile = const AppBoxKitSeedSucceed(),
    Set<AppBoxKitPaymentMethod> supportedMethods = const {
      AppBoxKitPaymentMethod.applePay,
      AppBoxKitPaymentMethod.googlePay,
    },
  }) : _supportedMethods = Set.of(supportedMethods);

  @override
  String get id => 'seed';

  @override
  Set<AppBoxKitPaymentMethod> get supportedMethods => Set.of(_supportedMethods);

  /// The profile that decides the next [requestPayment] result. Mutable so
  /// tests can flip the outcome between calls without re-registering.
  AppBoxKitSeedPaymentProfile profile;

  @override
  Future<bool> canPay(AppBoxKitPaymentMethod method) async =>
      _supportedMethods.contains(method);

  @override
  Future<AppBoxKitPaymentResult> requestPayment({
    required AppBoxKitPaymentConfig config,
    required List<AppBoxKitPaymentItem> items,
  }) async {
    final active = profile;
    return switch (active) {
      AppBoxKitSeedSucceed() => AppBoxKitPaymentSuccess(
          token: 'seed_token_${config.method.wireId}',
          method: config.method,
          raw: const {'provider': 'seed', 'profile': 'succeed'},
        ),
      AppBoxKitSeedDecline(:final reason) => AppBoxKitPaymentDeclined(reason: reason),
      AppBoxKitSeedCancel() => const AppBoxKitPaymentCancelled(),
      AppBoxKitSeedTimeout(:final duration) => await Future<AppBoxKitPaymentResult>.delayed(
          duration,
          () => const AppBoxKitPaymentError('Seed payment timed out'),
        ),
    };
  }
}
