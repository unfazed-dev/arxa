# Regime-3a theme/preference capture — FINAL whole-implementation review

**VERDICT: APPROVED WITH MINOR NOTES**

Scope reviewed: cumulative diff `310e4f8..HEAD` over `scripts/` + `fixtures/theme/`
(commits 5ac8966 → 50547a8) against the design spec
`docs/plans/regime3a-theme-preference-capture-design.md`. Full suite **358 passed**
(`scripts && python3 -m pytest -q`, 2.90s). `content_firewall.py` UNCHANGED
(empty diff over the range). No source file modified by this review.

The single advisor-flagged risk (bare-string `image-set` bypassing both the redactor
early-out and the extensionless `_CONTENT_URL` backstop) was probed against **live host
Chrome** and resolved: NOT reachable from the capture path. Details in the Content-free
subsection below.

---

## 1. Content-free invariant (HIGHEST PRIORITY) — PASS

Forward trace, end to end:

capture (`_styles_by_backend` → `parse_snapshot`, raw resolved styles) →
`_theme.diff_theme` (raw `cond_value`) → `_theme.rekey_by_node_id` →
`_theme.build_node_theme` → `web_skeleton` sets `sk["_node_theme"]` (raw, in-memory only) →
`bundle_writer.main` pops `_node_theme`, int-keys → `assemble` calls
`apply_node_theme` (line 188) which writes `n["theme"] = _style.redact_theme(tv)` →
`cf.redact_node` (line 192) → write → `audit_bundle`.

- **Redaction-before-disk:** every theme value passes through `_style.redact_theme`
  (`content` → `redact_content_value`; all else → `redact_style_value`) BEFORE the node
  is serialized. `apply_node_theme` (bundle_writer:163-175) is invoked at assemble:188,
  strictly before `redact_node` at assemble:192 and the subsequent write/audit. Order is
  guaranteed by straight-line code, not by chance. CONFIRMED.
- **`theme` not in `CONTENT_KEYS`** → `redact_node` keeps the already-redacted nested map
  (it only strips top-level content keys); the nested values survive *because they are
  already redacted*. Correct per spec §7/§8.
- **image-set / url-fragmentation class (the prior-leak class):** ran
  `redact_style_value` over `image-set(url("https://host/p.png") 1x)`, 2-source image-set,
  multi-url `background-image`, `cross-fade`, unquoted, protocol-relative `//`, `data:`,
  mixed frag+ext. ALL collapse every external token to `url("<asset>")` with NO host
  surviving; same-doc `url(#frag)` and gradients kept verbatim. The `_URL` regex is global
  (`.sub`) with matched-quote backreference, so multi-url does NOT fragment. No `://`
  survives any case; firewall `_CONTENT_URL`/`_DATA_URI` find nothing in the redacted
  output. CONFIRMED CLEAN.

## 2. `backendNodeId` never on disk — PASS

- `parse_snapshot` reads the dense `nodes["backendNodeId"]` array (web_skeleton:242) and
  stamps `"backend"` per record indexed by `dom_i` with a short-array guard (web_skeleton:262).
- `to_skeleton` builds `node_backend[node["id"]] = r.get("backend")` (web_skeleton:474) —
  keyed by **positional node id → backendNodeId**, returned as the 5th tuple value (line 512).
- `capture_with_themes` uses `node_backend` only in-process for the join; it sets
  `sk["_node_theme"]` (line 654) but NEVER `sk["_node_backend"]`. The on-disk sidecar is
  keyed by node id (`build_node_theme`/`rekey_by_node_id`).
- Non-theme callers discard the new return: `_capture_one`-driven paths unpack
  `sk, _, _, _ =` (web_skeleton:764, 775) and `web_states.py` `rest, _, _, _ =`.
- `node["theme"]` is keyed by positional node id (apply_node_theme uses `n["id"]`).
  CONFIRMED: backendNodeId is internal-only, never serialized.

## 3. Join correctness — PASS

- Join key is **`backendNodeId`**, not the positional skeleton id (spec §1). `diff_theme`
  iterates `base_by_backend` and looks up `cond_by_backend.get(b)` by backend.
- **Base `node_backend` reused for ALL conditions:** captured once at
  capture_with_themes:643 and passed to every `rekey_by_node_id` call (line 652).
  Drop-on-miss in `rekey` is therefore defensive (base drives both). CONFIRMED.
- **Phantom-diff guard:** `base_styles` and every `cond_styles` come from the SAME
  `_styles_by_backend(ev)` helper with identical `WANT_STYLES` and `dpr=1.0`, single Chrome
  engine, no navigate — byte-identical serialization, so `base != cond` fires only on real
  changes. CONFIRMED (spec §3).
