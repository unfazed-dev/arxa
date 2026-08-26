# studio-v2 missing shells — grill decisions

Date: 2026-08-13. Continues `studio-v2-relay-grill-decisions.md` (D1–D7).
Scope: the 4 roster shells with no `ui/views/` directory — `studio_unknown_shell`,
`studio_auth_shell`, `studio_intake_shell`, `studio_design_shell`.

## State at grill time

- Ratified roster (D2/D3): 6 shells. Built: `studio_dashboard_shell`,
  `studio_startup_shell` (+ `studio_application_hub` host composition).
- Derived registry marks the 4 as `landed: false`; stages ledger holds
  `auth`/`intake`/`design` at `enabled: false, href: "#"` (D3 shape).
- `services/facades/` does not exist despite the spine spec requiring
  ViewModel → Facade → Repository; existing shells read via
  `services/repositories/fixture_reader.js` directly.

## Decisions

| # | Question | Ruling |
|---|----------|--------|
| M1 | `studio_application_hub` vs roster | Hub-hosted composition, not a shell. Roster stays 6. Hub is consumed by **all shells except `unknown` and `startup`** — same structure as the showcase app. Directory stays. |
| M2 | Build order | Serial, `unknown` first (standalone, proves the non-hub path), then `auth` → `intake` → `design` in stage order. Full D6 landed gate between each; tree gate-clean at every commit. |
| M3 | Visual fidelity | Port, don't redesign. v1 (`designs/arxa-studio/ui`) layout re-expressed in v2 mechanics (five-file split, closed 15-kind widget vocabulary, hub-hosting for auth/intake/design, inspectAttrs triple, canonical frontmatter). Vocabulary gaps stop the work and surface to the operator — never invent a widget. Exception: `design_canvas` is the canon-exempt canvas island (runtime/vendor canvas.js + inspect.js, no kit widget). |
| M4 | Route activation | Live at land. Passing the D6 gate triggers one derived-registry regeneration flipping that shell to `enabled: true` + real href, and wires `app.routes.js`. `structure.json` freeze still waits for all 6 (D4 unchanged). |
| M5 | Data spine | `unknown`/`auth`: no models (empty-state + chrome; session is not content per determinism law). `intake`: `models/intake_model/` (interview-thread seed + generate.mjs). `design`: `models/design_model/` reading the Portalo seed, consuming `intake/registry.json`. New models get real `services/facades/*_facade.mjs` from creation. Startup/dashboard facade retrofit = separate logged debt, out of scope here. |

## Debt logged

- Facade retrofit for `startup_model` / `studio_dashboard_model` consumers
  (spine spec violation predates this work; M5d rules it out of scope).

## Execution order

1. `studio_unknown_shell` — standalone, `unknown_notice` empty-state → D6 gate → regen (M4).
2. `studio_auth_shell` — hub-hosted, `credential_form` (form-field + cta-link), proceed trigger → gate → regen.
3. `studio_intake_shell` — hub-hosted, `interview_thread` + `asset_upload_dropzone`, intake_model + facade → gate → regen.
4. `studio_design_shell` — hub-hosted, canvas island + `inspector_panel` + `composer_slider_panel` + `needs_you_strip` + `activity`, design_model + facade → gate → regen.
5. Final 6-shell freeze per D4.
