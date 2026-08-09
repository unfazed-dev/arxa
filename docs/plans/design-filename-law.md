# Law: designer filenames — no leading underscore, no version prefixes

Date: 2026-08-09. Session: v2 bug sweep (route-table hot-reload fix + renames).

## Ruling (user)

1. **No leading `_`** in any designer-generated filename. `_panel.tsx` → `panel.tsx`.
   The emitted tree has no "private module" convention; a base module's role is
   stated by its name, not by punctuation.
2. **No version/era prefixes** (`v1_`, `v2_`, …). `v1_strings.tsx` → the showcase
   kit name the scaffolder will receive: `appbox_kit_app_strings.tsx` (mirrors
   `appbox_kit_app_strings.dart` in the Flutter kit mirror — SKILL.md §kit).
3. **General principle**: filenames follow showcase-app naming conventions
   (`references/showcase-anatomy.md`); they describe role in design vocabulary,
   never history or visibility. Applies to all files a designer writes into an
   artifact.

## Renames performed (designs/appbox-studio-v2, git mv)

- `ui/common/v1_strings.tsx` → `ui/common/appbox_kit_app_strings.tsx`
  (zero importers today — created for the v1-design port, consumers pending).
- `ui/widgets/studio_application_widgets/_panel.tsx` →
  `ui/widgets/studio_application_widgets/panel.tsx`; import specifiers updated
  in `header_panel.tsx`, `footer_panel.tsx`; header comment de-referenced the
  never-created `ui/common/_integration_panels.md` (dead pointer, now
  self-describing). `npx tsc --noEmit` clean after.

## Gate

The mechanical check joins the pending naming gate (task #4, single-letter law):
fail any tracked artifact file matching `(^|/)_[^_]` or `(^|/)v[0-9]+_` under
`designs/*/ui/**` and `designs/*/services/**`.

## Notes

- Law prose lives in `skills/appbox-designer/SKILL.md` ("Filename law (locked)").
- SSOT procedure per `docs/plans/no-single-letter-identifiers-law.md`: edit
  `skills/appbox-designer` (git SSOT), rsync → `.claude/skills/appbox-designer`.
- Advisor unavailable this session (consult-z HTTP 429, balance exhausted).
