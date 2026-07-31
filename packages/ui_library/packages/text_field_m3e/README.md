# text_field_m3e

Material 3 Expressive text field for `ui_library`. The container shape morphs
between its resting silhouette (`round` / `square`) and a squarer focused radius,
mirroring the pressed/open morph the M3E collection uses for split button,
toolbar, and FAB.

Consumed by `ui_library/lib/widgets/kit_native_textfield.dart` as the Android/M3E
branch of `KitNativeTextField`.

## Provenance — first-party

**This is original `stacked_kit` code, not a vendored third-party fork.** It is
covered by the repository's [`LICENSE`](../../../LICENSE) like any other
first-party package.

It is written *against* `m3e_design` (MIT) for tokens, but it is not a copy or
fork of any upstream package — the M3E collection has never shipped a text field.

This needs saying because the package spent time in `ui_library/vendor/`, which
holds genuine third-party forks. It was swept in there by commit `3d4b4c2`
("fold m3e forks, cupertino_native_better, text_field_m3e into ui_library/vendor")
along with the real forks, and its `pubspec.yaml` carried a `repository:` field
pointing at `EmilyMoonstone/material_3_expressive/tree/main/packages/text_field_m3e`
— a path that has never existed. Both the location and the field implied an
upstream owner that isn't real.

Corrected 2026-07-26: moved to `ui_library/packages/`, false `repository:` and
`issue_tracker:` fields removed, `publish_to: none` added.

Origin: p2 commit `6817d19` (2026-07-14), *"feat(text_field_m3e): new M3E text
field package with focus shape-morph, tokens, and widget tests"* — 682 LOC
including a 130-line widget test suite, authored by the repository owner.

## Note on the SDK pin

`sdk: ^3.9.2` is tighter than the kit-wide `>=3.0.3 <4.0.0`, inherited from
`m3e_design ^0.2.0`. Left as-is deliberately: a tighter pin can't loosen the
resolved floor, and relaxing it would claim a Dart 3.0.3 compatibility this
code has never been tested against.

## Tests

```sh
cd ui_library/packages/text_field_m3e && flutter test
```
