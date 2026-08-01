# Media, 3D, animation & games — rename, designer islands, smoke screens

**Status:** **COMPLETE** (2026-07-31). Settled with the operator 2026-07-31;
landed in commit d327c60. Three JS-runtime sub-steps (2.2, 4.6, 5.6 — the
serve.test.mjs / lint.mjs edits) were superseded by the Dart port in 4f9c458.
**Inputs:** [`../VOCABULARY.md`](../VOCABULARY.md) (appbox lens entry) ·
[`../../appboxd/README.md`](../../appboxd/README.md) (appbox-tools-first rule) ·
[`../../skills/appbox-designer/docs/adr/0002-zero-custom-client-js-boundary.md`](../../skills/appbox-designer/docs/adr/0002-zero-custom-client-js-boundary.md).

## Goal

Prove the appbox pipeline's media/3D/animation/games free space end to end in
the design shell: rename the product dirs to `appbox-studio`, make named
islands a first-class designer-skill architecture (3D model viewer, dotLottie,
Lottie, Rive, three.js, playable game), vendor one free example asset per
runtime, and ship six mobile-first smoke screens verified with the **appbox
lens** at the viewport ladder (390/744/1280).

## Architecture

- **Rename (product only).** `appbox/` → `appbox-studio/`, `designs/appbox/` →
  `designs/appbox-studio/`. Pipeline-level names stay: `appboxd/`,
  `config/appbox.config.json`, `config/kit-registry.json`, `appbox_kit_*`,
  `skills/appbox-*` / `.kimi-code/skills/appbox-*` names, the `appbox/structure@1`
  schema id, the concept "appbox pipeline".
- **Islands (ADR-0002 amendment).** The zero-ad-hoc-client-JS boundary stands;
  the "one named island" clause becomes "named islands only, enumerated in the
  contract". Third-party runtimes are vendored into
  `skills/appbox-designer/runtime/vendor/` (SRI-pinned, `manifest.json` +
  `SRI.md`, like htmx today); first-party glue islands are dependency-free
  data-attribute scripts next to them (`canvas.js` precedent — no SRI, no
  globals, re-arm on `htmx:load`). Served at `/assets/vendor/*` by
  `runtime/lib/router.mjs:50-58` (already in place; no router change needed).
- **Smoke screens.** Six screens under the app shell of the renamed design,
  composed exactly like the existing screens (Nunjucks view extending
  `ui/views/main_shell/main_shell_view.html`, co-located `*_viewmodel.js`,
  routes spread into `app.routes.js`, l10n keys in `l10n/app_*.arb`).
  Interactivity: htmx fragment swaps where declarative works (dotLottie
  play/pause, model-viewer auto-rotate), island-bound controls where it
  doesn't (Rive state-machine inputs, three.js toggles, the game).
- **Verification.** appbox lens only — `appboxd/lib/lens.dart` over
  `appboxd/lib/cdp.dart` (headless Chrome via CDP; console/page errors
  auto-fail). This plan extends `cdp.dart` with input driving
  (`Input.dispatchKeyEvent` / `Input.dispatchMouseEvent`) and adds a
  `tool/lens_check.dart` driver. Never probe-runner; never
  `archives/tooling-pre-dart/`.

## Tech stack

Hono + htmx 2.0.10 (server-rendered MVVM, Nunjucks) · vendored
`@google/model-viewer` 4.3.1, `@lottiefiles/dotlottie-wc` 0.9.24 (+
`@lottiefiles/dotlottie-web` 0.78.2 WASM), `@lottiefiles/lottie-player`
2.0.12, `@rive-app/canvas-single` 2.39.1, `three` 0.185.1 · Dart `appboxd`
(CDP/lens) · Flutter app `appbox-studio` (Stacked).

## Global constraints

- **No git commits, ever, in this plan.** `git mv` stages moves; committing is
  the user's call afterwards (repo rule: no git mutations without explicit
  user approval).
- **Canonical skill copy is `skills/appbox-designer/`** (git-tracked). The
  live mirror the design's `serve.mjs` actually executes is
  `.kimi-code/skills/appbox-designer/` (untracked). Every task that edits a
  file under `skills/` ends by copying that file to the same relative path
  under `.kimi-code/skills/`. Runtime commands in this plan invoke the
  `.kimi-code/` copy (that is what the design itself uses); edits happen in
  `skills/`.
- **Zero ad-hoc client JS.** No `<script>` blocks in templates, no `hx-on:*`,
  no `js:`-prefixed attributes, no `[expr]` trigger filters. All client code
  lives in `runtime/vendor/` and loads via `<script src="/assets/vendor/…">`.
  `node .kimi-code/skills/appbox-designer/runtime/lint.mjs designs/appbox-studio`
  must stay clean after every screen task.
- **Frozen artifacts stay untouched:** `docs/design/brief.md`,
  `docs/design/story-map.json`, `docs/moodboards/*` (preserve-by-default;
  probe-runner mentions were reworded to the appbox lens by the 2026-07-31
  retirement sweep — see Follow-up work).
- **Historical documents stay untouched:** `archives/**`, superseded plans and
  research reports (`docs/plans/architecture.md`,
  `docs/plans/consolidate-one-app-plus-daemon.md`,
  `docs/plans/design-shell-canvas-redesign.md`,
  `docs/plans/appbox-dart-only-tooling.md`, `docs/plans/implementation/*`,
  `docs/research/*`, `tools/phase5_kit_copy.sh`). They are records, not living
  docs; their `appbox`/`designs/appbox-app` mentions are historical.
- **Generated files stay untouched:** `appbox-studio/macos/Flutter/ephemeral/**`,
  `appbox-studio/build/**`, `appbox-studio/.dart_tool/**`.
- **Vendored libraries:** pinned versions only, sha384 SRI computed locally
  (`openssl dgst -sha384 -binary <file> | openssl base64 -A`), recorded in
  `manifest.json` + `SRI.md`, licences recorded in `THIRD-PARTY-NOTICES.md`.
- **kit/ motion vocabulary untouched.** Code-driven choreography
  (flutter_animate) is out of scope; no kit changes in this plan.

---

## Task 1: Rename the product directories

Moves only; reference edits are Task 2.

**Interfaces**
- Consumes: nothing (first task).
- Produces: `appbox-studio/` and `designs/appbox-studio/` on disk, staged in
  the git index; nothing referencing them updated yet (repo is expected to be
  red until Task 2 finishes).

### Steps

- [x] 1.1 Move the Flutter app:
  ```sh
  cd /Volumes/developer_ssd/Developer/totem_labs/app-box
  git mv appbox appbox-studio
  git mv designs/appbox designs/appbox-studio
  git status --short | head -20
  ```
  Expected: `R  appbox/... -> appbox-studio/...` and
  `R  designs/appbox/... -> designs/appbox-studio/...` rename entries.
- [x] 1.2 Rename the Dart package in `appbox-studio/pubspec.yaml:1`: change
  `name: appbox` to `name: appbox_studio`, and in line 2 change the
  description's leading `appbox —` to `appbox-studio —`.
- [x] 1.3 Rewrite all package imports:
  ```sh
  cd /Volumes/developer_ssd/Developer/totem_labs/app-box
  grep -rl "package:appbox/" appbox-studio/lib appbox-studio/test \
    | xargs sed -i '' 's|package:appbox/|package:appbox_studio/|g'
  grep -rc "package:appbox/" appbox-studio/lib appbox-studio/test | grep -v ':0' || echo "imports clean"
  ```
  Expected: `imports clean` (32 files / 84 imports rewritten).
- [x] 1.4 Update product display names: `appbox-studio/web/manifest.json:2-3`
  (`"name": "appbox"` → `"name": "appbox-studio"`, same for `"short_name"`)
  and `appbox-studio/android/app/src/main/AndroidManifest.xml:13`
  (`android:label="appbox"` → `android:label="appbox-studio"`).
- [x] 1.5 Verify the app still analyzes and tests green:
  ```sh
  cd /Volumes/developer_ssd/Developer/totem_labs/app-box/appbox-studio
  flutter pub get && flutter test
  ```
  Expected: `All tests passed!`

---

## Task 2: Sweep every reference to the old paths

Enumerated exhaustively — this list, not "grep and fix". The `$schema` value
`appbox/structure@1` (in `designs/appbox-studio/structure.json:2`,
`designs/appbox-studio/services/repositories/files_repository.js:56`, and
emitted by `skills/appbox-scaffolder/scaffold.py:600`) is a **format
identifier, pipeline-level: it stays**.

**Interfaces**
- Consumes: Task 1's moved trees.
- Produces: a grep-clean repo (against the list below), green `appboxd` tests,
  green designer-runtime serve test, a servable `designs/appbox-studio`.

### Steps

- [x] 2.1 `appboxd` — pipeline code pointing at the design dir. Edit:
  - `appboxd/bin/appbox.dart:515` — `designDir ??= 'designs/appbox';` →
    `'designs/appbox-studio'`
  - `appboxd/lib/gate_freeze.dart:50` — `const designRel = 'designs/appbox';`
    → `'designs/appbox-studio'`
  - `appboxd/lib/gate_structure.dart:20` — same const, same change
  - `appboxd/lib/gates.dart:44-45` — `'$appRoot/designs/appbox'` and
    `'$repoRoot/designs/appbox'` → append `-studio` to both
  - `appboxd/lib/gate_coverage.dart:75` — comment mention → `designs/appbox-studio`
  - `appboxd/lib/config.dart:28` — `p.join(repoRoot, 'appbox', 'build', 'web')`
    → `p.join(repoRoot, 'appbox-studio', 'build', 'web')`
- [x] 2.2 Designer runtime serve test — `skills/appbox-designer/runtime/serve.test.mjs` (superseded by Dart port):
  line 22 repo-root anchor `path.join(ROOT, 'designs', 'appbox', 'app.routes.js')`
  → `'designs', 'appbox-studio', 'app.routes.js'`; line 18-19 comment →
  `designs/appbox-studio`; line 25 error string → `designs/appbox-studio`;
  line 115 `start(['designs/appbox', …])` → `'designs/appbox-studio'`;
  lines 84, 101, 120 bare design name `'appbox'` → `'appbox-studio'`.
  Then mirror: `cp skills/appbox-designer/runtime/serve.test.mjs .kimi-code/skills/appbox-designer/runtime/serve.test.mjs`.
