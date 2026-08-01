---
name: appbox-story-mapper
description: "Elicit product requirements as an Epic → Feature → Story user story map (MoSCoW priorities, release swimlanes) — the tail of the intake chain: consumes `appbox intake` answers (--answers, auto-discovered from pipeline/state when omitted) and emits the unified docs/design/brief.md (intake sections + releases + story hierarchy + surface inventory), plus an interactive HTML story map and story-map.json. Also valid standalone (no answers — intake is optional, plan 10.7): features then derive surfaces as before, flagged [inferred]. The intake traceability gate (appbox gate intake, plan 10.6) traces the registry against the brief both ways. Trigger on story mapping, backlog visualization, MoSCoW priority, release planning, organize requirements into a story map, or 'map the requirements before design'."
license: MIT
---

# appbox-story-mapper — story map → brief → designer

Visualizes product requirements as an interactive HTML page using the **Epic →
Feature → Story** three-tier structure, with MoSCoW priority color coding and
Release version swimlanes — and emits the **design brief + surface table** that
hands those requirements to `appbox-designer`.

## Where this sits in the appbox pipeline

```
appbox intake (answers)  →  appbox emit story-map  →  docs/design/brief.md (unified) + story-map.json + story_map.html  →  appbox-designer
```

- This skill is the **tail of the intake chain** — one chain, one brief. Given
  intake answers, it emits the **unified** `docs/design/brief.md`: the intake
  sections, then Releases, then the epic/feature/story hierarchy, then a
  surface inventory built from the intake-declared surfaces.
- It also remains valid **standalone** (no answers): `appbox-intake` is
  optional — a story map alone is valid designer input (plan 10.7). Standalone,
  surfaces are derived from features exactly as before.
- Like intake, this skill **elicits; it does not generate** (architecture §22).
  The map is the client's words, structured. You do NOT produce views,
  viewmodels, routes, or layouts — that is the designer's job.
- The emitted `brief.md` carries a **`## Surface inventory`** table (and
  `## Layout template` when intake elicited one) in the exact format
  `appbox gate intake` (pure Dart, `appboxd/lib/gate_intake.dart`; plan 10.6)
  parses — so the gate passes unchanged: every registry surface the designer
  authors traces to a row here, no orphans either way.

### Intake owns the surface inventory; stories ATTACH

When answers are present, the surface inventory is **the intake-declared
surfaces**, not a derivation. A feature pins a declared surface by carrying an
explicit `id` field equal to that surface's id — the feature's stories then
attach to that surface. A feature whose `id` (explicit or slug-derived) matches
**no** declared intake surface is derived as before and flagged ` — [inferred]`
in the unified brief's surface table, so a reader can tell client-declared
scope from mapper-derived scope at a glance.

### The mapping (enforced by the script, not by prose)

| Story map | appbox | Rule |
|---|---|---|
| Epic | shell | slugified from its first ascii word, lowercase (`User System` → `user`) |
| Feature | surface | **with intake answers:** an explicit `id` field equal to a declared intake surface id pins (attaches to) that surface. **Without a match (or standalone):** derived as before — `id = <epic-slug>.<feature-slug>` (`shop.cart` → comp `ShopCart`); ids match `^([a-z][a-z0-9]*)\.([a-z][a-z0-9]*)$`; unmatched derived surfaces are flagged ` — [inferred]` in the brief's surface table |
| Story | requirement | listed under its feature in the brief — what that screen must satisfy |
| MoSCoW + release | sibling metadata | rolled up per surface (strongest live priority, earliest live release) into the table's `priority` / `release` columns; `appbox intake seed` carries them into the registry as additive fields (the four-field canon is untouched) |
| all-`wont` feature | out-of-scope | excluded from the surface table, listed in the brief's Out of scope |

---

## Quick Start

The user only needs to provide product requirements — the Agent handles the rest:

1. Guides the user through organizing Epics / Features / Stories
2. Confirms MoSCoW priorities and Release assignments
3. Builds the JSON data and invokes the script to generate all artifacts
4. Outputs a self-contained HTML file that opens directly in any browser,
   plus the `brief.md` / `story-map.json` handoff for the designer

The user simply says:
> "Build me a story map — I have 3 Epics: user registration, product browsing, and checkout"

The Agent will walk the user through the entire story map construction step by step.

