/// Scriptable fakes for `arxa_kit_payments`. Import ONLY from tests /
/// storybook wiring:
///
/// ```dart
/// import 'package:arxa_kit_payments/arxa_kit_testing.dart';
/// ```
///
/// Nothing here touches the `pay` plugin, so these run on a plain Dart test
/// host with no platform channels.
library;

import 'src/models/arxa_kit_payment_config.dart';
import 'src/models/arxa_kit_payment_item.dart';
import 'src/models/arxa_kit_payment_method.dart';
import 'src/models/arxa_kit_payment_result.dart';
import 'src/providers/arxa_kit_payments_provider.dart';
import 'src/service/arxa_kit_payments_service.dart';

export 'src/models/arxa_kit_payment_config.dart';
export 'src/models/arxa_kit_payment_item.dart';
export 'src/models/arxa_kit_payment_method.dart';
export 'src/models/arxa_kit_payment_result.dart';

/// A [ArxaKitPaymentsService] whose answers you script. [canPay] is driven by a
/// per-method map; [requestPayment] returns each entry of [results] in turn,
/// falling back to [defaultResult] once the script is exhausted.
///
/// The four outcomes are all directly scriptable — build a sequence out of
/// [ArxaKitPaymentSuccess], [ArxaKitPaymentCancelled], [ArxaKitPaymentDeclined] and [ArxaKitPaymentError]
/// to exercise every branch of a ViewModel's result handling.
class FakeArxaKitPaymentsService implements ArxaKitPaymentsService {
  /// Per-method availability returned by [canPay]. Missing method ⇒ false.
  final Map<ArxaKitPaymentMethod, bool> canPayByMethod;

  /// Results handed out by [requestPayment], in order.
  final List<ArxaKitPaymentResult> results;

  /// Returned once [results] is exhausted (defaults to user cancellation).
  final ArxaKitPaymentResult defaultResult;

  int _cursor = 0;

  /// Every [canPay] argument, in call order — for test assertions.
  final List<ArxaKitPaymentMethod> canPayCalls = [];

  /// Every [requestPayment] invocation, in call order — for test assertions.
  final List<({ArxaKitPaymentConfig config, List<ArxaKitPaymentItem> items})>
      requestPaymentCalls = [];

  FakeArxaKitPaymentsService({
    Map<ArxaKitPaymentMethod, bool>? canPayByMethod,
    List<ArxaKitPaymentResult>? results,
    this.defaultResult = const ArxaKitPaymentCancelled(),
  })  : canPayByMethod = canPayByMethod ?? const {},
        results = results ?? const [];

  /// canPay ⇒ true for every method, and every payment succeeds with [token].
  factory FakeArxaKitPaymentsService.alwaysSucceeds({
    String token = 'fake-token',
  }) =>
      FakeArxaKitPaymentsService(
        canPayByMethod: {
          for (final m in ArxaKitPaymentMethod.values) m: true,
        },
        defaultResult: ArxaKitPaymentSuccess(
          token: token,
          method: ArxaKitPaymentMethod.applePay,
        ),
      );

  /// canPay ⇒ true, but every payment is dismissed by the user.
  factory FakeArxaKitPaymentsService.alwaysCancels() => FakeArxaKitPaymentsService(
        canPayByMethod: {for (final m in ArxaKitPaymentMethod.values) m: true},
        defaultResult: const ArxaKitPaymentCancelled(),
      );

  /// canPay ⇒ true, but every payment is declined.
  factory FakeArxaKitPaymentsService.alwaysDeclined({String? reason}) =>
      FakeArxaKitPaymentsService(
        canPayByMethod: {for (final m in ArxaKitPaymentMethod.values) m: true},
        defaultResult: ArxaKitPaymentDeclined(reason: reason),
      );

  /// canPay ⇒ true, but every payment errors.
  factory FakeArxaKitPaymentsService.alwaysErrors({String message = 'fake error'}) =>
      FakeArxaKitPaymentsService(
        canPayByMethod: {for (final m in ArxaKitPaymentMethod.values) m: true},
        defaultResult: ArxaKitPaymentError(message),
      );

  @override
  Future<bool> canPay(ArxaKitPaymentMethod method) async {
    canPayCalls.add(method);
    return canPayByMethod[method] ?? false;
  }

  @override
  Future<ArxaKitPaymentResult> requestPayment({
    required ArxaKitPaymentConfig config,
    required List<ArxaKitPaymentItem> items,
  }) async {
    requestPaymentCalls.add((config: config, items: items));
    if (_cursor < results.length) return results[_cursor++];
    return defaultResult;
  }
}

/// A scriptable [ArxaKitPaymentsProvider] for exercising the registry / routing
/// layer directly. Same scripting model as [FakeArxaKitPaymentsService].
class FakeArxaKitPaymentsProvider implements ArxaKitPaymentsProvider {
  @override
  final String id;

  @override
  final Set<ArxaKitPaymentMethod> supportedMethods;

  final Map<ArxaKitPaymentMethod, bool> canPayByMethod;
  final List<ArxaKitPaymentResult> results;
  final ArxaKitPaymentResult defaultResult;

  int _cursor = 0;

  FakeArxaKitPaymentsProvider({
    this.id = 'fake',
    Set<ArxaKitPaymentMethod>? supportedMethods,
    Map<ArxaKitPaymentMethod, bool>? canPayByMethod,
    List<ArxaKitPaymentResult>? results,
    this.defaultResult = const ArxaKitPaymentCancelled(),
  })  : supportedMethods =
            supportedMethods ?? ArxaKitPaymentMethod.values.toSet(),
        canPayByMethod = canPayByMethod ?? const {},
        results = results ?? const [];

  @override
  Future<bool> canPay(ArxaKitPaymentMethod method) async =>
      canPayByMethod[method] ?? false;

  @override
  Future<ArxaKitPaymentResult> requestPayment({
    required ArxaKitPaymentConfig config,
    required List<ArxaKitPaymentItem> items,
  }) async {
    if (_cursor < results.length) return results[_cursor++];
    return defaultResult;
  }
}
