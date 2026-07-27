# app_box — architecture

A shippable product that turns a client's design into a bespoke, opinionated
Flutter application in stacked MVVM, for mobile (iOS + Android, the default), web
(PWA) and desktop — with the pipeline, gates, memory, logs and a desktop UI that
makes it operable by someone who is not its author.

Evidence base: `.claude-flow/audit/app-box-spine-rubric.md` (pre-registered) and
`.claude-flow/audit/app-box-spine-findings.md` (measured). Read those first; this
document assumes their conclusions.

---

## 1. Personas

Four of the five are the same human in different modes. Designing for "the solo
developer" as one persona is what produces a tool that only its author can run.

### P1 — Evan, in **client-intake mode**
Has a signed client, a brief, maybe a Figma or a set of HTML mocks. Needs to turn
that into a frozen, approvable design and quote a delivery date.
- *Wants:* how many surfaces is this, what's already covered by kits, what's bespoke.
- *Fails today:* nothing gives a surface count before work starts. `structure.json`
  now can, but only after a producer has run.
- *Success:* a surface inventory and a coverage estimate within an hour of intake.

### P2 — Evan, in **autonomous-build mode**
Design is frozen and approved. Wants to walk away and come back to graded work.
- *Wants:* the loop to run unattended, stop on a red gate rather than plough on,
  and leave a legible trail of what it did.
- *Fails today:* `--fix-cmd` dispatch works, but every surface costs a model call
  and nothing is reproducible; re-running produces different code.
- *Success:* comes back to N surfaces built, each with a green gate record, and a
  diff he can actually review.

### P3 — Evan, in **red-gate recovery mode**
Something failed. This is where tools are actually judged.
- *Wants:* which gate, which check, which file, which line, what it expected —
  without reading a scrollback.
- *Fails today:* 16 of 22 gates print to stdout only. If the terminal is gone, the
  finding is gone.
- *Success:* clicks the red gate in the UI, sees the finding with file/line and the
  exact command to reproduce it.

### P4 — Evan, in **ship mode**
Client approval, then three platform builds.
- *Wants:* proof that what he's shipping is what was approved; per-platform builds
  that are genuinely native, not a phone layout stretched.
- *Fails today:* approval is not bound to a design hash, so an approved review can
  survive a design change.
- *Success:* `done` exits non-zero if the design moved after approval.

### P5 — **The buyer** — a different person entirely
Bought app_box. Has none of your paths, repos, conventions or context. This
persona is the hard filter, and the reason D4 was scored as a gate.
- *Wants:* install it, point it at a design, get an app.
- *Fails today, measured:* asko hard-codes another repo's absolute path as a
  default (`orchestrate.py:45`); flutter-crew has 27 tracked files containing
  `/Volumes/`, including production code. stacked_kit is the only clean repo
  (0 absolute paths in 1,244 tracked files).
- *Success:* `app_box init` on a fresh machine with no `~/Developer` produces a
  working run.

---

## 2. What app_box takes from where

Settled by the measured findings — one execution model, not a blend of three.

| from | what | why (measured) |
|---|---|---|
| **flutter-crew** | the **stage contract**: one module, `--self-test`, JSON emit | 29/32 stages emit JSON; 22/32 self-test; 628 assertions |
| **flutter-crew** | **regenerate-and-diff freshness** (`gen_freshness.py`) | cannot be fooled by mtime because it never reads mtime |
| **flutter-crew** | the **`ViewModelBase` / `ViewModel` split** | regenerated base + hand-editable subclass — the only pattern here that lets determinism and hand edits coexist |
| **flutter-crew** | **dual harness manifests** | already ships `.claude-plugin` *and* `.zcode-plugin` |
| **asko** | the **ledger** — `run.json` + `history.jsonl` | S3 staleness propagation and S5 from-scratch both pass |
| **asko** | **fault-injected smoke** (S4) | the only repo that attacks its own gates |
| **asko** | the **`input/ work/ output/`** root layout | the decoupling the user asked for, already built |
| **stacked_kit** | the **22 kits + 73 design checks** | the domain opinion; expensive and irreplaceable |
| **stacked_kit** | **two human gates + `ESC_LIMIT`** | the only formal approval semantics in the corpus |
| **stacked_kit** | **adversarial twin discipline** | 221 suite assertions, all green, tree clean |
| **factory** | **packaging** — `install.sh`, relative symlinks, one tool per dir | portable by construction |

