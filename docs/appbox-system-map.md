# appbox — System Map

One visual reference for the whole repo. Every node and edge traces to a file;
`(planned)` marks wiring that is designed but not built. Canonical terms per
`docs/VOCABULARY.md`; build order per `docs/plans/architecture.md` §21.

## 1. System overview

The operator drives Kimi CLI skills; the skills drive the `appbox` CLI and the
`appboxd` daemon; the daemon owns the pipeline FSM, gates, emitters, memory,
vault/licence, and the loopback LLM gateway that fronts all provider traffic.

```mermaid
flowchart TD
    user["Operator (Evan) / Buyer (Michelle)"]

    subgraph skills["Kimi CLI skills — skills/ (11)"]
        sk_intake["appbox-intake / appbox-story-mapper / appbox-moodboarder"]
        sk_design["appbox-designer"]
        sk_build["appbox-scaffolder / appbox-builder / appbox-tester"]
        sk_gate["appbox-reviewer / appbox-lens / appbox-lint"]
        sk_deploy["appbox-deployer"]
    end

    subgraph daemon["appboxd — the daemon (appboxd/)"]
        cli["appbox CLI (bin/appbox.dart): gate, crud, serve, lens, design, deploy, intake, emit, lint, docs, kb, watermark"]
        engine["Engine (lib/engine.dart): headless stage runner — spawns kimi -p via temp KIMI_CODE_HOME"]
        fsm["Pipeline FSM (lib/pipeline_fsm.dart + lib/phases.dart)"]
        gates["Gates (lib/gate_*.dart + gate_runner.dart; review at gates/review/review.dart)"]
        emitters["Emitters (emit_structure, scaffold, htmx, synthesize, blueprint, emit_stage, …)"]
        server["HTTP server (lib/server.dart) :8787 loopback — /api/* + static webRoot"]
        gateway["LLM gateway (lib/gateway.dart) /llm/v1 — TokenMinter, tier routing, usage ledger"]
        fabric["Model fabric (lib/fabric.dart + config/model-fabric.json)"]
        memory["Memory (lib/memory*.dart): event log, response cache, curator"]
        vault["Vault + SecureStore + Credentials (lib/vault.dart, secure_store.dart, credentials.dart)"]
        licence["Licence + watermark (lib/licence.dart, watermark.dart) — Ed25519, offline"]
    end

    subgraph design["Design surface — designs/appbox-studio/"]
        artifact["htmx artifact: registry.json, app.routes.js, ui/views/**, structure.json"]
        dserver["Design server (lib/design_server.dart) — artifact JS in headless-Chrome CDP worker"]
    end

    subgraph studio["appbox-studio/ — the one Flutter app (Stacked MVVM)"]
        shells["Build shells: web / macos / ios / android"]
        sec["lib/security/: pairing, channel, pipeline control, prototype"]
    end

    subgraph kit["kit/ — 25 vendored packages"]
        kit_groups["core plumbing / device + hardware / platform services / genui_bridge / showcase_app"]
    end

    subgraph external["External"]
        llm["LLM providers: kimi, zai, anthropic, openai, deepseek, gemini, xai, fugu (optional)"]
        stores["App stores / OTA / web: fastlane, shorebird, Cloudflare Pages — vercel (planned, stub)"]
        osvault["OS vault: macOS Keychain — Windows/Linux (planned)"]
    end

    user --> skills
    skills --> cli
    cli --> fsm
    cli --> gates
    cli --> emitters
    cli --> server
    server --> fsm
    server --> gateway
    engine -->|"stage run: kimi CLI pointed at 127.0.0.1/llm with stage-scoped token"| gateway
    fsm --> gates
    gates --> emitters
    gateway --> fabric
    gateway -->|"provider keys by key_ref"| vault
    gateway -->|"https"| llm
    emitters --> artifact
    dserver --> artifact
    emitters -->|"scaffold: structure.json + targets → lib/ui/views tree"| studio
    studio -->|"kit packages (dependencyMode: vendored)"| kit
    sec -->|"heartbeat + pipeline control over loopback/tailnet"| server
    server -->|"static webRoot: appbox-studio/build/web"| shells
    licence --> vault
    vault --> osvault
    sk_deploy -->|"fastlane / shorebird / cloudflare CLIs (lib/deploy.dart)"| stores
    engine --> memory
    gateway --> memory
    gates --> memory
```

