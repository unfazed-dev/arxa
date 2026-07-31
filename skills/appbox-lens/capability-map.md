# Capability map — probe-runner (archived) → appbox lens

Full audit of every probe-runner script
(`archives/tooling-pre-dart/tools/vendor/probe-runner/scripts/`, 225 `.py`
files: 138 verbs + 31 `_*.py` shared cores + 56 `test_*.py` behavior specs)
against the appbox lens — `appboxd/lib/lens.dart` over `appboxd/lib/cdp.dart`,
the `appboxd/lib/lens/` modules, and `appboxd/lib/lens/native/`. The
probe-runner is **retired**; this map is the audit trail proving every verb
ported or dropped with reason — no script is left without a disposition.

Status legend:

- **ported** — the capability lives in Dart. Invoke via the lens library API
  (`appboxd/lib/lens/*.dart`) or the `tool/lens_*.dart` one-off drivers.
- **ported (partial: …)** — landed, with a recorded ceiling (named in the row).
- **dropped** — not ported, with a one-line reason (another tool owns it, or it
  is research/extraction machinery with no appbox consumer).

The `appbox lens <verb>` CLI dispatch is **live** in `appboxd/bin/appbox.dart`
(`case 'lens'` → `runLensCli`); every ported verb is reachable as
`appbox lens <verb>` (see `lens_cli.dart`). The library beneath every verb is
landed; the `tool/lens_*.dart` one-off drivers remain for ad-hoc scripting.

## Web block — ported

| probe-runner verb | Dart implementation | status |
|---|---|---|
| `web_open` / `web_launch` | `CdpClient.launch` + `CdpSession.navigateAndSettle` (`cdp.dart`); cores `_nav.py`, `_settle.py` | ported |
| `web_shot` | `captureGolden` (`lens.dart`), `CdpSession.screenshot` (`cdp.dart`); driver `tool/lens_shot.dart` | ported |
| `web_emu` | `CdpSession.setViewport(w, h)` (`cdp.dart`) | ported |
| `web_scroll` | `CdpSession.screenshot(fullPage: true)` + `evaluate('window.scrollBy')` (`cdp.dart`) | ported |
| `web_eval` | `CdpSession.evaluate` / `evaluateFunction` (`cdp.dart`); cores `_web.py`, `_web_eval.py` | ported |
| `web_console` | `consoleErrors` / `pageErrors` auto-fail in `compareGolden` (`cdp.dart`, `lens.dart`) | ported |
| `web_click` | `CdpSession.click(x, y)` (`cdp.dart`) | ported |
| `web_key` | `CdpSession.key(key)` (`cdp.dart`) | ported |
| `web_type` | value-set via `CdpSession.evaluate`; assertion via `tool/lens_check.dart --expect` | ported |
| `web_hover` | `Input.dispatchMouseEvent` (mouseMoved), inlined in `captureStates` (`lens/states.dart`) | ported |
| `web_tokens` | `extractTokens` + `clusterColors` (`lens/tokens.dart`); core `_style.py` | ported |
| `web_dom` | `extractDom` / `extractOuterHtml` (`lens/dom.dart`) | ported |
| `web_a11y` | `extractA11y` (`lens/a11y.dart`) | ported |
| `web_net` | `traceNet` (`lens/net.dart`) | ported |
| `web_anim` | `captureScrollAnim` + `fitEasing` (`lens/motion.dart`); cores `_anim_core.py`, `_transition.py` | ported |
| `web_flipbook` | `captureFlipbook` (`lens/motion.dart`); core `_flipbook.py` | ported (partial: WAAPI `getAnimations()` oracle only; non-WAAPI frame-recovery via `burstFrames`+region tracking deferred — `kimitail:` note in `motion.dart`) |
| `web_record` | `recordVideo` (`lens/motion.dart`); core `_frames.py` | ported |
| `multishot` | `burstFrames` (`lens/motion.dart`) | ported |
| `web_states` | `captureStates` (`lens/states.dart`); core `_states.py` | ported |
| `web_skeleton` | `captureSkeleton` (`lens/skeleton.dart`, format `lens-skeleton/1`) | ported |
| `skeleton_diff` | `diffSkeleton` (`lens/skeleton.dart`) | ported |
| `pixdiff` | `compareGolden(mode: byte\|pixel\|ssim)` (`lens.dart`) + `pixelDiff` / `ssimSimilarity` / `meanSimilarity` (`lens/pixels.dart`); cores `_metrics.py`, `_substrate.py` | ported |
| `color_assert` | `deltaE2000Lab` / `regionMeanLab` (`lens/pixels.dart`) | ported |
| `text_diff` | `textDiffLines` (`lens/ocr.dart`) | ported |
| `ocr` | `ocrText` (`lens/ocr.dart`, Swift Vision helper) | ported |
| `site_capture` (+ `crawl_*` route expansion) | `crawlSite` + `robotsAllows` (`lens/crawl.dart`); cores `_site.py`, `_crawl.py` | ported |
| `site_merge` | `mergeDesignSystem` (`lens/crawl.dart`); core `_merge.py` | ported |
| `design_golden` | `runLensGate` (`lens.dart`) | ported |

