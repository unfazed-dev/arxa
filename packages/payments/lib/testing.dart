/// Scriptable fakes for `appbox_kit_payments`. Import ONLY from tests /
/// storybook wiring:
///
/// ```dart
/// import 'package:appbox_kit_payments/testing.dart';
/// ```
///
/// Nothing here touches the `pay` plugin, so these run on a plain Dart test
/// host with no platform channels.
library;

import 'src/models/kit_payment_config.dart';
import 'src/models/kit_payment_item.dart';
import 'src/models/kit_payment_method.dart';
import 'src/models/payment_result.dart';
import 'src/providers/kit_payments_provider.dart';
import 'src/service/kit_payments_service.dart';

export 'src/models/kit_payment_config.dart';
export 'src/models/kit_payment_item.dart';
export 'src/models/kit_payment_method.dart';
export 'src/models/payment_result.dart';

/// A [KitPaymentsService] whose answers you script. [canPay] is driven by a
/// per-method map; [requestPayment] returns each entry of [results] in turn,
/// falling back to [defaultResult] once the script is exhausted.
///
/// The four outcomes are all directly scriptable — build a sequence out of
/// [PaymentSuccess], [PaymentCancelled], [PaymentDeclined] and [PaymentError]
/// to exercise every branch of a ViewModel's result handling.
class FakeKitPaymentsService implements KitPaymentsService {
  /// Per-method availability returned by [canPay]. Missing method ⇒ false.
  final Map<KitPaymentMethod, bool> canPayByMethod;

  /// Results handed out by [requestPayment], in order.
  final List<PaymentResult> results;

  /// Returned once [results] is exhausted (defaults to user cancellation).
  final PaymentResult defaultResult;

  int _cursor = 0;

  /// Every [canPay] argument, in call order — for test assertions.
  final List<KitPaymentMethod> canPayCalls = [];

  /// Every [requestPayment] invocation, in call order — for test assertions.
  final List<({KitPaymentConfig config, List<KitPaymentItem> items})>
      requestPaymentCalls = [];

  FakeKitPaymentsService({
    Map<KitPaymentMethod, bool>? canPayByMethod,
    List<PaymentResult>? results,
    this.defaultResult = const PaymentCancelled(),
  })  : canPayByMethod = canPayByMethod ?? const {},
        results = results ?? const [];

  /// canPay ⇒ true for every method, and every payment succeeds with [token].
  factory FakeKitPaymentsService.alwaysSucceeds({
    String token = 'fake-token',
  }) =>
      FakeKitPaymentsService(
        canPayByMethod: {
          for (final m in KitPaymentMethod.values) m: true,
        },
        defaultResult: PaymentSuccess(
          token: token,
          method: KitPaymentMethod.applePay,
        ),
      );

  /// canPay ⇒ true, but every payment is dismissed by the user.
  factory FakeKitPaymentsService.alwaysCancels() => FakeKitPaymentsService(
        canPayByMethod: {for (final m in KitPaymentMethod.values) m: true},
        defaultResult: const PaymentCancelled(),
      );

  /// canPay ⇒ true, but every payment is declined.
  factory FakeKitPaymentsService.alwaysDeclined({String? reason}) =>
      FakeKitPaymentsService(
        canPayByMethod: {for (final m in KitPaymentMethod.values) m: true},
        defaultResult: PaymentDeclined(reason: reason),
      );

  /// canPay ⇒ true, but every payment errors.
  factory FakeKitPaymentsService.alwaysErrors({String message = 'fake error'}) =>
      FakeKitPaymentsService(
        canPayByMethod: {for (final m in KitPaymentMethod.values) m: true},
        defaultResult: PaymentError(message),
      );

  @override
  Future<bool> canPay(KitPaymentMethod method) async {
    canPayCalls.add(method);
    return canPayByMethod[method] ?? false;
  }

  @override
  Future<PaymentResult> requestPayment({
    required KitPaymentConfig config,
    required List<KitPaymentItem> items,
  }) async {
    requestPaymentCalls.add((config: config, items: items));
    if (_cursor < results.length) return results[_cursor++];
    return defaultResult;
  }
}

/// A scriptable [KitPaymentsProvider] for exercising the registry / routing
/// layer directly. Same scripting model as [FakeKitPaymentsService].
class FakePaymentsProvider implements KitPaymentsProvider {
  @override
  final String id;

  @override
  final Set<KitPaymentMethod> supportedMethods;

  final Map<KitPaymentMethod, bool> canPayByMethod;
  final List<PaymentResult> results;
  final PaymentResult defaultResult;

  int _cursor = 0;

  FakePaymentsProvider({
    this.id = 'fake',
    Set<KitPaymentMethod>? supportedMethods,
    Map<KitPaymentMethod, bool>? canPayByMethod,
    List<PaymentResult>? results,
    this.defaultResult = const PaymentCancelled(),
  })  : supportedMethods =
            supportedMethods ?? KitPaymentMethod.values.toSet(),
        canPayByMethod = canPayByMethod ?? const {},
        results = results ?? const [];

  @override
  Future<bool> canPay(KitPaymentMethod method) async =>
      canPayByMethod[method] ?? false;

  @override
  Future<PaymentResult> requestPayment({
    required KitPaymentConfig config,
    required List<KitPaymentItem> items,
  }) async {
    if (_cursor < results.length) return results[_cursor++];
    return defaultResult;
  }
}