- [x] 2.3 Repo docs:
  - `THIRD-PARTY-NOTICES.md:98` — heading `Lexend fonts
    (`designs/appbox/assets/fonts/`)` → `designs/appbox-studio/assets/fonts/`
  - `THIRD-PARTY-NOTICES.md:104` — inventory path →
    `designs/appbox-studio/assets/fonts/FONTS.md`
  - `docs/INDEX.md:54` — `` `appbox/lib/security/` `` →
    `` `appbox-studio/lib/security/` ``; `` `appbox/` not yet scaffolded from
    `designs/appbox/` `` → `` `appbox-studio/` … from `designs/appbox-studio/` ``
  - `docs/INDEX.md:55` — `` `appbox/` is the hand-bootstrapped shell `` →
    `` `appbox-studio/` is the hand-bootstrapped shell ``
- [x] 2.4 Design-internal path strings (inside `designs/appbox-studio/`):
  - `services/repositories/files_repository.js:113-114` — the two embedded
    keys `'designs/appbox/models/design_model/design_seed.en.json'` and
    `'designs/appbox/models/design_model/run.json'` → `designs/appbox-studio/…`
  - `models/design_model/design_seed.en.json:338`,
    `models/design_model/design_seed.pl.json:338`,
    `models/design_model/run.en.json:404`,
    `models/design_model/run.pl.json:404`,
    `models/design_model/run.json:404` — `"path"` values →
    `designs/appbox-studio/models/design_model/<same filename>`
  - `models/design_model/design_seed.en.json:342` and
    `models/design_model/run.en.json:342/408`-style cross references — every
    `"path"` value in these five files that starts `designs/appbox/` gets
    `designs/appbox-studio/` (10 values total across the 5 files; verify with
    `grep -n 'designs/appbox/' designs/appbox-studio/models` → no output)
  - `l10n/README.md` — the one `designs/appbox` mention →
    `designs/appbox-studio`
  - `ui/views/main_shell/intake/_integration_intake.md:78` — regenerate
    command path → `designs/appbox-studio/…`
  - `ui/views/main_shell/design/_integration_design.md:44,94,98` — three
    `designs/appbox/…` code paths → `designs/appbox-studio/…`
- [x] 2.5 Design-internal project name — the design describes the renamed
  product. In each of these 15 JSON files change `"project": "appbox"` to
  `"project": "appbox-studio"`:
  `models/intake_model/intake.json`, `intake.en.json`, `intake.pl.json`,
  `intake_seed.en.json`, `intake_seed.pl.json`;
  `models/design_model/run.json`, `run.en.json`, `run.pl.json`,
  `design_seed.en.json`, `design_seed.pl.json`;
  `models/build_model/run.json`, `run.en.json`, `run.pl.json`,
  `build_seed.en.json`, `build_seed.pl.json` (all under
  `designs/appbox-studio/`).
  ```sh
  cd /Volumes/developer_ssd/Developer/totem_labs/app-box/designs/appbox-studio
  grep -rl '"project": "appbox"' models | xargs sed -i '' 's/"project": "appbox"/"project": "appbox-studio"/g'
  ```
- [x] 2.6 Grep-clean check (the whole point of the enumerated list):
  ```sh
  cd /Volumes/developer_ssd/Developer/totem_labs/app-box
  grep -rn 'designs/appbox\b' --exclude-dir=.git --exclude-dir=node_modules \
    --exclude-dir=archives --exclude-dir=.kimi-code . \
    | grep -v 'designs/appbox-studio' | grep -v 'designs/appbox-app'
  ```
  Expected output: only the historical documents named in Global constraints
  (`docs/plans/*`, `docs/research/*`) — nothing else.
- [x] 2.7 Green checks:
  ```sh
  cd /Volumes/developer_ssd/Developer/totem_labs/app-box/appboxd && dart test
  node /Volumes/developer_ssd/Developer/totem_labs/app-box/.kimi-code/skills/appbox-designer/runtime/serve.test.mjs
  ```
  Expected: all dart tests pass; serve test prints its checklist ending with
  all `ok` lines, exit 0.
- [x] 2.8 Serve smoke: `node designs/appbox-studio/serve.mjs --port 4399 --no-watch &`,
  then `curl -sf -o /dev/null -w '%{http_code}\n' http://localhost:4399/dashboard`
  → `200`; `kill %1`.

---

## Task 3: Vendor the island runtimes (SRI-pinned)

**Interfaces**
- Consumes: nothing but network access. Independent of Tasks 1-2.
- Produces: 7 new vendored files in `skills/appbox-designer/runtime/vendor/`
  (+ mirror), updated `manifest.json`, `SRI.md`, `THIRD-PARTY-NOTICES.md`.

### Steps

- [x] 3.1 Download the pinned builds:
  ```sh
  cd /Volumes/developer_ssd/Developer/totem_labs/app-box/skills/appbox-designer/runtime/vendor
  curl -sfLO https://unpkg.com/@google/model-viewer@4.3.1/dist/model-viewer.min.js
  curl -sfLO https://unpkg.com/@lottiefiles/dotlottie-wc@0.9.24/dist/dotlottie-wc.js
  curl -sfL -o dotlottie-player.wasm https://unpkg.com/@lottiefiles/dotlottie-web@0.78.2/dist/dotlottie-player.wasm
  curl -sfLO https://unpkg.com/@lottiefiles/lottie-player@2.0.12/dist/lottie-player.js
  curl -sfL -o rive.js https://unpkg.com/@rive-app/canvas-single@2.39.1/rive.js
  curl -sfLO https://unpkg.com/three@0.185.1/build/three.module.min.js
  curl -sfLO https://unpkg.com/three@0.185.1/build/three.core.min.js
  ls -la model-viewer.min.js dotlottie-wc.js dotlottie-player.wasm lottie-player.js rive.js three.module.min.js three.core.min.js
  ```
  Expected sizes (approx): model-viewer ~1.0 MB, dotlottie-wc ~76 KB,
  wasm ~1-3 MB, lottie-player ~376 KB, rive ~3.1 MB (canvas-single embeds the
  WASM — deliberately the `-single` build so no second fetch), three.module
  ~357 KB, three.core ~700 KB.
- [x] 3.2 Self-containment audit (the vendored-no-CDN rule):
  ```sh
  grep -oE 'from"[^"]+"' three.module.min.js | sort -u
  grep -oE 'https?://[a-z0-9.-]+' model-viewer.min.js lottie-player.js rive.js three.module.min.js three.core.min.js | sort -u
  ```
  Expected: `three.module.min.js` imports only `"./three.core.min.js"`
  (satisfied by the sibling file). The URL grep prints only *inert* strings
  — license/spec/doc URLs (w3.org, github.com, rive.app, MDN, jcgt.org) and
  dormant fallbacks never hit by these assets: model-viewer's
  `lottieLoaderLocation` default (only used for Lottie-textured models),
  rive-single's RuntimeLoader fallback (its WASM is embedded — that is why
  the `-single` build was chosen), dotlottie-wc's CDN WASM fallback
  (overridden by `dotlottie_island.js`'s `setWasmUrl` before any player
  instantiates). The behavioral proof of no-network is Task 15: any real CDN
  fetch failure surfaces as console errors, which the lens auto-fails.
- [x] 3.3 Compute SRI hashes and record them. For each of the 7 files:
  ```sh
  for f in model-viewer.min.js dotlottie-wc.js dotlottie-player.wasm lottie-player.js rive.js three.module.min.js three.core.min.js; do
    printf '%s  sha384-%s\n' "$f" "$(openssl dgst -sha384 -binary "$f" | openssl base64 -A)"
  done
  ```
  Append one entry per file to
  `skills/appbox-designer/runtime/vendor/manifest.json` (same shape as the
  existing entries: `file`, `package`, `version`, `integrity`; packages
  `@google/model-viewer` 4.3.1, `@lottiefiles/dotlottie-wc` 0.9.24,
  `@lottiefiles/dotlottie-web` 0.78.2 (file `dotlottie-player.wasm`),
  `@lottiefiles/lottie-player` 2.0.12, `@rive-app/canvas-single` 2.39.1,
  `three` 0.185.1 (two file entries)), and one table row per file to
  `skills/appbox-designer/runtime/vendor/SRI.md`.
