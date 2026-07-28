# Multi-Route Site Capture (G3a) — Design Spec

**Status:** approved design (2026-06-01). Rung G3a of the G3 multi-route ladder.

**Goal:** Drive the existing per-route capture pipeline across an explicit list of
URLs and emit one self-contained, firewall-gated bundle per route plus a content-free
`site.json` manifest that is the stable interface later merge rungs (G3b/c/d) consume.

**Architecture:** A new orchestrator (`site_capture.py`) loops the explicit route list
and, per route, subprocess-chains the already-gated CLIs `web_skeleton` → `web_tokens` →
`bundle_writer` into `routes/<id>/` (the same subprocess pattern the `validate_realsite`
harnesses already use). It captures **nothing itself** — it only invokes gated tools and
tallies their outputs — so it introduces **zero new content-extraction surface**. A pure
helper (`_site.py`) assembles the manifest from per-route result rows (CDP-free, unit
testable). The whole site tree (`site.json` + every route bundle) is re-audited through the
**unchanged** `content_firewall.audit_bundle` before the run is declared clean.

**Tech Stack:** Python 3 stdlib; CDP via the existing `web_*` CLIs (no direct CDP in the
orchestrator); `subprocess` for the per-route chain; pytest for the pure core; a local
`http.server` + host-Chrome integration gate for the browser path.

---

## §1 — Scope & intent

### The G3 ladder (full synthesis is the committed target)

The user committed to **tokens + components + layout** cross-route synthesis as the
destination. That is four rungs of work; this project builds one probe-grounded,
TDD'd rung per cycle. G3a is the **build-order foundation**, not a reduced scope:

| Rung | Builds | Depends on |
|---|---|---|
| **G3a (this spec)** | Route orchestration → per-route bundles + content-free `site.json` | — |
| *(recurrence probe)* | Empirical study on G3a's real output (see §1.2) | G3a |
| **G3b** | Cross-route token/scale merge → unified palette | G3a + probe |
| **G3c** | Recurring-component synthesis (content-free signature match) | G3b + probe |
| **G3d** | Cross-route layout/skeleton reconciliation | G3b + G3c |

G3a delivers working, testable software on its own (a multi-route capturer with a site
manifest). G3b–G3d are committed follow-on rungs, each its own spec → plan → build cycle.

### §1.1 — `site.json` is the merge contract

The manifest layout is the interface G3b/c/d read. Designing G3a blind to merge needs
would force rework, so the contract is fixed now: **stable per-route `route_id`s**,
**self-locating bundle paths**, and a **cheap per-route recurrence hint** (`node_count`).
No empty merge fields are pre-added (YAGNI) — JSON is extensible, so later rungs append
fields (token-frequency rollups, component signatures) without breaking the schema. The
anti-rework requirement is satisfied by stable IDs + self-describing bundle paths, not by
speculative slots.

### §1.2 — The real unknown is recurrence, and it is deferred (correctly)

Multi-route *navigation* is trivial (N routes = N navigates). The unknown that gates the
merge rungs is empirical: **do a real site's tokens / components / layouts actually recur
across routes, matchable content-free by structural signature (role / tag / bbox-class /
`token_ref`) rather than by text?** That study needs real multi-route captures as input,
so the recurrence probe runs on G3a's output **after G3a lands, before G3b is designed** —
it is explicitly out of scope for G3a.

---

## §2 — Route source & input

**Explicit list only** (crawl deferred — see §9). Routes come from either or both of:

- `--urls-file PATH` — one URL per line; blank lines and `#`-prefixed comment lines
  ignored; leading/trailing whitespace stripped.
- `--urls "u1,u2,…"` — comma-separated URLs on the command line.

Both may be supplied; the combined list is **deduplicated preserving first-seen order**.
An empty resulting list is a hard error (`die`). No page content is read to discover
routes ⇒ route discovery is fully content-free and the run is reproducible (a precondition
for the recurrence probe).

---

## §3 — Per-route capture

