import 'package:flutter/foundation.dart';

import 'appbox_kit_compliance_document.dart';
import 'appbox_kit_consent_service.dart';

/// The outcome of evaluating whether the app may proceed past its compliance
/// gate. Pure logic — presents no UI.
@immutable
sealed class AppBoxKitConsentGateResult {
  const AppBoxKitConsentGateResult();

  /// All required documents are satisfied; the app may proceed.
  const factory AppBoxKitConsentGateResult.allowed() = AppBoxKitConsentGateAllowed;

  /// [outstanding] documents must be presented and accepted first, in registry
  /// order.
  const factory AppBoxKitConsentGateResult.blocked(
      List<AppBoxKitComplianceDocument> outstanding) = AppBoxKitConsentGateBlocked;

  /// Whether the app may proceed.
  bool get canProceed => this is AppBoxKitConsentGateAllowed;
}

/// The gate is satisfied.
@immutable
final class AppBoxKitConsentGateAllowed extends AppBoxKitConsentGateResult {
  const AppBoxKitConsentGateAllowed();

  @override
  bool operator ==(Object other) =>
      other is AppBoxKitConsentGateAllowed && runtimeType == other.runtimeType;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => 'AppBoxKitConsentGateAllowed()';
}

/// The gate is blocked on [outstanding] documents (in registry order).
@immutable
final class AppBoxKitConsentGateBlocked extends AppBoxKitConsentGateResult {
  const AppBoxKitConsentGateBlocked(this.outstanding);

  /// The documents that must be accepted, in registry order.
  final List<AppBoxKitComplianceDocument> outstanding;

  @override
  bool operator ==(Object other) =>
      other is AppBoxKitConsentGateBlocked &&
      listEquals(outstanding, other.outstanding);

  @override
  int get hashCode => Object.hashAll(outstanding);

  @override
  String toString() =>
      'AppBoxKitConsentGateBlocked(${outstanding.length} outstanding)';
}

/// Computes a [AppBoxKitConsentGateResult] from a [AppBoxKitConsentService].
///
/// The evaluation runs against the registry and store the [service] was built
/// with — the gate holds no independent state.
class AppBoxKitConsentGate {
  const AppBoxKitConsentGate(this._service);

  final AppBoxKitConsentService _service;

  /// Evaluates the gate against the current registry + store state.
  Future<AppBoxKitConsentGateResult> evaluate() async {
    final outstanding = await _service.outstandingDocuments();
    if (outstanding.isEmpty) return const AppBoxKitConsentGateResult.allowed();
    return AppBoxKitConsentGateBlocked(
        List<AppBoxKitComplianceDocument>.unmodifiable(outstanding));
  }
}