## Web block — dropped

| probe-runner verb | reason |
|---|---|
| `web_vectors` | `vtracer` external binary; non-certified research output, no gate consumer |
| `dom` / `console` | Dioxus/wry debug-probe pair (`templates/dioxus_debug_probe.rs`); appbox doesn't ship Dioxus |
| `content_firewall` / `slots` / `bundle_writer` / `motion_adapter` / `site_chrome` | ADR-0001 extraction-pipeline machinery — appbox authors designs; nothing consumes content-free bundles |
| `vision_probe` | face/body/rect/barcode/saliency — no gate consumer; the Swift Vision CLI (via `lens/ocr.dart`) is the re-entry point |
| `safari_inspect` + Safari fallback paths in `web_*` | Chrome-only doctrine — one render engine, the one appbox gates on |

## Native — ported (capture + deterministic-chrome only)

| probe-runner verb | Dart implementation | status |
|---|---|---|
| `adb_list` | `LensAdb.devices` (`lens/native/adb.dart`); core `_adb.py` | ported |
| `adb_shot` | `LensAdb.shot` (`lens/native/adb.dart`) | ported (partial: stdout→bytes via `latin1.encode` because the `ProcessRunner` seam is String-only — `kimitail:` note in `adb.dart`; add a `runBytes` seam if real captures mangle bytes) |
| `adb_record` | `LensAdb.record` (`lens/native/adb.dart`) | ported |
| `adb_url` | `LensAdb.openUrl` (`lens/native/adb.dart`) | ported |
| `adb_ui_tree` | `LensAdb.uiTree` (`lens/native/adb.dart`) | ported |
| `ios_list` | `LensSimctl.devices` (`lens/native/simctl.dart`); core `_ios.py` | ported |
| `ios_shot` | `LensSimctl.shot` (`lens/native/simctl.dart`) | ported |
| `ios_record` | `LensSimctl.record` (`lens/native/simctl.dart`) | ported |
| `ios_url` | `LensSimctl.openUrl` (`lens/native/simctl.dart`) | ported |
| `ios_status_bar` | `LensSimctl.statusBarOverride` / `statusBarClear` (`lens/native/simctl.dart`) | ported |
| `ios_appearance` | `LensSimctl.appearance` (`lens/native/simctl.dart`) | ported |
| `shot` (SCK, macOS) | `LensSck.shot` + `LensSck.tccOk` (`lens/native/sck.dart`); core `_sck.py` | ported |
| `flutter_attach` / `flutter_vm` | `FlutterVm.connect` + `parseVmServiceUri` (`lens/native/flutter_vm.dart`); core `_flutter.py` | ported |
| `flutter_shot` | `FlutterVm.screenshot` (`lens/native/flutter_vm.dart`) | ported |
| `flutter_tree` | `FlutterVm.dumpRenderTree` / `dumpWidgetTree` (`lens/native/flutter_vm.dart`) | ported |
| `flutter_eval` | `FlutterVm.evalDart` (`lens/native/flutter_vm.dart`) | ported |
| `flutter_semantics` | `FlutterVm.dumpSemanticsTree` (`lens/native/flutter_vm.dart`) | ported |
| `flutter_diag` | `FlutterVm.rpc` / `setFlag` / `callServiceExtension` (`lens/native/flutter_vm.dart`) | ported |

