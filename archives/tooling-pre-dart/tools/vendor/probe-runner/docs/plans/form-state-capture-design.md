# Form-state pseudo-class capture (`:checked` / `:disabled`) — design spec

**Status:** APPROVED design (probe-grounded). Successor to Regime-3b interactive pseudo-states.
**Regime:** ladder rung after P13 reduced-motion. Capture the per-node computed-style DELTA
when a form control is forced into `:checked` / `:disabled`, content-free, joined by
`backendNodeId`. Sidecar `form_state`.

---

## 0. Probe facts (FS-series — grounded, not assumed)

Source: `research/capture-gap-probes/probe_form_states.py` (commits `06aa81b`, `65277e6`),
run on host Chrome. The F-series (Regime-3b) deferred form states with `:focus-visible` the
only thing probe-confirmed; capture-completeness-gaps:75 *asserted* `forcePseudoState` supports
`checked`/`disabled` but never verified the DELTA. These facts close that gap.

- **FS1 — ACCEPTANCE.** `CSS.forcePseudoState` accepts the bare strings `"checked"` and
  `"disabled"` in `forcedPseudoClasses` with no exception (this Chrome).
- **FS2 — DELTA overrides DOM state.** Forcing `:checked` on an *unchecked* `<input>` applied
  the author `input#cb:checked{}` rule (opacity/accent-color/bg/outline moved); forcing
  `:disabled` on an *enabled* `<button>` applied `button:disabled{}` (opacity .4,
  cursor not-allowed, color, bg, border-top-color). No DOM-attribute mutation needed —
  forcePseudoState overrides the match regardless of live DOM state.
- **FS3 — FORCE-ALL SMEARS; TARGETING KILLS IT.** A bare `:disabled{outline}` rule smeared onto
  ~9 *non-disableable* nodes (divs/html/body) when `:disabled` was forced on EVERY element
  (Regime-3b force-all). Restricting the force-set via `DOM.querySelectorAll` to state-eligible
  element types eliminated the smear at the source: plain divs and a text `<input>` were never
  forced, so the bare `:disabled{}` / bare-ish `input:checked{}` rules never reached them.
  **R3b's force-all is WRONG for form states.**
- **FS4 — FORM_PROPS curation.** Props that actually moved across both states:
  `opacity, accent-color, cursor` (the additions) + `color, background-color,
  border-top-color, outline-style, outline-width, outline-color` (already in THEME_PROPS).
- **FS5 — TOGGLE COMBINATOR (dominant `:checked` use).** `#cb:checked ~ #sib` restyled the
  **non-forced sibling DIV** (background-color delta) while only the checkbox was forced. The
  CSS-toggle pattern (`input:checked + label`, `~ .panel`) is captured: forcing the input
  re-evaluates combinator selectors and the delta lands on the sibling/descendant node, keyed by
  *its own* backendNodeId. (R3b F3 showed the analogue for `:hover` descendants.)
- **FS-benign — button-internal node.** A button-internal box (anonymous/content) mirrors the
  button's own `:disabled` delta. Button-internal, faithful, not a foreign smear. Noted as a
  ceiling, no action.

---

## 1. Scope (locked, user-approved)

- **States:** `checked`, `disabled` ONLY (roadmap-literal, YAGNI). Broader family
  (`:enabled`/`:indeterminate`/`:required`/`:invalid`/`:placeholder-shown`/`:read-only`) is an
  append-only future add; some (`:invalid`) need DOM-validity state forcePseudoState may not
  synthesize → its own probe. Out of scope.
- **Prop universe — `FORM_PROPS`** = `THEME_PROPS + ["opacity", "accent-color", "cursor"]`.
  Explicit list snapshotted via `_snapshot_recs(ev, FORM_PROPS)` (the `capture_with_breakpoints`
  / reduced-motion pattern); **NOT a subset of `WANT_STYLES`**, so no `WANT_STYLES` change.
  `cursor` is **user-approved**, a deliberate break of the project-wide cursor deferral
  (Regime-3b/§2) because `cursor:not-allowed` is the canonical `:disabled` affordance (FS4).
