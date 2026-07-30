# appbox dart-only tooling — retirement of Python/bash/Node

**Status:** planned, **not started**. Documentation only; no implementation has
been done. Settled in the Rust-vs-Dart grill, 2026-07-30. Green-light trigger:
"start the CDP spike".

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
   KitGlyphs.lucide. `tools/vendor/` snapshots serve only as golden-test
   baselines; re-sync (check_freshness / re-vendor) before porting any piece
   so the Dart port targets the latest behavior, and capture baselines from
   that same version.
3. **Archive policy (very important)** — nothing retired is deleted. All
   superseded tooling moves into **one archive directory** under
   `archives/` (working name `archives/tooling-pre-dart/`): the Python, bash,
   and mjs sources, the vendored snapshots, VENDOR.lock, and each bash gate
   as it is replaced. The done-criterion is "archived and grep-clean", never
   "rm". Existing `archives/` entries (app-box-app, appbox-variants,
   design-v1|v2, spikes) are untouched. **Scope: the app-box repo only.** The
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
   `app-box` → `appbox` everywhere (docs, file names, config keys) via a
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
