# appbox — System Map

One visual reference for the whole repo. Every node and edge traces to a file.
Canonical terms per `docs/VOCABULARY.md`. Verified against the code 2026-08;
`(planned)` marks wiring that is designed but not built.

## 1. System overview

The operator drives Kimi CLI skills; skills drive the `appbox` CLI and `appboxd`.
The design server renders the studio artifact (`designs/appbox-studio/`) plus a
live overlay of the current user project (`~/.appbox/projects/<name>/`). The
Flutter app (`appbox-studio/`) is the product shell — today it implements only
`startup`/`home`/`unknown`; the full surface set exists in the design artifact.

```mermaid
flowchart TD
    user["Operator / client"]

    subgraph skills["Kimi CLI skills — skills/"]
        sk_intake["appbox-intake / story-mapper / moodboarder"]
        sk_design["appbox-designer"]
        sk_build["appbox-scaffolder / appbox-builder / appbox-tester"]
        sk_gate["appbox-reviewer / appbox-lens / appbox-lint"]
        sk_deploy["appbox-deployer"]
    end

    subgraph daemon["appboxd — CLI + daemon (appboxd/)"]
        cli["appbox CLI (bin/appbox.dart): intake, emit, gate, crud, design, lens, deploy, kb, lint, docs, watermark"]
        fsm["Pipeline FSM (lib/pipeline_fsm.dart + phases.dart)"]
        gates["Gates (lib/gate_*.dart + gate_runner.dart)"]
        emitters["Emitters (emit_structure, scaffold, htmx, story-map, …)"]
        proj["Project model (lib/project.dart) — ~/.appbox resolver"]
        server["HTTP server (lib/server.dart) :8787 loopback"]
        gateway["LLM gateway (lib/gateway.dart) /llm/v1 → fabric + vault"]
        dserver["Design server (lib/design_server.dart + design_server/worker.dart) — artifact JS in headless-Chrome CDP tab"]
    end

    subgraph home["~/.appbox (APPBOX_HOME override)"]
        current["current — one-line active-project marker"]
        projects["projects/<name>/{intake,design,build,settings}"]
    end

    subgraph design["designs/appbox-studio/ — studio design artifact (in repo)"]
        shells["Shells: app / main (intake·design·build) / workspace — registry.json + flows.json + ui/views/** + app.routes.js"]
    end

    subgraph studio["appbox-studio/ — the Flutter app (Stacked MVVM)"]
        fviews["lib/ui/views: startup, home, unknown (+ security layer)"]
    end

    user --> skills --> cli
    cli --> fsm --> gates --> emitters
    cli --> proj
    proj --> current
    proj --> projects
    emitters -->|"intake emit / design seeds / build evidence"| projects
    dserver -->|"live-read: artifact + project overlay, hot reload"| design
    dserver -->|"live-read"| projects
    cli -->|"appbox design serve <dir|name>"| dserver
    emitters -->|"scaffold: structure.json + targets → lib/ui/views"| studio
    server -->|"static webRoot: appbox-studio/build/web"| studio
    cli -->|"fastlane / shorebird / cloudflare (lib/deploy.dart)"| stores["App stores / OTA / web"]
    gateway --> providers["LLM providers (config/model-fabric.json)"]
```

## 2. Pipeline stages and user-interaction checkpoints

FSM phase order (`lib/phases.dart`): intake → prototype → design → scaffold →
review → build → deploy, with per-phase gates (`phaseGates`). Human checkpoints
an agent can reach but never pass are marked ⧗; the studio design surfaces where
they happen are named under each.

```mermaid
flowchart LR
    subgraph p1["intake"]
        g1["gate: intake — registry ↔ answers/brief traceability"]
        c1["⧗ intake interview + item-engine confirm steps — /intake, /intake/{personas,surfaces,flows,direction}: confirm / save / skip / edit / accept-all"]
    end
    subgraph p2["prototype"]
        g2["gate: freeze — inputs + approval.lock + clean renders; writes designHash"]
        c2["⧗ design chat refine loop — /design/chat (context chips, checkpoints, revert)"]
        c3["⧗ HUMAN GATE 1: manifest approval — /design/freeze (freeze & trace, recheck) → freeze --approve mints approval.lock"]
    end
    subgraph p3["design"]
        g3["gate: structure — structure.json sync + designHash fresh"]
    end
    subgraph p4["scaffold"]
        g4["gates: scaffold S0–S10 + coverage C1–C5"]
    end
    subgraph p5["review"]
        g5["gates: review (arch_guard + ponytail + manifest hash) + memory"]
        c4["⧗ HUMAN GATE 2: review verdict — POST /api/review/approve|reject"]
    end
    subgraph p6["build"]
        g6["gates: native_deps + lens (design-vs-built goldens)"]
        c5["⧗ build gate decisions — POST /build/gates/decide (needs-you strip); stage controls /build/stages/:id/control"]
    end
    subgraph p7["deploy"]
        g7["gates: deploy (triple + licence, fail-closed) + advertise"]
        c6["⧗ HUMAN GATE 3: deploy --approval token — human-supplied, never minted by code (pay-at-deploy)"]
    end

    p1 --> p2 --> p3 --> p4 --> p5 --> p6 --> p7
    p5 -.->|"review REJECT rewinds FSM to design"| p3
    dash["⧗ dashboard project ops — /dashboard: createProject, projects/use (writes ~/.appbox/current), gates/decide"] -.-> p1
```

