# ARIA landmark-role enrichment — design

**Type:** capture-engine feature (additive). Adds a content-free, computed-ARIA-**landmark**
role to each skeleton node, sourced from CDP `Accessibility.getFullAXTree`, joined to the
DOMSnapshot in one session. Geometry `role` is left untouched.

**Grounding:** de-risked by `§C9-R-aria-probe` (`research/capture-gap-probes/probe_aria_recurrence.py`).
The probe proved the AX-role join is **deterministic** (Floor A jac 1.0), **content-free**
(in-memory enriched `skeleton.json` audits CLEAN), and that a **landmark anchor** recovers
genuine recurring site-chrome components (python.org: landmark core=5, jac 0.71) that the 5
geometry buckets (`§C9-R-G3c-calib`) could not express. The win is **modest and
site-size-dependent** (small sites: ≈none) — this rung delivers the capture primitive; the
cross-route G3c consumer is a separate, later decision.

## 1. Scope

**In:** an additive optional `aria_role` node field, set ONLY when the node's browser-computed
ARIA role is in a fixed **landmark allowlist**; sourced from `getFullAXTree` at the DOMSnapshot
REST state; joined via the existing internal `backendNodeId`. Pure parse/filter/attach cores +
one new CDP call. Unit tests + a firewall canary + a host gate.

**Out:** non-landmark roles (links/listitems/headings/etc. — the probe showed they recur
trivially and inflate noise); overwriting geometry `role`; any consumer rewrite
(`bundle_writer`/`web_vectors`/`skeleton_diff` are untouched — additive); the G3c component
synthesizer (separate rung); non-CDP engines (safari/android get no `aria_role` — graceful).

**Path scoping (important).** `_snapshot_skeleton` is shared by `_capture_one`, which every
`capture_with_*` variant (themes, breakpoints, viewports, container-queries, keyframes,
reduced-motion, form-states) calls — several call it **multiple times and then merge/transform**
the node lists (`merge_breakpoints`, the viewport merge). `aria_role` is guaranteed **only on
the base single-snapshot path** that `site_capture`/G3a emit per route — which is exactly what
the (future) G3c consumer reads. Whether the multi-snapshot **merge/post-process** transforms
preserve the new key is **explicitly out of scope and not relied upon** (those transforms
reconstruct node lists; key-preservation is unverified and irrelevant to G3c). The host gate
asserts `aria_role` on the base path only. (Consequence: `getFullAXTree` fires once **per
snapshot**, so a 5-width breakpoint capture makes 5 AX calls — expected, not a regression.)

## 2. The field: `aria_role`

- Emitted on a skeleton node **only when** a landmark role is present (mirrors the conditional
  `substrate`/`pseudo` precedent — absent, not `null`, otherwise). Consumers read
  `n.get("aria_role")`.
- Value is a single canonical role string from the allowlist (§4) — never author free text.
- **Geometry `role` is unchanged.** `aria_role` is a parallel, additive axis. No schema/version
  bump (additive-key precedent: `pseudo`, `substrate`, `token_ref`).
- It is a **mechanism** key (not content): `content_firewall.redact_node` preserves any key not
  in `CONTENT_KEYS`, and `classify_node` already buckets non-image/text/svg roles as
  `mechanism`. No firewall code change.

## 3. LANDMARK_ROLES allowlist (13)

```
banner, navigation, main, contentinfo, complementary, region, search, form,   # 8 ARIA landmarks
article,                                                                        # document region
menubar, tablist, toolbar, dialog                                               # region-like composites
```

A computed role outside this set yields **no** `aria_role` (the node is simply un-enriched).
This fixed allowlist is the content-safety boundary: arbitrary author `role="..."` text can
never reach disk. Defined once as a module constant in `web_skeleton` (a tunable; documented).

## 4. Capture & join

In `web_skeleton._snapshot_skeleton(ev, url, width)` — which already owns the DOMSnapshot,
`to_skeleton`, and returns `node_backend = {node_id: backendNodeId}` — after the skeleton is
built and **at the same REST state**:

1. Guard: only when `hasattr(ev, "sess")` (CDP transport). Non-CDP engines skip silently.
2. Best-effort `ev.sess.send("Accessibility.enable", {})` (ignore failure).
3. **Best-effort** `ax = ev.sess.send("Accessibility.getFullAXTree", {})` — one extra CDP call; on failure, skip enrichment and return. `aria_role` is additive, so a CDP/AX failure must NOT fail the shared base capture (every `capture_with_*` path goes through `_snapshot_skeleton`).
4. `role_by_backend = landmark_roles(ax, LANDMARK_ROLES)` (pure, §5).
5. `apply_aria_roles(sk["nodes"], node_backend, role_by_backend)` (pure, §5).
6. Return `sk` (nodes now carry `aria_role`); signature of `_snapshot_skeleton` unchanged.

The `backendDOMNodeId` (AX) ≡ `backendNodeId` (DOMSnapshot) id space — **empirically validated
by the probe** (78%/96% join coverage with sensible roles). `backendNodeId` stays internal
(never emitted), consistent with existing use.

## 5. Pure cores (unit-testable, no I/O)