For each route URL `U` at positional index `i`, the raw scratch (`_sk.json`/`_tok.json`)
goes to a system tempdir `<scratch>` OUTSIDE the site tree (see §4 — `bundle_writer` audits
its whole `--out` dir, so raw pre-redaction handoff must not live under `routes/<id>/`); the
clean bundle goes into `routes/<id>/`:

1. `web_skeleton --url U --out <scratch>/_sk.json` *(+ transport flags, §3.1)*
2. `web_tokens   --url U --out <scratch>/_tok.json` *(+ transport flags)*
3. `bundle_writer --skeleton <scratch>/_sk.json --tokens <scratch>/_tok.json --out routes/<id>/`

Step 3 produces the standard bundle (`meta/skeleton/tokens/motion/substrate.json` +
`assets/manifest.json`) and runs the per-bundle firewall audit internally. Each `web_*`
navigates independently (two navigations per route) — correctness over speed for v1. On any
route failure `routes/<id>/` is removed so no partial/flagged files persist.

**Capture depth = skeleton + tokens only.** That is the minimal valid bundle
(`bundle_writer` requires `--skeleton` + `--tokens`; `--motion` is optional) and is exactly
what the merge rungs consume. Motion, states, and per-route regime flags
(`--breakpoints`/`--themes`/…) are **deferred** (documented ceiling, §9).

### §3.1 — Transport passthrough

`web_skeleton`/`web_tokens` resolve their transport via the shared `add_transport_args`
(`--cdp-port` / `--browser` / `--ios` / `--android` / `--serial` / `--url`). `site_capture`
does NOT reuse `add_transport_args` directly — that helper registers `--url`, which would
collide with the orchestrator's own `--urls`/`--urls-file`. Instead it declares the transport
flags itself and a `_transport_argv` forwarder rebuilds them (all of `--cdp-port`/`--browser`/
`--android`/`--ios`/`--serial`, but NOT `--url`, which is supplied per route) for every
subprocess, so one host browser at `--cdp-port` serves the whole run.

---

## §4 — Output layout & `route_id`

```
<out>/
  site.json
  routes/
    r00/  meta.json skeleton.json tokens.json motion.json substrate.json  assets/manifest.json
    r01/  …
```

`route_id` = `"r%02d" % i` (zero-padded positional index by deduped input order):
deterministic for a given ordered list and the stable correlation key the merge rungs
join on. The intermediate `_sk.json`/`_tok.json` (raw `web_skeleton`/`web_tokens` output)
are PRE-redaction content and MUST live in a system tempdir **outside** the site tree —
never in `routes/<id>/`. `bundle_writer` audits its whole `--out` dir and the site-root
backstop rglobs all of `<out>`, so any raw scratch inside the tree trips the firewall on
real content (confirmed on iana.org). The only durable per-route artifact is the redacted
bundle; on any route failure its `routes/<id>/` dir is removed so no partial/flagged files
persist and the failure stays isolated to that route.

---

## §5 — `site.json` (the merge contract)

```json
{
  "schema": "probe-runner/site-manifest@1",
  "hosts": ["example.com"],
  "route_count": 3,
  "ok_count": 2,
  "routes": [
    { "route_id": "r00", "url": "https://example.com/",
      "bundle": "routes/r00", "node_count": 412, "ok": true },
    { "route_id": "r01", "url": "https://example.com/pricing",
      "bundle": "routes/r01", "node_count": 388, "ok": true },
    { "route_id": "r02", "url": "https://example.com/broken",
      "bundle": "routes/r02", "ok": false, "error_kind": "skeleton_failed" }
  ]
}
```

- `hosts` — sorted distinct `urlparse(url).netloc` across routes (a site may span hosts).
- `routes[]` — one row per input route, **in input order**. Successful rows carry
  `node_count` (read from the written `skeleton.json`; cheap recurrence hint). Failed rows
  carry `ok:false` + a categorical `error_kind` (§7) and **no** `node_count`/bundle stats.
- `url` is the captured route URL, recorded consistently with the existing per-bundle
  `meta.json["url"]` posture — it is **input metadata the operator supplied**, not extracted
  page content.
- Counts (`route_count`, `ok_count`) are integers derived from `routes[]`.