- **Force-set eligibility (the divergence from R3b) — `DOM.querySelectorAll` per state:**
  - `checked`  → `"input[type=checkbox], input[type=radio], option"`
  - `disabled` → `"input, button, select, textarea, fieldset, optgroup, option"`
  The selector encodes state-eligibility EXACTLY (incl. input `type`, which snapshot recs do
  not carry — they have `tag` only). Returns frontend `nodeId`s fed straight to
  `forcePseudoState` (no `pushNodesByBackendIdsToFrontend` round-trip).
- **Sidecar:** additive per-node `form_state` field `{state_label: {prop: raw_value}}`, internal
  carrier `_node_form_state`. Sparse: a node with no delta under any state carries no field.
- **Content-free:** deltas are resolved styles → redacted by the SAME redactor as theme.
  `backendNodeId` (and transient CDP `nodeId`) internal. **REVISED (post-canary):**
  `content_firewall.py` is NOT unchanged — the `cursor` url() canary surfaced that the firewall's
  url() detector was extension-allowlisted (missed `url(...x.cur)` and any non-media-ext external
  asset URL inside a delta value). Added `_CSS_URL_REF` (a `url(`-wrapper, extension-agnostic
  detector) — see §5. The prose path is unchanged.

---

## 2. Mechanism — `capture_with_form_states(ev, engine, url, states, max_wait)`

Mirrors `capture_with_reduced_motion` (sidecar build) + `capture_with_pseudo_states` (force +
clear discipline), with the force-set obtained per state via `DOM.querySelectorAll`.

```
sk, _layout, _page, node_backend = _capture_one(ev, engine, url, max_wait=max_wait)
base = _theme.styles_by_backend(_snapshot_recs(ev, FORM_PROPS))
ev.sess.send("DOM.enable", {}); ev.sess.send("CSS.enable", {})
root = ev.sess.send("DOM.getDocument", {"depth": -1, "pierce": True})["root"]["nodeId"]
forced = set()                      # for finally-clear
try:
    per_state = {}
    for state in states:
        found = ev.sess.send("DOM.querySelectorAll",
                             {"nodeId": root, "selector": FORM_STATE_SELECTORS[state]})
        ids = [n for n in (found.get("nodeIds") or []) if n]
        for nid in ids:
            ev.sess.send("CSS.forcePseudoState",
                         {"nodeId": nid, "forcedPseudoClasses": [state]}); forced.add(nid)
        time.sleep(0.2)             # forced restyle settle (same as R3b; < 0.3s media flip)
        cond = _theme.styles_by_backend(_snapshot_recs(ev, FORM_PROPS))
        delta = _theme.diff_theme(base, cond, FORM_PROPS)
        per_state[state] = _theme.rekey_by_node_id(delta, node_backend)
        for nid in ids:             # clear so next state starts from base
            ev.sess.send("CSS.forcePseudoState", {"nodeId": nid, "forcedPseudoClasses": []})
            forced.discard(nid)
    node_fs = _theme.build_node_theme(per_state)
    sk["_node_form_state"] = {str(k): v for k, v in node_fs.items()}
    return sk
finally:
    for nid in forced:              # exception mid-state: leave the tab unpolluted
        try: ev.sess.send("CSS.forcePseudoState", {"nodeId": nid, "forcedPseudoClasses": []})
        except Exception: pass
```

- Base + every state use identical capture params over `FORM_PROPS` (phantom-diff guard).
- The delta is keyed by `backendNodeId` and rekeyed to `node_id` — combinator deltas land on the
  sibling/descendant node automatically (FS5), because the diff is over the whole snapshot, not
  the forced set.
- CDP-only; the `main` caller guards on `hasattr(ev, "sess")` and `die(...)`s otherwise, then
  `ev.close()` in `finally` (the `--reduced-motion` branch verbatim).
