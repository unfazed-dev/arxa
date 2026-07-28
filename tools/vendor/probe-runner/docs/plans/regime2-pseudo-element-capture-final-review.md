# Regime-2 pseudo-element capture — final whole-implementation review

**Scope:** commits `e05464e..c72a007` on master. Per-task spec + code-quality reviews already passed; this is the integration / content-free-invariant / cross-seam review.

**Verdict: SHIP.** 330/330 tests pass. Data flow is type-consistent end to end; the active `content` redactor runs exactly once on every pseudo on the production path; the firewall backstop is wired into production (`write_bundle` → `audit_bundle`, raises on leak). No critical or important issues.

## End-to-end trace (verified)

`parse_snapshot` builds `pseudo_by_node` from `nodes.pseudoType` (sparse RareStringData) and stamps `"pseudo": pseudo_by_node.get(dom_i)` on each *record* (intermediate `recs`, not the emitted node).

`to_skeleton`:
- Records with `r.get("pseudo")` truthy → `continue` (never become standalone nodes). Real elements have `pseudo=None`, never copied into the emitted node dict — so no raw `pseudo` field leaks from the record path.
- Second pass: only `r["pseudo"] in {"before","after","marker"}` is harvested; attached to originating element via `dom_to_id[parent_index[r["dom_index"]]]`, dropped on miss. `_collect_pseudo` builds sparse style + RAW `content`.
- Returns 4-tuple; `_snapshot_skeleton` serializes `sk["_node_pseudo"] = {str(k): v ...}` (int→str for JSON).

`bundle_writer.main`: `raw_pseudo = skeleton.pop("_node_pseudo", {})` then `{int(k): v ...}` (str→int). `assemble` → `apply_node_pseudo` sets `n["pseudo"] = _style.redact_pseudo(pv)` for matching int id. Runs BEFORE `cf.redact_node`, which filters only top-level `CONTENT_KEYS` (`pseudo` not among them) so the redacted nested map survives to disk.

**Key types consistent at every hop:** int id in sidecar → str in JSON → int in `main` → int lookup against `n["id"]`. No mismatch.

## Content-free invariant (verified end to end)

- **Active redaction:** `apply_node_pseudo` → `redact_pseudo` → `redact_content_value` (content tokenizer: quoted strings → `"<text>"`, empty `""` kept, external/data `url()` → `url("<asset>")` via `redact_style_value`; counter()/keywords/`/`/same-doc `url(#frag)` kept). Applied EXACTLY ONCE (only call site is `apply_node_pseudo` in the production `assemble` path). Idempotent markers prevent corruption if hit twice.
- **The guarantee is the active redactor**, not the audit. `redact_content_value` runs unconditionally on every `content` prop of every pseudo (sole call site `apply_node_pseudo` in `assemble`). Directly tested: `test_style.py:75` (`'"Read more"' -> '"<text>"'`), glyph/attr-resolved, mixed url+text, idempotence; `test_bundle_writer.py:421` exercises the full `apply_node_pseudo` path on `content: '"Buy now"'`.
- **Backstop (partial defense-in-depth, BOTH in production path):** `bundle_writer.write_bundle` (line 211) calls `cf.audit_bundle(root)` unconditionally after writing and raises `ContentLeak` on violation — module docstring: "the unconditional gate." `_scan_text` reads the whole serialized JSON and runs `_DATA_URI`/`_CONTENT_URL`/`_B64_BLOB`/`_prose_in_json` (recurses nested dicts via `_walk_strings` → reaches `node.pseudo["::before"].content`). Canary `test_audit_canary_unredacted_url_in_pseudo_trips` proves an un-redacted external url trips it. **Limitation:** `_prose` requires >=4 letters and short text is not a URL/data-URI/base64, so an un-redacted short literal (e.g. `content: "Hi"`) would slip the audit — which is why the active redactor, not the audit, is the content-free guarantee. The audit is a safety net for the box-style url() vector and long prose, not the primary defense for the text vector.

## Color parent-diff sparseness (verified)

`node_colors[nid]["fg"] = st.get("color")` (line 435) and `_collect_pseudo`'s `color = st.get("color")` — both raw `st.get("color")`, identical serialization. Comparison `color != parent_color` is valid; default `::marker` over a `<li>` with inherited color is correctly suppressed (no bloat). Worst case on mismatch is over-emit (bloat), never a leak.

## Latent-bug-fix asymmetry (correct & intentional)

`if r.get("pseudo"): continue` skips ALL pseudo records (any kind, incl. unsupported ones) from becoming junk nodes — broad gate. The narrower `_PSEUDO_SELECTORS = {before, after, marker}` gate controls only what gets HARVESTED into `node_pseudo`. Asymmetry is correct: an unsupported future pseudoType (e.g. `first-line`) is still excluded from the node list (no junk) but also not harvested (not yet supported). Confirmed intentional.

## Seam / caller audit

`to_skeleton` callers: production `_snapshot_skeleton` (migrated, 4-tuple) and 6 tests (all migrated to 4-tuple unpack). **`fixtures/skdiff-calib/harness2.py:49` still unpacks `sk, _ = ws.to_skeleton(...)` (2-tuple) → would raise `ValueError` if run.** This is a MINOR pre-existing issue, NOT a regression that matters: harness2.py is a standalone manual retina-calibration script (shebang, requires a live Chrome on CDP port 9222), not imported by any module and not collected by pytest. It was already non-runnable unattended. Recommend a one-line fix for hygiene only.

## Docs fidelity (no over-claim)

capture-completeness §C9-R-P8 + design spec match the code: geometry deferred, only before/after/marker (the statically-reachable set), counter() names kept verbatim. The premise correction (DOMSnapshot DOES enumerate pseudo nodes) is accurate. Wikipedia real-site clean-audit claim is consistent with the validator extension.

## Issues

- **Critical:** none.
- **Important:** none.
- **Minor:** `fixtures/skdiff-calib/harness2.py:49` stale 2-tuple unpack (inert; one-line fix `sk, *_ = ...` for hygiene). **RESOLVED** — fixed to `sk, *_ = ws.to_skeleton(...)` in commit `7b4712c` (arity-tolerant).