## Native — dropped (Patrol / native-E2E owns interaction)

| probe-runner verbs | reason |
|---|---|
| `adb_tap` / `adb_swipe` / `adb_type` / `adb_key` / `adb_intent` / `adb_push` / `adb_files` / `adb_boot` / `adb_app` / `adb_settings` / `adb_perm` / `adb_location` / `adb_log` | adb interaction — Patrol / native-E2E owns it |
| `adb_cdp` | forward+CDP trick re-addable from archive when an Android-web gate asks; no consumer today |
| `adb_flipbook` | native motion-recovery; Patrol owns interaction |
| `ios_tap` / `ios_swipe` / `ios_type` / `ios_key` / `ios_ui_tree` / `ios_log` / `ios_safari` / `ios_privacy` / `ios_location` / `ios_files` / `ios_boot` / `ios_app` / `ios_push` / `ios_entrance` / `ios_flipbook` | external `idb` dependency + Patrol owns interaction |
| `ios_sweep` / `android_sweep` | app-specific harnesses, hardcoded coords |
| `flutter_tap` / `flutter_set_text` / `flutter_reload` / `flutter_find` / `flutter_inspect` / `flutter_flipbook` / `flutter_anim` / `flutter_skeleton` / `flutter_log` | `flutter_test` + Patrol own interaction; the VM block is capture/inspect only |
| `ax_tree` / `ax_text` / `ax_click` / `ax_observe` | macOS host accessibility automation — operator-machine, never app verification |
| `click` / `drag` / `hover` / `key_chord` / `type_text` / `context_menu` / `gesture` / `scroll` (host) | macOS host input automation — operator-machine |
| `focus` / `reposition` / `window_state` / `menu` / `drop_file` / `clipboard` / `find_window` / `wait_window` | macOS host window automation — operator-machine |
| `record` (host) / `region` | macOS host capture/region — operator-machine; the SCK capture verb (`LensSck.shot`) is the one-shot in scope |
| `wait_pixel` (host) | no host-screen consumer; the web wait case is covered by `CdpSession.evaluate` polling |
| `sample` / `mem` / `tail_log` / `fswatch` / `headless` / `nettrace` | operator diagnostics; `headless` folded into `CdpClient.launch`'s own headless Chrome; `nettrace` is the host-network tracer (the web network trace is `traceNet`) |
| `tcc_check` | operator preflight; folded into `LensSck.tccOk` (`lens/native/sck.dart`) |

## Workflow — dropped

| probe-runner verbs | reason |
|---|---|
| `pr-decide` | tool-routing manifest for a retired tool; the `appbox` CLI dispatch replaces it |
| `derisk_adb_flipbook` / `derisk_crawl_yield` / `derisk_flutter_skeleton` / `derisk_form_state_validity` / `derisk_pseudo_geometry` / `derisk_screencapturekit` / `derisk_t_anchor` | research spikes (behavior specs mined for Tasks 1-6, then archived with the tool) |
| `livesmoke_g2` / `livesmoke_web_capture` / `crawl_expander_smoke` | research smoke harnesses, archived |

## Shared cores `_*.py` — disposition

Named here so every `_*.py` basename is accounted for. Ported cores fold into
the Dart module named in their verb's row above; dropped cores are research
helpers or sub-cores with no consumer.

- Ported (folded into the Dart module beside their verb): `_nav`, `_settle`,
  `_web`, `_web_eval`, `_style`, `_anim_core`, `_transition`, `_flipbook`,
  `_frames`, `_site`, `_crawl`, `_merge`, `_metrics`, `_substrate`, `_states`,
  `_adb`, `_ios`, `_sck`, `_flutter`.
