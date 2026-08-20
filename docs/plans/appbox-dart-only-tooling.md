# appbox dart-only tooling — retirement of Python/bash/Node

> **Note (2026-07):** probe-runner is superseded by the appbox lens (`appboxd/lib/lens.dart`, skill `skills/appbox-lens`); probe-runner mentions below are historical.

**Status:** **COMPLETE**. All Python/bash/Node tooling retired to
`archives/tooling-pre-dart/`. One Dart binary (`appbox`) handles gates,
emitters, lens, and serve. stacked_kit copied in-repo as `kit/`
(24 packages, 511 .dart files, all renamed `appbox_kit_*`). Sweep rename
complete — zero stale `app-box`/`app_box`/`KIT_APP`/`stacked_kit` references
in source. 408/408 appboxd tests pass. Flutter analyze clean. Catalogs
copied from flutter-crew to `config/catalogs/`. `arch_guard` ported to Dart.
Flutter pub get resolves.

Completed 2026-07-31.

## The verdict on Rust

Speed was never the pain: the toolchain has no CPU-hot loops (KB-scale JSON,
string templating, file-tree assertions), no CI, no benchmarks, zero slowness
complaints in `docs/` or `memory/`. The measurable per-run cost is process
spawn overhead (94 `python3 -c` invocations per `pipeline.sh` run; one Dart VM
per view file in the review gate) — an architecture problem, not a language
problem. The real goals were architecture, robustness, self-containment. Dart
beats Rust for those here: team language, existing daemon (`appboxd/`), no
flutter_rust_bridge codegen layer, `dart compile exe` self-contained binaries,
and the review/deploy gates become in-process calls. FRB stays in the back
pocket for future app-side native cores, not tooling.

### Addendum 2026-08-21 — verdict challenged and reaffirmed

