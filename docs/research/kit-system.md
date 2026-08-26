# Kit system and runtime/artifact contract

Scope note: the original task brief referenced paths (`runtime/README.md`,
`runtime/vendor/`, `examples/hello-hda/`, `.claude/skills/arxa-designer/…`)
that do not exist in this worktree. The actual paths in this checkout are
`kit/`, `skills/arxa-designer/`, and there is no `runtime/` top-level dir or
`examples/` dir — design-time vendor JS lives under a `runtime/vendor/`
*reference path named in docs* (see `skills/arxa-designer/references/kit-catalog.md`,
"Visual islands" section) but that tree is not present on disk in this
worktree; it may live in the designer skill's own asset tree elsewhere. All
paths below are what actually exists here and were read directly.

## 1. What a kit is

A kit is a Flutter package under `kit/<dir>/` that a built app wires in at
build time. The single source of truth for what kits exist is
`config/kit-registry.json` (`version: 1`, 24 entries). Per
`skills/arxa-designer/references/kit-catalog.md` ("What the kit is"
section): *"If a capability is not in the registry, it does not exist — do
not design around an imagined module."*

`kit/` on disk has 25 subdirectories (confirmed via `ls kit/`): the 24
registered kits plus `genui_bridge`, which is **not** in the registry — it is
the generative-UI `ChatStream` bridge infrastructure, not a declarable
capability kit. `showcase_app` (`topology: app-integration`, `phase: n/a`) *is*
one of the 24 registered entries — a demo/integration app, not a
device-capability kit — and is explicitly excluded from the package-copy list
in `tools/phase5_kit_copy.sh` ("Packages to copy (all library packages,
excluding showcase_app)").

## 2. Full kit inventory (`config/kit-registry.json`, 24 entries)

Each entry carries: `dir` (declaration name), `package` (Dart package),
`capabilities`, `backing`, `topology`, `phase`, `playbook`, `hasSkill`,
`provides` (widgets/services the kit exports), and optionally `providers[]`
(each with a `verification` tier: `stub` → `port-tested` → `device-verified`).
Only 3 of the 24 kits have a `providers` seam at all (auth, payments, maps,
deploy — 4, see below); the rest are plain modules with no provider tier to
report.

| dir | package | topology | phase | providers (tier) |
|---|---|---|---|---|
| `core` | `arxa_kit_core` | core | stable | — |
| `ui_library` | `ui_library` | ui-tier | stable | — |
| `state` | `arxa_kit_state` | standalone | stable | — |
| `data` | `arxa_kit_data` | core-coupled | stable | — |
| `auth` | `arxa_kit_auth` | standalone | stable | SeedAuthBackend: port-tested; Apple SignIn: port-tested; Google SignIn: port-tested |
| `forms` | `arxa_kit_forms` | standalone | stable | — |
| `permissions` | `arxa_kit_permissions` | standalone | native-first | — |
| `media` | `arxa_kit_media` | standalone | native-first | — |
| `documents` | `arxa_kit_documents` | standalone | native-first-partial | — |
| `notifications` | `arxa_kit_notifications` | standalone | native-first-partial | — |
| `analytics` | `arxa_kit_analytics` | standalone | stable | — |
| `payments` | `arxa_kit_payments` | standalone | native-first | Stripe: port-tested; PayPal: port-tested; Apple Pay: stub |
| `maps` | `arxa_kit_maps` | standalone | native-first-partial | OpenStreetMap: port-tested; Mapbox: port-tested |
| `deploy` | `arxa_kit_deploy` | standalone | stable | Vercel: port-tested; Cloudflare Pages: port-tested; Cloudflare Workers: port-tested; fastlane: port-tested; Shorebird: port-tested |
| `haptics` | `arxa_kit_haptics` | standalone | stable | — |
| `bluetooth` | `arxa_kit_bluetooth` | standalone | native-first-partial | — |
| `wifi` | `arxa_kit_wifi` | standalone | stable | — |
| `support` | `arxa_kit_support` | standalone | stable | — |
| `security` | `arxa_kit_security` | standalone | native-first-partial | — |
| `compliance` | `arxa_kit_compliance` | standalone | stable | — |
| `branding` | `branding` | standalone | stable | — |
| `motion` | `arxa_kit_motion` | standalone | stable | — |
| `i18n` | `arxa_kit_i18n` | standalone | stable | — |
| `showcase_app` | `arxa_kit_showcase_app` | app-integration | n/a | — |

No `providers` entry means "a plain module, not a provider seam" — per
`kit-catalog.md`'s "The 24 kits" table note (`skills/arxa-designer/references/kit-catalog.md`).