## 2. Pipeline stages, gates, and skills

Phase order from `lib/phases.dart` / `lib/pipeline_fsm.dart`
(intake → prototype → design → scaffold → review → build → deploy); gates per
phase from `phaseGates`; the standalone gate suite order (`gateOrder` in
`lib/gate_runner.dart`) is intake, freeze, structure, scaffold, coverage,
memory, advertise, review, native_deps, lens, deploy.

```mermaid
flowchart LR
    subgraph p1["phase: intake"]
        g_intake["gate: intake — traceability: registry ↔ answers/brief, no orphans"]
    end
    subgraph p2["phase: prototype"]
        g_freeze["gate: freeze — inputs + approval.lock + render clean at derived viewports; writes designHash"]
    end
    subgraph p3["phase: design"]
        g_structure["gate: structure — structure.json sync with authored layer + designHash fresh"]
    end
    subgraph p4["phase: scaffold"]
        g_scaffold["gate: scaffold — shell-structure contract S0–S10"]
        g_coverage["gate: coverage — every frozen surface carries target-derived file set C1–C5"]
    end
    subgraph p5["phase: review"]
        g_review["gate: review — arch_guard + ponytail-review + manifest hash (gates/review/review.dart)"]
        g_memory["gate: memory — MEMORY.md ≤100 lines, facts parse, lessons ≤200 lines"]
    end
    subgraph p6["phase: build"]
        g_native["gate: native_deps — SwiftPM packaging for Apple targets"]
        g_lens["gate: lens — design-vs-built golden compare (byte/pixel/ssim)"]
    end
    subgraph p7["phase: deploy"]
        g_deploy["gate: deploy — target/version/account triple + §17 licence, fail-closed"]
        g_advertise["gate: advertise — no offer above evidence-tier (kit-registry.json vs evidence.json)"]
    end

    p1 --> p2 --> p3 --> p4 --> p5 --> p6 --> p7
    p5 -.->|"review REJECT rewinds FSM to design"| p3

    sk_i["skills: appbox-intake, appbox-story-mapper, appbox-moodboarder"] -.-> p1
    sk_d["skills: appbox-designer, appbox-lens"] -.-> p2
    sk_s["skill: appbox-scaffolder (appbox emit scaffold)"] -.-> p4
    sk_r["skill: appbox-reviewer"] -.-> p5
    sk_b["skills: appbox-builder, appbox-tester, appbox-lens"] -.-> p6
    sk_x["skill: appbox-deployer (appbox deploy)"] -.-> p7

    hg1["HUMAN GATE 1: prototype approval (approvePrototype)"] -.-> p2
    hg2["HUMAN GATE 2: review verdict (reviewVerdict)"] -.-> p5
    hg3["HUMAN GATE 3: deploy approval token + licence (pay-at-deploy)"] -.-> p7
```

Also on the CLI but outside the phase loop: `arch`, `gen-freshness`, `trace`,
`tier1`, `capability`, `api-map` gates (target-driven, bypass repo-root
discovery); emitters `structure`, `htmx`, `playground`, `transform_tokens`,
`synthesize`, `blueprint`, `emit_stage`, `generate_view`, `theme-map`,
`palette`, `story-map`, `scaffold`; `kb` (facts/build/check/lock/playbook/
conventions), `lint`, `docs`, `watermark`.

## 3. User-interaction checkpoints — a full run

Every point a human must act. Gates an agent can reach but never pass are
marked HUMAN GATE; the FSM enforces them via `humanApproved` / `approvalTokens`
/ review state in `pipeline/state/default.state.json`.