`_site.build_site_manifest(rows)` (pure, in `_site.py`) assembles this from a list of
result rows; it performs no I/O and is unit-tested without CDP.

---

## §6 — Content-free posture & firewall backstop

**The orchestrator extracts nothing** — every byte of page-derived data is produced by the
already-gated `web_*`/`bundle_writer` tools, each of which the firewall already governs.
`site.json` adds only: positional `route_id`s, `url`s (= `meta.url`), netlocs, integer
counts, booleans, and categorical `error_kind`s. No page content, no resolved styles, no
subprocess stderr.

**`site.json` is a NEW on-disk artifact and is NOT exempt from proof.** Per the P14 lesson
("prove content-free with a canary, don't assert it"), the new persistence surface gets the
same backstop as every bundle: after writing `site.json`, `site_capture` calls
`content_firewall.audit_bundle(<out>)` on the **site root**. `audit_bundle` `rglob`s every
file under the directory, so this single call re-audits `site.json` **and** every per-route
bundle. A non-empty result is a hard failure: `site_capture` raises a content-free error
(only `kind` + `file` of the first few violations — **never** the `sample` field, which can
embed leaked content) and exits nonzero. `content_firewall.py` is **UNCHANGED** — verified
by a canary test (§10) that feeds prose into a manifest field and asserts the audit trips.

(`url` fields pass `audit_bundle` because the existing per-bundle `meta.json["url"]` already
does — the URL detectors target `url()`/asset content-URLs, not a bare page-URL field.)

---

## §7 — Failure isolation & `error_kind` taxonomy

One unreachable or content-suspicious route must not abort the whole site capture. Each
route runs in a try/guard; on failure the orchestrator records an `ok:false` row and
**continues** with the remaining routes. `error_kind` is a fixed, code-controlled category —
**never** subprocess stderr (a `ContentLeak` message can embed a content sample, the
`validate_realsite` rule):

| `error_kind` | Cause |
|---|---|
| `skeleton_failed` | `web_skeleton` subprocess exited nonzero |
| `tokens_failed` | `web_tokens` subprocess exited nonzero |
| `bundle_audit_failed` | `bundle_writer` exited with the reserved content-audit code (3) |
| `bundle_failed` | `bundle_writer` exited nonzero for any other reason |
| `skeleton_unreadable` | every step exited 0 but the bundle's `skeleton.json` is missing/invalid JSON (partial write / fs race / regression) — the post-success read is guarded so this isolates to the route instead of aborting the run |

### §7.1 — `bundle_writer` distinct exit code (required change)

Today `write_bundle` raises `ContentLeak` (already content-free: `kind`+`file` only), which
propagates **uncaught** through `main()` → exit 1, indistinguishable from a generic error.
So the operator cannot tell a content-suspicious bundle from an ordinary failure without
reading stderr. Fix: wrap the `write_bundle` call in `bundle_writer.main()` in
`try/except ContentLeak` → print a content-free marker to stdout and `return 3` (reserved
audit-fire code). All other exceptions keep propagating (exit 1). `site_capture` then maps
exit 3 → `bundle_audit_failed`, any other nonzero from the bundle step → `bundle_failed`.

---

## §8 — Code surface

- **`scripts/_site.py`** (new, pure core): `build_site_manifest(rows)` →
  the §5 dict. `rows` is a list of dicts `{route_id, url, bundle, ok, node_count?,
  error_kind?}`. Computes `hosts` (sorted distinct netloc), `route_count`, `ok_count`.
  No I/O, no CDP — unit testable in isolation (mirrors the `_theme`/`_style` pure-core
  pattern).
- **`scripts/site_capture.py`** (new, orchestrator CLI): parse `--urls-file`/`--urls` →
  deduped ordered list; `add_transport_args` for passthrough; `--out` site dir. Per route:
  run the §3 subprocess chain, classify success/failure into a row (§7), read `node_count`
  from the written `skeleton.json` on success. Then `build_site_manifest(rows)` →
  write `site.json` → `content_firewall.audit_bundle(<out>)` backstop (§6) → emit a
  content-free summary (`route_count`, `ok_count`). Exit nonzero if the site-root audit
  trips.