---

## 1. Core Concepts

### Three-Tier Structure

| Tier | Meaning | Example |
|------|---------|---------|
| **Epic** | Major value theme / user activity | User Registration & Login |
| **Feature** | Functional module under an Epic | Phone signup, Email signup, SSO login |
| **Story** | Smallest deliverable user story | As a user, I can register with my phone number and a verification code |

### MoSCoW Priorities

| Level | Meaning | Color |
|-------|---------|-------|
| **Must** | Essential — product is unusable without it | 🔴 Red |
| **Should** | Important — significantly increases value | 🟠 Orange |
| **Could** | Nice to have — adds polish | 🔵 Blue |
| **Wont** | Not this time — recorded for future reference | ⚪ Gray |

### Release Swimlanes

Horizontal divider lines group story cards by version:
- Above the Release 1 (MVP) line = must ship in the first version
- Above the Release 2 line = planned for the second version
- And so on

---

## 2. Workflow

### Step 1: Gather Requirements

Collect the following from the user:

| Item | Required | Notes |
|------|----------|-------|
| Project name | ✅ | Displayed in the map title |
| Epic list | ✅ | 2–8 Epics |
| Features per Epic | ✅ | 1–6 Features per Epic |
| Stories per Feature | ✅ | 1–10 Stories per Feature |
| Priority per Story | ✅ | must / should / could / wont |
| Release per Story | ✅ | Which version it belongs to |
| Release list | ✅ | Version names and descriptions |
| Locales | ❌ | e.g. `[en, pl]` + the default locale — carried into the brief so the designer knows which ARB catalogs + seed locales to author (defaults to `[en]`) |
| Story Points (optional) | ❌ | Effort estimate |
| Story description (optional) | ❌ | Additional details |

### Step 2: Build the JSON Data

Organize the data in the following format:

```json
{
  "project": "E-Commerce Platform MVP",
  "releases": [
    {"name": "Release 1", "description": "MVP core features"},
    {"name": "Release 2", "description": "UX improvements"},
    {"name": "Release 3", "description": "Growth features"}
  ],
  "epics": [
    {
      "name": "User System",
      "features": [
        {
          "name": "Registration & Login",
          "stories": [
            {
              "name": "Phone number signup",
              "priority": "must",
              "release": "Release 1",
              "points": 3,
              "description": "User can register with phone number and verification code"
            },
            {
              "name": "WeChat login",
              "priority": "should",
              "release": "Release 2",
              "points": 5
            }
          ]
        }
      ]
    }
  ]
}
```

#### Field Reference

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `project` | string | ✅ | Project name |
| `releases` | array | ✅ | Release list (in order) |
| `releases[].name` | string | ✅ | Version name — must match the `release` field in Stories |
| `releases[].description` | string | ❌ | Version description |
| `epics` | array | ✅ | Epic list |
| `epics[].name` | string | ✅ | Epic name |
| `epics[].features` | array | ✅ | Feature list |
| `epics[].features[].name` | string | ✅ | Feature name |
| `epics[].features[].stories` | array | ✅ | Story list |
| `stories[].name` | string | ✅ | Story name |
| `stories[].priority` | string | ✅ | must / should / could / wont |
| `stories[].release` | string | ✅ | Assigned version name |
| `stories[].points` | number | ❌ | Story Points |
| `stories[].description` | string | ❌ | Additional description |

### Step 3: Generate the artifacts

One command emits all three handoff artifacts:

```bash
appbox emit story-map \
  --input data.json \
  --output docs/design/story_map.html \
  --data-out docs/design/story-map.json \
  --brief-out docs/design/brief.md

# Chained after intake: answers make the brief UNIFIED (intake sections first)
appbox emit story-map \
  --input data.json \
  --answers pipeline/state/run.intake.json \
  --output docs/design/story_map.html \
  --data-out docs/design/story-map.json \
  --brief-out docs/design/brief.md

# Read JSON from stdin
echo '{"project":"demo",...}' | appbox emit story-map \
  --output docs/design/story_map.html \
  --data-out docs/design/story-map.json \
  --brief-out docs/design/brief.md
```