```mermaid
sequenceDiagram
    autonumber
    participant H as Human (operator / client)
    participant S as Kimi CLI + skills
    participant C as appbox CLI
    participant D as appboxd (server + FSM + engine)
    participant G as Gates
    participant L as LLM gateway → providers

    H->>S: intake a project (answers elicitation questions)
    S->>C: appbox intake emit --answers …
    C->>C: write docs/design/brief.md + registry seed (pure function of answers)
    C->>G: gate intake (traceability answers/brief ↔ registry)
    S->>S: story-mapper / moodboarder (optional pre-design)
    S->>C: appbox design serve (design_server over CDP worker)
    H->>S: reviews rendered prototype in browser; requests changes
    loop design iteration
        S->>C: CRUD on authored layer (appbox crud …)
        Note over C: delete and verify --fix REQUIRE --confirm (§18)
        C->>G: gate freeze (render every surface at derived viewports)
    end
    H->>C: freeze --approve (HUMAN GATE 1: mints design/approval.lock)
    C->>D: POST /api/prototype/approve (or FSM approvePrototype)
    D->>D: record designHash + humanApproved.prototype in default.state.json
    D->>D: advance guard: prototype gate passed AND humanApproved
    S->>C: emit structure → structure.json; gate structure (designHash fresh)
    S->>C: emit scaffold → lib/ui/views tree per targets
    C->>G: gates scaffold + coverage
    S->>S: appbox-builder fills view/VM bodies; appbox-tester TDD
    D->>L: engine stage runs: kimi -p with stage-scoped token, tier from fabric
    L-->>D: response + usage.jsonl + llm_request event
    S->>C: gate review + gate memory
    H->>D: POST /api/review/approve|reject (HUMAN GATE 2)
    alt reject
        D->>D: FSM rewinds to design phase, rejections + 1
    else approve
        D->>D: review.approved = true; isDone when not dirty
    end
    S->>C: gates native_deps + lens (design-vs-built vs goldens)
    H->>C: licence present? (pay-at-deploy — everything before is free)
    C->>G: gate deploy: licence assertion FIRST (fail-closed; APPBOX_DEV_LICENCE=1 dev bypass)
    H->>C: appbox deploy deploy --target T --version V --account A --approval <tok> (HUMAN GATE 3)
    C->>C: deploy mechanics (fastlane/shorebird/cloudflare); append deploy-ledger.json
    Note over C: deploy.dart never mints the approval token — the human supplies it
```

## 4. Data and state wiring

Who writes, who reads. Runtime state lives in `pipeline/state/` (gitignored);
curated memory in `memory/`; catalogs in `config/`.