- [x] 3.4 Record licences — resolve from the registry, not memory (the
  repo's own rule in THIRD-PARTY-NOTICES):
  ```sh
  for p in '@google/model-viewer@4.3.1' '@lottiefiles/dotlottie-wc@0.9.24' \
           '@lottiefiles/dotlottie-web@0.78.2' '@lottiefiles/lottie-player@2.0.12' \
           '@rive-app/canvas-single@2.39.1' 'three@0.185.1'; do
    echo "$p: $(npm view "$p" license)"
  done
  ```
  Then extend the vendor table in `THIRD-PARTY-NOTICES.md` (section
  ``skills/appbox-designer/runtime/vendor/``) with the 7 files and the
  resolved licences (expected: model-viewer Apache-2.0; dotlottie-wc,
  dotlottie-web, lottie-player, canvas-single, three all MIT — record what
  npm actually says).
- [x] 3.5 Mirror everything:
  ```sh
  cd /Volumes/developer_ssd/Developer/totem_labs/app-box
  for f in model-viewer.min.js dotlottie-wc.js dotlottie-player.wasm lottie-player.js rive.js three.module.min.js three.core.min.js manifest.json SRI.md; do
    cp "skills/appbox-designer/runtime/vendor/$f" ".kimi-code/skills/appbox-designer/runtime/vendor/$f"
  done
  ```
- [x] 3.6 Serve check (runtime serves vendor statically — no router change):
  ```sh
  cd /Volumes/developer_ssd/Developer/totem_labs/app-box
  node designs/appbox-studio/serve.mjs --port 4399 --no-watch &
  sleep 2
  for f in model-viewer.min.js dotlottie-wc.js dotlottie-player.wasm lottie-player.js rive.js three.module.min.js three.core.min.js; do
    printf '%s %s\n' "$f" "$(curl -sf -o /dev/null -w '%{http_code}' "http://localhost:4399/assets/vendor/$f")"
  done
  kill %1
  ```
  Expected: `200` for every file.

---

## Task 4: Author the first-party islands

Four data-attribute islands, `canvas.js` shape (IIFE or module, no globals,
re-arm on `htmx:load`). All live in `skills/appbox-designer/runtime/vendor/`.

**Interfaces**
- Consumes: Task 3's vendored runtimes.
- Produces: `dotlottie_island.js`, `rive_island.js`, `three_island.js`,
  `game_island.js` (+ mirror); serve-test coverage that they are served.

### Steps

- [x] 4.1 Create `skills/appbox-designer/runtime/vendor/dotlottie_island.js`:
  ```js
  /* dotlottie_island.js — named island (ADR-0002 islands amendment).
     Imports the dotLottie web component and pins its WASM to the vendored
     copy. The pin MUST land before any <dotlottie-wc> element's first Lit
     update fetches the runtime: ES module evaluation completes before the
     microtask queue (Lit updates) flushes, so importing + calling here is
     a deterministic win over elements already in the DOM. */
  import { setWasmUrl } from './dotlottie-wc.js';
  setWasmUrl('/assets/vendor/dotlottie-player.wasm');
  ```
- [x] 4.2 Create `skills/appbox-designer/runtime/vendor/rive_island.js`:
  ```js
  /* rive_island.js — named island (ADR-0002 islands amendment).
     Data-attribute init for Rive .riv assets; global `rive` comes from the
     vendored canvas-single build. No globals added, no server calls.
       <div data-rive="/assets/media/off_road_car.riv" [data-rive-state-machine="Name"]>
         <canvas data-rive-canvas width="640" height="360"></canvas>
         <button data-rive-action="play|pause">…</button>
         <span data-rive-inputs></span>   <- island renders one button per
                                             discovered state-machine input
       </div>
     Test hooks: data-rive-ready="true" on load; data-rive-last-fired set to
     the last triggered input name. */
  (() => {
    const boot = (root) => {
      const canvas = root.querySelector('[data-rive-canvas]');
      if (!canvas || !window.rive) return;
      const sm = root.dataset.riveStateMachine || null;
      const inst = new window.rive.Rive({
        src: root.dataset.rive,
        canvas,
        stateMachines: sm || undefined,
        autoplay: true,
        layout: new window.rive.Layout({
          fit: window.rive.Fit.Contain,
          alignment: window.rive.Alignment.Center,
        }),
        onLoad: () => {
          root.dataset.riveReady = 'true';
          const name = sm || inst.stateMachineNames[0];
          const tray = root.querySelector('[data-rive-inputs]');
          if (tray && name) {
            inst.stateMachineInputs(name).forEach((input) => {
              const b = document.createElement('button');
              b.type = 'button';
              b.className = 'chip';
              b.dataset.riveFire = input.name;
              b.textContent = input.name;
              tray.appendChild(b);
            });
          }
        },
      });
      root.addEventListener('click', (e) => {
        const btn = e.target.closest('[data-rive-action],[data-rive-fire]');
        if (!btn || !root.contains(btn)) return;
        if (btn.dataset.riveAction === 'play') inst.play();
        if (btn.dataset.riveAction === 'pause') inst.pause();
        if (btn.dataset.riveFire) {
          const name = sm || inst.stateMachineNames[0];
          const input = inst
            .stateMachineInputs(name)
            .find((i) => i.name === btn.dataset.riveFire);
          if (input && typeof input.fire === 'function') input.fire();
          else if (input && 'value' in input) input.value = !input.value;
          root.dataset.riveLastFired = btn.dataset.riveFire;
        }
      });
    };
    const arm = () =>
      document.querySelectorAll('[data-rive]').forEach((r) => {
        if (!r.dataset.riveArmed) {
          r.dataset.riveArmed = '1';
          boot(r);
        }
      });
    document.addEventListener('DOMContentLoaded', arm);
    document.body.addEventListener('htmx:load', arm);
  })();
  ```
- [x] 4.3 Create `skills/appbox-designer/runtime/vendor/three_island.js`:
  ```js
  /* three_island.js — named island (ADR-0002 islands amendment), ES module.
     Renders the one demo scene into any <div data-three-scene="orbit-demo">.
     Controls: buttons inside the container carrying
     data-three-toggle="rotate|wireframe".
     Test hooks: data-three-ready="true"; data-three-frames = rendered frame
     counter (updated every 30 frames); data-three-rotating mirrors toggle. */
  import * as THREE from './three.module.min.js';

  const boot = (root) => {
    const w = root.clientWidth || 320;
    const h = root.clientHeight || 320;
    const renderer = new THREE.WebGLRenderer({ antialias: true });
    renderer.setSize(w, h);
    root.appendChild(renderer.domElement);
    const scene = new THREE.Scene();
    scene.background = new THREE.Color(0x101418);
    const camera = new THREE.PerspectiveCamera(50, w / h, 0.1, 100);
    camera.position.set(0, 1.2, 4);
    const key = new THREE.DirectionalLight(0xffffff, 2.2);
    key.position.set(3, 5, 4);
    scene.add(key, new THREE.AmbientLight(0x8899aa, 0.9));
    const mats = [0x4fc3f7, 0xffb74d, 0x81c784].map(
      (c) => new THREE.MeshStandardMaterial({ color: c, flatShading: true }),
    );
    const box = new THREE.Mesh(new THREE.BoxGeometry(1, 1, 1), mats[0]);
    box.position.x = -1.4;
    const knot = new THREE.Mesh(new THREE.TorusKnotGeometry(0.5, 0.16, 96, 16), mats[1]);
    const ico = new THREE.Mesh(new THREE.IcosahedronGeometry(0.7, 0), mats[2]);
    ico.position.x = 1.4;
    scene.add(box, knot, ico);
    const meshes = [box, knot, ico];
    let rotate = root.dataset.threeAutoRotate !== 'false';
    let frames = 0;
    root.addEventListener('click', (e) => {
      const btn = e.target.closest('[data-three-toggle]');
      if (!btn) return;
      if (btn.dataset.threeToggle === 'rotate') {
        rotate = !rotate;
        root.dataset.threeRotating = String(rotate);
      }
      if (btn.dataset.threeToggle === 'wireframe') {
        meshes.forEach((m) => {
          m.material.wireframe = !m.material.wireframe;
        });
      }
    });
    renderer.setAnimationLoop(() => {
      if (rotate) {
        meshes.forEach((m, i) => {
          m.rotation.x += 0.004 * (i + 1);
          m.rotation.y += 0.006 * (i + 1);
        });
      }
      renderer.render(scene, camera);
      frames += 1;
      if (frames % 30 === 0) root.dataset.threeFrames = String(frames);
    });
    root.dataset.threeReady = 'true';
  };
  const arm = () =>
    document.querySelectorAll('[data-three-scene]').forEach((r) => {
      if (!r.dataset.threeArmed) {
        r.dataset.threeArmed = '1';
        boot(r);
      }
    });
  arm();
  document.body.addEventListener('htmx:load', arm);
  ```
- [x] 4.4 Create `skills/appbox-designer/runtime/vendor/game_island.js`:
  ```js
  /* game_island.js — named island (ADR-0002 islands amendment).
     "Dungeon Dash": an 11×11 top-down grid walker on a canvas, drawn with
     three Kenney tiny-dungeon tiles. Keyboard (arrows/WASD) and an on-screen
     d-pad (data-game-move) both move the hero; walking over a gem scores.
       <div data-game="dungeon-dash" data-game-tiles="/assets/media/kenney">
         <canvas data-game-canvas width="352" height="352"></canvas>
         <button data-game-move="up|down|left|right">…</button>
       </div>
     Test hooks: data-game-ready="true" once all tiles loaded;
     data-game-moves / data-game-score mirror state for the lens. */
  (() => {
    const TILE = 32;
    const GRID = 11;
    const DIRS = {
      up: [0, -1], down: [0, 1], left: [-1, 0], right: [1, 0],
    };
    const KEYS = {
      ArrowUp: DIRS.up, ArrowDown: DIRS.down, ArrowLeft: DIRS.left,
      ArrowRight: DIRS.right, w: DIRS.up, s: DIRS.down, a: DIRS.left, d: DIRS.right,
    };
    const boot = (root) => {
      const canvas = root.querySelector('[data-game-canvas]');
      if (!canvas) return;
      const ctx = canvas.getContext('2d');
      const dir = root.dataset.gameTiles.replace(/\/$/, '');
      const floor = new Image();
      floor.src = `${dir}/tile_0000.png`;
      const heroImg = new Image();
      heroImg.src = `${dir}/tile_0084.png`;
      const gemImg = new Image();
      gemImg.src = `${dir}/tile_0085.png`;
      const hero = { x: 1, y: 1 };
      const gems = [
        { x: 5, y: 2 }, { x: 8, y: 4 }, { x: 3, y: 6 }, { x: 7, y: 8 }, { x: 9, y: 9 },
      ];
      let score = 0;
      let moves = 0;
      const inside = (x, y) => x > 0 && y > 0 && x < GRID - 1 && y < GRID - 1;
      const sync = () => {
        root.dataset.gameScore = String(score);
        root.dataset.gameMoves = String(moves);
      };
      const draw = () => {
        for (let y = 0; y < GRID; y += 1) {
          for (let x = 0; x < GRID; x += 1) {
            ctx.drawImage(floor, x * TILE, y * TILE, TILE, TILE);
          }
        }
        gems.forEach((g) => ctx.drawImage(gemImg, g.x * TILE, g.y * TILE, TILE, TILE));
        ctx.drawImage(heroImg, hero.x * TILE, hero.y * TILE, TILE, TILE);
      };
      const move = (dx, dy) => {
        const nx = hero.x + dx;
        const ny = hero.y + dy;
        if (!inside(nx, ny)) return;
        hero.x = nx;
        hero.y = ny;
        moves += 1;
        const i = gems.findIndex((g) => g.x === nx && g.y === ny);
        if (i >= 0) {
          gems.splice(i, 1);
          score += 1;
        }
        sync();
        draw();
      };
      document.addEventListener('keydown', (e) => {
        if (!KEYS[e.key] || !document.body.contains(root)) return;
        e.preventDefault();
        move(...KEYS[e.key]);
      });
      root.addEventListener('click', (e) => {
        const btn = e.target.closest('[data-game-move]');
        if (btn) move(...DIRS[btn.dataset.gameMove]);
      });
      let loaded = 0;
      [floor, heroImg, gemImg].forEach((img) =>
        img.addEventListener('load', () => {
          loaded += 1;
          if (loaded === 3) {
            root.dataset.gameReady = 'true';
            sync();
            draw();
          }
        }),
      );
    };
    const arm = () =>
      document.querySelectorAll('[data-game]').forEach((r) => {
        if (!r.dataset.gameArmed) {
          r.dataset.gameArmed = '1';
          boot(r);
        }
      });
    document.addEventListener('DOMContentLoaded', arm);
    document.body.addEventListener('htmx:load', arm);
  })();
  ```
- [x] 4.5 Mirror the four islands:
  ```sh
  cd /Volumes/developer_ssd/Developer/totem_labs/app-box
  for f in dotlottie_island.js rive_island.js three_island.js game_island.js; do
    cp "skills/appbox-designer/runtime/vendor/$f" ".kimi-code/skills/appbox-designer/runtime/vendor/$f"
  done
  ```
- [x] 4.6 Extend the runtime serve test (TDD-ish: the runtime's own test
  file is its check) (superseded by Dart port). In `skills/appbox-designer/runtime/serve.test.mjs`,
  after the legacy-path check (line ~117), add:
  ```js
  // --- named islands are served (ADR-0002 islands amendment) ----------------
  const isl = await start(['designs/appbox-studio', '--port', '4373']);
  for (const f of ['model-viewer.min.js', 'dotlottie-wc.js', 'dotlottie-player.wasm',
                   'lottie-player.js', 'rive.js', 'three.module.min.js', 'three.core.min.js',
                   'dotlottie_island.js', 'rive_island.js', 'three_island.js', 'game_island.js']) {
    chk(`vendor serves ${f}`, (await get(`http://localhost:4373/assets/vendor/${f}`)) === 200);
  }
  isl.proc.kill('SIGTERM');
  await waitFor(() => dead('http://localhost:4373/'));
  ```
  Mirror the file (`cp` to `.kimi-code/…`), then run:
  `node .kimi-code/skills/appbox-designer/runtime/serve.test.mjs` — expected:
  all checks ok, exit 0. (Read the file's `get`/`start` helpers first and
  match their exact signatures — they are defined at the top of the same
  file.)

---

## Task 5: Amend the islands contract in the skill docs

The boundary text changes from "zero custom client-side JS, one named island
exception" to "no ad-hoc client JS; named islands only". Edit the canonical
`skills/` copy; mirror each file at the end.

**Interfaces**
- Consumes: Tasks 3-4 (the islands exist before the docs bless them).
- Produces: amended `SKILL.md`, `CONTEXT.md`, `system-prompt.md`,
  `DESIGN-ARCHITECTURE.md`, `docs/adr/0002-zero-custom-client-js-boundary.md`,
  `runtime/README.md`, `runtime/lint.mjs` header comment (+ mirrors).

### Steps

- [x] 5.1 `skills/appbox-designer/SKILL.md`:
  - Line 6 (frontmatter description): replace
    `JavaScript (one named island exception: canvas.js, pan/zoom for the` /
    following line with `JavaScript — named islands only: reusable, vendored,
    SRI-pinned runtimes and first-party glue islands in runtime/vendor/`.
  - Lines 19-21: replace the "zero custom client-side JavaScript — one named
    island exception: `canvas.js`…" sentence with:
    `app with **no ad-hoc client-side JavaScript — named islands only**. An
    island is a reusable, vendored script in runtime/vendor/: a third-party
    declarative web component (<model-viewer>, <dotlottie-wc>, <lottie-player>)
    or a first-party data-attribute init module (canvas.js, drag.js,
    inspect.js, dotlottie_island.js, rive_island.js, three_island.js,
    game_island.js). Anything outside that registry is banned and linted.`
  - Line 98: change `(zero-custom-JS)` to `(no-ad-hoc-JS / named-islands)`.
- [x] 5.2 `skills/appbox-designer/CONTEXT.md`:
  - Line 3: replace `zero custom client-side JavaScript` with `no ad-hoc
    client-side JavaScript (named islands only)`.
  - Line 72-73 `Client-JS-Free` entry: append after the existing text:
    `Named islands (vendored, enumerated in ADR-0002's islands amendment)
    are the only permitted extension: third-party declarative web components
    and first-party data-attribute init modules, all loaded from
    /assets/vendor/.`
- [x] 5.3 `skills/appbox-designer/system-prompt.md`:
  - Line 44: replace `zero custom client-side JavaScript` with `no ad-hoc
    client-side JavaScript (named islands only, ADR-0002 islands amendment)`.
  - Line 63: replace the parenthetical `(the only <script> tags allowed
    anywhere in an artifact; canvas.js is the ADR-0002 amendment's single
    first-party exception, pan/zoom for the design canvas)` with `(the only
    <script> tags allowed anywhere in an artifact; the named islands of
    ADR-0002's amendments — canvas.js, drag.js, inspect.js, and the media
    islands dotlottie_island.js, rive_island.js, three_island.js,
    game_island.js)`.
  - Line 78: replace the sentence `The one first-party exception:
    assets/vendor/canvas.js — the design-canvas pan/zoom island from
    runtime/vendor/ (ADR-0002 amendment); no other first-party script, ever.`
    with: `The only permitted scripts beyond the vendored htmx set are the
    named islands in runtime/vendor/ (ADR-0002 amendments): the first-party
    data-attribute islands (canvas.js, drag.js, inspect.js, dotlottie_island.js,
    rive_island.js, three_island.js, game_island.js) and the third-party
    declarative web components (model-viewer, dotlottie-wc, lottie-player,
    plus the rive/three vendored runtimes the islands drive). No other
    first-party script, ever; new runtimes enter only as a new named,
    vendored, documented island.`
- [x] 5.4 `skills/appbox-designer/docs/adr/0002-zero-custom-client-js-boundary.md`:
  append a new paragraph at the end:
  ```md
  **Amendment (2026-07-31) — the media islands.** The island registry grows
  from three to a first-class, two-tier architecture. Tier one, third-party
  declarative web components, vendored and SRI-pinned via
  `vendor/manifest.json`: `<model-viewer>` (GLB 3D), `<dotlottie-wc>`
  (dotLottie; its WASM is pinned to the vendored copy by
  `dotlottie_island.js`), `<lottie-player>` (Lottie JSON), plus the runtimes
  the tier-two islands drive (`rive.js` canvas-single, `three.module.min.js`
  + `three.core.min.js`). Tier two, first-party data-attribute init islands,
  same shape as canvas.js (no SRI, no globals, re-arm on `htmx:load`):
  `dotlottie_island.js`, `rive_island.js` (state-machine inputs rendered as
  buttons), `three_island.js` (one demo scene, rotate/wireframe toggles),
  `game_island.js` (playable canvas game). The boundary otherwise stands
  unchanged: no ad-hoc client JS, no inline scripts, enforcement is still
  `allowEval:false` + the vendor-path lint. A new runtime enters only as a
  new named, vendored, documented island amending this ADR.
  ```
- [x] 5.5 `skills/appbox-designer/runtime/README.md`:
  - Lines 152-155: replace `(`<script src="/assets/vendor/canvas.js" defer>` —
    ADR-0002's one first-party` / `…exception…)` phrasing with `the deferred
    island tags — the named islands of ADR-0002's amendments, loaded from
    /assets/vendor/ as screens need them`.
  - Lines 239-240: replace `plus the ONE first-party island
    assets/vendor/canvas.js (pan/zoom for the design canvas, ADR-0002
    amendment …)` with `plus the named islands of ADR-0002's amendments
    (first-party data-attribute islands and third-party declarative web
    components, all vendored in runtime/vendor/)`.
- [x] 5.6 `skills/appbox-designer/runtime/lint.mjs` line 2 header comment (superseded by Dart port):
  replace `// Zero-custom-client-JS lint (ADR-0002).` with
  `// No-ad-hoc-client-JS lint (ADR-0002 + islands amendments). Named islands
  // pass because every allowlisted script loads from /assets/vendor/.`
  (No rule change: the existing vendor-path allowlist already admits the
  islands; anything else still fails.)
- [x] 5.7 `skills/appbox-designer/DESIGN-ARCHITECTURE.md`: after the Client-JS
  passage at line 74 (`…so the Client-JS-Free rule is untouched.`), append:
  `The same holds for the named media islands (ADR-0002's 2026-07-31
  amendment): 3D, animation and game runtimes are vendored web components or
  data-attribute islands — a surface uses them by writing markup, never
  script.`
- [x] 5.8 Mirror every edited file:
  ```sh
  cd /Volumes/developer_ssd/Developer/totem_labs/app-box
  for f in SKILL.md CONTEXT.md system-prompt.md DESIGN-ARCHITECTURE.md \
           docs/adr/0002-zero-custom-client-js-boundary.md runtime/README.md runtime/lint.mjs; do
    cp "skills/appbox-designer/$f" ".kimi-code/skills/appbox-designer/$f"
  done
  ```
- [x] 5.9 Lint still clean + docs consistent:
  ```sh
  node .kimi-code/skills/appbox-designer/runtime/lint.mjs designs/appbox-studio
  grep -rn 'one named island\|single first-party exception\|ONE first-party island' skills/appbox-designer --include='*.md' --include='*.mjs'
  ```
  Expected: `lint clean: …`; grep returns nothing (no stale singleton-island
  wording left).

---

## Task 6: Extend the appbox lens with input driving (TDD)

The lens lacks the verbs the game screen needs. Per the appbox-tools-first
rule, extend `appboxd` — never reach for archived tooling.

**Interfaces**
- Consumes: nothing from earlier tasks (independent; may run parallel).
- Produces: `CdpSession.key()` / `CdpSession.click()` in
  `appboxd/lib/cdp.dart`; new driver `appboxd/tool/lens_check.dart`; new test
  `appboxd/test/lens_input_test.dart`.

### Steps

- [x] 6.1 Write the failing test first —
  `appboxd/test/lens_input_test.dart`:
  ```dart
  // Lens input driving — proves Input.dispatchKeyEvent / dispatchMouseEvent
  // reach the page (the game-screen verification path).
  import 'dart:async';
  import 'dart:io';

  import 'package:appboxd/cdp.dart';
  import 'package:test/test.dart';

  Future<(HttpServer, String)> bootInputServer() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final base = 'http://${server.address.address}:${server.port}';
    server.listen((req) {
      req.response.headers.contentType = ContentType.html;
      req.response.write('''
  <!DOCTYPE html><html><body>
  <script>
    window.__keys = [];
    window.__clicks = [];
    document.addEventListener('keydown', (e) => window.__keys.push(e.key));
    document.addEventListener('click', (e) => window.__clicks.push([e.clientX, e.clientY]));
  </script>
  </body></html>
  ''');
      req.response.close();
    });
    return (server, base);
  }

  void main() {
    group('CdpSession input', () {
      late CdpClient client;
      late HttpServer server;
      late String baseUrl;

      setUp(() async {
        (server, baseUrl) = await bootInputServer();
        client = await CdpClient.launch();
      });
      tearDown(() async {
        await client.close();
        await server.close();
      });

      test('key() dispatches keydown to the page', () async {
        final tab = await client.newTab();
        await tab.enable();
        await tab.navigateAndSettle(baseUrl, settleMs: 300);
        await tab.key('ArrowRight');
        await tab.key('a');
        await Future.delayed(const Duration(milliseconds: 200));
        expect(await tab.evaluate('window.__keys.join(",")'), 'ArrowRight,a');
      });

      test('click() dispatches mouse events at coordinates', () async {
        final tab = await client.newTab();
        await tab.enable();
        await tab.setViewport(390, 844);
        await tab.navigateAndSettle(baseUrl, settleMs: 300);
        await tab.click(100, 200);
        await Future.delayed(const Duration(milliseconds: 200));
        expect(await tab.evaluate('window.__clicks.length'), 1);
      });
    });
  }
  ```
  Run `cd appboxd && dart test test/lens_input_test.dart` — expected:
  COMPILE ERROR (`key`/`click` undefined). Red confirmed.
- [x] 6.2 Add the two methods to the `CdpSession` class in
  `appboxd/lib/cdp.dart` (immediately after `screenshot()`, ~line 378):
  ```dart
  /// Dispatch a key press (down + up) via Input.dispatchKeyEvent.
  /// Supports arrows, Enter, Escape, Space and single characters.
  Future<void> key(String key) async {
    const vks = {
      'ArrowUp': 38, 'ArrowDown': 40, 'ArrowLeft': 37, 'ArrowRight': 39,
      'Enter': 13, 'Escape': 27, ' ': 32,
    };
    final vk = vks[key] ?? key.toUpperCase().codeUnitAt(0);
    for (final type in ['keyDown', 'keyUp']) {
      await send('Input.dispatchKeyEvent', {
        'type': type,
        'key': key,
        'code': key == ' ' ? 'Space' : (key.length == 1 ? 'Key${key.toUpperCase()}' : key),
        'windowsVirtualKeyCode': vk,
        'nativeVirtualKeyCode': vk,
      });
    }
  }

  /// Click at viewport coordinates via Input.dispatchMouseEvent.
  Future<void> click(int x, int y) async {
    for (final type in ['mousePressed', 'mouseReleased']) {
      await send('Input.dispatchMouseEvent', {
        'type': type,
        'x': x,
        'y': y,
        'button': 'left',
        'clickCount': 1,
      });
    }
  }
  ```
- [x] 6.3 Re-run `dart test test/lens_input_test.dart` — expected: 2 passed.
  Then the full suite: `dart test` — all green.
- [x] 6.4 Create the check driver `appboxd/tool/lens_check.dart`:
  ```dart
  // appbox lens check driver: navigate, assert, optionally drive input,
  // screenshot. Console/page errors are always a failure (lens doctrine).
  // Usage: dart run tool/lens_check.dart <url> <out.png> [width] [height] [settleMs]
  //        [--selector=<css>] [--press=<Key>]... [--expect=<js-expr>]
  import 'dart:io';

  import 'package:appboxd/cdp.dart';

  String? _flag(List<String> argv, String name) {
    final hit = argv.where((a) => a.startsWith('--$name='));
    return hit.isEmpty ? null : hit.first.substring(name.length + 3);
  }

  String _js(String s) => "'${s.replaceAll('\\', '\\\\').replaceAll("'", "\\'")}'";

  Future<void> main(List<String> argv) async {
    final positional = argv.where((a) => !a.startsWith('--')).toList();
    if (positional.length < 2) {
      stderr.writeln(
          'usage: dart run tool/lens_check.dart <url> <out.png> [width] [height] [settleMs] '
          '[--selector=<css>] [--press=<Key>]... [--expect=<js-expr>]');
      exit(2);
    }
    final url = positional[0];
    final out = positional[1];
    final width = positional.length > 2 ? int.parse(positional[2]) : 1280;
    final height = positional.length > 3 ? int.parse(positional[3]) : 800;
    final settleMs = positional.length > 4 ? int.parse(positional[4]) : 1500;
    final selector = _flag(argv, 'selector');
    final presses = argv
        .where((a) => a.startsWith('--press='))
        .map((a) => a.substring('--press='.length))
        .toList();
    final expect = _flag(argv, 'expect');

    final failures = <String>[];
    final client = await CdpClient.launch();
    try {
      final tab = await client.newTab();
      await tab.enable();
      await tab.setViewport(width, height);
      await tab.navigateAndSettle(url, settleMs: settleMs);

      if (selector != null) {
        final found = await tab.evaluate('!!document.querySelector(${_js(selector)})');
        if (found != true) failures.add('selector not found: $selector');
      }
      for (final k in presses) {
        await tab.key(k);
        await Future.delayed(const Duration(milliseconds: 250));
      }
      if (presses.isNotEmpty) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
      if (expect != null) {
        final ok = await tab.evaluate(expect);
        if (ok != true) failures.add('expect not truthy: $expect (got $ok)');
      }
      final errors = [...tab.consoleErrors, ...tab.pageErrors];
      if (errors.isNotEmpty) {
        failures.add('${errors.length} console/page error(s): ${errors.first}');
      }
      final png = await tab.screenshot();
      final f = File(out);
      f.parent.createSync(recursive: true);
      f.writeAsBytesSync(png);
    } finally {
      await client.close();
    }
    if (failures.isNotEmpty) {
      stderr.writeln('lens check FAILED: $url\n  ${failures.join('\n  ')}');
      exit(1);
    }
    stdout.writeln('lens check ok: $url -> $out (${width}x$height)');
  }
  ```
- [x] 6.5 Driver smoke against the live design:
  ```sh
  cd /Volumes/developer_ssd/Developer/totem_labs/app-box
  node designs/appbox-studio/serve.mjs --port 4399 --no-watch &
  sleep 2
  cd appboxd && dart run tool/lens_check.dart http://localhost:4399/dashboard /tmp/lens-dash.png 390 844 2000 --selector='main'
  cd .. && kill %1
  ```
  Expected: `lens check ok: … -> /tmp/lens-dash.png (390x844)`, and the PNG
  exists and is non-trivial (`stat -f %z /tmp/lens-dash.png` > 10000).

---

## Task 7: Source the five example assets

One free asset per runtime, vendored into the design shell. All URLs verified
reachable on 2026-07-31; licences recorded below from the sources named.

**Interfaces**
- Consumes: Task 1's renamed design dir.
- Produces: `designs/appbox-studio/assets/media/` (5 assets + Kenney tiles),
  `assets/media/MEDIA.md` manifest, `THIRD-PARTY-NOTICES.md` media section.

### Steps

- [x] 7.1 Download:
  ```sh
  cd /Volumes/developer_ssd/Developer/totem_labs/app-box
  M=designs/appbox-studio/assets/media
  mkdir -p "$M/kenney"
  curl -sfL -o "$M/boombox.glb" \
    https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Models/main/2.0/BoomBox/glTF-Binary/BoomBox.glb
  curl -sfL -o "$M/off_road_car.riv" \
    https://raw.githubusercontent.com/rive-app/rive-flutter/master/example/assets/off_road_car.riv
  curl -sfL -o "$M/lottie_logo.json" \
    https://raw.githubusercontent.com/airbnb/lottie-ios/master/Tests/Samples/LottieLogo1.json
  curl -sfL -o "$M/dotlottie-demo.lottie" \
    https://raw.githubusercontent.com/dotlottie/player-component/master/apps/react-player-test/public/test.lottie
  curl -sfL -o /tmp/kenney-tiny-dungeon.zip \
    https://kenney.nl/media/pages/assets/tiny-dungeon/f8422efb44-1674742415/kenney_tiny-dungeon.zip
  unzip -j -o /tmp/kenney-tiny-dungeon.zip \
    'Tiles/tile_0000.png' 'Tiles/tile_0084.png' 'Tiles/tile_0085.png' 'License.txt' \
    -d "$M/kenney/"
  mv "$M/kenney/License.txt" "$M/kenney/KENNEY-LICENSE.txt"
  ```
  Asset choices (licence-first): **BoomBox.glb** — CC0 (Microsoft), Khronos
  sample models. NOT Duck (SCEA Shared Source) and NOT DamagedHelmet
  (CC BY-NC — non-commercial is not acceptable). **off_road_car.riv** — Rive's
  own example asset in the MIT-licensed rive-flutter repo; has a state
  machine with inputs. **LottieLogo1.json** — Airbnb lottie-ios test sample,
  Apache-2.0 repo. **test.lottie** — dotlottie player-component test asset,
  MIT repo. **Kenney tiny-dungeon** — CC0 (kenney.nl), license text captured
  as `KENNEY-LICENSE.txt`.
- [x] 7.2 Validate the payloads:
  ```sh
  M=designs/appbox-studio/assets/media
  head -c4 "$M/boombox.glb"; echo            # expected: glTF
  python3 -c "import json;json.load(open('$M/lottie_logo.json'));print('lottie json ok')"
  unzip -l "$M/dotlottie-demo.lottie" | head -5   # a .lottie is a zip
  ls -la "$M" "$M/kenney"
  ```
  Expected: `glTF` magic, `lottie json ok`, a zip listing containing
  `manifest.json` + animations, non-empty files throughout
  (`off_road_car.riv` has no cheap magic check — the Rive screen's lens run
  in Task 14 is its proof).
- [x] 7.3 Record hashes for the manifest:
  ```sh
  M=designs/appbox-studio/assets/media
  shasum -a 256 "$M/boombox.glb" "$M/off_road_car.riv" "$M/lottie_logo.json" \
    "$M/dotlottie-demo.lottie" "$M/kenney/tile_0000.png" "$M/kenney/tile_0084.png" "$M/kenney/tile_0085.png"
  ```
- [x] 7.4 Write `designs/appbox-studio/assets/media/MEDIA.md` (per-file
  inventory, `assets/fonts/FONTS.md` precedent), one row per file with these
  columns filled from the downloads above: file · source URL (exact URLs from
  step 7.1) · author/publisher · licence · sha256 (from step 7.3) · notes.
  Header text:
  ```md
  # Media assets

  Example media for the island smoke screens — one free asset per runtime.
  Sourced 2026-07-31; every entry is CC0, public-domain, or from a
  permissively-licensed vendor repo (MIT/Apache-2.0), captured with its
  source URL and hash. Kenney license text: `kenney/KENNEY-LICENSE.txt`.
  ```
- [x] 7.5 Append a media section to `THIRD-PARTY-NOTICES.md`:
  ```md
  ---

  ## Example media assets (`designs/appbox-studio/assets/media/`)

  One example asset per island runtime, each free for commercial use.
  Per-file inventory with source URLs and sha256 hashes:
  `designs/appbox-studio/assets/media/MEDIA.md`.

  | file | source | licence |
  |---|---|---|
  | `boombox.glb` | Khronos glTF-Sample-Models (Microsoft) | CC0 1.0 |
  | `off_road_car.riv` | rive-app/rive-flutter example assets | MIT |
  | `lottie_logo.json` | airbnb/lottie-ios test samples | Apache-2.0 |
  | `dotlottie-demo.lottie` | dotlottie/player-component test asset | MIT |
  | `kenney/` tiles | Kenney.nl "Tiny Dungeon" | CC0 1.0 |
  ```

---

## Task 8: Media screens scaffold

Shared plumbing for the six screens; no screen content yet.

**Interfaces**
- Consumes: Tasks 1-2 (renamed design), 3-5 (islands + contract).
- Produces: `head_extra` block in `ui/common/base.html`;
  `assets/css/media.css`; `ui/views/app_shell/routes.media.js`; spread +
  import in `app.routes.js`; 6 entries in `structure.json`; `media.*` l10n
  keys in all three catalogs. **Caveat:** `routes.media.js` imports the six
  viewmodels at module load, so the design will not *boot* until Tasks 9-14
  land them — Task 8's own gate is lint + JSON validation only (steps 8.5,
  8.7); serve checks resume at Task 9.

### Steps

- [x] 8.1 `designs/appbox-studio/ui/common/base.html`: insert
  `{% block head_extra %}{% endblock %}` on its own line immediately before
  `</head>` (after line 25, the `appshell.css` link). Per-screen island tags
  and the scoped stylesheet load through this block — never globally.
- [x] 8.2 Create `designs/appbox-studio/assets/css/media.css`. Convention for
  this and every new file the screen tasks add: carry the repo's standard
  provenance header (`<!-- appbox:provenance … -->` as in
  `ui/common/base.html:2-5` for .html, `// appbox:provenance …` as in
  `app.routes.js:1-4` for .js), matching the neighboring files.
  ```css
  /* Media lab — smoke screens for the named islands (3D/animation/game). */
  .media-stage { margin-top: 16px; display: grid; gap: 12px; justify-items: center; }
  .media-frame { width: 100%; border-radius: 12px; overflow: hidden; background: #101418; }
  .media-canvas { width: 100%; height: auto; display: block; background: #101418; border-radius: 12px; }
  .media-viewer { width: 100%; height: 320px; display: block; border-radius: 12px; background: #101418; }
  .media-controls { display: flex; gap: 8px; flex-wrap: wrap; justify-content: center; }
  .media-inputs { display: flex; gap: 8px; flex-wrap: wrap; justify-content: center; }
  .media-three { min-height: 320px; width: 100%; border-radius: 12px; background: #101418; }
  .media-three canvas { border-radius: 12px; display: block; margin: 0 auto; }
  .media-game-canvas { width: 100%; max-width: 352px; height: auto; border-radius: 12px; background: #101418; }
  .media-dpad { display: grid; grid-template-columns: repeat(3, 48px); grid-template-areas: '. u .' 'l d r'; gap: 6px; }
  .media-dpad [data-game-move='up'] { grid-area: u; }
  .media-dpad [data-game-move='down'] { grid-area: d; }
  .media-dpad [data-game-move='left'] { grid-area: l; }
  .media-dpad [data-game-move='right'] { grid-area: r; }
  .media-dpad button { min-height: 48px; }
  ```
- [x] 8.3 Create `designs/appbox-studio/ui/views/app_shell/routes.media.js`:
  ```js
  // Media-lab routes — one smoke screen per named island runtime.
  import * as rive from './media/rive/rive_viewmodel.js';
  import * as lottie from './media/lottie/lottie_viewmodel.js';
  import * as dotlottie from './media/dotlottie/dotlottie_viewmodel.js';
  import * as model3d from './media/model3d/model3d_viewmodel.js';
  import * as scene3d from './media/scene3d/scene3d_viewmodel.js';
  import * as game from './media/game/game_viewmodel.js';

  export default [
    ['GET', '/media/rive', rive.page],
    ['GET', '/media/lottie', lottie.page],
    ['GET', '/media/dotlottie', dotlottie.page],
    ['GET', '/media/dotlottie/stage', dotlottie.stage],
    ['GET', '/media/model3d', model3d.page],
    ['GET', '/media/model3d/stage', model3d.stage],
    ['GET', '/media/scene3d', scene3d.page],
    ['GET', '/media/game', game.page],
  ];
  ```
- [x] 8.4 `designs/appbox-studio/app.routes.js`: add
  `import mediaRoutes from './ui/views/app_shell/routes.media.js';` after the
  line importing `appRoutes` (line 10), and `...mediaRoutes,` after
  `...appRoutes,` (line 26).
- [x] 8.5 `designs/appbox-studio/structure.json`: append six entries to the
  `screens` array (before the closing `]`), following the existing shape
  (`surface: null` — smoke screens are not scaffolder surfaces):
  ```json
  ,
      {
        "id": "app.mediaRive",
        "shell": "app",
        "comp": "AppMediaRive",
        "shellDir": "app_shell",
        "surface": null,
        "viewmodel": "ui/views/app_shell/media/rive/rive_viewmodel.js",
        "deps": []
      },
      {
        "id": "app.mediaLottie",
        "shell": "app",
        "comp": "AppMediaLottie",
        "shellDir": "app_shell",
        "surface": null,
        "viewmodel": "ui/views/app_shell/media/lottie/lottie_viewmodel.js",
        "deps": []
      },
      {
        "id": "app.mediaDotlottie",
        "shell": "app",
        "comp": "AppMediaDotlottie",
        "shellDir": "app_shell",
        "surface": null,
        "viewmodel": "ui/views/app_shell/media/dotlottie/dotlottie_viewmodel.js",
        "deps": []
      },
      {
        "id": "app.mediaModel3d",
        "shell": "app",
        "comp": "AppMediaModel3d",
        "shellDir": "app_shell",
        "surface": null,
        "viewmodel": "ui/views/app_shell/media/model3d/model3d_viewmodel.js",
        "deps": []
      },
      {
        "id": "app.mediaScene3d",
        "shell": "app",
        "comp": "AppMediaScene3d",
        "shellDir": "app_shell",
        "surface": null,
        "viewmodel": "ui/views/app_shell/media/scene3d/scene3d_viewmodel.js",
        "deps": []
      },
      {
        "id": "app.mediaGame",
        "shell": "app",
        "comp": "AppMediaGame",
        "shellDir": "app_shell",
        "surface": null,
        "viewmodel": "ui/views/app_shell/media/game/game_viewmodel.js",
        "deps": []
      }
  ```
  Validate: `python3 -c "import json;json.load(open('designs/appbox-studio/structure.json'));print('structure.json ok')"`.
- [x] 8.6 L10n keys — append to `designs/appbox-studio/l10n/app_en.arb`
  immediately before the closing `}` (add a comma after the previously-last
  entry so the file stays valid JSON):
  ```json
    "media.eyebrow": "Media lab",
    "media.action.play": "Play",
    "media.action.pause": "Pause",
    "media.rive.pageTitle": "appbox studio — Rive",
    "media.rive.title": "Rive",
    "media.rive.lede": "State-machine animation — play/pause and fire inputs.",
    "media.rive.inputsAria": "State machine inputs",
    "media.lottie.pageTitle": "appbox studio — Lottie",
    "media.lottie.title": "Lottie",
    "media.lottie.lede": "Lottie JSON with the player's built-in controls.",
    "media.dotlottie.pageTitle": "appbox studio — dotLottie",
    "media.dotlottie.title": "dotLottie",
    "media.dotlottie.lede": "A .lottie bundle; play and pause swap server-side.",
    "media.model3d.pageTitle": "appbox studio — 3D model",
    "media.model3d.title": "3D model",
    "media.model3d.lede": "GLB in the model-viewer — drag to orbit.",
    "media.model3d.action.rotateOn": "Auto-rotate on",
    "media.model3d.action.rotateOff": "Auto-rotate off",
    "media.scene3d.pageTitle": "appbox studio — 3D scene",
    "media.scene3d.title": "three.js scene",
    "media.scene3d.lede": "A custom three.js scene with island-bound toggles.",
    "media.scene3d.action.rotate": "Toggle rotation",
    "media.scene3d.action.wireframe": "Toggle wireframe",
    "media.game.pageTitle": "appbox studio — Game",
    "media.game.title": "Dungeon Dash",
    "media.game.lede": "Collect the gems. Arrow keys / WASD or the pad.",
    "media.game.hint": "Arrow keys / WASD move; the pad works too.",
    "media.game.move.up": "Move up",
    "media.game.move.down": "Move down",
    "media.game.move.left": "Move left",
    "media.game.move.right": "Move right"
  ```
- [x] 8.6b The same keys in `designs/appbox-studio/l10n/app_pl.arb` (same
  append procedure), with these exact Polish values:
  ```json
    "media.eyebrow": "Laboratorium mediów",
    "media.action.play": "Odtwarzaj",
    "media.action.pause": "Pauza",
    "media.rive.pageTitle": "appbox studio — Rive",
    "media.rive.title": "Rive",
    "media.rive.lede": "Animacja maszyny stanów — odtwarzaj, wstrzymuj i wyzwalaj wejścia.",
    "media.rive.inputsAria": "Wejścia maszyny stanów",
    "media.lottie.pageTitle": "appbox studio — Lottie",
    "media.lottie.title": "Lottie",
    "media.lottie.lede": "Lottie JSON z wbudowanymi kontrolkami odtwarzacza.",
    "media.dotlottie.pageTitle": "appbox studio — dotLottie",
    "media.dotlottie.title": "dotLottie",
    "media.dotlottie.lede": "Pakiet .lottie; odtwarzanie i pauza podmieniane po stronie serwera.",
    "media.model3d.pageTitle": "appbox studio — Model 3D",
    "media.model3d.title": "Model 3D",
    "media.model3d.lede": "GLB w model-viewer — przeciągnij, aby obracać.",
    "media.model3d.action.rotateOn": "Włącz auto-obrót",
    "media.model3d.action.rotateOff": "Wyłącz auto-obrót",
    "media.scene3d.pageTitle": "appbox studio — Scena 3D",
    "media.scene3d.title": "Scena three.js",
    "media.scene3d.lede": "Własna scena three.js z przełącznikami podpiętymi w wyspę.",
    "media.scene3d.action.rotate": "Przełącz obrót",
    "media.scene3d.action.wireframe": "Przełącz szkielet",
    "media.game.pageTitle": "appbox studio — Gra",
    "media.game.title": "Dungeon Dash",
    "media.game.lede": "Zbierz klejnoty. Strzałki / WASD albo pad.",
    "media.game.hint": "Strzałki / WASD poruszają; pad też działa.",
    "media.game.move.up": "Ruch w górę",
    "media.game.move.down": "Ruch w dół",
    "media.game.move.left": "Ruch w lewo",
    "media.game.move.right": "Ruch w prawo"
  ```
  Validate both files:
  `python3 -c "import json;json.load(open('designs/appbox-studio/l10n/app_en.arb'));json.load(open('designs/appbox-studio/l10n/app_pl.arb'));print('arb json ok')"`.
- [x] 8.7 Regenerate the pseudo-locale and confirm key parity:
  ```sh
  cd /Volumes/developer_ssd/Developer/totem_labs/app-box
  node .kimi-code/skills/appbox-designer/runtime/pseudolocalize.mjs designs/appbox-studio
  python3 - <<'EOF'
  import json
  en = set(json.load(open('designs/appbox-studio/l10n/app_en.arb')))
  for loc in ('pl', 'qps-ploc'):
      keys = set(json.load(open(f'designs/appbox-studio/l10n/app_{loc}.arb')))
      missing = [k for k in en - keys if not k.startswith('@')]
      assert not missing, f'{loc} missing: {missing}'
  print('arb parity ok')
  EOF
  ```

---

## Task 9: Rive screen

**Interfaces**
- Consumes: Task 4 `rive_island.js` + `rive.js`; Task 7 `off_road_car.riv`;
  Task 8 scaffold.
- Produces: `ui/views/app_shell/media/rive/{rive_view.html,rive_viewmodel.js}`;
  `GET /media/rive` renders, lint clean.

### Steps

- [x] 9.1 Create `designs/appbox-studio/ui/views/app_shell/media/rive/rive_viewmodel.js`:
  ```js
  export const surfaceId = 'app.mediaRive';

  const VIEW = 'ui/views/app_shell/media/rive/rive_view.html';

  export const page = (c, h) => h.render(c, VIEW, { activeShell: 'app' });
  ```
- [x] 9.2 Create `designs/appbox-studio/ui/views/app_shell/media/rive/rive_view.html`:
  ```html
  {% extends "ui/views/main_shell/main_shell_view.html" %}
  {% block title %}{{ t('media.rive.pageTitle') }}{% endblock %}
  {% block head_extra %}
  <script src="/assets/vendor/rive.js" defer></script>
  <script src="/assets/vendor/rive_island.js" defer></script>
  <link rel="stylesheet" href="/assets/css/media.css">
  {% endblock %}
  {% block surface %}
  <span class="eyebrow">{{ t('media.eyebrow') }}</span>
  <h1 class="display">{{ t('media.rive.title') }}</h1>
  <p class="muted">{{ t('media.rive.lede') }}</p>
  <section class="media-stage" data-rive="/assets/media/off_road_car.riv">
    <canvas data-rive-canvas class="media-canvas" width="640" height="360"></canvas>
    <div class="media-controls">
      <button type="button" data-rive-action="play">{{ t('media.action.play') }}</button>
      <button type="button" data-rive-action="pause" class="ghost">{{ t('media.action.pause') }}</button>
    </div>
    <div class="media-inputs" data-rive-inputs aria-label="{{ t('media.rive.inputsAria') }}"></div>
  </section>
  {% endblock %}
  ```
- [x] 9.3 Check:
  ```sh
  cd /Volumes/developer_ssd/Developer/totem_labs/app-box
  node .kimi-code/skills/appbox-designer/runtime/lint.mjs designs/appbox-studio
  node designs/appbox-studio/serve.mjs --port 4399 --no-watch &
  sleep 2
  curl -sf http://localhost:4399/media/rive | grep -c 'data-rive-canvas'
  kill %1
  ```
  Expected: lint clean; grep count `1`.

---

## Task 10: Lottie screen

**Interfaces**
- Consumes: Task 3 `lottie-player.js`; Task 7 `lottie_logo.json`; Task 8.
- Produces: `ui/views/app_shell/media/lottie/{lottie_view.html,lottie_viewmodel.js}`;
  `GET /media/lottie` renders, lint clean.

### Steps

- [x] 10.1 Create `designs/appbox-studio/ui/views/app_shell/media/lottie/lottie_viewmodel.js`:
  ```js
  export const surfaceId = 'app.mediaLottie';

  const VIEW = 'ui/views/app_shell/media/lottie/lottie_view.html';

  export const page = (c, h) => h.render(c, VIEW, { activeShell: 'app' });
  ```
- [x] 10.2 Create `designs/appbox-studio/ui/views/app_shell/media/lottie/lottie_view.html`:
  ```html
  {% extends "ui/views/main_shell/main_shell_view.html" %}
  {% block title %}{{ t('media.lottie.pageTitle') }}{% endblock %}
  {% block head_extra %}
  <script type="module" src="/assets/vendor/lottie-player.js"></script>
  <link rel="stylesheet" href="/assets/css/media.css">
  {% endblock %}
  {% block surface %}
  <span class="eyebrow">{{ t('media.eyebrow') }}</span>
  <h1 class="display">{{ t('media.lottie.title') }}</h1>
  <p class="muted">{{ t('media.lottie.lede') }}</p>
  <section class="media-stage">
    <lottie-player src="/assets/media/lottie_logo.json" autoplay loop controls
      class="media-viewer" aria-label="{{ t('media.lottie.title') }}"></lottie-player>
  </section>
  {% endblock %}
  ```
  (`controls` is the web component's declarative play/pause/seek UI — no
  island needed.)
- [x] 10.3 Check: same commands as 9.3 with `/media/lottie` and grep
  `lottie-player` (count ≥ 1).

---

## Task 11: dotLottie screen

**Interfaces**
- Consumes: Task 3 `dotlottie-wc.js` + `dotlottie-player.wasm`; Task 4
  `dotlottie_island.js`; Task 7 `dotlottie-demo.lottie`; Task 8.
- Produces:
  `ui/views/app_shell/media/dotlottie/{dotlottie_view.html,dotlottie_viewmodel.js}`;
  `GET /media/dotlottie` + `GET /media/dotlottie/stage` (fragment), lint clean.

### Steps

- [x] 11.1 Create `designs/appbox-studio/ui/views/app_shell/media/dotlottie/dotlottie_viewmodel.js`:
  ```js
  export const surfaceId = 'app.mediaDotlottie';

  const VIEW = 'ui/views/app_shell/media/dotlottie/dotlottie_view.html';

  export const page = (c, h) =>
    h.render(c, VIEW, { activeShell: 'app', playing: true });

  // Play/pause the hypermedia way: re-render the stage fragment with the
  // autoplay attribute flipped (named-fragment render, VIEW#stage).
  export const stage = (c, h) =>
    h.render(c, `${VIEW}#stage`, { playing: c.req.query('play') !== '0' });
  ```
- [x] 11.2 Create `designs/appbox-studio/ui/views/app_shell/media/dotlottie/dotlottie_view.html`:
  ```html
  {% extends "ui/views/main_shell/main_shell_view.html" %}
  {% block title %}{{ t('media.dotlottie.pageTitle') }}{% endblock %}
  {% block head_extra %}
  <script type="module" src="/assets/vendor/dotlottie_island.js"></script>
  <link rel="stylesheet" href="/assets/css/media.css">
  {% endblock %}
  {% macro stage(c) %}
  <dotlottie-wc src="/assets/media/dotlottie-demo.lottie" loop
    {% if c.playing %}autoplay{% endif %}
    class="media-viewer" aria-label="{{ t('media.dotlottie.title') }}"></dotlottie-wc>
  {% endmacro %}
  {% block surface %}
  <span class="eyebrow">{{ t('media.eyebrow') }}</span>
  <h1 class="display">{{ t('media.dotlottie.title') }}</h1>
  <p class="muted">{{ t('media.dotlottie.lede') }}</p>
  <section class="media-stage">
    <div id="dl-stage" class="media-frame">{{ stage(c) }}</div>
    <div class="media-controls">
      <button hx-get="/media/dotlottie/stage?play=1" hx-target="#dl-stage" hx-swap="innerHTML">{{ t('media.action.play') }}</button>
      <button hx-get="/media/dotlottie/stage?play=0" hx-target="#dl-stage" hx-swap="innerHTML" class="ghost">{{ t('media.action.pause') }}</button>
    </div>
  </section>
  {% endblock %}
  ```
- [x] 11.3 Check: lint clean; `curl -sf http://localhost:4399/media/dotlottie
  | grep -c 'dotlottie-wc'` ≥ 1; `curl -sf
  'http://localhost:4399/media/dotlottie/stage?play=0' | grep -c autoplay` =
  0 and with `play=1` = 1 (fragment round-trip works).

---

## Task 12: 3D model viewer screen

**Interfaces**
- Consumes: Task 3 `model-viewer.min.js`; Task 7 `boombox.glb`; Task 8.
- Produces:
  `ui/views/app_shell/media/model3d/{model3d_view.html,model3d_viewmodel.js}`;
  `GET /media/model3d` + `GET /media/model3d/stage`, lint clean.

### Steps

- [x] 12.1 Create `designs/appbox-studio/ui/views/app_shell/media/model3d/model3d_viewmodel.js`:
  ```js
  export const surfaceId = 'app.mediaModel3d';

  const VIEW = 'ui/views/app_shell/media/model3d/model3d_view.html';

  export const page = (c, h) =>
    h.render(c, VIEW, { activeShell: 'app', playing: true });

  // Auto-rotate toggle as a server round-trip: the stage fragment re-renders
  // with/without the auto-rotate attribute. Orbit is the component's own
  // camera-controls — declarative, no island.
  export const stage = (c, h) =>
    h.render(c, `${VIEW}#stage`, { playing: c.req.query('rotate') !== '0' });
  ```
- [x] 12.2 Create `designs/appbox-studio/ui/views/app_shell/media/model3d/model3d_view.html`:
  ```html
  {% extends "ui/views/main_shell/main_shell_view.html" %}
  {% block title %}{{ t('media.model3d.pageTitle') }}{% endblock %}
  {% block head_extra %}
  <script type="module" src="/assets/vendor/model-viewer.min.js"></script>
  <link rel="stylesheet" href="/assets/css/media.css">
  {% endblock %}
  {% macro stage(c) %}
  <model-viewer src="/assets/media/boombox.glb" camera-controls interaction-prompt="auto"
    shadow-intensity="1" {% if c.playing %}auto-rotate{% endif %}
    class="media-viewer" aria-label="{{ t('media.model3d.title') }}"></model-viewer>
  {% endmacro %}
  {% block surface %}
  <span class="eyebrow">{{ t('media.eyebrow') }}</span>
  <h1 class="display">{{ t('media.model3d.title') }}</h1>
  <p class="muted">{{ t('media.model3d.lede') }}</p>
  <section class="media-stage">
    <div id="mv-stage" class="media-frame">{{ stage(c) }}</div>
    <div class="media-controls">
      <button hx-get="/media/model3d/stage?rotate=1" hx-target="#mv-stage" hx-swap="innerHTML">{{ t('media.model3d.action.rotateOn') }}</button>
      <button hx-get="/media/model3d/stage?rotate=0" hx-target="#mv-stage" hx-swap="innerHTML" class="ghost">{{ t('media.model3d.action.rotateOff') }}</button>
    </div>
  </section>
  {% endblock %}
  ```
- [x] 12.3 Check: lint clean; page contains `model-viewer`;
  `curl -sf 'http://localhost:4399/media/model3d/stage?rotate=0' | grep -c auto-rotate` = 0, `rotate=1` = 1.

---

## Task 13: three.js scene screen

**Interfaces**
- Consumes: Task 4 `three_island.js` + three vendored builds; Task 8.
- Produces: `ui/views/app_shell/media/scene3d/{scene3d_view.html,scene3d_viewmodel.js}`;
  `GET /media/scene3d` renders, lint clean.

### Steps

- [x] 13.1 Create `designs/appbox-studio/ui/views/app_shell/media/scene3d/scene3d_viewmodel.js`:
  ```js
  export const surfaceId = 'app.mediaScene3d';

  const VIEW = 'ui/views/app_shell/media/scene3d/scene3d_view.html';

  export const page = (c, h) => h.render(c, VIEW, { activeShell: 'app' });
  ```
- [x] 13.2 Create `designs/appbox-studio/ui/views/app_shell/media/scene3d/scene3d_view.html`:
  ```html
  {% extends "ui/views/main_shell/main_shell_view.html" %}
  {% block title %}{{ t('media.scene3d.pageTitle') }}{% endblock %}
  {% block head_extra %}
  <script type="module" src="/assets/vendor/three_island.js"></script>
  <link rel="stylesheet" href="/assets/css/media.css">
  {% endblock %}
  {% block surface %}
  <span class="eyebrow">{{ t('media.eyebrow') }}</span>
  <h1 class="display">{{ t('media.scene3d.title') }}</h1>
  <p class="muted">{{ t('media.scene3d.lede') }}</p>
  <section class="media-stage media-three" data-three-scene="orbit-demo" data-three-auto-rotate="true">
    <div class="media-controls">
      <button type="button" data-three-toggle="rotate">{{ t('media.scene3d.action.rotate') }}</button>
      <button type="button" data-three-toggle="wireframe" class="ghost">{{ t('media.scene3d.action.wireframe') }}</button>
    </div>
  </section>
  {% endblock %}
  ```
- [x] 13.3 Check: lint clean; `curl -sf http://localhost:4399/media/scene3d
  | grep -c 'data-three-scene'` = 1. Rendering proof is the lens run (the
  island writes `data-three-frames` only in a real browser).

---

## Task 14: Game screen

**Interfaces**
- Consumes: Task 4 `game_island.js`; Task 7 Kenney tiles; Task 8.
- Produces: `ui/views/app_shell/media/game/{game_view.html,game_viewmodel.js}`;
  `GET /media/game` renders, lint clean.

### Steps

- [x] 14.1 Create `designs/appbox-studio/ui/views/app_shell/media/game/game_viewmodel.js`:
  ```js
  export const surfaceId = 'app.mediaGame';

  const VIEW = 'ui/views/app_shell/media/game/game_view.html';

  export const page = (c, h) => h.render(c, VIEW, { activeShell: 'app' });
  ```
- [x] 14.2 Create `designs/appbox-studio/ui/views/app_shell/media/game/game_view.html`:
  ```html
  {% extends "ui/views/main_shell/main_shell_view.html" %}
  {% block title %}{{ t('media.game.pageTitle') }}{% endblock %}
  {% block head_extra %}
  <script src="/assets/vendor/game_island.js" defer></script>
  <link rel="stylesheet" href="/assets/css/media.css">
  {% endblock %}
  {% block surface %}
  <span class="eyebrow">{{ t('media.eyebrow') }}</span>
  <h1 class="display">{{ t('media.game.title') }}</h1>
  <p class="muted">{{ t('media.game.lede') }}</p>
  <section class="media-stage" data-game="dungeon-dash" data-game-tiles="/assets/media/kenney">
    <canvas data-game-canvas class="media-game-canvas" width="352" height="352"></canvas>
    <div class="media-dpad">
      <button type="button" data-game-move="up" aria-label="{{ t('media.game.move.up') }}">{{ icon('arrow-up', {size: 18}) }}</button>
      <button type="button" data-game-move="left" aria-label="{{ t('media.game.move.left') }}">{{ icon('arrow-left', {size: 18}) }}</button>
      <button type="button" data-game-move="down" aria-label="{{ t('media.game.move.down') }}">{{ icon('arrow-down', {size: 18}) }}</button>
      <button type="button" data-game-move="right" aria-label="{{ t('media.game.move.right') }}">{{ icon('arrow-right', {size: 18}) }}</button>
    </div>
    <p class="muted">{{ t('media.game.hint') }}</p>
  </section>
  {% endblock %}
  ```
- [x] 14.3 Check: lint clean; `curl -sf http://localhost:4399/media/game |
  grep -c 'data-game-canvas'` = 1. Playability proof is the lens run.

---

## Task 15: Lens verification at the viewport ladder

The release bar for the whole plan. appbox lens only.

**Interfaces**
- Consumes: Tasks 1-14 (everything).
- Produces: 18 evidence PNGs in `designs/appbox-studio/evidence/media/`
  (6 screens × 3 rungs), each passing the per-screen bar below; a final
  green run of lint + serve.test + appboxd tests.

### Steps

- [x] 15.1 Boot the design (leave running for the whole task):
  ```sh
  cd /Volumes/developer_ssd/Developer/totem_labs/app-box
  node designs/appbox-studio/serve.mjs --port 4319 --no-watch &
  sleep 2
  ```
- [x] 15.2 Capture every screen at every rung. Run this matrix from
  `appboxd/` (heights pair with widths per the viewport ladder:
  390×844, 744×1133, 1280×832; settle 3500ms so WASM/GLB/rive load):
  ```sh
  cd /Volumes/developer_ssd/Developer/totem_labs/app-box/appboxd
  E=../designs/appbox-studio/evidence/media
  for W in 390 744 1280; do
    case $W in 390) H=844;; 744) H=1133;; 1280) H=832;; esac
    dart run tool/lens_check.dart "http://localhost:4319/media/rive"      "$E/rive-$W.png"      $W $H 3500 --selector='[data-rive-canvas]'   --expect="document.querySelector('[data-rive]').dataset.riveReady==='true'"
    dart run tool/lens_check.dart "http://localhost:4319/media/lottie"    "$E/lottie-$W.png"    $W $H 3500 --selector='lottie-player'      --expect="!!document.querySelector('lottie-player')"
    dart run tool/lens_check.dart "http://localhost:4319/media/dotlottie" "$E/dotlottie-$W.png" $W $H 3500 --selector='dotlottie-wc'       --expect="!!document.querySelector('dotlottie-wc')"
    dart run tool/lens_check.dart "http://localhost:4319/media/model3d"   "$E/model3d-$W.png"   $W $H 3500 --selector='model-viewer'       --expect="document.querySelector('model-viewer').loaded===true"
    dart run tool/lens_check.dart "http://localhost:4319/media/scene3d"   "$E/scene3d-$W.png"   $W $H 3500 --selector='[data-three-scene]' --expect="Number(document.querySelector('[data-three-scene]').dataset.threeFrames)>0"
    dart run tool/lens_check.dart "http://localhost:4319/media/game"      "$E/game-$W.png"      $W $H 3500 --selector='[data-game-canvas]' --press=ArrowRight --press=ArrowDown --expect="document.querySelector('[data-game]').dataset.gameReady==='true' && Number(document.querySelector('[data-game]').dataset.gameMoves)>=2"
  done
  ```
  Expected: 18 × `lens check ok: …`. Any `lens check FAILED` stops the task —
  fix the named cause (missing asset, island error, console error) and rerun
  that line.
- [x] 15.3 **Pass bar per screen** (state explicitly, verify every one):
  - **rive**: exit 0 AND `riveReady==='true'` AND (ReadMediaFile) the car is
    visibly rendered in the canvas — not a blank/poster frame.
  - **lottie**: exit 0 AND the Lottie logo animation visibly rendered, with
    the player controls bar present.
  - **dotlottie**: exit 0 AND the animation visibly rendered (not the blank
    stage) — proves the vendored WASM pin worked (a CDN-fetch failure would
    surface as console errors → auto-fail).
  - **model3d**: exit 0 AND `.loaded===true` AND the BoomBox model visibly
    rendered with shading (not the grey placeholder).
  - **scene3d**: exit 0 AND `threeFrames>0` AND three colored meshes visible.
  - **game**: exit 0 AND `gameMoves>=2` after two lens-dispatched key events
    (proves input driving end to end) AND tiles + hero visibly rendered.
  - **All screens**: zero console/page errors (the lens auto-fails on any);
    layout holds at all three rungs (no overflow, controls reachable at 390).
- [x] 15.4 Read the evidence back: open each of the 18 PNGs with
  ReadMediaFile and confirm the visual half of the bar in 15.3. Do not skip
  this — a green exit code with a blank canvas is a fail.
- [x] 15.5 Final green run + shutdown:
  ```sh
  cd /Volumes/developer_ssd/Developer/totem_labs/app-box
  node .kimi-code/skills/appbox-designer/runtime/lint.mjs designs/appbox-studio
  node .kimi-code/skills/appbox-designer/runtime/serve.test.mjs
  (cd appboxd && dart test)
  (cd appbox-studio && flutter test)
  kill %1
  ```
  Expected: lint clean; serve test all ok; all dart tests pass; all Flutter
  tests pass.

---

## Follow-up work (NOT this plan)

- **Kit layer** (deliberately out of scope here): kits `kit/animation`,
  `kit/scene3d`, `kit/games`; catalog ids `display.animation`,
  `display.scene3d`, `surface.game` in `config/catalogs/primitives-canonical.json`;
  `media-assets.json` catalog + CI budgets; Flutter tiers
  `model_viewer_plus` / `three_js` / `flutter_scene` (flagged) / Flame +
  `flame_3d` (flagged). This plan's islands and smoke screens are the design
  evidence those kits freeze against.
- **Frozen artifacts reworded to the appbox lens (2026-07-31):** `docs/design/brief.md`,
  `docs/design/story-map.json`, `docs/moodboards/*` predated the appbox lens
  doctrine; the probe-runner retirement sweep reworded them to name the
  appbox lens.
- **Historical plan/research docs** (`docs/plans/architecture.md`,
  `consolidate-one-app-plus-daemon.md`, `docs/research/*`) still say
  `appbox/` — records, deliberately not rewritten.
- **UI copy** still titles the product "appbox" (`l10n/app_*.arb`
  `dash.pageTitle`, `splash.pageTitle`) — a brand decision, separate from the
  directory/package rename.
- **`appbox lens` CLI verb**: `tool/lens_shot.dart` / `tool/lens_check.dart`
  are drivers until a proper `appbox lens` subcommand lands in
  `appboxd/bin/appbox.dart`.
