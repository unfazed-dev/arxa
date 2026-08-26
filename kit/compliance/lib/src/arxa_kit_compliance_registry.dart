import 'arxa_kit_compliance_document.dart';

/// An in-memory registry of the app's compliance documents.
///
/// Documents are keyed by [ArxaKitComplianceDocument.id]; registering an id again
/// replaces it in place (its registration position is preserved). [currentFor]
/// returns the most-recently-registered document of a kind, and
/// [currentDocuments] lists one document per kind in registration order — the
/// order the consent gate presents outstanding documents.
class ArxaKitComplianceRegistry {
  final Map<String, ArxaKitComplianceDocument> _byId =
      <String, ArxaKitComplianceDocument>{};

  /// Registers (or replaces, by id) [document].
  void register(ArxaKitComplianceDocument document) {
    _byId[document.id] = document;
  }

  /// Registers each of [documents] in iteration order.
  void registerAll(Iterable<ArxaKitComplianceDocument> documents) {
    for (final document in documents) {
      register(document);
    }
  }

  /// The document with [id], or null.
  ArxaKitComplianceDocument? byId(String id) => _byId[id];

  /// Every registered document, in registration order.
  List<ArxaKitComplianceDocument> get all =>
      List<ArxaKitComplianceDocument>.unmodifiable(_byId.values);

  /// The current (most-recently-registered) document of [kind], or null.
  ArxaKitComplianceDocument? currentFor(ArxaKitComplianceDocumentKind kind) {
    ArxaKitComplianceDocument? current;
    for (final document in _byId.values) {
      if (document.kind == kind) current = document;
    }
    return current;
  }

  /// One document per kind — the current version of each — ordered by the
  /// registration position of the first document seen for that kind.
  List<ArxaKitComplianceDocument> get currentDocuments {
    final order = <ArxaKitComplianceDocumentKind>[];
    final current = <ArxaKitComplianceDocumentKind, ArxaKitComplianceDocument>{};
    for (final document in _byId.values) {
      if (!current.containsKey(document.kind)) order.add(document.kind);
      current[document.kind] = document;
    }
    return List<ArxaKitComplianceDocument>.unmodifiable(
        [for (final kind in order) current[kind]!]);
  }

  /// Removes all registered documents.
  void clear() => _byId.clear();
}
