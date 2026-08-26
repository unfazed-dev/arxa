# studio-v2 relay — grill decisions (ratified 2026-08-12)

Grill of the arxa-studio-v2 restructure/handoff state (git history F0–F6, docs-conformance audit, scaffolder-handoff gap report). All rulings ratified by the operator 2026-08-12; operator reserves the right to update rulings as work proceeds.

Advisor consult skipped: consult-mode returned `status:"error"` (no API key in `ANTHROPIC_API_KEY` or `~/.config/consult-mode/api-key.json`). Proceeded on primary sources.

## Decisions

| # | Question | Ruling |
|---|----------|--------|
| 1 | F0 / pinning `intake/registry.json` | Fix panel kinds first, then pin. Remap the 3 `"kind": "panel"` entries (`header_panel`, `footer_panel`, `main_panel`) to legal 15-kind vocabulary entries or composed recipes — never improvise a mapping. Operator sign-off pins the file. |
| 2 | Roster conflict (canon vs emitted) | Amend the Registry canon to accept the ratified `studio_*` roster; freeze name-check resolves roles via mapping. Splash becomes a real surface under `studio_*` naming inside the startup shell — not a shell. |
| 3 | Derived registry shape | One regeneration of `models/screens_model/registry.json` at pin time, all 6 shells, canon Surface fields (`{id, labelKey, shell, consumes, produces, href, enabled}` → canon shape); unlanded shells route-less. Derived file is never hand-edited. |
| 4 | First freeze timing | Wait for all 6 shells — no `structure.json` until the full roster lands and validates. |
| 5 | Relay risk while waiting | Gitignored dry-runs allowed: freeze/`--check` into scratch; artifact root stays clean of frozen output until the real freeze. |
| 6 | "Landed" definition | Full gate per shell: five-file split + `inspectAttrs` triple on every surface + canonical `///` frontmatter + `arxa design lint` + `arxa lens check` clean. Dashboard retro-stamped through this gate now. |
| 7 | Conformance debris | One sweep commit now: panel-kind remap + missing `ui/widgets/common/widgets.tsx` root barrel + canonical frontmatter on the 3 built shells + 2 stray "screen" vocabulary hits. |
| 8 | F6 incident (`49249e93` swept 9 concurrent-agent files; message over-claims) | No history rewrite. Correction record in `emit-findings.md` attributing the 9 files to the concurrent emit; F6 closed. Trail-leaving correction over silent rewrite. |

## Execution order

1. Conformance sweep (D7) + dashboard retro-stamp (D6) — one pass, largely the same files.
2. Canon amendment for roster mapping + splash surface (D2).
3. Derived registry regeneration, all 6 shells (D3).
4. Operator sign-off → intake pins (D1).
5. F6 correction record (D8).
6. Remaining 4 shells, each through the full landed gate; gitignored dry-runs as desired (D5) → final 6-shell freeze (D4).

## Standing risk (acknowledged, overruled)

Waiting for all 6 shells before the first real freeze (D4) concentrates scaffolder-handoff risk at the end: dry-runs cover the contract shape, but the scaffolder never touches real studio-v2 data until freeze day. Raised twice during the grill; operator ruling stands.

## D9 — common/ root barrel: gate exemption ratified, presence-enforcement open

Ratified 2026-08-12. `isCommonRootBarrel` (arxa/lib/gate_design_widgets.dart)
exempts `ui/widgets/common/widgets.tsx|.ts` from W1 (flat-common) and W2 (dead):
it is a mandated fixture (showcase-anatomy §2), pure `export … from` lines that
`_importRe` does not read as edges, so zero importers is by design. Barrel
authored for studio-v2; W-gate suite 60/60.

**Open:** the barrel's PRESENCE is still ungated. Enforcing it requires
export-from edges in the import graph (today a re-export is invisible, which is
also why rewiring consumers to the root barrel flips group barrels to W2 dead).
Rule on graph semantics before adding the missing-barrel check.