**Explicitly rejected:** asko's `dep_hash` as written. It keys on
`path:size:mtime_ns`, which was proven to (a) false-invalidate on any clone,
(b) go **stale green** when content changes with mtime restored, (c) produce a
ledger that is not portable between machines. Keep the ledger shape, hash content.

**Explicitly rejected:** porting stacked_kit's gates into flutter-crew's contract.
Sidecars (§5) buy the same property without re-proving 221 assertions.

---

### 2b. What the industry research contributes

Named as an input in the request; recorded here so the provenance of each decision
is traceable, including one place it contradicts an earlier claim of mine.

- **Content-addressed stores (Nix, Guix)** key on content, never timestamps. This is
  exactly the `dep_hash` correction — the stale-green defect is the failure mode
  content addressing was invented to remove. Not preference; a solved problem.
- **Hermeticity means no network during a build**, not artifacts committed to VCS.
  This corrects an over-read of mine earlier in this work: the research does *not*
  support committing render evidence to git. It supports the `none` mode and
  network-free stage execution.
- **SARIF** carries `partialFingerprints` (stable finding identity across runs) and
  a provenance block. Both are things a bespoke schema would have to reinvent, and
  the first is what makes the UI's "is this the same failure as Tuesday?" answerable.
- **Evaluator–optimizer**: the gate produces the critique, a separate generator
  consumes it. Already the FSM's shape; asko cites it by name in `orchestrate.py`.
  The discipline it implies — the evaluator never authors what it grades — is
  precisely what the `--fix-cmd` seam exists to enforce.
- **Durable execution**: run state lives outside the process and is resumable. Why
  `run.json` and `history.jsonl` sit at the root rather than inside `output/`, and
  why closing the desktop app cannot lose a run.

### 2c. Inherited debt — closed, not copied

Found while verifying the mechanisms rather than reading about them:

- flutter-crew's shipped test fixture is **already drifted** — its own freshness gate
  exits 1 against it. The gate is not run against its own fixture.
- **10 of 32 stages have no `--self-test`**, including `run_pipeline.py` (the
  orchestrator) and `emit.py`. Three of them are inside the 7 modules asko vendored.
  `generate_view.py` does self-test, which is what contains step 5's risk.
- asko's smoke suite leaves **5 tracked files dirty** and leaks **4 design literals**
  into pipeline code.

app_box's smoke suite starts with genericity and tree-clean green, and no stage
ships without a self-test.

## 3. Layout

```
app_box/
├── input/           ← intake. Retargetable: --input <path>
│   ├── designs/<client>/<design>/     frozen 6-file contract + surfaces/
│   └── briefs/                        client brief, constraints, brand
├── process/         ← app_box's own machinery. Never client-specific.
│   ├── stages/          one module per stage, --self-test, JSON emit
│   ├── gates/           wrapped stacked_kit gates + new ones
│   ├── kits/            vendored stacked_kit (clean tag, PROVENANCE.md)
│   ├── harness/         adapters: claude-code, kimi-code, api, none
│   └── memory/          MEM-A (see §4)
├── work/            ← run state. Disposable, reproducible.
│   ├── run.json         ledger: stage → status, content_hash, outs, ts
│   ├── history.jsonl    append-only; every transition, forever
│   ├── findings/        SARIF per gate per run
│   └── logs/            per-stage stdout+stderr, retained
└── output/          ← the generated app. Retargetable: --output <path>
    ├── app/             the Flutter app. Knows nothing about app_box.
    └── MEM-B.md         travels WITH the app (see §4)
```

Two invariants, both testable:
1. **`process/` never contains a client literal.** This is asko's failing smoke
   S6 (4 design literals leaked into pipeline code) turned into a gate app_box
   passes from day one.
2. **`output/app/` contains no reference to app_box.** The delivered app must
   build with plain `flutter build` on a machine that has never seen this tool.
   That is the "decoupled, self-contained, isolated" requirement, made mechanical.

---

## 4. Two memory systems

Agreed during the grilling; the split is by **lifetime and ownership**, which is
what makes each independently useful.

