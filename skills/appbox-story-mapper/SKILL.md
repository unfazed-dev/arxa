---
name: appbox-story-mapper
description: "Use when product requirements need eliciting as an Epic → Feature → Story user story map (MoSCoW priorities, release swimlanes) — the tail of the intake chain: consumes `appbox intake` answers (--answers, auto-discovered from pipeline/state when omitted) and emits the unified docs/intake/brief.md (intake sections + releases + story hierarchy + surface inventory), plus an interactive HTML story map and story-map.json. Also valid standalone (no answers — intake is optional, plan 10.7): features then derive surfaces as before, flagged [inferred]. The intake traceability gate (appbox gate intake, plan 10.6) traces the registry against the brief both ways. Trigger on story mapping, backlog visualization, MoSCoW priority, release planning, organize requirements into a story map, or 'map the requirements before design'."
license: MIT
---

# appbox-story-mapper — story map → brief → designer

> Per-skill playbook (the folded canon for this phase): [`STORYMAP_playbook.mdx`](STORYMAP_playbook.mdx)

Visualizes product requirements as an interactive HTML page using the **Epic →
Feature → Story** three-tier structure, with MoSCoW priority color coding and
Release version swimlanes — and emits the **design brief + surface table** that
hands those requirements to `appbox-designer`.

## Where this sits in the appbox pipeline

```
appbox intake (answers)  →  appbox emit story-map  →  docs/intake/brief.md (unified) + story-map.json + story_map.html  →  appbox-designer
```

- This skill is the **tail of the intake chain** — one chain, one brief. Given
  intake answers, it emits the **unified** `docs/intake/brief.md`: the intake
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

**Chain position:** stage 0 of `appbox-orchestrator` (Ø, front door) → `appbox-story-mapper / appbox-moodboarder` (0, optional) → `appbox-intake` (1) → `appbox-designer` (2) → `appbox-scaffolder` (3) → `appbox-builder` (4) → `appbox-tester` (5) → `appbox-reviewer` (6) → `appbox-deployer` (9) — cross-cutting: `appbox-lint` (7), `appbox-lens` (8), `appbox-cicd` (10, day-zero frame wrapping all stages). Stage numbers and every stage's input/output artifacts: `docs/research/pipeline-map.md` §1; the visual map: `docs/appbox-system-map.md`; the CLI FSM phases: `appboxd/lib/phases.dart`.
- **Upstream:** the client's requirements (`data.json`) — or `appbox-intake` answers (`--answers`), which make the emitted brief the unified one.
- **Downstream:** `appbox-moodboarder` slices the emitted `story-map.json` per epic; `appbox-designer` consumes `docs/intake/brief.md` as its input contract.

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

### Step 3: Generate the artifacts

One command emits all three handoff artifacts:

---

## 4. Notes

1. **Data validation**: The script automatically checks that each Story's Release reference exists in the `releases` list
2. **Priority validation**: `priority` only accepts `must` / `should` / `could` / `wont`
3. **Empty data handling**: If a Feature has no Stories, the column shows an empty placeholder — and the Feature still becomes a surface (named, not yet detailed)
4. **Multilingual support**: Project names, Epic names, etc. support mixed CJK and Latin characters. Slugs are the name's first ascii word; a CJK-only name slugs to `s` — prefer names that slug readably, and confirm the derived ids with the user before emitting the brief
5. **Large map advisory**: If total Stories exceed 50, consider splitting into multiple sub-maps
6. **Self-check**: `appbox emit story-map --self-test` asserts the handoff contract — ids match the gate pattern, are unique, all-`wont` features stay out of the surface table, and the gate's own parse would recover exactly the emitted ids
7. **Licensed MIT** — third-party skill, adapted for appbox. See `LICENSE.txt` and the repository's `THIRD-PARTY-NOTICES.md`

## References

- `references/pipeline-and-mapping.md` — load when resolving how a feature's `id` pins to (or fails to match) an intake-declared surface, or when the exact Epic/Feature/Story → appbox mapping rule is needed.
- `references/data-schema.md` — load when constructing or validating the input JSON (full example + the field-by-field required/optional reference).
- `references/cli-and-handoff.md` — load when running `appbox emit story-map` (full command forms, `--input`/`--output`/`--answers`/etc. argument reference, the unified-brief section order) or handing `brief.md` / `story-map.json` / `story_map.html` off to the designer.
- `references/conversation-guide.md` — load when scripting the live conversation with the user (opening questions, epic/feature/story walkthrough, priority and release confirmation prompts).