```mermaid
flowchart TD
    subgraph state["pipeline/state/"]
        st_state["default.state.json — FSM: phase, phaseStatus, humanApproved, approvalTokens, designHash, review, dirty (schema 4)"]
        st_runs["runs/<run_id>.json — per-stage RunManifest"]
        st_runsjsonl["runs.jsonl — FSM audit trail"]
        st_score["scorecard.jsonl — per stage run (stage, tier, tokens, gate_pass, cache_hit)"]
        st_usage["usage.jsonl — per gateway call (consumer, tier, provider, model, tokens)"]
        st_events["memory/events.jsonl — raw MemoryEvent log (rotates ~50MB)"]
        st_cache["memory/cache/*.json — exact-match LLM response cache (FNV key, 24h TTL, 500 cap)"]
        st_intake["default.intake.json — intake answers"]
        st_targets["targets.derivation.json — targets → viewports/form-factors/ceremonies"]
        st_ledger["deploy-ledger.json — every deploy attempt, incl. halted"]
    end

    subgraph mem["memory/ (curated)"]
        mem_index["MEMORY.md — index, ≤100 lines"]
        mem_facts["facts/*.json — durable {fact, source, ts}"]
        mem_lessons["stages/<stage>.LESSONS.md — ≤200 lines, written ONLY on observed gate failure"]
    end

    subgraph cfg["config/"]
        cfg_app["appbox.config.json — targets, viewports 390/744/1280, escalationLimit, dependencyMode"]
        cfg_fabric["model-fabric.json — providers, tiers frontier/standard/fast, stage tiers, escalation rule"]
        cfg_evid["evidence.json — advertise evidence ledger (suite-written only)"]
        cfg_reg["kit-registry.json — kit capabilities, phase, verification tier"]
        cfg_rules["forbidden_abs_prefixes.txt / stripped_names.txt — lint rules"]
    end

    subgraph design2["designs/appbox-studio/ (authored layer)"]
        d_reg["models/screens_model/registry.json + migrations.json"]
        d_views["ui/views/** + app.routes.js"]
        d_struct["structure.json (GENERATED by emit_structure)"]
        d_lock["approval.lock (minted by freeze --approve)"]
        d_brief["docs/design/brief.md + story-map.json"]
    end

    fsm2["pipeline_fsm.dart"] -->|writes| st_state
    fsm2 -->|appends| st_runsjsonl
    srv2["server.dart /api/pipeline/*"] -->|reads/writes via FSM| st_state
    eng2["engine.dart runStage"] -->|writes| st_runs
    eng2 -->|appends| st_score
    eng2 -->|stage_run events| st_events
    eng2 -->|reads/writes| st_cache
    eng2 -->|on gate fail ONLY| mem_lessons
    gw2["gateway.dart"] -->|appends| st_usage
    gw2 -->|llm_request events| st_events
    gw2 -->|reads| cfg_fabric
    eng2 -->|stage tiers| cfg_fabric
    analytics["memory_analytics.dart (read-only) → /api/memory/briefing"] -->|reads| st_score
    analytics -->|reads| st_usage
    analytics -->|reads| st_events
    curator["memory_curate.dart (sole lesson writer)"] --> mem_lessons
    kbfacts["appbox kb facts (kit_facts.dart)"] -->|writes| mem_facts
    g_mem2["gate memory"] -->|asserts| mem_index
    g_mem2 -->|asserts| mem_facts
    g_mem2 -->|asserts| mem_lessons
    intake2["intake.dart emit/seed"] -->|writes| st_intake
    intake2 -->|writes| d_brief
    intake2 -->|seeds| d_reg
    crud2["crud.dart (the one authored-layer write path)"] -->|writes| d_reg
    crud2 -->|writes| d_views
    emit2["emit_structure.dart"] -->|reads| d_reg
    emit2 -->|reads| d_views
    emit2 -->|writes| d_struct
    freeze2["gate freeze"] -->|writes on PASS| st_state
    freeze2 -->|--approve mints| d_lock
    freeze2 -->|viewport widths| cfg_app
    freeze2 -->|derived widths| st_targets
    g_struct2["gates structure/scaffold/coverage"] -->|assert designHash fresh| st_state
    g_struct2 -->|read| d_struct
    scaf2["scaffold.dart emit"] -->|reads structure.json + targets| d_struct
    scaf2 -->|writes lib/ui/views tree| studio2["appbox-studio/lib/"]
    g_adv["gate advertise"] -->|reads| cfg_evid
    g_adv -->|reads| cfg_reg
    deploy2["deploy.dart"] -->|appends| st_ledger
    g_dep["gate deploy"] -->|asserts triple + licence| st_state
    lint2["appbox lint"] -->|reads| cfg_rules
    allgates["all gates"] -->|targets/viewports, never literals| cfg_app
    studio2 -.->|"MEM-B.md travels with the app (planned — architecture §4, not built)"| mem
```

## 5. appbox-studio wiring

One Flutter app (Stacked MVVM, `app.router/locator/dialogs/bottomsheets`),
four build shells. The security layer pairs devices and remote-controls the
pipeline; l10n ships en + pl. The full five-shell surface set exists only in
the design artifact so far — the Flutter app today implements `home`,
`startup`, `unknown` views plus the security widgets.

```mermaid
flowchart TD
    subgraph app["appbox-studio (lib/)"]
        main["main.dart — locator, KitI18n, url strategy"]
        views["ui/views: home (4 files: view + desktop/mobile/tablet + vm), startup, unknown"]
        widgets["security/widgets: channel_fab, companion_home_view, prototype_view (WebView)"]
        subgraph seclayer["lib/security/"]
            pairing["pairing: qr_payload, pairing_session, fingerprint, cert_pin — one-scan QR, revocable devices"]
            channel["channel: prototype_channel_service — heartbeat → live/reconnecting/dead; channel_state"]
            pipe["pipeline: pipeline_control (run phase, SARIF findings, approveGate — paired-device id REQUIRED), gate_status_feed"]
            proto["prototype: prototype_session, last_render_store"]
            cfg2["config: companion_config"]
        end
    end

    subgraph daemon3["appboxd"]
        srv3["server.dart :8787 — /api/phases/*/run, /api/pipeline/*, /api/prototype/approve, /api/review/*, static appbox-studio/build/web"]
        dsrv3["design_server.dart — serves the design artifact (prototype URL)"]
        gw3["gateway /llm — genui runtime consumer token (E2)"]
    end

    views --> widgets
    widgets --> channel
    widgets --> pipe
    channel -->|"HTTP heartbeat to prototype URL"| dsrv3
    pipe -->|"phase run / findings / approvals"| srv3
    pairing -.->|"approval honored ONLY if device id ∈ pairedDevices; revoke drops it"| pipe
    app -.->|"genui_bridge A2UI chat surface via scoped gateway token (planned — kit exists, no pubspec dependency yet)"| gw3
    srv3 -->|"serves the built web shell"| app
    note["Planned: full shell set from structure.json (intake/design/build/app/workspace) as Flutter views; genui_bridge wiring; MEM-B.md; approval binding to tailnet node identity (VOCABULARY: Daemon)"]
```