### MEM-A — `process/memory/` — *how app_box behaves*
- **Owns:** gate failure patterns and their fixes, harness quirks, kit capability
  index, "this check fails this way for this reason" lessons.
- **Lifetime:** the product's. Ships with app_box, improves across all customers.
- **Shape:** stacked_kit's existing memory system (`test_memory.sh`, 33/33) — it
  already works and is already tested. Not rebuilt.
- **Precedent:** asko's `read_notes(key)` feeds prior failure notes back into the
  next run's error message. That loop is the mechanism worth copying.

### MEM-B — `output/MEM-B.md` — *what happened to this app*
- **Owns:** decisions taken for this client, surfaces built and why, deviations
  from the frozen design and their approvals, what the client rejected.
- **Lifetime:** the app's. Travels with the delivered codebase.
- **Why separate:** a customer who buys app_box must not receive your other
  clients' decisions. This split is a confidentiality boundary, not just tidiness.
- **Precedent:** flutter-crew's `docs/ORIENTATION.md` — *"the file a NEW agent
  session reads FIRST… the memory file the crew was missing"* — replacing a
  `HANDOFF.md` that self-declared stale. Bounded (≤10 lines of current state),
  because an unbounded memory file is read by nobody.

Neither reads the other. MEM-A must work with `output/` deleted; MEM-B must be
readable by someone who has never installed app_box.

---

## 5. Findings, logs and the UI contract

The desktop UI is not a separate concern — it is the reason the observability
work has to happen. **A gate that only prints cannot be drawn.**

- Every gate, when `KIT_FINDINGS_OUT` is set, additionally writes **SARIF** to
  that path. Exit code, stdout and logic are unchanged. This takes D6 from 6/22
  to 22/22 without touching a single existing assertion.
- SARIF because it is an OASIS standard with `partialFingerprints` (stable
  finding identity across runs → "is this the same failure as last time?") and a
  provenance block. A bespoke schema would have to reinvent both.
- `work/logs/<stage>.log` retains full stdout+stderr per stage. app_box currently
  deletes its temp output; that stops.
- `work/history.jsonl` is append-only and never pruned. It is what the UI's
  timeline renders and what makes "what changed since Tuesday" answerable.

---

## 6. The state machine

stacked_kit's FSM, kept — it is the only one with real human gates.

```
intake → prototype → [HUMAN GATE 1: browser-approve] → design(freeze)
       → scaffold → review → [HUMAN GATE 2: approve|reject] → ship
```

Two rules imported from flutter-crew's discipline set, because they are what make
the loop trustworthy:
1. **Gates define stages.** A stage exists because a gate can judge it.
2. **Deterministic gates fail loud and HALT — they never self-loop.** Only the
   LLM-authored portion may retry, bounded by `ESC_LIMIT`.

**New: approval binds to a hash.** Human Gate 2's approval records the design's
content hash. `done` exits non-zero if the design has moved since. Hard failure on
the source hash; warning on the frozen-artifact hash, since re-emission can change
bytes without changing intent.

---

## 7. LLM surface — hybrid

Three interchangeable backends behind one interface, selected per run:

| mode | how | for |
|---|---|---|
| `harness` | shells out to the CLI in the session (`claude`, `kimi`, …) | P2 — Evan, already in a harness, no API key needed |
| `api` | direct API with the buyer's own key | P5 — the buyer, running app_box standalone |
| `none` | deterministic stages only; LLM stages skipped, marked `blocked` | CI, reproducibility proofs, and the honesty check |

`none` is not a degraded mode — it is the measurement that keeps D1 truthful. The
fraction of the app producible under `none` is app_box's determinism, reported
per run rather than asserted in a README.

---

## 8. The desktop app

**Recommendation: Flutter desktop.** It is dogfooding — app_box's UI becomes the
first bespoke stacked-MVVM app app_box is judged by, and every rough edge in the
generated architecture is one you feel daily. Alternative is Tauri/Rust; it is a
better shell but proves nothing about the product.

Bootstrap caveat, stated plainly: v1 of the UI must be hand-written, because
app_box does not exist yet to generate it. The dogfooding only starts at v2, when
the UI is regenerated through the pipeline. That is a real cost and it is the
reason this is a recommendation rather than a settled decision.