```python
def landmark_roles(ax_tree, allow):
    """{backendDOMNodeId: role_value} for non-ignored AX nodes whose role.value is in `allow`.
    Reads ONLY role.value — never name/description/value (accessible-name = content)."""
    out = {}
    for n in (ax_tree or {}).get("nodes", []):
        if n.get("ignored"):
            continue
        bk = n.get("backendDOMNodeId")
        role = (n.get("role") or {}).get("value")
        if bk is not None and role in allow:
            out[bk] = role
    return out

def apply_aria_roles(nodes, node_backend, role_by_backend):
    """Set node['aria_role'] for each node whose backendNodeId has a landmark role.
    Mutates nodes in place; leaves the key ABSENT when no landmark role."""
    for n in nodes:
        r = role_by_backend.get(node_backend.get(n["id"]))
        if r:
            n["aria_role"] = r
```

Fed synthetic `getFullAXTree` JSON, both are fully deterministic and offline-testable.

## 6. Content-free posture

- **Allowlist** ⇒ only short W3C structural tokens (≤14 chars) ever emitted; no author text;
  no `name`/`description` ever read.
- Firewall **unchanged**; `aria_role` is a mechanism key (preserved by `redact_node`, classed
  `mechanism` by `classify_node`); role values are far under the `_PROSE` ≥25-char threshold.
- **Canary test:** a synthetic AX node with a non-allowlist / long garbage `role.value` must
  produce **no** `aria_role` (dropped before emit), and an enriched bundle must `audit_bundle`
  CLEAN. (Update `redact_node`'s mechanism-keys docstring to mention `aria_role` — doc only.)

## 7. Consumers

Purely additive. `derive_slots` (geometry role → asset slots), `web_vectors` (`role=="svg"`),
`skeleton_diff` (`role` equality + `role=="text"` font branch), `_states`/`_consent`/`_substrate`
(copy `role` through) are **all unaffected** — they read `role`, not `aria_role`. A future G3c
synthesizer would anchor on `aria_role ∈ LANDMARK_ROLES`.

## 8. Determinism & verification

- `getFullAXTree` at REST + allowlist filter is deterministic (probe Floor A jac 1.0).
- Re-confirm in the host gate: capture a landmark page twice → identical `aria_role` assignments.

## 9. Testing

- **Unit (`test_web_skeleton.py` additions or a new `test_aria_roles.py`):** `landmark_roles`
  filters to allowlist, skips `ignored`, reads only `role.value`; `apply_aria_roles` sets the
  field by backend join and omits it when absent; the canary (garbage role → dropped).
- **Firewall test (`test_content_firewall.py`):** a skeleton node carrying `aria_role:"navigation"`
  audits CLEAN; a node that somehow carried a prose-length `aria_role` would trip (proving the
  field is scanned) — but the allowlist makes that unreachable in practice.
- **Host gate (`fixtures/aria/run_aria.py`):** capture a synthetic landmark-bearing page (own
  fixture markup, content-free), assert `aria_role` lands on `nav`→navigation / `header`→banner
  / `footer`→contentinfo / `main`→main, assert `audit_bundle` CLEAN, assert determinism (two
  captures identical), on the **base single-snapshot path** only. Controller runs it on host
  Bash (`dangerouslyDisableSandbox=true`; CDP unreachable from sandbox). **Fixture caveat:**
  `region` is AX-exposed only when the `<section>` has an accessible name — do NOT assert a bare
  `<section>` yields `region`; give the fixture's region/article an `aria-label` if asserting it
  (the label is the FIXTURE's own markup, not captured — only the role is read).

## 10. Files

- **Modify** `scripts/web_skeleton.py`: add `LANDMARK_ROLES`, `landmark_roles()`,
  `apply_aria_roles()`; the guarded `getFullAXTree` call + join in `_snapshot_skeleton`.
- **Modify** `scripts/content_firewall.py`: `redact_node` docstring mention of `aria_role` (doc
  only; no logic change).
- **Create** `scripts/test_aria_roles.py` (pure-core + canary units).
- **Modify** `scripts/test_content_firewall.py`: `aria_role` audit-clean assertion.
- **Create** `fixtures/aria/run_aria.py` (+ synthetic fixture markup) host gate.

## 11. Ceilings (documented, honest)

- **CDP/chrome-only.** Safari/android skeletons carry no `aria_role` (graceful absence).
- **Computed-role coverage.** Most nodes are non-landmark → no `aria_role` (by design). On
  small sites few landmarks exist → little signal (probe: iana landmark core=1).
- **Main-frame AX.** `getFullAXTree` covers the main document; cross-frame/OOPIF landmarks may be
  absent (consistent with existing OOPIF substrate ceiling).
- **One extra CDP call** per capture (`getFullAXTree`), at REST state.
- **Not a recurrence guarantee.** This delivers the landmark capture primitive; whether G3c
  component recurrence clears a bar is a later, separately-judged decision (`§C9-R-aria-probe`).
  Adding `token_ref` to a future signature would, per `§C9-R-G3c-calib` (specificity↑⇒recurrence↓),
  more likely lower recurrence than raise it — a tunable, not a free gain.

## 12. Commits

Single-line, no trailers. One commit per task; a review-driven fix gets its own commit. Stage
explicit paths only. No push. Host gate run by the controller after the implementing commits.
