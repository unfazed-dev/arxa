/// Scriptable fakes for `appbox_kit_payments`. Import ONLY from tests /
/// storybook wiring:
///
/// ```dart
/// import 'package:appbox_kit_payments/appbox_kit_testing.dart';
/// ```
///
/// Nothing here touches the `pay` plugin, so these run on a plain Dart test
/// host with no platform channels.
library;

import 'src/models/appbox_kit_payment_config.dart';
import 'src/models/appbox_kit_payment_item.dart';
import 'src/models/appbox_kit_payment_method.dart';
import 'src/models/appbox_kit_payment_result.dart';
import 'src/providers/appbox_kit_payments_provider.dart';
import 'src/service/appbox_kit_payments_service.dart';

export 'src/models/appbox_kit_payment_config.dart';
export 'src/models/appbox_kit_payment_item.dart';
export 'src/models/appbox_kit_payment_method.dart';
export 'src/models/appbox_kit_payment_result.dart';

/// A [AppBoxKitPaymentsService] whose answers you script. [canPay] is driven by a
/// per-method map; [requestPayment] returns each entry of [results] in turn,
/// falling back to [defaultResult] once the script is exhausted.
///
/// The four outcomes are all directly scriptable — build a sequence out of
/// [AppBoxKitPaymentSuccess], [AppBoxKitPaymentCancelled], [AppBoxKitPaymentDeclined] and [AppBoxKitPaymentError]
/// to exercise every branch of a ViewModel's result handling.
class FakeAppBoxKitPaymentsService implements AppBoxKitPaymentsService {
  /// Per-method availability returned by [canPay]. Missing method ⇒ false.
  final Map<AppBoxKitPaymentMethod, bool> canPayByMethod;

  /// Results handed out by [requestPayment], in order.
  final List<AppBoxKitPaymentResult> results;

  /// Returned once [results] is exhausted (defaults to user cancellation).
  final AppBoxKitPaymentResult defaultResult;

  int _cursor = 0;

  /// Every [canPay] argument, in call order — for test assertions.
  final List<AppBoxKitPaymentMethod> canPayCalls = [];

  /// Every [requestPayment] invocation, in call order — for test assertions.
  final List<({AppBoxKitPaymentConfig config, List<AppBoxKitPaymentItem> items})>
      requestPaymentCalls = [];

  FakeAppBoxKitPaymentsService({
    Map<AppBoxKitPaymentMethod, bool>? canPayByMethod,
    List<AppBoxKitPaymentResult>? results,
    this.defaultResult = const AppBoxKitPaymentCancelled(),
  })  : canPayByMethod = canPayByMethod ?? const {},
        results = results ?? const [];

  /// canPay ⇒ true for every method, and every payment succeeds with [token].
  factory FakeAppBoxKitPaymentsService.alwaysSucceeds({
    String token = 'fake-token',
  }) =>
      FakeAppBoxKitPaymentsService(
        canPayByMethod: {
          for (final m in AppBoxKitPaymentMethod.values) m: true,
        },
        defaultResult: AppBoxKitPaymentSuccess(
          token: token,
          method: AppBoxKitPaymentMethod.applePay,
        ),
      );

  /// canPay ⇒ true, but every payment is dismissed by the user.
  factory FakeAppBoxKitPaymentsService.alwaysCancels() => FakeAppBoxKitPaymentsService(
        canPayByMethod: {for (final m in AppBoxKitPaymentMethod.values) m: true},
        defaultResult: const AppBoxKitPaymentCancelled(),
      );

  /// canPay ⇒ true, but every payment is declined.
  factory FakeAppBoxKitPaymentsService.alwaysDeclined({String? reason}) =>
      FakeAppBoxKitPaymentsService(
        canPayByMethod: {for (final m in AppBoxKitPaymentMethod.values) m: true},
        defaultResult: AppBoxKitPaymentDeclined(reason: reason),
      );

  /// canPay ⇒ true, but every payment errors.
  factory FakeAppBoxKitPaymentsService.alwaysErrors({String message = 'fake error'}) =>
      FakeAppBoxKitPaymentsService(
        canPayByMethod: {for (final m in AppBoxKitPaymentMethod.values) m: true},
        defaultResult: AppBoxKitPaymentError(message),
      );

  @override
  Future<bool> canPay(AppBoxKitPaymentMethod method) async {
    canPayCalls.add(method);
    return canPayByMethod[method] ?? false;
  }

  @override
  Future<AppBoxKitPaymentResult> requestPayment({
    required AppBoxKitPaymentConfig config,
    required List<AppBoxKitPaymentItem> items,
  }) async {
    requestPaymentCalls.add((config: config, items: items));
    if (_cursor < results.length) return results[_cursor++];
    return defaultResult;
  }
}

/// A scriptable [AppBoxKitPaymentsProvider] for exercising the registry / routing
/// layer directly. Same scripting model as [FakeAppBoxKitPaymentsService].
class FakeAppBoxKitPaymentsProvider implements AppBoxKitPaymentsProvider {
  @override
  final String id;

  @override
  final Set<AppBoxKitPaymentMethod> supportedMethods;

  final Map<AppBoxKitPaymentMethod, bool> canPayByMethod;
  final List<AppBoxKitPaymentResult> results;
  final AppBoxKitPaymentResult defaultResult;

  int _cursor = 0;

  FakeAppBoxKitPaymentsProvider({
    this.id = 'fake',
    Set<AppBoxKitPaymentMethod>? supportedMethods,
    Map<AppBoxKitPaymentMethod, bool>? canPayByMethod,
    List<AppBoxKitPaymentResult>? results,
    this.defaultResult = const AppBoxKitPaymentCancelled(),
  })  : supportedMethods =
            supportedMethods ?? AppBoxKitPaymentMethod.values.toSet(),
        canPayByMethod = canPayByMethod ?? const {},
        results = results ?? const [];

  @override
  Future<bool> canPay(AppBoxKitPaymentMethod method) async =>
      canPayByMethod[method] ?? false;

  @override
  Future<AppBoxKitPaymentResult> requestPayment({
    required AppBoxKitPaymentConfig config,
    required List<AppBoxKitPaymentItem> items,
  }) async {
    if (_cursor < results.length) return results[_cursor++];
    return defaultResult;
  }
}