- New `--form-states` argparse flag (`action="store_true"`), branch after `--reduced-motion`.

`FORM_STATE_SELECTORS` and `FORM_PROPS` are module constants beside `MOTION_PROPS`.

---

## 3. Bundle threading — mirrors `apply_node_reduced_motion`

- `bundle_writer.apply_node_form_state(nodes, node_fs)` — attach `n["form_state"] =
  _style.redact_form_state(fv)` for each node with a delta; runs BEFORE `cf.redact_node`
  (which preserves the `form_state` key — not a `CONTENT_KEYS` entry). No entry / empty → no field.
- `assemble(...)` gains trailing kwarg `node_form_state=None`; call placed immediately after
  `apply_node_reduced_motion(...)`, before `cf.redact_node`.
- `main`: after the `_node_reduced_motion` pop, before `skeleton.pop("_node_backend", None)`:
  `raw = skeleton.pop("_node_form_state", {}); node_form_state = {int(k): v for k, v in raw.items()}`;
  extend the `assemble(...)` call with `, node_form_state=node_form_state`.

---

## 4. Redactor — `redact_form_state = redact_theme` (alias)

The per-node delta is the flat `{label:{prop:value}}` theme shape (labels `checked`/`disabled`),
so its redactor is the SAME walker — an alias, exactly like `redact_reduced_motion` /
`redact_pseudo_state` / `redact_responsive`. (Contrast `redact_keyframes`, a genuine walker for
the `[{timing,frames}]` shape.) Added in `_style.py` after `redact_reduced_motion`.

---

## 5. Content-free invariants & the `cursor` surface

- `backendNodeId` / `_node_*` / transient `nodeId` never reach disk (firewall + on-disk gate).
- The delta redactor (`redact_theme`) is a PASSTHROUGH (it does not strip values), so
  `content_firewall.audit_bundle` is the SOLE backstop for content in delta values. A prose-canary
  test plants prose at `form_state.checked.<prop>` and asserts the audit trips (TDD inversion — the
  key-aware `_walk_strings` already recurses all keys, as proven for reduced-motion).
- **`cursor` content surface — FIREWALL FIX (post-canary).** `cursor:url(...)` can embed a path.
  The url() canary (commits `4afd185` probe / `fc440d5` fix / `e0d84d6` test) revealed the firewall
  only flagged URLs ending in a media/font extension (`_CONTENT_URL` allowlist) — so `url(x.cur)`
  AND any external asset URL without a recognized extension inside a delta value (e.g.
  `background-image: url(https://cdn/x)`) leaked. This was a PRE-EXISTING gap, not new to
  form-state. Fix: `_CSS_URL_REF = url\(\s*\\?["']?\s*https?://` (extension-agnostic, matches the
  `url(`-wrapper). Chrome serializes the value quoted → json.dumps escapes the quote on disk
  (`url(\"https…`), so the regex tolerates the escaped quote; the `url(`-wrapper avoids firing on
  the bundle's bare top-level `url` field or `url(#fragment)` refs. The canary uses the REAL
  serialized shape (probe `probe_url_shape.py`) to avoid a false green. All 5 regression gates +
  the 32-test firewall suite stay green after the fix.

---

## 6. Tests & gates

**Unit (pure / mocked — implementer-run + static AST check):**
- `_style`: `redact_form_state is redact_theme`; round-trips a `{"checked":{...}}` delta;
  `redact_form_state(None) is None`.
- `bundle_writer`: `apply_node_form_state` attaches redacted delta to a node with an entry, skips
  a node with none; None / `{}` → no field.
- `web_skeleton`: `FORM_PROPS` curated (opacity/accent-color/cursor present; layout props absent);
  `FORM_STATE_SELECTORS` exact strings; `capture_with_form_states` diffs base vs each state with a
  DISTINCT backend≠node_id mock (`{0:5,1:7}`), asserts the sidecar keys by node_id, querySelectorAll
  selector per state, forcePseudoState set-then-clear sequence, and emulation/force cleared on error.
