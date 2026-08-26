import 'dart:async';

import 'package:flutter/foundation.dart';

import 'arxa_kit_compliance_document.dart';
import 'arxa_kit_compliance_registry.dart';
import 'arxa_kit_consent_record.dart';
import 'arxa_kit_consent_status.dart';
import 'arxa_kit_consent_store.dart';

/// A status change emitted on [ArxaKitConsentService.statusChanges].
@immutable
final class ArxaKitConsentStatusChange {
  const ArxaKitConsentStatusChange({required this.document, required this.status});

  final ArxaKitComplianceDocument document;
  final ArxaKitConsentStatus status;

  @override
  bool operator ==(Object other) =>
      other is ArxaKitConsentStatusChange &&
      document == other.document &&
      status == other.status;

  @override
  int get hashCode => Object.hash(document, status);

  @override
  String toString() => 'ArxaKitConsentStatusChange(${document.id}: $status)';
}

/// Reads and mutates consent for a single user track — the [userId] supplied at
/// construction (null = the anonymous track) — on top of a [ArxaKitConsentStore]
/// and a [ArxaKitComplianceRegistry].
///
/// [accept] and [withdraw] write to the store and push a
/// [ArxaKitConsentStatusChange] on the broadcast [statusChanges] stream. Call
/// [dispose] to release that stream.
class ArxaKitConsentService {
  ArxaKitConsentService({
    required ArxaKitConsentStore store,
    required ArxaKitComplianceRegistry registry,
    this.userId,
  })  : _store = store,
        _registry = registry;

  final ArxaKitConsentStore _store;
  final ArxaKitComplianceRegistry _registry;

  /// The user track this service reads and writes (null = anonymous).
  final String? userId;

  final StreamController<ArxaKitConsentStatusChange> _changes =
      StreamController<ArxaKitConsentStatusChange>.broadcast();

  /// Status changes produced by [accept] / [withdraw] on this service.
  Stream<ArxaKitConsentStatusChange> get statusChanges => _changes.stream;

  /// The consent status of [document] on this service's track.
  ///
  /// A document that does not require explicit acceptance is always
  /// [ArxaKitConsentNotRequired], irrespective of any implicit records.
  Future<ArxaKitConsentStatus> statusFor(ArxaKitComplianceDocument document) async {
    if (!document.requiresExplicitAcceptance) {
      return const ArxaKitConsentStatus.notRequired();
    }
    final latest = await _store.latestFor(document.id, userId: userId);
    if (latest == null) return const ArxaKitConsentStatus.neverAccepted();
    if (latest.method == ArxaKitConsentMethod.withdrawn) {
      return const ArxaKitConsentStatus.withdrawn();
    }
    if (latest.documentVersion == document.version) {
      return const ArxaKitConsentStatus.accepted();
    }
    return ArxaKitConsentStatus.acceptedOutdatedVersion(latest.documentVersion);
  }

  /// Records acceptance of [document] on this track and emits the new status.
  ///
  /// [method] defaults to [ArxaKitConsentMethod.explicitTap]; pass
  /// [ArxaKitConsentMethod.implicitContinue] to record implicit consent (e.g. for a
  /// document that does not require explicit acceptance).
  Future<void> accept(
    ArxaKitComplianceDocument document, {
    required String appVersion,
    ArxaKitConsentMethod method = ArxaKitConsentMethod.explicitTap,
    DateTime? at,
  }) async {
    await _store.record(ArxaKitConsentRecord(
      documentId: document.id,
      documentVersion: document.version,
      userId: userId,
      acceptedAt: at ?? DateTime.now(),
      method: method,
      appVersion: appVersion,
    ));
    await _emit(document);
  }

  /// Records a withdrawal of [document] on this track and emits the new status.
  Future<void> withdraw(
    ArxaKitComplianceDocument document, {
    required String appVersion,
    DateTime? at,
  }) async {
    await _store.withdraw(
      documentId: document.id,
      documentVersion: document.version,
      appVersion: appVersion,
      userId: userId,
      at: at,
    );
    await _emit(document);
  }

  /// The documents in the registry that require explicit acceptance and whose
  /// current version is not satisfied on this track, in registry order.
  Future<List<ArxaKitComplianceDocument>> outstandingDocuments() async {
    final outstanding = <ArxaKitComplianceDocument>[];
    for (final document in _registry.currentDocuments) {
      if (!document.requiresExplicitAcceptance) continue;
      final status = await statusFor(document);
      if (!status.isSatisfied) outstanding.add(document);
    }
    return List<ArxaKitComplianceDocument>.unmodifiable(outstanding);
  }

  /// Releases the status-change stream. Call when disposing the service.
  Future<void> dispose() => _changes.close();

  Future<void> _emit(ArxaKitComplianceDocument document) async {
    if (_changes.isClosed) return;
    _changes.add(ArxaKitConsentStatusChange(
        document: document, status: await statusFor(document)));
  }
}
