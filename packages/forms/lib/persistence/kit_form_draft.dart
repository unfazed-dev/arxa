/// STUB (scheduled: form draft-restore phase).
///
/// Persists a form's in-progress values so a user can leave and resume. The
/// port is defined now so hosts can code against the seam; concrete storage
/// (secure prefs / file) lands in a later phase.
abstract interface class KitFormDraftStore {
  /// Persists [values] under [formId].
  Future<void> save(String formId, Map<String, dynamic> values);

  /// Restores the draft for [formId], or null when none exists.
  Future<Map<String, dynamic>?> restore(String formId);

  /// Clears any draft for [formId].
  Future<void> clear(String formId);
}

/// STUB placeholder: an in-memory [KitFormDraftStore] (lost on restart).
///
/// Useful for tests and wiring the seam; swap for durable storage in the draft
/// phase.
class KitInMemoryDraftStore implements KitFormDraftStore {
  final Map<String, Map<String, dynamic>> _drafts = {};

  @override
  Future<void> save(String formId, Map<String, dynamic> values) async {
    _drafts[formId] = Map<String, dynamic>.of(values);
  }

  @override
  Future<Map<String, dynamic>?> restore(String formId) async {
    final draft = _drafts[formId];
    return draft == null ? null : Map<String, dynamic>.of(draft);
  }

  @override
  Future<void> clear(String formId) async {
    _drafts.remove(formId);
  }
}
