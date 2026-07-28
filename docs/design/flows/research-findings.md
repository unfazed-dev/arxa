# app_box — Flow Research Findings — 2026-07-28

Status: research complete. Grades: **[V]** verified (primary source read) ·
**[A]** assumed (inference, reason given) · **[U]** unknown. This doc grounds
the flow library; its findings feed the journey narratives and the flow docs in
this directory.

Inputs: 9 measured research docs (`docs/research/`) +
[`architecture.md`](../../plans/architecture.md) §1–§22. Every claim was
measured by running the thing, not inferred from reading it — where a claim was
later falsified, the correction is left in place.

---

## 1. Pipeline truth — the state machine and its gates [V]

**The FSM** (`architecture.md` §6):
```
intake → prototype → [GATE 1: approve] → design(freeze)
       → scaffold → review → [GATE 2: approve|reject] → ship
       → [GATE 3: confirm target+version+account] → released
```

- **Gates define stages.** A stage exists because a gate can judge it
  (`architecture.md` §6, from flutter-crew's discipline set). [V]
- **Deterministic gates fail loud and HALT — they never self-loop.** Only the
  LLM-authored portion may retry, bounded by `ESC_LIMIT` (`architecture.md` §6).
  [V]
- **Approval binds to a hash.** Gate 1's approval records the design's content
  hash. `done` exits non-zero if the design moved after approval
  (`architecture.md` §6). [V]
- **Gate 3 is a third human gate, the strictest.** It names target + version +
  account, requires explicit confirmation, and is the only gate that writes to
  the outside world (`architecture.md` §17). [V]

**SARIF sidecars** (`architecture.md` §5):
- Every gate, when `KIT_FINDINGS_OUT` is set, writes SARIF. Exit code and stdout
  unchanged. Takes gate observability from 6/22 to 22/22. [V]
- SARIF chosen for `partialFingerprints` (stable finding identity across runs →
  "is this the same failure as Tuesday?") and provenance block. [V]
- `work/history.jsonl` is append-only, never pruned — what the UI timeline
  renders. [V]

## 2. Prototype language — htmx MVVM, structure not pixels [V]

Measured in `docs/research/prototype-language.md` and
`headtohead-train-shell.md`:

- **LOC per screen:** 159 JSX / 118 HTMX / 596 Flutter. The asymmetry that
  outranks raw LOC: `new-flutter` produced **zero** reviewable artifacts. [V]
- **The htmx producer is already MVVM** (`architecture.md` §13): 8,454 lines
  of `_view`/`_viewmodel` pairs, `services/{repositories,facades}`, and
  fixtures. The freeze keeps 37 flat HTML files and re-infers `structure.json`
  from filenames. [V]
- **JSX translation captured 7 of 112 nodes** because the JSX was
  branch-matrixed on `role × state × params.branch`. Conditional rendering does
  not translate; declarative structure does (`architecture.md` §13). [V]
- **`tab → shell` is a pure rename table** (8 entries, zero fan-out) —
  `stage_shell` with tabs and eight `<tab>_shell`s are the same decomposition
  under two spellings (`architecture.md` §13). [V]

## 3. Targets & viewports — platform-only, viewports derive [V]

`architecture.md` §11, measured:

- **Zero platform awareness in the pipeline today.** Freeze renders at exactly
  one viewport, `390×844`, hardcoded in three places. [V]
- **`--targets` is platform-only; viewports derive.** `ios`/`android` → mobile
  + tablet; `web` → mobile + tablet + desktop; `macos`/`linux`/`windows` →
  desktop. Mobile is always present; viewport set is the union. [V]
- **Freeze widths from MD3 window size classes** (600/840 boundaries): render
  *inside* each class — 390 compact, 744 medium, 1280 expanded. Not the
  480/768/1024 Bootstrap triad. [V]
- **The coverage gate must read targets from state.** SCAFFOLD_GATE_E hardcodes
  the five-file set unconditionally. Deriving viewports from targets is not a
  flag change — the gate has to require exactly the derived set
  (`architecture.md` §11, §16). [V]
- **Layouts being invented are not stubs.** In `train_shell`: desktop is
  consistently larger than mobile (~1,600 lines across 12 files, every line
  inferred from a 390px render). [V]

## 4. Companion & credentials — OS vault, channel state [V]

`docs/research/remote-control-and-chat.md`, `architecture.md` §15:

- **QR pairing is LAN-local, TLS fingerprint pinned from the payload.** [V]
- **Credentials: OS vault** (`flutter_secure_storage` → macOS Keychain), never
  hand-rolled crypto; encrypted-file fallback only where no vault exists, key
  lives in the vault; UI states which tier is active. [V]
- **Verification standard: write → restart → read back, in a signed and
  notarised build.** Two macOS failure modes (App Group missing from
  `keychain-access-groups`, hardened runtime after notarisation) fail
  *silently and green*. [V]
- **Decision: shell out to an already-authenticated harness CLI where one is
  present; hold tokens only for the standalone case** (`architecture.md` §15).
  Owning a refresh loop for two vendors is permanent maintenance. [V]
- **The FAB carries channel state** (live / reconnecting / dead), driven by the
  paired channel's heartbeat — never by whether the WebView last painted
  successfully. A dead server showing a stale render during a client demo is
  the failure mode this feature invents. [V]

## 5. Competitors & pricing — per-seat backlash, BYO-key advantage [V]

`docs/research/competitors-and-pricing.md`:

- **FlutterFlow / Adalo / Lovable / Cursor pricing** surveyed. The per-seat
  backlash is the structural opening: solo developers resent paying per-seat
  for a tool they use alone. [V]
- **BYO-key is a structural cost advantage**, not a discount. Inference is the
  user's key, their cost, their control. The product's cost scales with the
  user's usage, not with a per-seat markup. [V]
- **The free tier is smaller, not crippled.** Free: designer + prototype. Paid:
  builder (scaffolding against real kits) + bundle (build + deploy). Someone
  who uses the free designer forever and hand-builds is a funnel, not a leak
  (`architecture.md` §17). [V]

## 6. Stub inventory — wired vs. what throws [V]

`docs/research/stub-inventory.md`:

- **5 of 23 kits are partial.** Stripe, PayPal, both auth providers, both map
  providers, and Vercel all throw `UnimplementedError`. [V]
- **Apple Pay is the only wired payment path.** The payment gate's *placement*
  stands; its *implementation* has no foundation in the kit yet
  (`architecture.md` §17). [V]
- **Three test tiers** (`docs/plans/stub-remediation.md`): Tier 1 (port +
  scripted fake — no toolchain, runs in CI), Tier 2 (simulator/emulator — UI +
  wiring only), Tier 3 (physical device — entitlements, certs, real tokens). A
  provider may only be **advertised at the tier it has passed**. [V]

## 7. Gates that cannot fail — the stale-green pattern [V]

`docs/research/spine-findings.md`, `architecture.md` §2c:

- **`dep_hash` keyed on `path:size:mtime_ns`** (asko): (a) false-invalidates on
  any clone, (b) goes **stale green** when content changes with mtime restored,
  (c) produces a ledger not portable between machines. **Rejected** — keep the
  ledger shape, hash content. [V]
- **`gen_freshness`** (flutter-crew): regenerate-and-diff — cannot be fooled by
  mtime because it never reads mtime. **Adopted.** [V]
- **An asset check that verified strings instead of resolving paths** — the
  `emit_htmx` asset bug, missed by three verification layers that all agreed
  the output was fine. [V]
- **A drift check guarded on a file the htmx producer does not have**
  (`[ -f "$DESIGN/jsx/app.jsx" ]`) — green by default for htmx. Fix: read
  `registry.json` when there is no `jsx/`; assert with `git status --porcelain`,
  not `git diff` (a producer that *adds* a surface is the expected case).
  `architecture.md` §14. [V]

## 8. Decisions for the flow library (open questions that shaped flows)

- **O2 — Licence model and price point** (`architecture.md` §10): comparables
  measured in `competitors-and-pricing.md`; no number chosen. The licence
  check's *placement* (before builder) stands; the *price* is open. Flows treat
  💳 as a precondition that runs before the phase, not a gate. [V placement, U
  price]
- **Payments are blocked on kit work**, not pipeline work: Stripe/PayPal are
  stubs; Apple Pay is the only wired path. The payment gate's implementation
  has no foundation yet (`architecture.md` §17). Flows show the gate surface;
  the underlying payment path is [U].
- **Delete is the CRUD hole** (`architecture.md` §18): the pipeline only
  writes; an orphaned scaffolded view whose registry entry was deleted keeps
  compiling, passing, shipping. Two things needed: an orphan assertion and a
  guarded delete path behind a human confirm. [V gap, A fix shape]

## Sources

**Repo:** [`architecture.md`](../../plans/architecture.md) §1–§22 ·
[`feature-crud.md`](../../plans/feature-crud.md) ·
[`stub-remediation.md`](../../plans/stub-remediation.md) ·
[`docs/research/`](../../research/README.md) (spine-rubric, spine-findings,
prototype-language, headtohead-train-shell, htmx-producer-test,
web-research-drift, remote-control-and-chat, competitors-and-pricing,
stub-inventory).