## 6. Glossary (as used in the diagrams)

Phases (FSM order, `lib/phases.dart`):

- **intake** — elicitation only; emits brief + registry seed, never design or
  code (`lib/intake.dart`). Gate: intake (traceability).
- **prototype** — the htmx design artifact is built and frozen. Gate: freeze
  (inputs, `approval.lock`, clean renders at derived viewports; records
  `designHash`).
- **design** — structure derivation. Gate: structure (`structure.json` in sync
  with the authored layer, hash-fresh).
- **scaffold** — per-surface Flutter file emission; form factors follow
  targets. Gates: scaffold (shell contract S0–S10), coverage (C1–C5).
- **review** — QC. Gates: review (arch_guard + ponytail-review + manifest
  hash), memory (curated-memory caps).
- **build** — fill + verify. Gates: native_deps (SwiftPM packaging), lens
  (design-vs-built goldens, byte/pixel/ssim; console errors auto-fail).
- **deploy** — ship. Gates: deploy (target/version/account triple + §17
  licence, fail-closed), advertise (no offer above evidence tier).

Terms:

- **Gate** — isolated self-tested assertion unit; exits pass / fail /
  not-applicable (exit 2, `envExit`); never calls a sibling gate.
- **Human Gate** — one of three approvals an agent can reach but never pass:
  prototype approval (`approvePrototype`), review verdict (`reviewVerdict`),
  deploy approval token (`deploy --approval`, never minted by code).
- **Freeze / designHash** — hash-locked approval: PASS records sha256 of the
  design tree into `state.designHash`; structure/scaffold/coverage re-assert
  freshness (§6).
- **Authored layer** — `registry.json` + `ui/views/**` + `app.routes.js`;
  written only by intake seed and `crud`. **Generated**: `structure.json`,
  `lib/**` — written only by emitters.
- **Targets** — platform set in `config/appbox.config.json`; derives viewport
  rungs (390/744/1280), scaffold file counts, ceremonies via
  `targets.derivation.json`.
- **Golden** — frozen capture the lens gate compares the built app against;
  recapture only via the approval-pattern path.
- **Model fabric** — `config/model-fabric.json`: providers (key_ref → vault),
  tiers (frontier/standard/fast), stage→tier pins, escalation (gate fail → one
  tier up, bounded once, never silent downgrade).
- **Scoped token** — in-memory per-consumer gateway token (`abx_…`) listing
  the tiers it may request; dies with the daemon (persistence/revocation:
  planned).
- **Scorecard / usage ledger** — `pipeline/state/scorecard.jsonl` (per stage
  run) and `usage.jsonl` (per gateway call); tokens null when unknown, never
  fabricated; cost null until fabric pricing wiring lands.
- **Memory (M1)** — deterministic writers append raw events
  (`memory/events.jsonl`); curated lessons promoted only on observed gate
  failure; caps enforced by the memory gate. **MEM-B** (`output/MEM-B.md`
  travelling with the app): planned, not built.
- **Pay-at-Deploy** — licence (Ed25519, offline-verified, annual/perpetual,
  30-day grace) hard-blocks first deploy; everything before is free;
  `APPBOX_DEV_LICENCE=1` is the documented dev bypass.
- **Stub** — unimplemented provider that throws by design; never offered
  (vercel deploy target; fugu fabric provider with `base_url: null`).
