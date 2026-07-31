# emit_htmx — htmx producer screens → hermetic frozen surfaces

Renders each screen of the app's htmx + Nunjucks design producer
(`<app>/design/new-htmx/`) to a chrome-stripped, self-contained static HTML
file at **`design/surfaces-htmx/<surface>.html`**.

The htmx sibling of [`tools/emit_playground`](../emit_playground/README.md),
which does the same job for the React + Babel producer. Same operational
contract — same CLI, same write-on-diff semantics, same exit discipline —
over a different kind of producer: the React playground is a static bundle
that can be served straight off disk, whereas the htmx tree is a **live node
server**, so this tool boots it, drives it, and always tears it down.

## Destination — read this before changing it

Output goes to `design/surfaces-htmx/`, **never** `design/surfaces/`.

`design/surfaces/` is `emit_playground`'s committed, diff-clean output and the
input to `freeze_design.sh`. Two producers, two frozen trees. Emitting the
htmx tree over the React tree would silently destroy the other producer's
SSOT and, because both trees carry the same registry surface names, the
damage would look like an ordinary content diff rather than an overwrite.

## Usage

```sh
python3 emit_htmx.py [--app <app-root>]          # emit (default app: $APPBOX_APP)
python3 emit_htmx.py --app <app-root> --check    # pre-gate drift guard
python3 emit_htmx.py --self-test                 # hermetic calibration
EMIT_RENDER=skip python3 emit_htmx.py            # skip the browser pass
```

Exit discipline (`freeze_design.sh` precedent — a gate never auto-installs):

- **0** — every emitted surface rendered error-free (write-on-diff: unchanged
  files report `unchanged`, nothing is rewritten); with `--check`, every
  surface `in-sync`
- **1** — registry/exclusions missing or unparseable, a render console/page
  error, an extraction failure (bad selector, no `.phone-screen` root), a
  surface that came back as the Phase-E placeholder, an un-rewritten
  `/assets/` URL, or — with `--check` — any surface DRIFT
- **2** — environment: no app root (`--app`/`$APPBOX_APP` both absent), no render
  backend, no `node`, or the producer server failed to boot

## How it works

1. **Boots the producer.** Picks a free ephemeral port, starts
   `node --import frozen_clock.mjs server.js` in `<app>/design/new-htmx/`
   with `$PORT` set, and waits for the server's own ready line on stdout.
   The server is torn down in a `finally` — success, failure, or exception.

   Readiness is the stdout announcement rather than a TCP poll on purpose: a
   poll cannot distinguish "not listening yet" from "died on import", and
   death on import is the common failure (`new-htmx/node_modules` is
   gitignored, so a fresh checkout has no `nunjucks`). A dead server is
   reported **with its real stderr** and exits 2.

2. **Freezes the clock.** `frozen_clock.mjs` is a `node --import` preload that
   pins `Date.now()` and zero-argument `new Date()` to a fixed epoch. This is
   load-bearing, not a nicety: the tree reads the wall clock while rendering
   (`services/facades/player_facade.js` — `startedAt: Date.now()` on session
   creation, `restEnd - Date.now()` for the rest countdown), so `train.player`
   renders `0:00` on one request and `0:01` on the next. Measured: 41 of 42
   registry screens are byte-stable across back-to-back renders; `train.player`
   is not. Without the freeze, every run rewrites that surface and the
   write-on-diff no-op is impossible.

   The fix is determinism at the source, not a loosened diff. Stripping the
   volatile node instead would hide real drift in any *other* time-derived
   value that shows up later. The fixture producer prints `Date.now()` into
   its output precisely so `--self-test` calibrates the freeze itself.

3. **Reads the registry.** `models/screens_model/registry.json` —
   `[{id, label, surface, shell, phase, comp, roles?}]`.

4. **Picks the role that can actually see each screen** — `entry.roles[0]`,
   else `comp` prefix `Studio` → `leo` / `Admin` → `erika`, else `felix`. This
   is the rule `scripts/seed/sweep_htmx_routes.mjs` already encodes; the htmx
   tree has no `window.P2.roles` table to consult, so the role is derived from
   the registry entry itself.

5. **Renders and verifies.** `GET /?role=<role>&screen=<id>` in headless
   Chromium (viewport 390×844), ~1500 ms settle; any console `error` or
   `pageerror` fails the run. Two further assertions exist because the htmx
   tree can return a *valid* page that is not the surface you asked for:
   `stage_viewmodel` renders the **Phase-E placeholder** when the role cannot
   see the screen (200, clean console, its own `data-screen-label`). So the
   placeholder marker is asserted absent and `data-screen-label` is asserted
   to equal `"<role> · <id>"`. Either check failing is a hard failure — a
   frozen placeholder would be a silent lie.

6. **Extracts the screen content.** The `.phone-screen` subtree (stage,
   toolbar, phone hardware and brand strip are outside it by construction),
   with every subtree matching a `design/exclusions.json` `selectors` entry
   stripped — the same shared exclusions SSOT `emit_playground` reads.
   Exclusions are destructive: keep them scoped to chrome nodes.

