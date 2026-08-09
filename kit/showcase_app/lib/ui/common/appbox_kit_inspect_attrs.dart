// Inspect identity (Q12)

/// The inspect-identity triple, stamped on every emitted view and widget.
///
/// This is the Dart form of the JS shape in
/// `skills/appbox-designer/references/app-architecture.md:169`. The JS object
/// spells the third key `nodeId`; Dart spells it [anatomyNodeId], per
/// `skills/appbox-scaffolder/SKILL.md:263`. Same slot, two spellings — the
/// prose in both documents calls it "anatomy-node id".
///
/// The triple is **stamped at emit time from the frozen artifact, never
/// inferred at runtime** — the same trick as Flutter's
/// `--track-widget-creation`. Studio's inspect mode reads the triple and
/// nothing else: zero widget-tree heuristics, no structural guessing. Inspect
/// therefore survives regeneration by construction rather than by luck.
///
/// This type lives in kit core rather than being emitted into each generated
/// app, for the same reason colors and spacing do (Q6 Tier 1): a shape the
/// scaffolder re-emits per app is a shape that can drift per app. See
/// `skills/appbox-scaffolder/kind-resolution.registry.json`
/// (`designVocabulary.inspectAttrs`).
///
/// Usage — one `static const` per surface:
/// ```dart
/// static const AppBoxKitInspectAttrs inspectAttrs = AppBoxKitInspectAttrs(
///   screenId: 'showcase.notes',
///   surfaceId: 'surface.notes.shell',
///   anatomyNodeId: 'anatomy:view.body',
/// );
/// ```
class AppBoxKitInspectAttrs {
  const AppBoxKitInspectAttrs({
    required this.screenId,
    required this.surfaceId,
    required this.anatomyNodeId,
  });

  /// The registry screen id this surface belongs to.
  final String screenId;

  /// This surface's own id.
  final String surfaceId;

  /// The anatomy node this surface stamps.
  ///
  /// Drawn from the closed vocabulary in
  /// `skills/appbox-scaffolder/kind-resolution.registry.json#/anatomyNodes`.
  /// An id outside that set is a gate failure on both sides — never improvise
  /// one, exactly as with a widget `kind`.
  final String anatomyNodeId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppBoxKitInspectAttrs &&
          other.screenId == screenId &&
          other.surfaceId == surfaceId &&
          other.anatomyNodeId == anatomyNodeId;

  @override
  int get hashCode => Object.hash(screenId, surfaceId, anatomyNodeId);

  @override
  String toString() => 'AppBoxKitInspectAttrs(screenId: $screenId, '
      'surfaceId: $surfaceId, anatomyNodeId: $anatomyNodeId)';
}
