# Industry practice: generated artifacts, drift, and spec authority

Research against the open question — *when the producer's structure and the
frozen `structure.json` disagree, which is authoritative, and is it a gate?*

## 🔥 Strong consensus

**1. `generate && fail-on-diff` is the canonical verification.** Regenerate in
CI, fail the build if the tree changed. Design-token guidance states it as
policy: *if you commit generated artifacts, regenerate them in CI and fail on
diff — treat any hand-edit of a generated file as a policy violation.*

**2. The gotcha we would have shipped: `git diff --exit-code` misses NEW
files.** Untracked files are in no git state, so `git diff` ignores them. A
generator that *adds* a file exits 0 — green while broken. Fixes:

```bash
# Option A — porcelain catches both modified and untracked
test -z "$(git status --porcelain)" || { git status --porcelain; exit 1; }

# Option B — stage first
git add -A && git diff --cached --exit-code
```

Neither catches `.gitignore`d output; don't ignore generated paths.

**3. Pin the generator version.** Version skew between dev and CI emits
different headers/hashes → spurious diffs that train people to ignore the gate.

**4. Print the diff on failure.** A bare `--exit-code` gives a red X with no
means to act.

**5. `.gitattributes` hygiene.** `linguist-generated=true` collapses generated
files in review; `text eol=lf` stops line-ending false positives.

**6. Tokens: DTCG is the standard.** `tokens.json` at root as SSOT, per-platform
outputs generated, a validation layer linting naming/contrast/duplication.

## 🌡️ Contested / worth knowing

**7. Spec-driven development's identified failure is exactly ours.** Spec Kit
and Kiro-style specs *drive first generation but do not durably govern* — the
authority is **convention, not enforcement**. Drift is the central complaint.
That is the precise gap between "structure.json exists" and "structure.json is
gated."

**8. Diff-based drift detection has ~30% recall.** Reported: grep/diff scored
100% precision but only **30% recall**; canary *execution* reached 100/100 but
needs full runtime. Meaning: regenerate-and-diff catches drift only when the
*output* changes. Semantics can move without the artifact moving.

## ❄️ Thin

**9. Git-ref pinning** — record the commit SHA at generation, later check
whether commits since touched related files. Proposal-stage, not established.

## What this changes for app_box

- **§13's recommendation is the industry pattern.** Producer authoritative,
  regenerate-and-diff, hand-edit = policy violation. No change needed.
- **The freeze gate cannot do this for htmx today.** The drift check is guarded
  on `[ -f "$DESIGN/jsx/app.jsx" ]`, and the gate says so in its own comment:
  *"A producer with no jsx/ has no second source to drift from: there, coverage
  (b) IS the drift check."* So building §13's exporter does not merely add
  data — **it turns on a drift check that is currently structurally impossible
  for `new-htmx`.** That is the strongest argument for §13 yet.
- **Use porcelain semantics, not `git diff`,** wherever a gate asserts
  regenerated output — a producer that adds a surface is the expected case.
- **Recall caveat:** pair the diff with the existing coverage assertions.
  Diff alone is a 30%-recall instrument.

## Correction to §11 — the flag already exists as prior art

`factory/flutter-crew/flutter_crew.config.json`:

```json
{ "version": "1.0.0", "platforms": ["ios", "android", "web"] }
```

`platforms` scopes *which targets `map_all` resolves and `synthesize` emits*,
overridable per-run with `run_pipeline --platforms ios,android`. `blueprint.py`
already carries per-provider platform allowlists (Apple sign-in `["ios"]`) —
i.e. the platform-conditional ceremonies §11 proposed. `transform_tokens.py`
already emits per-platform token files (Dart / Swift / XML) from DTCG.

So "zero platform awareness" was true of **stacked_kit's pipeline**, not of the
corpus. flutter-crew has the mechanism; app_box should adopt it, not invent it.

**And its config comment carries a design lesson that refines §11:**

> *"Neither script auto-loads config; pass `--config` explicitly (so
> deterministic snapshot runs stay flag-free → golden stable)."*

Targets deliberately are **not** ambient. That is in tension with "targets live
in pipeline state." Reconciliation: state is right for the *product* (GUI, CLI
and harness must not drift), but **gate and golden runs must take targets
explicitly**, or reproducibility depends on ambient state — the exact thing
`dep_hash`'s stale-green defect was.