- Base media pinned via `BASE_FEATURES` (light / forced-colors:none / contrast:no-preference,
  web_skeleton:89-93); each condition flips exactly one axis via `_condition_features`
  (single-feature override). `finally: setEmulatedMedia({features:[]})` clears emulation
  (capture_with_themes:656-657). Matches spec §3 exactly.

## 4. Diff semantics — PASS

`diff_theme` (test_theme.py-verified): emits a prop only when `base[prop] != cond[prop]`,
catches BOTH directions (real-shadow→`none` and `none`→real-shadow tested), drops nodes
absent from the condition (continue on `cond_style is None`), emits nothing for an
unchanged node (no `out[b]` set when `delta` empty). No missing-key asymmetry: both raw
maps carry every requested prop because computed-style resolves all of `THEME_PROPS` for a
laid-out node; `.get(prop)` symmetric on both sides. `THEME_PROPS` excludes geometry/sizing
props (verified: only `background-image` among url-capable props; no `display`/`width`/
`height`/`box-sizing`), consistent with spec §5 (visibility handled by drop-on-miss).

## 5. Firewall — PASS

- `content_firewall.py` UNCHANGED across the range (empty diff). CONFIRMED.
- Backstop genuinely recurses into `node.theme[label][prop]`: the **prose canary**
  (`test_audit_canary_unredacted_prose_in_theme_trips`) asserts a leak with
  `kind == "prose"`, which can ONLY come from `_prose_in_json`/`_walk_strings` (the flat
  `_CONTENT_URL`/`_DATA_URI`/`_B64_BLOB` detectors do not match plain prose) — this proves
  the key-aware walk reaches the theme path.