- **`scripts/bundle_writer.py`** (modify, §7.1): `main()` catches `ContentLeak` → exit 3.
- **Tests:** `scripts/test_site.py` (pure `_site` units),
  `scripts/test_bundle_writer.py` (extend: exit-3-on-ContentLeak),
  `fixtures/site/run_site_capture.py` (host CDP integration gate, §10).

---

## §9 — Ceilings (documented, not silently dropped)

- **Cross-route MERGE is deferred** — G3a emits per-route bundles + the manifest contract;
  unifying tokens/components/layout is G3b–G3d.
- **Auto-crawl deferred** — explicit list only (§2). A shallow same-origin crawl is a later
  increment; it would read page anchors (content-adjacent) and be nondeterministic.
- **Capture depth = skeleton + tokens** — motion/states/regime-flags per route deferred
  (§3). The merge rungs consume skeleton+tokens; motion does not merge across routes.
- **`route_id` is positional** — stable within one run (the only context the merge consumes),
  but it **shifts if the URL list is reordered or edited** across re-captures. Cross-run
  correlation is not a v1 goal; a content-addressed id (hash of normalized URL) is a noted
  future option if cross-run diffing is ever needed.
- **Cross-route state bleed** — the reused browser's **cookies / localStorage /
  sessionStorage persist across routes; navigation resets only the DOM, not storage.** A
  consent cookie set on `r00` can suppress `r01`'s banner; an A/B cookie can pin a variant —
  which **skews cross-route component recurrence** and is therefore a factor the recurrence
  probe (§1.2) must account for. Per-route storage isolation (clearing cookies/storage, or a
  fresh per-route context) is deferred to a future increment.
- **`url` query/fragment kept as-is** — recorded verbatim in `meta.url`/`site.json`
  (consistent with existing posture); the existing firewall governs, no extra redaction.
- **Per-route inherited limits** — shadow/iframe non-piercing, push-resolve drop-on-miss,
  etc., are inherited unchanged from `web_skeleton`/`web_tokens`.

---

## §10 — Test plan

**Pure unit (`scripts/test_site.py`, no CDP):**
- `build_site_manifest` shape: rows → §5 dict with correct `hosts` (sorted distinct
  netloc), `route_count`, `ok_count`, in-order `routes[]`.
- Mixed success/failure rows: failed rows carry `ok:false` + `error_kind`, no `node_count`;
  `ok_count` counts only successes.
- Netloc rollup across multiple hosts; single-host case.
- Dedup-preserving-order of the input list (helper for parsing) — empty list rejected.

**`bundle_writer` (`scripts/test_bundle_writer.py`, extend):**
- A bundle whose audit fires → `main()` returns exit 3 (not 1), and the marker printed is
  content-free (no `sample`).

**Firewall canary (pure, no CDP — `scripts/test_site.py` or `scripts/test_content_firewall.py`):**
- Write a minimal `<dir>/site.json` with an injected prose string in a manifest field, then
  assert `content_firewall.audit_bundle(<dir>)` returns a violation. Proves `site.json` is
  inside the firewall (not merely asserted content-free) against the **unchanged** firewall —
  the P14 lesson, run without a browser.

**Host CDP integration gate (`fixtures/site/run_site_capture.py`, controller-run):**
A local `http.server` serves a synthetic 3-route mini-site sharing one palette, where one
route is deliberately broken (e.g. serves malformed HTML or 404s) to exercise failure
isolation. Asserts:
- `routes/r00`, `routes/r01` bundles exist and are structurally valid (`skeleton.json` +
  `tokens.json` present); `site.json` matches the §5 schema with stable `route_id`s.
- The broken route records `ok:false` with the correct `error_kind` and does **not** abort
  the run; `ok_count` reflects the survivors.
- `site_capture` exits 0 on a clean run; the site-root `audit_bundle` backstop passes; no
  subprocess stderr is echoed anywhere in `site.json` or stdout.

The gate runs on host Bash with CDP reachable (the sandbox cannot reach CDP) — the
controller runs it, implementer subagents write it + static-check only.
