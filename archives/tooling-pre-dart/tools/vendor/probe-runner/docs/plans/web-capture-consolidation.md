# Web-Capture Consolidation Plan

**Goal:** Harden the LANDED web-capture stack (P0–P15 CSS coverage + G3b cross-route token merge + ARIA enrichment) as a whole — lock it against regression with a real-artifact-validated integration test, and document the capability set.

**Status:** DONE (2026-06-02). Chosen off-ladder after the de-risk ladder exhausted (G3c×2/G3d/G4 DEFERRED; G2 BUILD-JUSTIFIED-but-gated). User picked "consolidate landed stack." Outcome: the suite was already strong (497 green; every landed field type + the delta url() canary already tested) → a SMALL consolidation is the correct result. T1 live-smoke validated the real artifact (firewall-clean) and is now a repeatable manual harness; T2 dropped as redundant; T3 capability reference added. No engine code changed.

**Baseline:** `cd scripts && python3 -m pytest -q` → **497 passed** (2026-06-02). Unit coverage strong; firewall well-gated (`audit_bundle` re-runs in bundle_writer / site_capture / site_chrome / site_merge).

## What the audit found (so scope stays lean)

- **Firewall axis is de-risked.** `audit_bundle` is **content-based, not key-based** — it text-scans every non-binary bundle file for prose/urls/base64/data-URIs + magic bytes. A new landed field type that carried content is caught regardless of field name. No per-field maintenance needed. → Not a consolidation target on its own.
- **Real gaps (only two):**
  1. **No single end-to-end test** composing the landed features through the real pipeline and asserting firewall-clean on the *produced* bundle.
  2. **SKILL.md capability framing is target-class only** (macOS/web/iOS/android/flutter) — does NOT enumerate the landed web-skeleton feature set; that knowledge lives scattered across 18 §C9-R sections of the research plan.

## Advisor-locked design constraints (do NOT relax)