The UI is a **viewer and a controller, never a source of truth.** Everything it
renders comes from `work/` — `run.json`, `history.jsonl`, `findings/*.sarif`,
`logs/*`. Closing the app loses nothing; a run continues headless. This is what
makes "any harness CLI *or* the desktop app" honest rather than two divergent
implementations.

Screens, in build order: **Run** (stage timeline, live) → **Findings** (SARIF,
grouped by gate, file/line, reproduce command) → **Artifacts** (generated tree,
diff vs previous run) → **Intake** (design import, surface inventory, coverage
estimate) → **Memory** (MEM-A patterns, MEM-B decisions).

---

## 9. Build order

Each step ends with something runnable, and none is blocked on the desktop app.

1. **Skeleton + packaging.** `input/process/work/output`, `install.sh` with
   relative symlinks, `app_box init`. Gate: runs on a path with no `~/Developer`.
2. **Ledger.** asko's `run.json` + `history.jsonl`, **content-hashed**. Gate: the
   four mutation experiments from the findings doc, as tests — including E3, which
   asko fails today.
3. **Vendor stacked_kit** from a clean tag with a `PROVENANCE.md`. Gate:
   `test_gates.sh` 83/83 and `pipeline.sh selftest` 105/105 still pass vendored.
4. **SARIF sidecars** across all gates. Gate: 22/22 emit valid SARIF; exit codes
   and stdout byte-identical to before.
5. **Stage contract + first deterministic emitter.** Base is flutter-crew's
   `generate_view`, measured. Three additions, in dependency order:
   **(a) an HTML capture path** — `capture_design` is JSX-only and its bulk is
   React component expansion, which rendered HTML does not need; feeding it
   stacked_kit's already-branch-resolved `surfaces/<id>.html` is what removes the
   branch problem, and it is a new front-end for `build_spec`, not a flag.
   **(b) form-factor dispatch** — `ScreenTypeLayout` occurs 0 times in 22,738
   lines; the five-file surface set does not exist in its model.
   **(c) kit vocabulary** — it emits `Icons.*` and raw `SizedBox`/`EdgeInsets`;
   the kit demands `KitGlyphs.*` and the spacing helpers.
   Gate: one surface regenerates byte-identically twice, passes all 73 checks, and
   `gen_freshness` catches a hand-edit to the base.
6. **Harness adapters** — `harness` | `api` | `none`. Gate: the same design
   produces the same deterministic output under all three.
7. **Desktop UI**, screens in the order above.
8. **Smoke suite**, modelled on asko's seven properties, with S6 (genericity) and
   tree-clean green from the start — the two asko fails.

---

## 10. Open questions

1. ~~Full flutter-crew end-to-end run~~ — **done**, see
   `.claude-flow/audit/app-box-headtohead-train-shell.md`. It reaches Dart
   deterministically and its gates bite. Judged by stacked_kit's `enforce_design`:
   4 of 17 applicable checks failed, against 73/73 for the stacked_kit-built
   surface.
2. ~~Which of the three emitters is the base~~ — **flutter-crew's
   `generate_view`**, on evidence: the emitted Dart is clean and idiomatic and
   already uses the `ViewModelBase`/`ViewModel` split. It needs three additions
   before a surface can pass, which is now step 5's real scope.
3. **kit-designer prototype quality.** The requirement is that it match
   kimi-design's output. Nothing measured yet — needs a side-by-side.
4. **Licensing.** flutter-crew's `.zcode-plugin` declares MIT; stacked_kit
   vendors 39 git dependencies. A paid product needs that graph audited.
5. **Where app_box lives.** `factory/app_box/` matches the existing packaging
   convention, but factory is currently a personal repo.

## 11. Targets — one flag, two derived axes

Measured starting point: the pipeline has **zero** platform awareness. No
`--mobile/--tablet/--desktop/--web/--pwa`, no `PLATFORM`, no `targets` in
`pipeline.sh` or `freeze_design.sh`. The freeze renders at exactly one
viewport, `390×844`, hardcoded in three places (`freeze_design.sh:239`, `:269`,
`emit_htmx.py:346`). p2 ships `android/ ios/ web/` only; `web/manifest.json`
exists but nothing claims PWA. `ScreenTypeLayout` already appears in 16 p2
files — the *output* pattern is correct; only the *input* is phone-only.