- Dropped (research / no consumer): `_chrome_dedup` (chrome-instance dedup
  utility), `_crawl_yield` (crawl rate-limit, `derisk_crawl_yield` target),
  `_native_flipbook` (native motion core, Patrol owns), `_consent`
  (consent-banner detection, `web_states` sub-core; no consumer),
  `_keyframes` (keyframe extraction, `web_states` sub-core; the `getAnimations()`
  oracle covers keyframes), `_shape_key` (`derisk_pseudo_geometry` target),
  `_t_anchor` (`derisk_t_anchor` target), `_theme` (theme research helper;
  design-token transform lives in `appboxd`, not the lens), `_virt`
  (virtualization research helper), `_url_template` (URL templating, folded
  into `crawlSite` route seeds), `_platform` (host-platform routing; the lens
  is CDP/native-spawn, no host-platform branch), `_common` (shared Python
  helpers, folded into the Dart modules).

## Test specs `test_*.py` (56) — mined, archived

Behavior specs mined for Tasks 1-6 (`_anim_core` easing, `crawl`/`merge`,
skeleton calibration, pixdiff metrics, settle/nav); the rest archived with the
tool. Not ported — Dart unit tests in `appboxd/test/lens_*_test.dart` replace
them. Basenames, for the audit grep:

`test_adb_flipbook`, `test_adb_helper`, `test_anim_core_segments`,
`test_anim_core_z`, `test_aria_roles`, `test_bundle_writer`,
`test_chrome_dedup`, `test_color_assert`, `test_color_assert_delegate`,
`test_consent`, `test_content_firewall`, `test_crawl`, `test_crawl_expand`,
`test_crawl_yield`, `test_flutter_inspect`, `test_flutter_skeleton`,
`test_flutter_tap`, `test_ios_entrance`, `test_ios_flipbook`, `test_ios_helper`,
`test_keyframes`, `test_merge`, `test_motion_adapter`,
`test_motion_adapter_bezier`, `test_motion_summary`, `test_native_flipbook`,
`test_nav`, `test_nav_firewall_canary`, `test_pixdiff_metrics`, `test_platform`,
`test_pr_decide`, `test_redact_preserves_ids`, `test_settle`, `test_shape_key`,
`test_site`, `test_site_capture_nav`, `test_site_capture_nav_e2e`,
`test_site_capture_post`, `test_site_chrome`, `test_site_manifest_nav`,
`test_site_merge`, `test_skeleton_diff`, `test_slots`, `test_states`,
`test_style`, `test_substrate`, `test_t_anchor`, `test_theme`, `test_transition`,
`test_url_template`, `test_virt`, `test_vision_probe`, `test_web_skeleton`,
`test_web_skeleton_anchor_href`, `test_web_tokens`, `test_web_vectors`.

## Rule of thumb

The lens owns **rendered-surface truth over CDP** (web + htmx designs today) and
**native capture** (adb/simctl/SCK one-shots + Flutter VM capture/inspect).
Native *interaction* truth belongs to Patrol / `flutter_test`. The
extraction-pipeline and research machinery (ADR-0001) have no appbox consumer
and stay archived. Every archived verb above is reachable from the archive if a
concrete gate ever asks for it — extend the lens, never resurrect the tool.

---

## Skills runtimes

The audit trail for the **dartification of the skill runtimes** — every
non-Dart runtime file under `skills/` (`.mjs` / `.py` / `.sh`), one row,
ported (with its new Dart name/location) or dropped with reason. Task 23's
archive moves are the mechanical half (the files move to
`archives/tooling-pre-dart/skills-pre-dart/`); this section records *why*
each one retires and where the capability now lives. No runtime file is left
without a disposition.

The same legend as above: **ported** (capability in Dart), **ported (partial:
…)** (landed, with a recorded ceiling), **dropped** (not ported, with reason).

### Designer `agents/` — ported (DS intake trio)

