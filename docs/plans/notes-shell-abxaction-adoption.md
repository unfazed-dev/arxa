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