No `hasSkill: true` entries exist yet (all 24 report `false`) — every kit
currently relies on general designer/builder skill guidance rather than a
kit-specific skill.

Verification-tier semantics (`kit-catalog.md`, "What the kit is"):
- `stub` — declared, not implemented against a real backend.
- `port-tested` — real port, tests green, no device surface run.
- `device-verified` — run on simulator/device (none present yet in this registry).

## 3. Declaration (design-time) vs manifestation (runtime)

### 3a. How a design declares a kit

A design artifact's screen registry (`models/screens_model/registry.json` in
a design project — SSOT per `skills/arxa-designer/references/app-architecture.md:14`)
adds an optional `kits` array to a surface entry:

```json
{ "id": "shop.locator", "label": "Store Locator",
  "surface": "shop_shell_locator_view", "shell": "shop",
  "comp": "ShopLocator", "route": "/locator", "kits": ["maps"] }
```

Contract table row: `skills/arxa-designer/references/app-architecture.md:53`
— *"`kits` | no | kit dir names from `config/kit-registry.json` (`kits[].dir`)
— the kit modules the surface's built app will use"*. Lines 55–67 spell out
that `kits`, `requiresAuth`, and `tab` are the only sanctioned optional
extensions to the registry contract, and that a declared kit "is a promise
the builder must wire" — never decorative.

