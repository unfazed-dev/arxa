# CLI command reference and handoff details

```bash
appbox emit story-map \
  --input data.json \
  --output docs/intake/story_map.html \
  --data-out docs/intake/story-map.json \
  --brief-out docs/intake/brief.md

# Chained after intake: answers make the brief UNIFIED (intake sections first)
appbox emit story-map \
  --input data.json \
  --answers pipeline/state/run.intake.json \
  --output docs/intake/story_map.html \
  --data-out docs/intake/story-map.json \
  --brief-out docs/intake/brief.md

# Read JSON from stdin
echo '{"project":"demo",...}' | appbox emit story-map \
  --output docs/intake/story_map.html \
  --data-out docs/intake/story-map.json \
  --brief-out docs/intake/brief.md
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

Standard appbox layout: all three under `docs/intake/` — the gate's default
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
  `appbox intake seed --brief docs/intake/brief.md`
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
