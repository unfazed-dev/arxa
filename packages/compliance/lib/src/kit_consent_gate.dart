import 'package:flutter/foundation.dart';

import 'kit_compliance_document.dart';
import 'kit_consent_service.dart';

/// The outcome of evaluating whether the app may proceed past its compliance
/// gate. Pure logic — presents no UI.
@immutable
sealed class KitConsentGateResult {
  const KitConsentGateResult();

  /// All required documents are satisfied; the app may proceed.
  const factory KitConsentGateResult.allowed() = KitConsentGateAllowed;

  /// [outstanding] documents must be presented and accepted first, in registry
  /// order.
  const factory KitConsentGateResult.blocked(
      List<KitComplianceDocument> outstanding) = KitConsentGateBlocked;

  /// Whether the app may proceed.
  bool get canProceed => this is KitConsentGateAllowed;
}

/// The gate is satisfied.
@immutable
final class KitConsentGateAllowed extends KitConsentGateResult {
  const KitConsentGateAllowed();

  @override
  bool operator ==(Object other) =>
      other is KitConsentGateAllowed && runtimeType == other.runtimeType;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => 'KitConsentGateAllowed()';
}

/// The gate is blocked on [outstanding] documents (in registry order).
@immutable
final class KitConsentGateBlocked extends KitConsentGateResult {
  const KitConsentGateBlocked(this.outstanding);

  /// The documents that must be accepted, in registry order.
  final List<KitComplianceDocument> outstanding;

  @override
  bool operator ==(Object other) =>
      other is KitConsentGateBlocked &&
      listEquals(outstanding, other.outstanding);

  @override
  int get hashCode => Object.hashAll(outstanding);

  @override
  String toString() =>
      'KitConsentGateBlocked(${outstanding.length} outstanding)';
}

/// Computes a [KitConsentGateResult] from a [KitConsentService].
///
/// The evaluation runs against the registry and store the [service] was built
/// with — the gate holds no independent state.
class KitConsentGate {
  const KitConsentGate(this._service);

  final KitConsentService _service;

  /// Evaluates the gate against the current registry + store state.
  Future<KitConsentGateResult> evaluate() async {
    final outstanding = await _service.outstandingDocuments();
    if (outstanding.isEmpty) return const KitConsentGateResult.allowed();
    return KitConsentGateBlocked(
        List<KitComplianceDocument>.unmodifiable(outstanding));
  }
}
