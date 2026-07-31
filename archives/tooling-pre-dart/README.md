# tooling-pre-dart

Archive for Python, bash, and Node tooling superseded by the Dart-only
consolidation (docs/plans/appbox-dart-only-tooling.md).

**Nothing here yet** — files move here as each Dart replacement proves
identical output via golden-diff testing (plan §4: strangler pattern).

## Archive policy

- Nothing retired is deleted — it moves here.
- Each retired piece arrives with a note: what replaced it, when, and
  the golden-diff evidence that approved the swap.
- `tools/vendor/VENDOR.lock` and `check_freshness.sh` retire here last
  (there is no upstream left to sync once appbox is self-contained).

## Scope

The app-box repo only. The `stacked_kit` and `flutter-crew` sibling repos
are never archived, moved, or deleted by this plan — they live on
independently.
