# Flows

Diagrams only. Narrative lives in [journeys.md](journeys.md); the surface
inventory in [brief.md](brief.md).

## The pipeline, with its three human gates

```mermaid
flowchart TD
  I[Intake<br/><i>optional</i>] --> P[Prototype<br/>app-box-designer]
  P --> G1{{Gate 1 — approve direction}}
  G1 -->|iterate| P
  G1 -->|approved| F[Freeze<br/>6 inputs + render + structure]
  F --> S[Scaffold<br/>app-box-scaffolder]
  S --> R[Review<br/>app-box-reviewer]
  R -->|red| RC[Recovery]
  RC --> S
  R -->|green| G2{{Gate 2 — accept build}}
  G2 --> B[Bundle<br/>app-box-builder 💳]
  B --> D[Deploy<br/>app-box-deployer]
  D --> G3{{Gate 3 — target + version + account}}
  G3 --> OUT((released))

  classDef gate fill:#D2522B,stroke:#B8431F,color:#fff
  classDef pay fill:#C68D2E,stroke:#A46A21,color:#fff
  class G1,G2,G3 gate
  class B pay
```

💳 = the licence precondition. It runs **before** the phase and fails with a
licence message — never as a gate going red (§17).

## Where a feature's truth lives

```mermaid
flowchart LR
  subgraph authored [authored — humans write these]
    REG[registry.json]
    TREE["ui/views/**<br/>_view.html + _viewmodel.js"]
  end
  subgraph generated [generated — never hand-edited]
    ST[structure.json]
    SUR[surfaces/*.html]
    DART["lib/ui/views/**<br/>5 or 3 Dart files"]
  end
  REG --> ST
  TREE --> ST
  TREE --> SUR
  ST --> DART
  SUR --> DART
  ST -.->|regenerate + porcelain diff| DRIFT{{drift gate}}

  classDef gen fill:#EAE3D6,stroke:#D8CFBE,color:#1A1714
  class ST,SUR,DART gen
```

Every CRUD operation writes to the **authored** box only. The drift gate exists
because `structure.json` is a pure function of the authored side — see
[feature-crud.md](../plans/feature-crud.md).

## Targets derive viewports and ceremonies

```mermaid
flowchart LR
  T["--targets"] --> IOS[ios]
  T --> AND[android]
  T --> WEB[web / pwa]
  T --> DESK[macos / linux / windows]

  IOS --> VM[mobile]
  IOS --> VT[tablet]
  AND --> VM
  AND --> VT
  WEB --> VM
  WEB --> VT
  WEB --> VD[desktop]
  DESK --> VD

  VM --> W1["freeze @ 390"]
  VT --> W2["freeze @ 744"]
  VD --> W3["freeze @ 1280"]

  IOS --> C1["NSLocalNetworkUsageDescription<br/>NSBonjourServices"]
  DESK --> C2["Keychain Sharing<br/>Debug + Release entitlements"]
  WEB --> C3["manifest.json<br/>service worker"]
```

Viewport set is the **union**; mobile is always present. Freeze widths sit
*inside* each MD3 window size class, never on the 600/840 boundaries.

## The three test tiers

```mermaid
flowchart LR
  T1[Tier 1<br/>port + scripted fake] -->|no toolchain, runs in CI| T2[Tier 2<br/>simulator / emulator]
  T2 -->|UI + wiring only| T3[Tier 3<br/>physical device]
  T3 -->|entitlements, certs, real tokens| OK((wired))

  classDef ok fill:#4A7C3A,stroke:#0B4F30,color:#fff
  class OK ok
```

A provider may only be **advertised at the tier it has passed**. See
[stub-remediation.md](../plans/stub-remediation.md).