- The two url/image-set canaries are honestly commented as **flat content-url detector
  regression locks** ("Does NOT prove key-aware walk recursion" / "caught via the flat
  scan, same as the bare-url canary"), NOT as walk-recursion proofs. Comment claims match
  the mechanism each actually exercises. Matches spec §8.

## 6. Consistency & dead code — PASS

- 4→5-tuple migration applied consistently: `to_skeleton`, `_snapshot_skeleton`,
  `_capture_one` all return/propagate `node_backend`; all call sites migrated
  (`web_states.py` 6-line tuple-arity bump, no behavior change — verified diff is purely
  `_, _` → `_, _, _`).
- Types consistent: `_node_theme` is `{str(node_id): {label: {prop: redacted_value}}}` on
  disk, int-keyed back in `bundle_writer.main`, mirroring `_node_pseudo`/`_node_style`.
- No leftover dead code spotted. `_node_by_bg` in the host gate matches by **bbox size,
  not bg color** — this is EXTENSIVELY and honestly documented (run_theme.py:65-108,
  90-97): background-color lives in `_node_colors` (stripped before skeleton.json) and is
  absent from regular nodes' `style`, so bbox is the deterministic identifier. Naming is
  documented, not misleading.

## 7. Tests + suite — PASS

- **358 passed** in 2.90s.
- `test_theme.py` is non-vacuous: covers changed-only emission, both-directions
  (appeared/disappeared), drop-on-miss, no-change-emits-nothing, backend→node_id rekey,
  transpose, empty-delta skip, pseudo/None-backend skipping.
- Host gate (`run_theme.py`) proves JOIN CORRECTNESS in both directions: #known gets the
  RIGHT resolved dark rgb (240,240,240)/(17,17,17), the right contrast (0,0,0), and a
  forced-colors delta — keyed to the right node; #static (no @media rule) carries NEITHER
  dark NOR contrast (per-condition isolation), and legitimately carries forced-colors
  (UA-dense, spec §9, correctly caveated). Uses format-robust `parse_color`. `write_bundle`
  audit must not raise → GATE PASS.
- Real-site harness (`validate_realsite.py`) is content-free: prints host (operator's own
  `--url` input, not discovered content), node/with-delta COUNTS, prop NAMES from the fixed
  `THEME_PROPS` universe, per-label volume %, and explicit forced-colors VOLUME. Never a
  resolved value, color, selector, or url. Audit-clean exit proves the firewall passed at
  scale.

## 8. Spec coverage — COMPLETE

| Spec section | Implementation | Status |
|---|---|---|
| §1 join by backendNodeId | `diff_theme`/`rekey_by_node_id`; backend parsed dense | covered |
| §3 base-pin + phantom-guard + finally-clear | `capture_with_themes` (BASE_FEATURES, shared `_styles_by_backend`, finally) | covered |
| §5 diff core | `_theme.py` (THEME_PROPS in web_skeleton, geometry excluded) | covered |
| §6 redaction | `_style.redact_theme` (content→content_value, else style_value) | covered |
| §7 bundle | `apply_node_theme` before `redact_node`; `assemble`/`main` thread it | covered |
| §8 firewall UNCHANGED + backstop | confirmed unchanged; prose canary proves recursion | covered |
| §9 ceilings | drop-on-miss; forced-colors dense documented + measured in harness | covered |
| §10 testing | unit + redaction + parse + bundle + firewall + host gate + real-site | covered |

No gaps found against the spec.

---

## Content-free invariant — concrete trace results

**image-set / url-fragmentation (the prior-leak class):** `redact_style_value` over the
flagged inputs — every external url collapses to `url("<asset>")`, no host survives,
multi-url image-set does not fragment, frags/gradients kept. CLEAN (see §1).

**backendNodeId:** never written to disk on any path. `capture_with_themes` sets only
`sk["_node_theme"]`; non-theme callers discard the 5th tuple value; on-disk sidecar keyed
by positional node id. CONFIRMED (see §2).

**Advisor-flagged residual — bare-string `image-set` (RESOLVED by live probe):**
`redact_style_value` early-outs when `"url(" not in value`, leaving a *bare-string*
`image-set("https://host/x" 1x)` UNCHANGED; for an extensionless url the firewall
`_CONTENT_URL` (which requires a known asset extension) ALSO misses — both layers would
miss. This is exactly the prior gate's "redactor AND backstop both miss" class, so I probed
**reachability against live host Chrome** rather than reasoning from recall.

Probe (local server + CDP, computed `getComputedStyle().backgroundImage`):

| authored | Chrome computed value | has `url(` | redacted |
|---|---|---|---|
| `image-set("/x.png" 1x)` | `image-set(url("http://.../x.png") 1dppx)` | yes | `image-set(url("<asset>") 1dppx)` |
| `image-set("//cdn.host/x" 1x)` (extensionless) | `image-set(url("http://cdn.host/x") 1dppx)` | yes | `image-set(url("<asset>") 1dppx)` |
| `image-set(url("/y.png") 1x, url("/y2.png") 2x)` | two `url(...)` | yes | two `url("<asset>")` |
| `image-set("https://cdn.host/z.png" type(...))` (extensionless+typed) | `image-set(url("https://cdn.host/z.png") 1dppx type(...))` | yes | `image-set(url("<asset>") ...)` |
| `url("/plain.png")` | `url("http://.../plain.png")` | yes | `url("<asset>")` |

**Conclusion:** Chrome's *computed* `background-image` serialization ALWAYS normalizes the
bare-string form into a `url(...)` wrapper — including extensionless and typed cases — so
`redact_style_value` catches every variant and no host survives. The bare-string-without-
`url()` form is **NOT reachable from the capture path**; it only matters for hand-authored
JSON, which never occurs in production. This is the same "safe only because Chrome
normalizes the url form" invariant the `_style.py` docstring already relies on for relative
urls, now empirically extended to `image-set`. Content-free invariant HOLDS on the real
capture path. (Pre-existing Regime-1 behavior, not introduced by 3a — spec §6 "no new
content vector".)

---

## Minor notes (non-blocking)

1. **`redact_style_value` bare-string early-out (documented ceiling, not a leak).** The
   `"url(" not in value` early-out leaves a hypothetical bare-string `image-set("..." …)`
   unredacted, and an extensionless such url evades `_CONTENT_URL` too. Empirically
   unreachable on the capture path (Chrome normalizes to `url()`, probed above). Suggest a
   one-line ceiling note in `_style.py` next to the existing relative-url ceiling comment,
   recording that computed `background-image` image-set is `url()`-normalized so the
   bare-string form never reaches the redactor. Pure documentation; no code change required.
2. **No live image-set/url canary in the committed suite.** The host gate exercises color
   deltas only; the image-set normalization fact above lives in this review, not in a
   committed regression test. Optional: add an `image-set` div to `run_theme.py`'s page (or
   a `redact_theme` unit asserting `image-set(url("https://h/x.png") 1x)` →
   `image-set(url("<asset>") 1x)`) to lock the normalization assumption. The existing
   `test_style.py` `redact_theme` cases + the firewall image-set canary already cover the
   `url()`-wrapped form; this would lock the *capture-path* normalization explicitly.
3. **`build_node_theme` double empty-guard.** `diff_theme` already omits empty deltas, and
   `build_node_theme` re-checks `if delta`. Harmless redundancy / defensive; no action.

No Critical or Important findings. The feature satisfies the design spec and the
content-free invariant on the real capture path.
