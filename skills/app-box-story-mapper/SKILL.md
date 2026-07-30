---
name: app-box-story-mapper
description: "Elicit product requirements as an Epic → Feature → Story user story map (MoSCoW priorities, release swimlanes) and hand it to app-box-designer: emits an interactive HTML story map, the story-map.json data file, and a gate-compatible docs/design/brief.md whose surface table the intake traceability gate (plan 10.7) traces the registry against. Runs before design; feeds the designer directly, bypassing app-box-intake. Trigger on story mapping, backlog visualization, MoSCoW priority, release planning, organize requirements into a story map, or 'map the requirements before design'."
license: MIT
---

# app-box-story-mapper — story map → brief → designer

Visualizes product requirements as an interactive HTML page using the **Epic →
Feature → Story** three-tier structure, with MoSCoW priority color coding and
Release version swimlanes — and emits the **design brief + surface table** that
hands those requirements to `app-box-designer`.

## Where this sits in the app_box pipeline

```
story-mapper  →  docs/design/brief.md (+ story-map.json, story_map.html)  →  app-box-designer
```

- This skill **feeds the designer directly**; `app-box-intake` is bypassed
  (intake is optional — a brief is valid designer input, plan 10.7).
- Like intake, this skill **elicits; it does not generate** (architecture §22).
  The map is the client's words, structured. You do NOT produce views,
  viewmodels, routes, or layouts — that is the designer's job.
- The emitted `brief.md` carries a **surface inventory table** in the exact
  format `gates/intake/intake.sh` (traceability, plan 10.6) parses — so the
  gate passes unchanged: every registry surface the designer authors traces to
  a row here, no orphans either way.

### The mapping (enforced by the script, not by prose)

| Story map | app_box | Rule |
|---|---|---|
| Epic | shell | slugified from its first ascii word, lowercase (`User System` → `user`) |
| Feature | surface | `id = <epic-slug>.<feature-slug>` (`shop.cart` → comp `ShopCart`); ids match `^([a-z][a-z0-9]*)\.([a-z][a-z0-9]*)$` |
| Story | requirement | listed under its feature in the brief — what that screen must satisfy |
| MoSCoW + release | sibling metadata | rolled up per surface (strongest live priority, earliest live release) into the table's `priority` / `release` columns; `intake.py seed` carries them into the registry as additive fields (the four-field canon is untouched) |
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
python3 skills/app-box-story-mapper/scripts/generate_story_map.py \
  --input data.json \
  --output docs/design/story_map.html \
  --data-out docs/design/story-map.json \
  --brief-out docs/design/brief.md

# Read JSON from stdin
echo '{"project":"demo",...}' | python3 skills/app-box-story-mapper/scripts/generate_story_map.py \
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
| `--self-test` | ❌ | Run the handoff self-check (slugs, gate parse, all-wont rule) and exit |

Standard app-box layout: all three under `docs/design/` — the gate's default
paths (`--brief docs/design/brief.md`), so `gates/intake/intake.sh` needs no
flags.

### Step 4: Hand off to design

- **`brief.md`** → `app-box-designer` reads it as its requirements source; the
  surface inventory seeds what it authors into `registry.json` (it binds a
  `surface` to each entry — this skill never binds). The brief also carries the
  **locales list** (+ default locale) — the designer authors one ARB catalog
  per locale (`l10n/app_en.arb` is the template) and seeds copy for each.
- **`story-map.json`** → the full-fidelity data (priorities, releases, points)
  the designer consults while designing.
- **`story_map.html`** → the human artifact: show it to the client to confirm
  scope before design starts.
- Optionally seed the registry without rewriting a word:
  `python3 skills/app-box-intake/intake.py seed --brief docs/design/brief.md`
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
6. **Self-check**: `python3 scripts/generate_story_map.py --self-test` asserts the handoff contract — ids match the gate pattern, are unique, all-`wont` features stay out of the surface table, and the gate's own parse would recover exactly the emitted ids
7. **Licensed MIT** — third-party skill, adapted for app_box. See `LICENSE.txt` and the repository's `THIRD-PARTY-NOTICES.md`