- `content_firewall`: prose canary on `form_state`; **cursor url() canary** on
  `form_state.disabled.cursor`.

**Host CDP gate (CONTROLLER-run, sandbox disabled) — `fixtures/form-state/run_form_state.py`:**
Synthetic offline page proving, content-free:
- a checkbox with `input#cb:checked{}` → `form_state.checked` carries the rule's props;
- **a combinator sibling `#cb:checked ~ #panel{}` → the PANEL node (not the checkbox) carries the
  delta** (FS5 — the dominant case, must be in the gate per advisor);
- a `<button>` with `button:disabled{}` → `form_state.disabled` carries opacity/cursor/color/bg;
- **a plain `<div>` + a bare `:disabled{}` rule → NO `form_state` field** (FS3 smear-negative,
  proves targeting);
- a text `<input>` + a bare-ish `input:checked{}` rule → no `checked` field (type-targeting);
- no `_node_form_state`/`_node_backend`/`backend` on disk; `bundle_writer` audit CLEAN.
Nodes identified by bbox size (motion-gate convention; controls sized distinctly).

**Real-site harness (after-task, controller-run) — `fixtures/form-state/validate_realsite.py`:**
Content-free signal only (host netloc, counts, changed-prop NAMES, per-prop freq, delta-size dist).
Precision heuristic differs from reduced-motion: UA disabled styling greys ~every control
(FS2 color→rgb(84,84,84)), so a HIGH `:disabled` node count is EXPECTED, not over-capture; the
smear signal to watch is deltas on nodes that are neither state-eligible nor combinator-reachable.

---

## 7. Ceilings (documented, not silently dropped)

- States limited to `checked`/`disabled`; the rest of the form-state family deferred (§1).
- `cursor` INCLUDED (deliberate deferral-break, §1); custom-cursor `url()` relies on the firewall
  URL backstop (§5) — covered by the url() canary.
- `DOM.querySelectorAll` does NOT pierce shadow DOM / iframes → form controls inside web
  components or cross-frame get no `form_state` delta (consistent with the main-frame focus of the
  other regimes).
- `:checked` is forced per element independently; radio-group mutual exclusion is NOT modeled
  (each radio's checked appearance is captured in isolation — the design intent, since we want each
  control's checked styling, not a runtime group state).
- A button-internal box may carry the button's own `:disabled` delta (FS-benign) — faithful,
  button-internal, not foreign smear.
- `accent-color` (new prop) is a color/keyword value — content-free; redacted as any other.

---

## 8. New code surface (summary)

| File | Change |
|---|---|
| `scripts/_style.py` | `redact_form_state = redact_theme` alias |
| `scripts/web_skeleton.py` | `FORM_PROPS`, `FORM_STATE_SELECTORS`, `capture_with_form_states`, `--form-states` flag + branch |
| `scripts/bundle_writer.py` | `apply_node_form_state`, `assemble` kwarg, `main` pop/cast |
| `scripts/test_*.py` | unit tests above |
| `scripts/test_content_firewall.py` | prose canary + cursor url() canary |
| `fixtures/form-state/run_form_state.py` | host CDP gate |
| `fixtures/form-state/validate_realsite.py` | content-free real-site harness (after-task) |
| `.gitignore` | `fixtures/form-state/_sk.json`, `_tokens.json`, `_bundle/` |
| `docs/plans/probe-runner-engine-capture-gaps.md` | `§C9-R-P14` results + roadmap footer (after-task) |
| `scripts/content_firewall.py` | **REVISED:** `_CSS_URL_REF` url()-wrapper detector (closes the pre-existing extension-allowlist gap surfaced by the cursor canary — §5) |

`content_firewall.py` was REVISED (not unchanged): the cursor canary forced a real firewall fix
(`_CSS_URL_REF`). See §5. The prose-detection path is unchanged.