| runtime file | Dart target | CLI | status |
|---|---|---|---|
| `agents/check-design-system.mjs` (110) | `design_tools.dart` → `dsCheck(projectDir)` (read-only DS validator, exit-64 usage contract) | `appbox design ds-check` | ported |
| `agents/record-asset.mjs` (187) | `design_tools.dart` → `recordAsset(...)` (appends the deliverable record into `_d_meta.json`; JSON shape ported exactly) | `appbox design record-asset` | ported |
| `agents/import-design-system.mjs` (274) | `design_tools.dart` → `dsImport(projectDir, slug)` (syncs compiled DS into `_ds/<slug>/` + `_d_meta.json` note) | `appbox design ds-import` | ported |

> The three DS-intake functions above are the Task 22.1 port; their tests live
> in `design_tools_test.dart` with fixture dirs. The CLI verbs
> (`ds-check`/`record-asset`/`ds-import`) are wired into `appbox design`.

### Designer `agents/` — dropped with reason

| runtime file | reason |
|---|---|
| `agents/import-figma.mjs` (740) | The offline `.fig` decoder (kiwi + zstd/deflate → node tree → React JSX / token CSS emit); a babel/JSX concern, not a Dart port. **Archived** under `archives/tooling-pre-dart/skills-pre-dart/appbox-designer/agents/` — restorable if Figma import returns. |
| `agents/compile-design-system.mjs` (381) | Lazily requires `agents/vendor/babel.min.js` (absent; verified: fails with the fetch hint). The portable-DS *compiler* (JSX/TSX → `_ds_bundle.js` + manifest) — archived with its fetch hint intact; no gate consumes it. |
| `agents/build-preview.mjs` (1919), `agents/lib/ds-core.mjs` (750), `agents/lib/ds-prompt.mjs` (290), `agents/lib/asset-store.mjs` (177) | The design-system **preview compiler** — a self-contained ~3k-line subsystem (parse/compile/preview/prompt/asset store). No pipeline gate consumes it. Archived under `archives/tooling-pre-dart/skills-pre-dart/appbox-designer/agents/` — port on demand (the capability-map convention) only if a gate or the designer's DS flow asks for it. |

### Designer `runtime/` — ported

| runtime file | Dart target | CLI | status |
|---|---|---|---|
| `runtime/serve.mjs` (387) | `design_server.dart` → `designServe` (Task 20; loopback bind, `--port 0 --json`, hot-reload supervisor) | `appbox design serve` | ported (partial: the Dart design server **supersedes** it; `serve.mjs` stays in tree until Task 23 archives it) |
| `runtime/serve.test.mjs` (195) | `design_server` Dart tests (serve contract) | — | ported |
| `runtime/lint.mjs` (53) | `design_tools.dart` → `designLint` (ADR-0002 no-custom-JS check) | `appbox design lint` | ported |
| `runtime/console-check.mjs` (32) | the lens — `consoleErrors`/`pageErrors` auto-fail (`cdp.dart`); navigate + assert | `appbox lens check` | ported |
| `runtime/shoot.mjs` (100) | the lens — viewport-ladder capture pass (`lens_cli.dart`) | `appbox lens shoot` | ported |
| `runtime/pseudolocalize.mjs` (119) | `design_tools.dart` → `pseudolocalizeDir` (en → `qps-ploc`) | `appbox design pseudolocalize` | ported |
| `runtime/doctor.mjs` (92) | `design_tools.dart` → `designDoctor` (preflight the toolchain the gates use) | `appbox design doctor` | ported |
| `runtime/check_ladder.mjs` (43) | `design_tools.dart` → `designCheckLadder` (ladder config ↔ doctrine drift) | `appbox design check-ladder` | ported |
| `runtime/check_wiring.mjs` (134) | `design_tools.dart` → `designCheckWiring` (fragments/mutations-posted/urls-resolve/targets-exist) | `appbox design check-wiring` | ported |
| `runtime/verify-interact.mjs` (41), `verify-shots.mjs` (37), `verify-timeline.mjs` (13) | folded into `design_selftest.dart` (structural-contract selftest + falsifiability) | `appbox design selftest` | ported |
| `runtime/vendor/fetch.mjs` | `design_tools.dart` → `designVendorFetch` (fetch + SRI-pin vendored client libs) | `appbox design vendor-fetch` | ported |
| `runtime/eject.mjs` (153) | target: `appbox design eject` (self-contained Hono eject) | `appbox design eject` | ported (partial: the `design eject` CLI verb + Dart port land with the Task 22.1 code — not present at this HEAD; flag for verification) |
| `runtime/lib/` (helpers, l10n, router, state, templates, timers — `.mjs`) | the Runtime internals, folded into `design_server.dart` (session/locale/router/timer helpers) | — | ported |
| `runtime/vendor/` (htmx, islands, lucide, …) | **not a runtime** — served, SRI-pinned *client assets* (browser data), nothing to port; `fetch.mjs` above is the one tool that touched them | served by `appbox design serve` | n/a (data) |