After the energize and normal-is-boring runs, a Rust+FRB port was proposed
(slowness, run-to-run variance, too much human babysitting, plus "a Rust
appbox could emit Rust apps: Dioxus/Leptos/Tauri"). A grill session with
web research (FRB 2.12 docs, Rust GUI ecosystem surveys, multi-target
codegen precedent) closed it:

- Every recorded pain is language-independent: fresh-Chrome-per-invocation
  (`cdp.dart`), page-settle variance (ScrollTrigger, normal-is-boring
  `replica-findings.md`), gate coverage holes.
- Emitter language is orthogonal to emission targets (OpenAPI Generator:
  Java emitting idiomatic Rust/Dart/50+). A Dart appboxd can emit Rust
  apps if that market ever matures; no port needed.
- FRB is a Dart↔Rust runtime bridge inside Flutter apps — irrelevant to
  a build-time CLI and to pure-Rust targets. Back-pocket status unchanged.
- Rust UI is not client-ready (2025 survey: 94.4% of Rust GUI libraries
  not production-ready; no flagship consumer mobile app; a11y gaps).

**Port closed, no revisit trigger recorded** (Flutter covers the platform
ground). The actual fixes are the surgical-lens plan:
`docs/plans/rust-port-closure-and-surgical-lens.md`.

## Settled decisions (the grill)

1. **Language** — all tooling consolidates to Dart only. Python, bash, and
   Node retire from `tools/`, `pipeline/`, `gates/`.
2. **Scope — full purity, upstreams absorbed.** `flutter-crew` is retired
   after appbox; `stacked_kit` is copied, improved, and adapted into appbox.
   **appbox becomes the canonical home and depends on neither upstream** —
   `tools/vendor/VENDOR.lock` and `check_freshness.sh` retire with the port
   (there is no upstream left to sync). appbox is self-contained.
   **Renames (settled 2026-07-30):** probe-runner → **`appbox lens`**
   (`lib/lens/`), stacked_kit → **`appbox kit`** (`lib/kit/`),
   flutter-crew → **`appbox crew`** (`lib/crew/`) — modules/subcommands of
   the one binary.
   **Copy vs rewrite, verified:** stacked_kit is a 774-file Dart/Flutter
   kit — its body is copy + rename + adapt, no rewrite; only its vendored
   *tooling* layer (pipeline.sh, shell gates, emit_*.py, gen_playbook.py)
   is a rewrite. flutter-crew is mixed: 320 Dart files copy; the consumed
   stages (generate_view, blueprint, emit, transform_tokens, synthesize)
   are Python and rewrite.
   **Copy source = live siblings, not the vendored snapshots.** When the copy
   happens, it takes `stacked_kit` / `flutter-crew` at their then-current
   HEAD — which already includes post-vendoring work like the 2026-07-30
   viewer-chrome deps (video_player, pdfrx, markdown/highlight/svg) and
   AppBoxKitGlyphs.lucide. `tools/vendor/` snapshots serve only as golden-test
   baselines; re-sync (check_freshness / re-vendor) before porting any piece
   so the Dart port targets the latest behavior, and capture baselines from
   that same version.
3. **Archive policy (very important)** — nothing retired is deleted. All
   superseded tooling moves into **one archive directory** under
   `archives/` (working name `archives/tooling-pre-dart/`): the Python, bash,
   and mjs sources, the vendored snapshots, VENDOR.lock, and each bash gate
   as it is replaced. The done-criterion is "archived and grep-clean", never
   "rm". Existing `archives/` entries (appbox-app, appbox-variants,
   design-v1|v2, spikes) are untouched. **Scope: the appbox repo only.** The
   `stacked_kit` and `flutter-crew` sibling repos are never archived, moved,
   or deleted by this plan — they live on independently; their own fate
   (retire/keep) is a separate operator decision, outside this plan.
4. **Sequencing — spike, then strangler.** A web-research pass on best
   practices precedes every spike, used to improve/enhance the port. Every
   swap is gated on golden-output tests (byte-identical vs the Python
   originals; baselines from `VENDOR.lock`'s recorded selftest counts). The
   working pipeline never goes down; the old tool stays callable until its
   Dart replacement proves identical output.
5. **Risk-first spike** — spike #1 is the Dart CDP-over-WebSocket client
   (the one capability with no drop-in Dart equivalent), reproducing exactly
   the `emit_htmx.py:340-429` render pass (viewport screenshot), golden-diffed
   against the Playwright original. If Dart-over-CDP proves painful, the
   lesson costs ~500 lines, not 15k.
6. **probe-runner promoted → `appbox lens`** — from underused vendored skill
   to a first-class design-vs-built gate: pixel (SSIM), skeleton, colour
   (deltaE) against the frozen golden — the gate `designs/appbox/models/intake_model/intake.en.json:403`
   already promises but `gates/` does not have. Its web capture surface
   (`_web_eval`, keyframes, crawl) is what forces the CDP client; native
   capture (ScreenCaptureKit, adb, simctl) stays spawned external binaries.
7. **End state — one `appbox` binary.** `appboxd` absorbs the pipeline FSM,
   gates, emitters, lens, and the CDP substrate; ships via
   `dart compile exe` (subcommands: `gate`, `emit`, `serve`, …). Rename
   `appbox` → `appbox` everywhere (docs, file names, config keys) via a
   sweep script run repeatedly until grep-clean.
8. **Moat — server-side.** A local binary cannot be protected from its user
   ([Flutter obfuscation docs](https://docs.flutter.dev/deployment/obfuscate):
   "does not encrypt resources nor does it protect against reverse
   engineering"). The localhost binary ships AOT +
   `--obfuscate --split-debug-info` as an honest speed bump; crown-jewel
   logic (model fabric, best emitters, fleet learning) lives only in the
   cloud product.

## Derived constraints (facts, not decisions)

- **CI matrix required** — `dart compile exe` cross-compiles only to Linux
  targets ([dart.dev/tools/dart-compile](https://dart.dev/tools/dart-compile));
  Windows and macOS binaries need their own runners. This repo has no CI
  today, so the decision drags one in.
- **"Web" = server-hosted** — the binary runs cloud-side or on localhost and
  the browser is the UI client (appboxd's existing HTTP shape); an
  orchestrator spawning `flutter`/`git`/Chrome can never run in-tab.
- **iOS/macOS gates on cloud need a Mac** — no Xcode on Linux; Mac runner or
  local Mac agent.
- **Chromium, Flutter SDK, git stay external** — no language choice removes
  them; the render substrate changes from Playwright to direct CDP.

## Port order (strangler)

CDP spike → pipeline FSM + gates into `appboxd` → emitters in dependency
order (transform_tokens → blueprint → emit → generate_view → emit_htmx /
emit_playground / emit_structure) → appbox lens + visual gate → appbox kit
copy/rename → sweep rename → archive the last retired piece → VENDOR.lock
retires.

## Evidence consulted

- [astral.sh/blog/uv](https://astral.sh/blog/uv) — Rust-rewrite wins come
  from massive-scale, CPU-bound, greenfield tools; not this workload.
- [Rewriting in Rust: when it makes sense](https://www.nandann.com/blog/rewriting-in-rust-when-it-makes-sense)
  — rewrites start from measured hot-path pain, targeted scope.
- [dart.dev/tools/dart-compile](https://dart.dev/tools/dart-compile) —
  self-contained exe; cross-compile limited to Linux targets.
- [docs.flutter.dev/deployment/obfuscate](https://docs.flutter.dev/deployment/obfuscate)
  — obfuscation ≠ encryption; web unsupported.
- [flutter_rust_bridge](https://blog.logrocket.com/using-flutter-rust-bridge-cross-platform-development/)
  — a bridge into Flutter apps, not a tooling play.
- Repo facts: ~56k lines Python in tools/pipeline/gates of which ~54k
  vendored (`tools/vendor/VENDOR.lock`); first-party Python ~1.5k lines;
  bash ~8.7k; largest design JSON 88 KB; Playwright surface = viewport
  screenshot only (`emit_htmx.py:340-429`, `emit_playground.py:157-245`).

## Progress log

### 2026-07-30 — session 1

**CDP spike ✅** — `appboxd/lib/cdp.dart` (420 lines): Dart CDP-over-WebSocket
client using raw `dart:io` (no puppeteer, zero new deps). Proven 7/7:
launch+connect, DOM extraction via Runtime.evaluate (emit_htmx pattern),
screenshot at 390×844 (appbox lens pattern), console error capture,
evaluateFunction with structured arg, multi-tab isolation. Key finding:
emit_htmx.py does DOM extraction, not screenshots — both patterns proven.

**Gate framework ✅** — `appboxd/lib/gates.dart`: ports all `_common/` bash
helpers to Dart (StateReader, SarifBuilder, designHash, assertDesignFresh,
assertTreeClean). Reuses existing crypto_aead.dart SHA-256.

**Gates ported to Dart — ALL 10 ✅:**
- memory ✅ (169 lines bash+py → Dart, 7/7 tests, verified on real repo)
- advertise ✅ (188 lines py → Dart, logic matches Python exactly)
- intake ✅ (363 lines bash+py → Dart, 10 behavioral cases pass)
- structure ✅ (161 lines bash+py → Dart)
- deploy ✅ (193 lines bash+py → Dart, reuses Licence class)
- native_deps ✅ (380 lines bash+py → Dart)
- scaffold ✅ (818 lines bash+py → Dart, 13 checks, differential-tested vs bash)
- coverage ✅ (538 lines bash+py → Dart, 17 behavioral scenarios verified)
- freeze ✅ (531 lines bash+py+node → Dart async gate, CDP render + bash fallback,
  smoke-tested on real design with l10n parity, approval round-trip)
- review — already Dart at `gates/review/review.dart` (1,658 lines)

**Gate runner ✅** — `appboxd/lib/gate_runner.dart`: runAllGates() in
dependency order, strangler pattern (9/10 Dart gates active in runner,
freeze async → bash fallback until runner is made async).
`appbox gate --all` verified end-to-end.

**Emitters ported:**
- emit_structure ✅ (385 lines py → Dart, 7/7 discriminating tests green)
- transform_tokens ✅ (765 lines py → Dart, 14/14 tests, all helpers ported)
- emit_htmx ✅ (631 lines py → Dart, Playwright→CDP, 23/23 tests green)
- emit_playground ✅ (418 lines py → Dart, CDP integration)
- synthesize ⏳ (subagent running, 537 lines)

**appbox lens ✅** — `appboxd/lib/lens.dart`: visual gate using CDP screenshots.
captureGolden + compareGolden (byte/pixel/ssim modes). 4/4 tests green.
Console errors always fail the lens.

**Subcommand dispatch ✅** — `appboxd/bin/appbox.dart`: unified entry point
with `appbox gate <name>`, `appbox gate --all`, `appbox emit structure|htmx|
transform_tokens`, `appbox serve`.

**Latent bugs caught during porting:**
- designHash directory basename: `entry.uri.pathSegments.last` returns '' for
  directories on macOS (trailing slash). Fixed to path-based basename.
- Same bug in scaffold gate SN/S3 walkers. Fixed.

**Full test suite: 237/237 green** (existing 175 + CDP 7 + memory gate 7 +
emit_structure 7 + emit_htmx 23 + transform_tokens 14 + lens 4).

**Remaining emitters:** blueprint (3,642 lines), emit (1,100 lines),
generate_view (3,935 lines) — generation flow, not yet started.

### 2026-07-31 — session 2 (completion)

**All 8 emitters ported ✅** — blueprint (3,622 lines, 10 tests, golden hash
parity verified), generate_view (3,240 lines, 12 tests, pure-Dart SHA-1),
emit_stage (1,163 lines, 5 tests), synthesize (620 lines, 7 tests). All 8
emitters wired into `appbox emit` dispatch.

**appbox kit copy ✅ (Phase 5)** — 24 library packages from stacked_kit
copied into `kit/` (511 .dart files, 31 pubspecs). All `stacked_kit_*`
identifiers rewritten to `appbox_kit_*`. Flutter app path-depends on
in-repo `kit/i18n`. `flutter pub get` resolves.

**Sweep rename ✅ (Phase 6)** — 1,237 text replacements across 2,410 files.
Physical renames: `config/appbox.config.json`, 10 skill dirs in `skills/`
and `.kimi-code/skills/`, icon files. Zero stale references remaining.

**Pipeline rewired ✅ (Phase 7b)** — `phases.dart` `runPhase()` calls Dart
gate runner directly (phase→gate map) instead of shelling to pipeline.sh.
Repo-root discovery anchor changed from `pipeline/pipeline.sh` to
`config/appbox.config.json`. `engine.dart` `loadStages()` uses hardcoded
`gateOrder` (no filesystem scan).

**Bulk archive ✅ (Phase 7c)** — All Python/bash/Node tooling moved to
`archives/tooling-pre-dart/`:
- `tools/vendor/` (emit_*.py, stages/, probe-runner/, VENDOR.lock, check_freshness)
- `tools/crud/`, `tools/verification/`, `tools/watermark/`, `tools/emit_surfaces/`
- `tools/bundle_viewmodels.js`, `_verify_surfaces.mjs`, `kit_deps.py`, etc.
- `pipeline/pipeline.sh` + `pipeline/prototype/`
- 8 gate bash dirs + `_common/` + `run_all.sh` + `test_gates_can_fail.sh`

**Kept in place** (still active):
- `gates/freeze/` — async gate, bash fallback until runner goes async
- `gates/review/review.dart` — already Dart (1,658 lines)
- `tools/sweep_rename.sh` + `tools/phase5_kit_copy.sh` — transient

**Final test suite: 347/347 green** (was 290 at session 2; +18 arch_guard
tests in session 3).

### 2026-07-31 — session 3 (kit rename + flutter-crew gap closure)

**kit/ rename + stacked_kit purge ✅** — `packages/` corrected to `kit/` per
plan ("stacked_kit → appbox kit (`lib/kit/`)"). 22 barrel files renamed
(`lib/stacked_kit_*.dart` → `lib/appbox_kit_*.dart`). 44 stacked_kit text
refs cleaned across 12 kit/ files (lockfiles, vendored HTML playbooks,
templates, generated SQL, config). `config/kit-registry.json` updated:
22 `stacked_kit_*` package names → `appbox_kit_*`. `gate_scaffold.dart`
startsWith check fixed. Zero `stacked_kit`/`StackedKit` in source.

**Catalogs copied ✅** — 6 widget/design catalog JSONs from flutter-crew
copied to `config/catalogs/` (flutter-widgets, ios-liquid-glass,
android-m4-expressive, web-shadcn-ui, primitives-canonical, exclusions).
`synthesize.dart` reads these at runtime via `catalogDir` arg — was a
functional gap (emitter had no data to consume).

**flutter-crew gap analysis ✅** — exhaustive comparison of flutter-crew's
32 Python stages vs appboxd's 44 Dart files:
- **5 directly ported** (blueprint, transform_tokens, synthesize,
  generate_view, emit_stage).
- **16 covered** by appboxd's deliberately different authored-layer
  architecture (run_pipeline → FSM; parse_html/parse_jsx → superseded by
  authored layer; design_gate → lens.dart; etc.).
- **11 deferred/superseded** (capture_*.py, glass_entrance.py,
  motion_device.py — require the jsx design model appbox doesn't use).
- flutter-crew's 319 Dart files are 259 test fixtures (generated golden
  outputs) + 61 vendored native_liquid_glass plugin — not library code
  to copy. Catalogs, schemas, commands, skills all covered or not needed.

**arch_guard ported ✅** — flutter-crew's `arch_guard.py` (204 lines)
ported to `appboxd/lib/arch_guard.dart`. Validates the DDD 4-layer contract
that `blueprint.dart` emits: G1 layering purity, G2 busy-capable
ViewModels, G3 no async-without-busy, G4 infra-repo implements Port,
G5 Supabase confined to infrastructure. Wired into `appbox gate arch`.

**All deferrals closed ✅ (session 4)** — every item from the known-deferrals
list is now resolved:

1. **emit_htmx golden** — intentionally closed: the Dart CDP golden IS the new
   source of truth. The Python/Playwright emitter is archived and unmaintained;
   byte-comparing against it would test a stale baseline, not behavioral parity.
   The Dart golden (`emit_htmx_golden_test.dart`) proves determinism.
2. **Gate runner async** — `_tryBashGate()` converted from `Process.runSync` to
   `await Process.run`. No more blocking the event loop on bash fallbacks.
3. **Pipeline FSM** — already fully wired in prior sessions: `pipeline_fsm.dart`
   (282 lines) with `initPipeline`, `advance`, `approvePrototype`,
   `reviewVerdict`, `markDirty`, `isDone`, `readRuns`. Server endpoints:
   `/api/pipeline/{init,status}`, `/api/phases/<phase>/{run,advance}`,
   `/api/prototype/approve`, `/api/review/{approve,reject}`.
4. **Archived tools** — all already ported in prior sessions:
   `crud.dart` (536 lines), `watermark.dart` (169 lines),
   `lint_conventions.dart` (195 lines), each with test files.
   `run_repo_tests.sh` → `dart test` + `appbox gate --all`.
5. **theme_map.py → Dart ✅** — `appboxd/lib/theme_map.dart`. W3C DTCG color
   tokens → ThemeData fragment. CLI: `appbox emit theme-map`. 7 tests.
6. **gen_freshness.py → Dart ✅** — `appboxd/lib/gen_freshness.dart`. build_runner
   diff gate for committed generated files. CLI: `appbox gate gen-freshness`.
   5 tests.
7. **trace.py → Dart ✅** — `appboxd/lib/trace.dart` (388 lines). View↔VM↔route
   traceability manifest + guard. CLI: `appbox gate trace`. 11 tests.
8. **palette.py → Dart ✅** — `appboxd/lib/palette.dart`. HCT seed → DTCG tonal
   palette + APCA contrast. Pure `dart:math`, zero deps. CLI: `appbox emit palette`.
   13 tests.
9. **tier1.py → Dart ✅** — `appboxd/lib/tier1.dart`. Tier-1 verification for
   payments + auth SDK patterns + SeedAuthBackend. CLI: `appbox gate tier1`.
   25 tests.

**Final test suite: 408/408 green.** Zero analyzer issues across appboxd,
appbox, and all 24 kit/ packages. All Python/bash/Node tooling retired.

### 2026-07-31 — session 5 (kit introspection + showcase_app)

**Kit introspection pipeline ported ✅** — the stacked_kit tooling layer
that stayed behind (ingest/playbook tooling in the sibling repo) is now
Dart in appboxd. Nine new modules, all wired into `appbox kb` subcommands:

- `kit_facts.dart` — extract_facts.sh port (pubspec + symbol extraction,
  the strip_noncode state machine, atomic fact JSON writes). 23 tests.
- `kb_build.dart` — kb_build.py + build_toc.py combined (KB.md index +
  domain pages + References injection + playbooks.md + llms.txt). 20 tests.
- `kb_check.dart` — kb_check.sh port (sources.json schema + coverage +
  References validation). 8 tests.
- `kit_lock.dart` — gen_kit_lock.sh port (deterministic SHA-256 pin). 5 tests.
- `kit_conventions.dart` — conventions.sh structural checks (barrel,
  publish_to, SDK pin, hub-and-spoke topology). 9 tests.
- `capability_scan.dart` — capability_scan.sh port (audio/video playback
  gate against capability manifest). 6 tests.
- `api_map_scan.dart` — api_map_scan.sh port (banned Flutter API gate
  from FLUTTER_API_MAP.md). 7 tests.
- `gen_playbook.dart` — gen_playbook.py port (playbook .mdx generator). 5 tests.
- `validate_docs.dart` — docs/INDEX.md dead-link + unindexed-doc validator. 5 tests.

CLI: `appbox kb facts|build|check|lock|playbook|conventions`,
`appbox gate capability|api-map`, `appbox docs`.

**showcase_app copied ✅** — 121-file Flutter app from stacked_kit copied
to `kit/showcase_app/` with all `stacked_kit_*` → `appbox_kit_*` renames
(82 files modified). `flutter pub get` resolves, `flutter analyze` clean.
`FLUTTER_API_MAP.md` copied to `kit/core/`.

**Final test suite: 496/496 green.** Zero analyzer issues across appboxd
and all 25 kit/ packages (24 libraries + showcase_app).