Two declaration styles, per `kit-catalog.md` ("Visual islands vs
declaration-only"):
- **Design-time islands** — a data-attribute-driven vendor JS island mounts a
  real interactive preview (e.g. `maps` → `map_island.js`, Leaflet-backed; the
  view template renders a `div` with `data-center-lat`/`data-zoom`/`data-markers`
  and the island mounts a live map). Media/3D kits similarly get
  `dotlottie_island.js`, `rive_island.js`, `three_island.js`.
  Referenced as living in a `runtime/vendor/` tree — not present in this
  worktree's filesystem, so this could not be verified against source; only
  the doc reference was confirmed.
- **Declaration-only** — no visual island; `auth` is a plain server-rendered
  login form, `payments` a checkout summary + pay button. The `kits` array is
  the only carrier of intent downstream in this case.

### 3b. How a kit manifests at runtime (build side)

- Validation + threading: `arxa/lib/emit_structure.dart` reads each
  screen's `kits` list, loads the valid dir set from
  `config/kit-registry.json` via `_loadKitDirs` (`emit_structure.dart:351-365`),
  and fails hard on an unknown name (`emit_structure.dart:248-250`:
  *"declares unknown kit '$name' — not a kits[].dir in config/kit-registry.json"*)
  or non-list/non-string values (`emit_structure.dart:236-243`). Valid
  declarations are threaded into the emitted `structure.json` at
  `emit_structure.dart:304` (`if (kits != null) screen['kits'] = kits;`).
  Test coverage: `arxa/test/emit_structure_test.dart:136-207` — passthrough,
  omission-when-absent, and three hard-fail cases (unknown kit, non-list,
  wrong item type).
- Scaffolder: stamps the declaration into each generated stub's header comment
  as `//   kits (builder wires): <names>` and into `.shell-structure.json`
  (per `skills/arxa-builder/SKILL.md:54-57`: *"Stubs carry `//   kits
  (builder wires): <names>` — the designer's declaration, threaded through
  `structure.json`."*). `decision_log.dart:41` independently confirms
  `scaffold.dart:499` is the consumer of `screen['kits']`, and
  `blueprint.dart:81` receives it as a parameter — *"Nothing anywhere picks a
  kit for a project, so there is no kit decision to record and none is
  invented"* (`arxa/lib/decision_log.dart:39-46`).
- Builder: for each named kit, wires the **real providers** via locator
  injection per the kit's playbook (`kit/<name>/<name>_playbook.mdx`) and the
  tier recorded in `config/kit-registry.json`
  (`skills/arxa-builder/SKILL.md:59-61`). Required credentials
  (`config/credentials.catalog.json`, keyed by `module: kit/<name>`) are read
  from the environment/credential store at build time
  (`skills/arxa-builder/SKILL.md:66`) — never embedded by the designer.
- Deployer / advertise gate: `arxa/lib/gate_advertise.dart` builds a
  `{(kit_dir/provider_name): verification}` ledger across all kits in
  registry order (`gate_advertise.dart:48-53`, reading
  `config/kit-registry.json` at `gate_advertise.dart:221`) and caps any
  capability offer at the recorded tier — *"say 'port-tested', not 'proven'"*
  (`skills/arxa-deployer/SKILL.md:33`).
- Anti-rot check: `arxa/lib/design_selftest_kit_catalog_mirror.dart`
  enforces that every `dir` in `config/kit-registry.json` also appears in
  `skills/arxa-designer/references/kit-catalog.md` as `` `dir` `` — it
  caught the catalog doc rotting to zero listed kits against 24 in the
  registry before being wired (file header, lines 1-26). Registered into
  `design_selftest.dart` as of 2026-08-02, bringing that selftest to 25
  checks total.
- Spec-vs-real pairing: `arxa/lib/tier1.dart` is a pure-Dart **spec copy**
  of provider behavior (auth/payments/maps) used for Tier-1 behavioral
  testing without a Flutter dependency; it explicitly is not an importer of
  kit code (`tier1.dart:31-37`) but is paired 1:1 with real implementations —
  e.g. `SeedAuthBackend` spec (`tier1.dart:302-309`) paired with
  `kit/auth/lib/src/backends/seed_auth_backend.dart` and its test at
  `kit/auth/test/backends/seed_auth_backend_test.dart`.

### 3c. Credentials

`config/credentials.catalog.json` is the single source for kit credential
requirements: rows keyed by `module` (e.g. `kit/payments`) + `provider` (e.g.
`stripe`), each with `key`, `required`, `kind`, a docs `url`, and a
`simulator_note` (e.g. Stripe test keys work fully on simulators; Apple Pay's
sheet requires a physical device). Designs reference key **names** only,
never values (`kit-catalog.md`, "Credentials" section) — the design's job is
to surface which keys the client must collect before build, not to hold them.

## 4. Pipeline flow — who reads the declaration

```
registry.json (design, hand-authored, kits: [...])
        ↓  arxa emit structure  (arxa/lib/emit_structure.dart)
        ↓  validates names against config/kit-registry.json; fails on unknown
structure.json  (generated, carries kits per screen)
        ↓  arxa emit scaffold  (arxa/lib/scaffold.dart:499 per decision_log.dart:41)
per-surface stub headers ("// kits (builder wires): <names>") + .shell-structure.json
        ↓  builder (skills/arxa-builder/SKILL.md:54-66)
locator-wired real providers, keyed against kit-registry.json tiers + credentials.catalog.json
        ↓  gates/advertise (arxa/lib/gate_advertise.dart)
capability offer to the client, capped at the recorded verification tier
```

Consistency between the registry and the human-facing catalog doc is
enforced by `design_selftest_kit_catalog_mirror.dart`, not by convention.

## 5. Dependency relationships between kits

Registry `backing` field states the only formal dependency data:
- `ui_library` → `core` + vendored `cupertino_native`/`m3e` forks.
- `data` → `core` + `ui_library` (`topology: core-coupled`).
- All other 21 kits are `topology: standalone` or `core`/`ui-tier`/
  `app-integration` with `backing` either `pure Dart` or a named third-party
  package set — no other kit-on-kit backing declared in the registry.

Individual kit docs assert **no** dependency beyond that, explicitly, as a
design constraint rather than an accident:
- `arxa_kit_motion`: "No dependency back on `arxa_kit` core,
  `stacked_services`, or a host app's locator. The kit is pure widgets — no
  service registration at all."
- `arxa_kit_security`: "This package depends on no other kit. The host app
  (or `arxa_kit` core) binds the ports in its locator."
- `arxa_kit_maps`: "Standalone by design: no dependency on stacked,
  stacked_services, or arxa_kit core."

So the only real inter-kit coupling in the registry is `ui_library → core`
and `data → core + ui_library`; every capability kit (auth, payments, maps,
security, motion, etc.) is deliberately standalone, bound only through the
host app's service locator — never through a kit-to-kit import.

## Files read for this report

- `config/kit-registry.json`
- `skills/arxa-designer/references/kit-catalog.md`
- `skills/arxa-designer/references/app-architecture.md`
- `config/credentials.catalog.json`
- `arxa/lib/emit_structure.dart`
- `arxa/test/emit_structure_test.dart`
- `arxa/lib/gate_advertise.dart`
- `arxa/lib/decision_log.dart`
- `arxa/lib/design_selftest_kit_catalog_mirror.dart`
- `arxa/lib/tier1.dart`
- `arxa/lib/prd_adr.dart`
- `skills/arxa-builder/SKILL.md`
- `skills/arxa-deployer/SKILL.md`
- `skills/arxa-designer/built-in-skills/declare-structure.md`
- `tools/phase5_kit_copy.sh`
- `kit/` directory listing (25 subdirs)
