import 'appbox_kit_compliance_document.dart';

/// An in-memory registry of the app's compliance documents.
///
/// Documents are keyed by [AppBoxKitComplianceDocument.id]; registering an id again
/// replaces it in place (its registration position is preserved). [currentFor]
/// returns the most-recently-registered document of a kind, and
/// [currentDocuments] lists one document per kind in registration order — the
/// order the consent gate presents outstanding documents.
class AppBoxKitComplianceRegistry {
  final Map<String, AppBoxKitComplianceDocument> _byId =
      <String, AppBoxKitComplianceDocument>{};

  /// Registers (or replaces, by id) [document].
  void register(AppBoxKitComplianceDocument document) {
    _byId[document.id] = document;
  }

  /// Registers each of [documents] in iteration order.
  void registerAll(Iterable<AppBoxKitComplianceDocument> documents) {
    for (final document in documents) {
      register(document);
    }
  }

  /// The document with [id], or null.
  AppBoxKitComplianceDocument? byId(String id) => _byId[id];

  /// Every registered document, in registration order.
  List<AppBoxKitComplianceDocument> get all =>
      List<AppBoxKitComplianceDocument>.unmodifiable(_byId.values);

  /// The current (most-recently-registered) document of [kind], or null.
  AppBoxKitComplianceDocument? currentFor(AppBoxKitComplianceDocumentKind kind) {
    AppBoxKitComplianceDocument? current;
    for (final document in _byId.values) {
      if (document.kind == kind) current = document;
    }
    return current;
  }

  /// One document per kind — the current version of each — ordered by the
  /// registration position of the first document seen for that kind.
  List<AppBoxKitComplianceDocument> get currentDocuments {
    final order = <AppBoxKitComplianceDocumentKind>[];
    final current = <AppBoxKitComplianceDocumentKind, AppBoxKitComplianceDocument>{};
    for (final document in _byId.values) {
      if (!current.containsKey(document.kind)) order.add(document.kind);
      current[document.kind] = document;
    }
    return List<AppBoxKitComplianceDocument>.unmodifiable(
        [for (final kind in order) current[kind]!]);
  }

  /// Removes all registered documents.
  void clear() => _byId.clear();
}