### The proposed flag list conflates two axes

`--desktop-macos` fuses a **platform** (macOS) with a **viewport** (desktop).
They are independent: a web app is browsed on a phone; an iPad is iOS at tablet
width. Treating them as one flag makes `--web` ambiguous — one viewport or
three? — and there is no answer that is right for both PWA and desktop web.

- **Platform target** — `ios, android, web, pwa, macos, linux, windows`.
  Drives **ceremonies**: which platform folders exist, icons, splash, manifest,
  service worker, window sizing, native menus.
- **Viewport class** — `mobile, tablet, desktop`. Drives **design freeze
  widths** and the three layout files `enforce_design` already demands.

### Recommendation: `--targets` is platform-only; viewports derive

| target | ceremonies it turns on | viewports implied |
|---|---|---|
| `ios` *(default)* | Runner.xcodeproj, launch storyboard, Cupertino page transitions | mobile, tablet *(iPad)* |
| `android` *(default)* | `android/`, adaptive icons, splash | mobile, tablet |
| `web` | `web/index.html`, renderer choice | mobile, tablet, desktop |
| `pwa` | **web +** `manifest.json`, service worker, offline shell, install prompt | inherits web |
| `macos` `linux` `windows` | platform dir, `window_manager` min size, native menu bar | desktop |

Viewport set = union of the implied sets. Mobile is always present.
`--targets ios,android` (the default) therefore freezes **two** widths, not
three — and a phone-only client project never pays for desktop layouts it will
not ship. This is the mechanism that closes the responsive-input hole: it is a
producer change, driven by a value that already had to exist.

### What this actually costs — a gate must change

The five-file set is **unconditional today**. `scaffold_coverage_gate.sh:144`
(SCAFFOLD_GATE_E) hardcodes
`[_view.dart, _view.mobile.dart, _view.tablet.dart, _view.desktop.dart,
_viewmodel.dart]` and its own header says *"No partial credit"*, citing
`enforce_design` check 5. (Correction to an earlier note: the requirement lives
in the coverage gate, not in `enforce_design.dart`, which never mentions a form
factor.)

So a 2-viewport target set does not merely skip work — it **fails
SCAFFOLD_GATE_E**. Deriving viewports from targets is therefore not a
producer-only change: the coverage gate has to read targets from state and
require exactly the derived set. That is the honest scope, and it is larger
than "add a flag."

**And the layouts being invented are not stubs.** In `train_shell` alone:

| surface | mobile | tablet | desktop |
|---|---|---|---|
| today | 139 | 158 | **177** |
| stats_streak | 146 | 156 | **197** |
| session_runner | 80 | 121 | **131** |
| programme_calendar | 85 | 129 | **120** |

Desktop is consistently *larger* than mobile. These are genuinely distinct
layouts, roughly 1,600 lines across 12 files — every line of it inferred from a
390px render. That is the size of the hole, measured.

**Freeze widths, from MD3 window size classes** (600 / 840 boundaries): render
*inside* each class, never on its boundary — `390` compact, `744` medium,
`1280` expanded. Not the 480/768/1024 triad; those are 2010-era device widths
that Bootstrap fossilised, and current guidance is to treat them as legacy.

### Targets live in pipeline state, not in flags

Three surfaces will set targets — the desktop GUI, the harness skill
invocation, and the CLI. If targets are a flag, those three drift and a design
frozen for two viewports gets scaffolded for three. The FSM state file is
already the SSOT for phase; targets belong beside it. Flags and GUI both
*write* state; every gate *reads* state. This also makes targets auditable in
the ledger and hashable into the design-approval invalidation.

### `app-box-*` command surface

The phase skills already exist as `kit-designer` / `kit-scaffolder` /
`kit-reviewer`. `app-box-designer` is therefore not a new category — it is the
port of a slot that is already occupied. `app-box-designer` is settled — a
clean-room rewrite, BYO designer optional. What is **not** settled is whether
`app-box-scaffolder` / `app-box-reviewer` are ports too, or thin shims that
invoke the kit's. Porting is what makes app_box standalone and sellable;
shimming keeps one implementation so p2 and app_box cannot drift. The designer
had a licensing reason to be clean-room; the scaffolder and reviewer do not, so
the same answer does not follow automatically.