### Designer `selftest.sh` — ported

| runtime file | Dart target | CLI | status |
|---|---|---|---|
| `selftest.sh` | `design_selftest.dart` (structural-contract selftest + `--negative` falsifiability; the `check_ladder`/`check_wiring`/`lint` calls it shelled out to are the Dart functions above) | `appbox design selftest [<dir>] [--negative]` / `appbox design --self-test` | ported |

### The `.py` skill runtimes — ported

| runtime file | Dart target | CLI | status |
|---|---|---|---|
| `appbox-scaffolder/scaffold.py` | `scaffold.dart` → `scaffoldMain` | `appbox emit scaffold --design-dir … --app-root … --targets … [--check] [--self-test]` | ported |
| `appbox-story-mapper/scripts/generate_story_map.py` | `story_map.dart` → `storyMapMain` | `appbox emit story-map -i … -o … --data-out … --brief-out … [--self-test]` | ported |
| `appbox-deployer/deploy.py` | `deploy.dart` → `deployMain` (fastlane/shorebird/wrangler over a `ProcessRunner` port) | `appbox deploy doctor` / `appbox deploy deploy …` / `appbox deploy --self-test` | ported |
| `appbox-lint/lint_kb.py` | `docs_lint.dart` → `lintKb` (dead links, orphans, half-wired supersede pointers, unresolved wikilinks) | `appbox docs [root]` | ported |
| `appbox-intake/intake.py` | `intake.dart` → `intakeMain` | `appbox intake emit --answers …` / `seed --brief …` / `validate …` / `--self-test` | ported |

### Skills-runtimes tally

Every retired non-Dart runtime file under `skills/` has a disposition (35 files
total: 29 `.mjs`, 5 `.py`, 1 `.sh`):

- **Ported:** 27 — the DS-intake trio (`check-design-system`/`record-asset`/`import-design-system`); the designer runtime `serve.test`/`lint`/`console-check`/`shoot`/`pseudolocalize`/`doctor`/`check_ladder`/`check_wiring`/`verify-interact`/`verify-shots`/`verify-timeline`/`vendor/fetch` (12) + the 6 `runtime/lib/*.mjs` server internals; `selftest.sh`; and the five `.py` ports (`scaffold`/`generate_story_map`/`deploy`/`lint_kb`/`intake`).
- **Ported (partial):** 2 — `serve.mjs` (the Dart design server supersedes it; archived by Task 23) and `eject.mjs` (the `design eject` CLI verb + Dart port land with the Task 22.1 code — not present at this HEAD; flagged for verification).
- **Dropped with reason:** 6 — `import-figma.mjs` (crashes on load — absent `vendor/fig-materialize.mjs`), `compile-design-system.mjs` (absent `agents/vendor/babel.min.js`), and the preview-compiler subsystem `build-preview.mjs` / `ds-core.mjs` / `ds-prompt.mjs` / `asset-store.mjs` (~3k lines, no gate consumer, port on demand).

The `appbox` CLI dispatch (`appboxd/bin/appbox.dart`) routes every ported verb:
`appbox design <sub>` (Task 19-21 + 22.1), `appbox lens check|shoot` (Task 7),
`appbox emit story-map|scaffold` (Tasks 14-16), `appbox deploy` / `appbox intake`
/ `appbox docs` (the `.py` ports). Task 23 moves every file in this section to
`archives/tooling-pre-dart/skills-pre-dart/` and rewrites the doc references that
still name them.