Also on the CLI outside the phase loop: gates `arch`, `gen-freshness`, `trace`,
`tier1`, `capability`, `api-map`; emitters `structure`, `htmx`, `playground`,
`synthesize`, `blueprint`, `story-map`, `scaffold`; `kb`, `lint`, `docs`,
`watermark`.

## 3. The ~/.appbox project model

User projects live outside the repo (`lib/project.dart`). The studio's own
design stays in `designs/appbox-studio/`; `~/.appbox` holds user projects only.
Stage is derived deterministically from which outputs exist — never stored.

```mermaid
flowchart TD
    home["appboxHome() = $APPBOX_HOME ?? ~/.appbox (test hook: appboxHomeOverride)"]
    cur["~/.appbox/current — one line, active project name (default 'portalo'; useProject() validates + writes)"]
    subgraph prj["~/.appbox/projects/<name>/ — name: lowercase alnum + dash"]
        intake["intake/ — answers.json, brief.md, registry.json, flows.json, story-map outputs"]
        dsgn["design/ — seeds, surfaces/**.html partials, l10n/app_*.arb; models/design_model/run.en.json marks build stage"]
        bld["build/ — evidence *.json (any json ⇒ stage 'gates')"]
        stngs["settings/project.json — {name, targets, locales}; no clock fields (byte-identical emit)"]
    end

    home --> cur
    home --> prj
    stage["projectStage(): intake → design (intake/registry.json) → build (design run.en.json) → gates (build/*.json)"]
    prj --> stage
    cards["projectCards() → {name, targets, stage, surfaces, flows} — feeds the dashboard grid via GET /__projects"]
    stage --> cards
    init["ensureProject(name) — idempotent; never clobbers project.json"] --> prj
```

## 4. Design server: live-read wiring (artifact + project overlay)

`appbox design serve <dir|name>` (`lib/design_cli.dart` →
`lib/design_server.dart`) runs the artifact's ES-module JS in a headless-Chrome
tab over CDP (`design_server/worker.dart`). Dart owns HTTP/sessions/timers; the
worker tab owns viewmodel dispatch + Nunjucks render. `_scanArtifact` prefetches
everything into sync in-memory maps; two file watchers hot-reload the worker.

```mermaid
flowchart TD
    subgraph repo["Repo artifact — designs/appbox-studio/"]
        a_tpl["ui/**.html templates + app.routes.js"]
        a_arb["l10n/app_*.arb"]
        a_fix["models/**.json fixtures (registry, flows, intake seeds)"]
    end
    subgraph overlay["Project overlay — ~/.appbox/projects/<current>/"]
        p_surf["design/surfaces/**.html → templates ui/project/<sub> (screen partials)"]
        p_arb["design/l10n/app_*.arb → merged OVER artifact arb (project wins)"]
        p_json["**.json anywhere → fixtures at /project/<rel> (intake registry+flows, design seeds, build evidence)"]
    end
    scan["_scanArtifact(artifactDir, origin, projectDir:) — one _Prefetch {templates, fixtures, arb, icons}"]
    worker["JsWorker — headless Chrome tab: __templates/__fixtures/__arb/__icons injected, __boot(origin), __dispatch per request"]
    watch1["artifact watcher → worker.reload() (cache-busted re-import; sessions/timers ride out reload in Dart state)"]
    watch2["project watcher → worker.reload() — editing a partial or fixture reloads too"]
    write["POST /__project_write {path, body} — writes ONE file inside the project dir (path-escape rejected); watcher reloads"]
    list["GET /__projects → projectCards() + current"]
    use["POST /__project_use {name} → useProject() writes ~/.appbox/current"]

    repo --> scan
    overlay --> scan
    scan --> worker
    repo -.-> watch1 -.-> worker
    overlay -.-> watch2 -.-> worker
    write --> overlay
    use --> cur2["~/.appbox/current"] -.-> overlay
    list --> cards2["dashboard grid"]
```