- **C1 — Live-smoke is REQUIRED, not optional.** Per memory `validate-real-artifact-not-keys-proxy`: a hand-authored-fixture-only test is the exact proxy that false-passed G3d. The keystone is a REAL live CDP capture validated on real artifact bytes. The deterministic golden-bundle test is the CI *complement*, not the keystone.
- **C2 — Assert real field VALUES/bytes, not key-presence.** (Same memory's other half.)
- **C3 — Must cover P4/P5 state/transition DELTA outputs.** Delta dicts are NOT key-stripped (`redact_node` only strips base-node CONTENT_KEYS); their redactor is a passthrough, so the firewall `_CSS_URL_REF` regex (content_firewall.py ~L70) is the SOLE backstop. This is the likeliest leak site → exercise it deliberately (positive canary + clean pass).
- **C4 — Keep lean.** Doc is lowest-value. Do NOT sprawl into unit-testing every web_states/site_capture orchestrator path — the integration test covers composition.

## Tasks

### T1 — Live-smoke keystone (REQUIRED; validates real artifact)
- Serve a fixture (or use a live page) carrying landed field types over localhost.
- Run the REAL capture path via CDP :9222 → produce an on-disk bundle.
- Assert: produced skeleton/bundle carries real landed field VALUES (regime/delta maps populated, aria_role present where applicable) — not just keys (C2).
- Assert: `content_firewall.audit_bundle(produced_dir)` == 0 violations on the REAL produced bundle (C1).
- RUN IT NOW (Chrome is up on :9222), record the result inline in this plan + the §C9-R writeup.
- CI form: a pytest gated `skipif` no CDP on :9222 (so CI stays green headless; the real validation is the recorded manual run).

### T2 — Deterministic golden-bundle integration test (CI complement)
- Multi-route skeleton+token fixtures carrying landed field types INCLUDING a state/transition DELTA dict (C3) with a `url(https://…)`-wrapped asset value as a CANARY.
- Run the REAL post-processors (`_chrome_dedup` / `_merge` / aria / `slots`) + `bundle_writer` + `audit_bundle`.
- Assert: landed field VALUES survive composition (C2); `audit_bundle` == 0 on the produced bundle.
- Negative control: when the url() canary is left UN-stripped in a delta, `audit_bundle` MUST flag it (proves the sole-backstop fires — C3). Deterministic, no live CDP.

### T3 — Lean capability doc (lowest priority)
- `docs/probe-runner-web-capture-capabilities.md`: enumerate the landed web-skeleton feature set (P0–P15 + G3b + ARIA) as rows: feature → producing module → field(s) → §C9-R provenance. The maintainable reference SKILL.md lacks.

## Execution log

### T1 — Live-smoke keystone: PASS (2026-06-02, real CDP :9222)
Served fixtures over localhost; ran the REAL landed path against live Chrome.
- `site_capture --urls-file <2 routes> --merge --dedup` → rc=0, route_count=2, ok_count=2, **post.merge=ok, post.dedup=ok** (full G3a+G3b+dedup+ARIA composition on real capture).
- **Real field VALUES (not keys, C2):** 2 skeleton.json produced; 9/10 nodes carry real `style` maps (sample: `border-*-color: rgb(0, 0, 0)`), 10/10 real `bbox`. `site.json` (G3a manifest) emitted.
- `web_states` (P4/P5 delta capture, the non-key-stripped leak site) → rc=0, triggers_driven=2, states=2, components_built=2, appeared_total=7 — real delta artifacts.
- **FIREWALL (C1): `audit_bundle` = 0 violations** on the produced site bundle AND 0 on the states delta tree.
- Honest caveat: the chosen fixtures (disclosure/multi-band/multi-trigger) lack landmark-roles/@keyframes/theme-switch, so `aria_role`/`theme`/`keyframes` are absent-by-CONTENT (not capture failure). The keystone validated what the `validate-real-artifact-not-keys-proxy` memory demands: real captured bytes + firewall-clean on the REAL produced artifact — not a `.keys()` proxy.

**T1 codification — MANUAL harness, NOT a pytest (revised after empirical evidence).** The plan first specified a `skipif`-no-CDP pytest. Built it (`test_web_capture_livesmoke.py`), ran it: it FAILED on a fragile manifest parse AND took **1656s (27 min)** — the live captures blocked ~25 min driving the single shared :9222 Chrome tab before navigating (a wedged-tab symptom; the SAME captures ran <220s in the manual smoke). Afterward the shared tab was left pointed at a dead localhost URL. Conclusions: (a) a test bound to one shared mutable Chrome tab is too slow/stateful for the unit suite, and (b) it always-skips in headless CI anyway → near-zero regression value. Per advisor's stated alternative, recorded T1 as **manual-validated** and codified the repeatable harness as a plain script `scripts/livesmoke_web_capture.py` (no `test_` prefix → not collected) with the parse bug fixed. The deleted pytest is gone; suite unchanged at 497.

**Harness verification status (honest):** the parse fix (`json.loads(stdout[stdout.index("{"):])` vs the old `splitlines()[-1]` that grabbed the bare `}`) is **verified deterministically** — fed a realistic pretty-printed `site_capture` manifest, OLD path raises `JSONDecodeError` (reproduces the bug), NEW path yields `ok_count=2 / merge=ok / dedup=ok`. A clean END-TO-END harness run was NOT re-obtained this session: the live path is ~3–4 min, and bounded retries left zombie Chrome tabs that broke the capture's single-target resolution (multi-minute hangs). Discovered operational prereq, now documented in the harness: **exactly ONE clean :9222 page target** (>1 tab → may attach a stale tab → hang). **Validation of record remains the manual smoke above** (real `rgb()`/`bbox` values, merge/dedup ok, firewall 0×2) — the harness's capture logic is identical to that validated path; only its glue (parse + asserts) is new, and that glue is deterministically verified. Shared debug-Chrome left clean (1 `about:blank` tab); no leaked processes.

### T2 — Deterministic golden-bundle test: DROPPED (redundant; 2026-06-02)
Audit of the existing suite showed the composition is ALREADY covered, so building T2 would be manufacturing work (forbidden by CLAUDE.md):
- `test_bundle_writer.py`: every `apply_node_*` (style/pseudo/theme/pseudo_state/responsive) + `apply_token_refs` + `derive_slots` individually tested; `write_bundle`→`audit_bundle` end-to-end tested (clean-pass, leak-trips, nonascii-leak, states.json+audit, substrate.json+audit).
- `test_content_firewall.py`: per-field passes (component, transition, redacted-style, cut2-style, pseudo) AND the delta `url()` canary negative-control **already exists** (`test_audit_canary_unredacted_external_url_in_style_trips`).
- `test_site_capture_post.py`: real multi-route post-processor composition (merge+dedup → `design_system.json`+`chrome_dedup.json`) asserted, plus firewall-leak surfacing.
Only residual was a single all-fields-on-one-node combined-apply test; `apply_node_*` are independent (each writes its own node key) and `audit_bundle` is byte-level, so it would catch ~nothing. Advisor concurred (reversed its earlier "composition uncovered" steer on reading the files).

### T3 — Capability reference: DONE (2026-06-02)
`docs/probe-runner-web-capture-capabilities.md` — enumerates the landed web-skeleton feature set (per-node fields P0–P15 + token_ref + substrate + aria_role; per-route bundle outputs; cross-route G3a/G3b/G3-wire outputs) as feature → producer → field → §C9-R provenance, with the firewall invariant, the delta leak-site note, the deferred set, and the manual live-smoke procedure. The maintainable reference SKILL.md (target-class framed) lacked.

## Net
Suite 497 green, unchanged. New: `scripts/livesmoke_web_capture.py` (manual harness), `docs/probe-runner-web-capture-capabilities.md` (reference), this plan. The honest finding is that the landed stack was already well-tested; consolidation's real value was (a) a real-artifact live validation that the suite structurally cannot do, and (b) a discoverable capability reference. No new suite tests were manufactured where coverage already existed.
