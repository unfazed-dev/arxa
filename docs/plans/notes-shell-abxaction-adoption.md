# Notes-shell abxAction adoption + InkWell ripple fix

Grilled and ratified 2026-08-12. Fan-out base commit: `76415df0`.
Advisor consult skipped (consult-mode returned `status:"error"` — no API key);
proceeding on primary sources per advisor-conventions.

## Ratified decisions

1. **No renames — the abx kill is dead.** `abx*` (lowerCamel constants and
   identifiers) and `AppBoxKit*` (PascalCase types, capital B) are BOTH
   canonical, per the standing rule in DESIGN-ARCHITECTURE.md ("Kit token
   binding"): every constant carries the `abx` prefix, chosen deliberately
   over Flutter's `k`-prefix style. `abxAction`/`abxActionHub` follow that
   convention. Any doc framing abxAction as deprecated/to-be-renamed is wrong
   and gets swept (decision reversed by operator after fact-check; do not
   re-litigate).
2. **Guard, not docs**: new `G14 naming` group in the arch-guard engine
   (tests in `appboxd/test/arch_guard_test.dart`, engine wherever G0–G13
   live), covering kit + appboxd source:
   - kit constants/identifiers use the `abx` prefix (no bare `k` constants,
     no raw literals crossing the token boundary)
   - types use `AppBoxKit` casing — ban the `AppboxKit` lowercase-b typo
   - no rival action vocabulary bypassing `AppBoxKitActionHub`
3. **Adoption**: all notes-shell surfaces route actions through the existing
   `abxAction` / `AppBoxKitActionHub` solution (`ui_library`
   `utils/kit_action/appbox_kit_action.dart`).
4. **InkWell/ripple fix** rides the adoption: long-press in the native liquid
   glass UI becomes an abxAction-owned press state on the native surface — no
   Material `InkWell`/ripple leaking over platform views
   (evidence: ScreenRecording_08-12-2026 18-29-24_1.MP4).
5. **Topology**: no rename phase. Fan-out 3–4 subagents by surface, each in a
   worktree branched EXPLICITLY from `76415df0` (never stale origin):
   - A: showcase note editor surface (view + form-factor variants + viewmodel)
   - B: showcase notes folder surface
   - C: showcase notes list + shell surface, including the long-press fix
   - D: G14 guard group + doc sweep (disjoint from A–C)
6. **Gates** (done means all green):
   - full arch guard incl. G14
   - `flutter analyze` clean, build green
   - probe suite verdict by process exit (never grep "ALL PASSED")
   - closing evidence: on-device long-press video, same channel as the report
7. **Commits**: single line, no author mentions; one commit per surface after
   shared groundwork.

## Non-goals

- Renaming anything abx→AppBoxKit or the reverse.
- Moving action code between appbox and kit (no `Abx*` class definitions
  exist anywhere; kit already owns the implementation).
- Touching surfaces outside the notes shell in this pass.

## Outcome (2026-08-12, fan-out complete)

- **Adoption was already done one layer down.** Every notes-shell mutation
  routes through `ShowcaseNotesFacadeService` → `AppBoxKitDataFacade.mutate()`
  (`kit/data/lib/facades/appbox_kit_data_facade.dart:70`), which calls
  `abxActionHub.send()` with ENTITY-SCOPED keys (`'pin.${note.id}'`). Editor,
  folder, and notes/shell viewmodels required zero changes. Standing rule
  learned the hard way (a viewmodel-level wrapper was written and reverted):
  do NOT wrap facade-reaching viewmodel actions in class-wide
  `abxActionHub.on(...)` commands — the class-wide key swallows concurrent
  per-entity ops. Wrap only for debounce/guard/confirm the facade doesn't
  provide (pattern: `showcase_note_editor_viewmodel.dart` `_autosave`).
- **Decision 4's premise was corrected in flight**: abxAction is async-op
  busy/error state, not touch feedback, and the kit has NO reusable
  press-state primitive. The shipped fix (`0b494bde`) is a local
  `_ShowcaseNotesPressable` (GestureDetector + AnimatedOpacity dim,
  `Semantics(button: true)`) duplicated in `showcase_notes_note_row_widget`
  and `showcase_notes_folder_row_widget`. Deliberate debt: hoist to a kit
  primitive when a third caller appears.
- The folder row's leak was inherited from `AppBoxKitListTile`'s
  Material+InkWell via `ShowcaseNotesRowWidget` (gesture-arena share with the
  outer long-press); fixed by inlining the row with the same kit tokens.
  `ShowcaseNotesRowWidget`/`AppBoxKitListTile` untouched (shared blast
  radius).
- Audio row / photo strip never had an ink ancestor — no leak possible; left
  WITHOUT press feedback because wrapping a platform view or BackdropFilter
  in Opacity forces saveLayer (documented anti-pattern,
  `rail_item_button_m3e.dart:89`). Needs on-device evidence on both glass
  tiers before adding.
- **G14 naming guard** landed (`b3774452`): 3 checks, no self-allowlist,
  80/80 tests, baselines unchanged. Doc sweep found NO doc framing abxAction
  as deprecated — premise was already stale; citations added instead.
- Gates green: arch guard at baseline (57/21/12/9), analyze clean, showcase
  tests 128/128. Outstanding: on-device long-press video retest.