#### Command Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `--input` | ❌ | Input JSON file path (reads from stdin if omitted) |
| `--output` | ✅ | Output HTML file path (unless `--self-test`) |
| `--data-out` | ❌ | Write the validated story-map data JSON here — the machine-readable handoff |
| `--brief-out` | ❌ | Write the gate-compatible design brief here — the traceability source |
| `--answers` | ❌ | Intake answers JSON — makes the emitted brief the **unified** one. When omitted, auto-discovers `pipeline/state/run.intake.json`, then `pipeline/state/default.intake.json`; when neither exists (or has no answers), the story map runs standalone as before (10.7) |
| `--self-test` | ❌ | Run the handoff self-check (slugs, gate parse, all-wont rule) and exit |

Standard appbox layout: all three under `docs/design/` — the gate's default
paths, so `appbox gate intake` needs no flags.

#### The unified brief (when answers are present)

Section order: the intake sections — Product, Audience (JTBD), What the app
must do, Existing systems, Targets, **Locales**, Brand, **Design direction**,
**Content anchors**, Constraints, Out of scope, **Layout template** (when one
was elicited) — then **Releases**, then the epic/feature/story hierarchy, then
the **surface inventory** built from the intake-declared surfaces (stories
attached by feature `id`; unmatched derived surfaces flagged ` — [inferred]`).
Every intake field carries its provenance (`client` | `founder` | `inferred`),
with `inferred` visibly marked.

### Step 4: Hand off to design

- **`brief.md`** → `appbox-designer` reads it as its requirements source; the
  surface inventory seeds what it authors into `registry.json` (it binds a
  `surface` to each entry — this skill never binds). The brief also carries the
  **locales list** (+ default locale) — the designer authors one ARB catalog
  per locale (`l10n/app_en.arb` is the template) and seeds copy for each.
- **`story-map.json`** → the full-fidelity data (priorities, releases, points)
  the designer consults while designing.
- **`story_map.html`** → the human artifact: show it to the client to confirm
  scope before design starts.
- Optionally seed the registry without rewriting a word:
  `appbox intake seed --brief docs/design/brief.md`
  (plan 10.7 — the brief passes through unmodified).

The script produces a **self-contained HTML file** (no external dependencies) with these features:

- 📊 Three-tier card layout: Epic → Feature → Story
- 🎨 MoSCoW priority color coding
- 📏 Release version swimlane grouping
- 📱 Responsive design with horizontal scrolling
- 🖨️ Print-friendly (auto-fits A3 landscape)
- 💡 Hover tooltips showing Story details
- 📈 Stats panel (Story counts and Points totals by priority and release)

---

## 3. Conversation Guide

### Opening

> I'll help you build a user story map. First, let me know:
> 1. What's the project name?
> 2. What are the major functional areas (Epics)?
> 3. How many releases are you planning?

### Step-by-Step Walkthrough

> Great, let's flesh out the "{Epic name}" Epic:
> - What specific features does it include?
> - What user stories fall under each feature?

### Confirming Priorities

> Here are the stories under "{Feature name}" — please confirm each one's priority:
> | Story | Suggested Priority | Your Call |
> |-------|-------------------|-----------|
> | ... | Must | |

### Confirming Release Assignments

> Please confirm which Release each Story belongs to:
> - Release 1 (MVP): Core essentials
> - Release 2: UX improvements
> - Release 3: Growth features

---

## 4. Notes

1. **Data validation**: The script automatically checks that each Story's Release reference exists in the `releases` list
2. **Priority validation**: `priority` only accepts `must` / `should` / `could` / `wont`
3. **Empty data handling**: If a Feature has no Stories, the column shows an empty placeholder — and the Feature still becomes a surface (named, not yet detailed)
4. **Multilingual support**: Project names, Epic names, etc. support mixed CJK and Latin characters. Slugs are the name's first ascii word; a CJK-only name slugs to `s` — prefer names that slug readably, and confirm the derived ids with the user before emitting the brief
5. **Large map advisory**: If total Stories exceed 50, consider splitting into multiple sub-maps
6. **Self-check**: `appbox emit story-map --self-test` asserts the handoff contract — ids match the gate pattern, are unique, all-`wont` features stay out of the surface table, and the gate's own parse would recover exactly the emitted ids
7. **Licensed MIT** — third-party skill, adapted for appbox. See `LICENSE.txt` and the repository's `THIRD-PARTY-NOTICES.md`