7. **Composes a standalone doc.** `fonts.css` + `tokens.css` + `app.css` +
   `hda.css` (the four `ui/common/base.html` links, in that order) inlined as
   one `<style>` with `/* */` comments stripped first, the stripped content as
   `<body>`, and a timestamp-free banner
   (`<!-- GENERATED by stacked_kit/tools/emit_htmx — do not hand-edit.
   Source: design/new-htmx/ screen '<id>' (role '<role>'). -->`).
   Written on diff only.

   **Asset rewriting.** The htmx tree serves assets from an *absolute* root
   (`/assets/…`), unlike the playground's relative `assets/…`, so every URL is
   repointed to `../new-htmx/assets/…` to resolve from `surfaces-htmx/`. The
   rewrite covers attribute values (`src` `href` `poster` `srcset` `data-src`
   `content`), `url()` in both inlined stylesheets and inline `style`
   attributes, and trailing `srcset` entries. It is per URL-context rather
   than a blanket string replace so that prose merely containing the
   characters `/assets/` is never silently altered — and a post-pass then
   **fails the run** on any `/assets/` URL the rewrite did not reach, because
   a missed one is a silently broken surface (404 image, unstyled font).

## The null-surface rule

Five of the 42 registry entries carry `surface: null` — `train.home`,
`account.home`, `auth.signin`, `studio.seat`, `admin.home`.

**They are skipped, and every one is reported**: a `skip:` line naming the
screen, plus a count and the full list in the summary. Nothing is silently
dropped.

Why skip rather than derive a name from the id: `surface` is the *shared
naming SSOT* across producers — it is the canonical Flutter view name that
`design/surfaces/`, the scaffolder and the Flutter tree all key off. Minting
`train_shell_home_view` here would create a surface that exists in exactly one
producer's frozen output and in no registry, no scaffold and no other tree —
an invented name is worse than an absent one, and it would silently diverge
the two producers' surface sets. The absence is a registry fact; the fix, if
these screens should be surfaces, is to give them `surface` values in the
registry, at which point this tool emits them with no change.

## `--check` — the pre-gate drift guard

`--check` renders every registry surface exactly as a normal emit would but
WRITES NOTHING: each result is compared byte-for-byte against the on-disk
`design/surfaces-htmx/<surface>.html` and reported per-surface as `in-sync` or
`DRIFT` (a missing file is DRIFT). Exit 0 only when all surfaces are in-sync
and every render check passes.

Files under `design/surfaces-htmx/` whose names match no registry surface are
**orphans**: reported as informational `note:` lines, never failures — sibling
parity with `emit_playground`, where a legacy frozen surface outliving its
registry entry is a human call, not a gate failure.

## Environment (backend cascade)

Mirrors `emit_playground` / `freeze_design.sh` exactly:

1. `uv run --with playwright python emit_htmx.py --worker …` (uv present)
2. system `python3` with `playwright` importable (in-process)
3. neither → **exit 2** with install instructions

Chromium binaries already cached at `~/Library/Caches/ms-playwright` are
reused. `EMIT_RENDER=skip` mirrors `FREEZE_RENDER=skip`: the browser pass is
skipped entirely, a skip note is printed, nothing is written — hermetic/CI
runs only.

Additionally the producer needs `node` on PATH and its own dependencies
installed (`npm install` in `design/new-htmx/`, which is gitignored).

## Self-test

`--self-test` is hermetic and offline. `fixtures/app/` is a miniature app whose
producer, `fixtures/app/design/new-htmx/server.js`, is **dependency-free node**
— it implements the same contract the real tree exposes (`$PORT`, a ready line,
`/?role=&screen=`, a `.phone-screen` root with chrome around it, `/assets/`
serving, the Phase-E placeholder), so the self-test exercises the *real* boot
path rather than a bypass, with no `npm install` and no network.

28 checks cover: environment discipline (no app root → 2, `EMIT_RENDER=skip`),
the emit and its summary, the null-surface report, CSS inlining of all four
sheets, comment stripping, chrome stripping, asset rewriting in all three
contexts plus the no-leftovers assertion, the write-on-diff no-op (which is
also the frozen-clock calibration), `--check` in-sync / orphan / DRIFT, the
placeholder trap (`FIXTURE_PLACEHOLDER=1` → exit 1), and a producer that dies
on import (→ exit 2 with its stderr).

It also asserts that `design/surfaces/` is never created — the destination
guard, enforced by a test rather than by comment.

Registered in `tools/test_gates.sh` alongside the sibling's self-test.

## Pipeline wiring — deliberately none

`emit_htmx` is **not** wired into `pipeline.sh`, because there is no seam to
wire it into:

- `pipeline.sh` contains zero references to `htmx`, and zero to
  `emit_playground` — **the sibling is standalone too**. Neither producer's
  emit step is a pipeline stage.
- `gate_prototype` (`pipeline.sh:197-212`) delegates to
  `PROTO_GATE` = `tools/freeze_design.sh`, which hard-codes
  `"$DESIGN"/surfaces/*.html` (`freeze_design.sh:58`) — the React producer's
  output only.
- `PROTOTYPE_TARGET` accepts `native` and `none`; there is no producer-select
  axis an `htmx` value could slot into.

Wiring would therefore mean inventing a new stage or changing prototype-gate
semantics, which is out of scope for this tool. **The seam that would be
needed**: a producer-aware prototype gate — either `freeze_design.sh` taught
to take a surfaces directory (so `design/surfaces-htmx/` can be frozen and
render-checked like `design/surfaces/`), or a `PROTOTYPE_PRODUCER` axis in
`gate_prototype` selecting which producer's frozen tree the gate validates.
Until one of those exists, run `emit_htmx --check` by hand or in CI, exactly
as you would `emit_playground --check`.