## 12. Resolved

**Human gates, from a harness.** The person holds both, always. The gate writes
an approval token into state; an agent can *reach* a gate and stop there, but
cannot mint the token. Otherwise "never automate the two human gates" is true
of the GUI and false of the plugin — and the plugin is the path a buyer uses.

**The design skills do not solve viewports — and the asymmetry says why.**

| skill | tablet/desktop doctrine? | evidence |
|---|---|---|
| `kimi-design-flutter` | **yes, genuine** | no `node_modules`; `references/layout-archetypes.md`, `starter-surfaces/surface/{{snake}}_view.tablet.dart` |
| `kimi-design-htmx` | **no** | 46 doc files, zero breakpoint doctrine |

Every `744` in the htmx skill is vendored (playwright, pptxgenjs, babel). Every
`1280` is `make-a-deck.md` or `gen-pptx` — **slide width, not an app
breakpoint**. Its only `@media` are `max-width:600px`, `print`,
`prefers-color-scheme`, `prefers-reduced-motion`. That independently confirms
the p2 measurement from a second source.

The reason is structural: **the Flutter skill carries form factors because its
output contract demands five files; HTML never demanded anything.** So porting
the htmx lineage *inherits the gap*. `app-box-designer` must add the viewport
ladder — it cannot receive it. Borrow the ladder from `kimi-design-flutter`,
which already reasons in 390/744 archetypes.