## 5. Design viewer: three lenses, one SSOT

`ui/common/design_viewer.html` is the shared screen stage. All three lenses
render from the same source of truth — `registry.json` (screens) + `flows.json`
(flow edges) of the current project, live-read through the overlay. Mode
`v.mode`: `views` (default) | `flows` | `proto`.

```mermaid
flowchart TD
    ssot["SSOT: project intake/registry.json + intake/flows.json (fixtures at /project/intake/*.json)"]
    views["VIEWS lens — every screen as a flat wrapping grid; add-to-flow menu per tile"]
    flows["FLOWS lens — one dashed row per flow, tiles in edge-chain order; move ←/→ + remove per tile"]
    proto["PROTO lens — the wired app: one live screen in device chrome, edges are clickable nav"]
    edits["Flow edits: POST /design/flows/:flow/{move,add,remove}/:screen (prototype_viewmodel.js)"]
    facade["facade → fixture_reader.js → POST /__project_write"]
    back["flows.json written back; project watcher hot-reloads; whole stage (#panels) re-renders"]

    ssot --> views
    ssot --> flows
    ssot --> proto
    views --> edits
    flows --> edits
    edits --> facade --> back --> ssot
```

## 6. Intake chain and studio boot chain

Intake (`lib/intake.dart`, `lib/intake_cli.dart`): answers carry per-field
provenance (`client | founder | inferred`); `inferred` fields are visibly marked
in the brief (`> **[inferred]**`) and derived flows get `provenance: inferred`
so the confirm step has something to confirm. The studio app shell
(`ui/views/app_shell/`, `routes.app.js`) is the boot chain; root lands on the
dashboard, whose project grid is live from `~/.appbox`.

```mermaid
sequenceDiagram
    autonumber
    participant H as Human
    participant S as Studio (design server)
    participant C as appbox CLI
    participant P as ~/.appbox/projects/<name>/intake/

    H->>S: /intake interview (answer / skip / depth)
    S->>C: appbox intake emit --answers a.json --project <name>
    C->>C: validate {value, provenance} per field; deriveComp/deriveRoute (mechanical naming only)
    C->>P: write answers.json + brief.md + registry.json + flows.json (undeclared flows derived as inferred)
    C->>C: appbox emit story-map — unified brief (renderBriefSections answers path) → story-map.json
    H->>S: item-engine steps personas/surfaces/flows/direction: confirm / save / skip / edit / accept-all
    H->>C: appbox intake flows confirm --project <name> --flow <id> --as founder|client (derive + confirm)
    C->>P: flip flow provenance in flows.json
    Note over H,S: boot chain: / →303 /dashboard; /splash auto-advances → /startup → /auth (POST /auth/signin) → /dashboard
    S->>S: /dashboard grid ← GET /__projects (projectCards); use → POST /__project_use; new → POST /dashboard/projects creates REAL project, lands on /intake
```

## 7. Glossary (as used in the diagrams)

- **Authored layer** — `registry.json` + `flows.json` + `ui/views/**` +
  `app.routes.js`; written by intake emit and the design surfaces.
  **Generated**: `structure.json`, `appbox-studio/lib/**` — emitters only.
- **Gate** — isolated assertion unit; exits pass / fail / not-applicable (exit
  2); never calls a sibling gate. **Human Gate** — prototype approval, review
  verdict, deploy approval token: an agent can reach, never pass.
- **Freeze / designHash** — freeze PASS records sha256 of the design tree;
  structure/scaffold/coverage re-assert freshness. `approval.lock` is minted
  only by `freeze --approve`.
- **Provenance** — `client | founder | inferred` on every intake field and
  flow; `inferred` = not elicited, must be confirmed (`intake flows confirm`).
- **Project overlay** — the design server's live read of the current
  `~/.appbox` project merged over the repo artifact (§4); project l10n wins,
  project JSON serves at `/project/<rel>`.
- **Targets** — platform set in `settings/project.json` /
  `config/appbox.config.json`; derives viewport rungs (390/744/1280) and
  scaffold file counts.
- **Pay-at-Deploy** — licence (Ed25519, offline-verified) hard-blocks first
  deploy; everything before is free; `APPBOX_DEV_LICENCE=1` dev bypass.
- **Stub** — unimplemented provider that throws by design; never offered
  (fugu fabric provider — optional catalog entry, no endpoint yet). The
  vercel deploy target was one until 2026-08-01, when `261b2ad` made it real
  (live smoke tests in `93cf1ef`).
