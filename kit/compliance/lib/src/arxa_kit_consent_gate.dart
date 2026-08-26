import 'package:flutter/foundation.dart';

import 'arxa_kit_compliance_document.dart';
import 'arxa_kit_consent_service.dart';

/// The outcome of evaluating whether the app may proceed past its compliance
/// gate. Pure logic — presents no UI.
@immutable
sealed class ArxaKitConsentGateResult {
  const ArxaKitConsentGateResult();

  /// All required documents are satisfied; the app may proceed.
  const factory ArxaKitConsentGateResult.allowed() = ArxaKitConsentGateAllowed;

  /// [outstanding] documents must be presented and accepted first, in registry
  /// order.
  const factory ArxaKitConsentGateResult.blocked(
      List<ArxaKitComplianceDocument> outstanding) = ArxaKitConsentGateBlocked;

  /// Whether the app may proceed.
  bool get canProceed => this is ArxaKitConsentGateAllowed;
}

/// The gate is satisfied.
@immutable
final class ArxaKitConsentGateAllowed extends ArxaKitConsentGateResult {
  const ArxaKitConsentGateAllowed();

  @override
  bool operator ==(Object other) =>
      other is ArxaKitConsentGateAllowed && runtimeType == other.runtimeType;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => 'ArxaKitConsentGateAllowed()';
}

/// The gate is blocked on [outstanding] documents (in registry order).
@immutable
final class ArxaKitConsentGateBlocked extends ArxaKitConsentGateResult {
  const ArxaKitConsentGateBlocked(this.outstanding);

  /// The documents that must be accepted, in registry order.
  final List<ArxaKitComplianceDocument> outstanding;

  @override
  bool operator ==(Object other) =>
      other is ArxaKitConsentGateBlocked &&
      listEquals(outstanding, other.outstanding);

  @override
  int get hashCode => Object.hashAll(outstanding);

  @override
  String toString() =>
      'ArxaKitConsentGateBlocked(${outstanding.length} outstanding)';
}

/// Computes a [ArxaKitConsentGateResult] from a [ArxaKitConsentService].
///
/// The evaluation runs against the registry and store the [service] was built
/// with — the gate holds no independent state.
class ArxaKitConsentGate {
  const ArxaKitConsentGate(this._service);

  final ArxaKitConsentService _service;

  /// Evaluates the gate against the current registry + store state.
  Future<ArxaKitConsentGateResult> evaluate() async {
    final outstanding = await _service.outstandingDocuments();
    if (outstanding.isEmpty) return const ArxaKitConsentGateResult.allowed();
    return ArxaKitConsentGateBlocked(
        List<ArxaKitComplianceDocument>.unmodifiable(outstanding));
  }
}