**No Tailwind style flag.** Nothing in the kit parses CSS — the only
`postcss`/`style-dictionary` hits are transitive `node_modules` under
`translate_design`, never called on a prototype. So there is no mapper to
write; the "translator" is the model reading HTML. Which is exactly why
Tailwind hurts: the measured reason htmx beat JSX on the same surface was
inline `style=` **7 vs 22** and semantic class names (*"the screen declares
zero style — it only names classes; I never had to reverse-engineer intent from
inline CSS"*). `class="flex items-center px-4 py-2 text-sm"` is inline styling
relocated into the class attribute, and it deletes the semantic name (`.lrow`,
`.appbar`) that the generator maps to a kit widget. Adding Tailwind would
require building a utility→widget mapper to get back to where the default
already stands. The axis clients actually vary is **brand tokens**, and that
flag is worth having.

## 13. The htmx producer is already MVVM — the freeze throws it away

This is not a proposal to build. It is already built, and the intake contract
is blind to it. Measured in `design/new-htmx/`:

| layer | files | lines | shape |
|---|---:|---:|---|
| `ui/views/<shell>/<tab>/<surface>/` | 97 | 4,529 | `X_view.html` + `X_viewmodel.js` pairs |
| `services/{repositories,facades}/` | 13 | 1,759 | `people_repository.js`, `navigation_facade.js` |
| `models/<x>_model/*_fixtures.json` | 10 | 2,101 | seed/fake data |
| `app.routes.js` | 1 | 65 | URL inventory, cites ADR-0005 |

That is **8,454 lines** carrying the *exact* stacked convention — `_view` /
`_viewmodel` naming, and the `services/{facades, repositories}` split named in
the app_box requirements.

**What the freeze keeps: 37 flat HTML files.** `structure.json` is then
re-inferred from *filenames*, which is why `new-htmx` shows `registry: null`
and `tabRoots: {}` while the JSX producer shows six real tab roots.

**Correction to a stronger claim I first made here:** the inferred shells are
*not* a decomposition the producer never made. Measured, `tab → shell` has
**zero fan-out** — it is a pure rename table of 8 entries
(`admin → admin_shell`, `train → train_shell`, …). One `stage_shell` with tabs
and eight `<tab>_shell`s are the same decomposition under two spellings. The
inference is flat, not wrong.

### What to actually build: an exporter, not an architecture

The delta is `emit_structure` learning a second input. Today it reads
`jsx/app.jsx` for `P2_REGISTRY` and falls back to filenames. It should read the
htmx producer's real tree — `app.routes.js` + the `ui/views/**` pairs — and
emit `registry`, `tabRoots`, per-surface viewmodel name, repository and facade
dependencies, and route/link semantics.

**Measured joinability** (34 viewmodel pairs vs 37 frozen screens):

| | result |
|---|---|
| shell mapping | **pure rename table, 8 entries, zero fan-out** — mechanical |
| surface join on `(tab, short)` | **21 / 37** resolve mechanically |
| the residual 16 | lexical (`giftcards`↔`gift_cards`, `whitelabel`↔`white_label`, `productedit`↔`product_edit`) plus a few semantic (`inbox.thread_list` ↔ `inbox/home`) |

**So do not write a normalizer — make the producer declare the id.** A fuzzy
matcher would close maybe 13 of the 16 and leave the semantic ones failing
silently, which is the stale-green pattern this whole assessment exists to
avoid. One line per viewmodel —
`export const surfaceId = 'inbox.thread_list';` — takes the residual to zero
permanently and makes the join an assertion instead of a guess. The join only
exists at all because `structure.json` is filename-inferred; declaring the id
deletes the problem rather than automating it.

### Why this is safe where the JSX translation was not

The JSX translation captured **7 of 112 nodes** because the JSX was
branch-matrixed on `role × state × params.branch`. Conditional rendering does
not translate. **Declarative structure does.** Names, boundaries and
dependency edges survive a language change intact; that is the discriminator,
and it is why extending the contract here does not repeat that failure.

### Three things this does *not* give you, stated plainly

1. **Shape, not semantics.** An htmx viewmodel is a JS closure over fixtures.
   A stacked one is a `BaseViewModel` with `notifyListeners`, busy state and
   DI. The names and edges transfer; the logic does not.
2. **`stage_shell` ≠ p2's shells.** The producer has one stage shell; the
   Flutter app has `train_shell` / `admin_shell` / `account_shell`. This needs
   a *declared mapping*, not a copy — and that mapping is a design decision.
3. **It raises the stakes on the producer.** Making htmx authoritative for
   architecture means a wrong boundary there is now a wrong boundary
   everywhere. That argues for the mapping being explicit and gated, not
   inferred.

## 14. The hybrid — already authored, simply not wired

*Answering: can the designer author structure while the emitter still derives
it, without recreating two-writers-one-artifact?*

Yes, and the corpus already does it. `design/new-htmx/models/screens_model/`
`registry.json` is a **42-entry list whose keys are exactly what
`emit_structure` regexes out of `P2_REGISTRY`**:

```json
{"id":"train.library","label":"Training Library","tab":"train",
 "comp":"TrainLibrary","surface":"train_shell_training_library_view",
 "phase":"Belong"}
{"id":"train.home", ..., "surface": null}
{"id":"train.programme", ..., "roles":["felix"]}
```

Its own header says *"ported verbatim from `jsx/app.jsx`"*. It is read in anger
by `screens_repository.js` and `navigation_facade.js`.

**`emit_structure` never looks at it.** It searches for `jsx/app.jsx`, finds
none, and falls back to filename inference — which is why `new-htmx` emits
`registry: null` and `tabRoots: {}`, and why 42 registry entries become 37
frozen screens (the 5 carrying `surface: null`, e.g. `train.home`, vanish
silently instead of being declared exclusions).

### The three-layer split that keeps the gate real

| layer | artifact | writer |
|---|---|---|
| **authored** | `models/screens_model/registry.json` — ids, tabs, comps, surface bindings, role gating | the designer |
| **derived** | `ui/views/**` pairs + `app.routes.js` — structure and nav edges | the producer's code |
| **generated** | `structure.json` = *f*(registry, tree, `surfaces/`) | `emit_structure`, never a human |

This is a genuine hybrid *because the authored layer is a different shape from
the generated one* — a declarative id table, not screen records. That is the
discriminator. Had the designer written `structure.json` directly, the artifact
would have two writers and regenerate-and-diff would have nothing to compare
against. Here it stays a pure function of two inputs, neither of which is
itself.

### The fix is small, and it turns the gate on

`emit_structure` gains a second registry source: no `jsx/`, so read
`models/screens_model/registry.json` — **no regex needed, it is already JSON**.
`tabRoots` still needs an htmx source (JSX declares `P2_TAB_ROOTS`); either
`app.routes.js` exports one or a sibling `tab_roots.json` declares it.

Consequence: the drift check currently guarded on `[ -f "$DESIGN/jsx/app.jsx" ]`
starts applying to htmx. Per `docs/research/web-research-drift.md`, assert it
with `git status --porcelain`, not `git diff` — a producer that *adds* a
surface is the expected case, and `git diff` cannot see new files.

### (see §15 for the companion that drives all of this)

### Why this also explains the translation result

The JSX producer put role logic in **conditionals** —
`if (role === 'leo') return <TrainHomeLeo/>`, plus `params.branch` matrices —
which is why its translation captured 7 of 112 nodes. The htmx producer
declares the same thing as **data**: `"roles":["felix"]` in the registry.
Declared variation survives a language change; branched rendering does not. The
registry is not merely convenient here — it is *why* this producer is
translatable at all.

## 15. The iOS companion — remote control, with the prototype as a mode

**Decision (supersedes the research doc's "ship zero-install first"):** the
prototype is reached **through the app_box iOS app**, not a bare Safari URL.
The companion is the remote control; serving the prototype is something it
*commands the desktop to do*. Rationale: the app is needed for control
regardless, and one surface that both drives the pipeline and shows its output
beats two surfaces with different capabilities. A plain LAN URL stays available
as a fallback for handing a client a link — it is simply not the primary path.

### The loop

1. Companion pairs to the desktop by QR — LAN-local, TLS-key fingerprint
   pinned from the QR payload (see `docs/research/remote-control-and-chat.md`).
2. From the companion: **Serve prototype**. The desktop starts the htmx
   producer's `server.js` and returns the URL over the paired channel.
3. The companion opens it **fullscreen in a WebView** — at true device width,
   which is why this doubles as real-device design review.
4. A **floating, draggable FAB** rides above the WebView: app_box controls,
   stop server, back to the companion.

### What the FAB must not do

**It must not lie about server state.** If the desktop process dies, the
WebView keeps showing the last render — a stale page that looks live. Demoing a
dead server to a client is the failure mode this feature invents. So the FAB
carries the connection state as its own affordance (live / reconnecting /
dead), driven by the paired channel's heartbeat, **not** by whether the WebView
last painted successfully.

Secondary constraints:

- It occludes the prototype by definition — needs an edge-dock/minimised state,
  and must never park over the phone's home indicator.
- Gesture capture is scoped to the FAB; the WebView owns every other touch, or
  the prototype stops being usable.
- A WebView is a platform view. The safe-area handling that bit every
  `UIHostingController` surface in p2 applies here — verify insets rather than
  assuming.

### Credentials

Settled — see the research doc. OS vault (`flutter_secure_storage`), never
hand-rolled crypto; encrypted-file fallback only where no vault exists, and
only if its key lives in the vault; the UI states which tier is active. The
verification standard is **write → restart → read back, in a signed and
notarised build**, because two of the known macOS failure modes (App Group
missing from `keychain-access-groups`, hardened runtime after notarisation)
fail *silently and green*.

### Subscription vs API key

Two different problems: a static API key never expires; an OAuth subscription
token has refresh, expiry and remote revocation.

**Decision: shell out to an already-authenticated harness CLI where one is
present; hold tokens only for the standalone case.** Owning a refresh loop for
two vendors is permanent maintenance, and the only user who needs it is the
buyer with no harness installed. This also keeps the harness-plugin path
credential-free — app_box never sees a token it does not have to store.

## 16. Form-factor emission follows targets

**Decision: a macOS-only app emits three files** — `_view.dart`,
`_view.desktop.dart`, `_viewmodel.dart` — not five, and
`scaffold_coverage_gate.sh` reads targets from state to require exactly the
derived set.

The rejected alternative was emitting empty `.mobile`/`.tablet` files to
satisfy the current unconditional five-file counter. That is the stale-green
pattern in its purest form: a file that exists, passes the check, and is never
rendered. **A gate that cannot fail for the right reason is not a gate.**

Cost, stated plainly: this is the second time §11's "gates read state" bill has
come due — first for freeze widths, now for emission. The macOS dogfood is what
forces it, which is the argument for dogfooding at all. Better to pay it on our
own app than on a client's.
