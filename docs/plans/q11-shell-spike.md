# Q11 shell spike — design record

Status: in progress. Executor: `shell-spike`. Authority: `docs/plans/designer-scaffolder-grill-decisions.md` (Q11 locked), Q8 manifest, Q5, Q12, Q2↔Q11 audit resolution.

## What the spike must show

Five shells (startup, unknown, auth, application, design) **plus** the splashscreen (not a shell —
the mobile-device splash surface, brand logo only). **One probe, five verdicts**, on the existing
`ProbeReport`/`ProbeTarget` plumbing — no new harness.

## Where the plumbing actually is (verified)

- `appboxd/lib/probes/probe_base.dart` — `Probe`, `ProbeReport`, `ProbeContext`, `ProbeTarget`.
- `appboxd/lib/probes/probe_cli.dart` — runner.
- `appboxd/lib/probes/registry.dart` — `const List<Probe> kProbes`; registration = one import +
  one entry, in run order (documented at line 5).
- Suites: `kSuiteContract` / `kSuiteStudio`; probe files live in `contract/` and `studio/`.

Two facts that make a filesystem probe legal here rather than a hack:

1. `Probe.needsBrowser: false` is first-class — the runner launches **no Chrome at all** when no
   selected probe needs a page (`probe_cli.dart:184`), and `ProbeContext.browser` is nullable
   precisely so a browserless probe that reaches for a page fails to compile.
2. The runner contacts the server **only** when a selected probe `mutates` (the
   `checkDisposableProject` guard) or when `--project` is passed. A non-mutating browserless probe
   runs fully offline; `base` is resolved but never dialled.

So the spike probe is: `needsBrowser: false`, `mutates: false`, five `report.check(...)` calls.

## Pipeline split — forced by Q2↔Q11

Byte-identity applies to **transliteration output only**; the designer's creative stage is exempt.
The spike therefore splits into two stages with a frozen artifact between them:

    input/design.json   (creative/designer stage output — frozen, committed)
          |
          v
    bin/emit_spike_app.dart   (pure transliterator — reads ONLY design.json + manifest + registry)
          |
          v
    golden/                   (the emitted tree)

Verdict 3 runs the transliterator twice from the frozen input and diffs. Consequences that are
design constraints, not incidentals:

- **No timestamps, no dates, no run ids** in Q5 frontmatter. Provenance is `manifestVersion` +
  registry version only. A generated-at stamp makes verdict 3 unpassable by construction.
- Diff excludes `pubspec.lock` and `.dart_tool/` (pub artifacts, not transliteration output).

## The five verdicts, mechanically

The Q8 manifest is machine-readable and already carries the fields each verdict needs — the probe
reads the manifest rather than hardcoding expectations.

| # | Verdict | Mechanism |
|---|---------|-----------|
| 1 | Golden tree matches manifest expansion | Both directions: every `pathTemplate`×`nameTemplate` expansion exists, **and** every golden file is accounted for by some template. One-way is not a match. |
| 2 | `dart analyze` clean | Run in `golden/`. Emit `analysis_options.yaml` mirroring `kit/showcase_app` — `flutter_lints` as a dev dep with no options file means the lints never run, and the verdict would be weaker than the showcase's own bar. |
| 3 | Second run byte-identical | Transliterator twice from frozen input; SHA-256 per file; excludes pub artifacts. |
| 4 | Every emitted surface carries `inspectAttrs` | Scoped by the manifest, not by guesswork: artifact types declare `inspectAttrs: true` (shell-view, shell-view-factor, surface-view, surface-view-factor) or `false` (viewmodels). Verdict = for every artifact of a true-type, the (screenId, surfaceId, anatomy-node id) triple is present. Triple must **resolve**, not merely be present — anatomy-node id checked against the node set in `skills/appbox-designer/references/showcase-anatomy.md`. |
| 5 | Frontmatter/comment conventions | Artifact types declare `frontmatter: full`; Q5's normative rules enforced against those files. |

Splashscreen: it is not a shell, but it **is** a surface, and it expands as a `surface-view`
(`inspectAttrs: true`). It therefore carries the triple. Recorded explicitly because Q11's wording
("not a shell") could otherwise be read as exempting it.

## Findings so far

**F1 — a freshly scaffolded app does not resolve.** `kit/data/pubspec.yaml` carries three
`dependency_overrides` (`win32: ^6.0.1`, `device_info_plus: ^13.0.0`, `package_info_plus: ^10.0.0`)
and its own comment states: *"Host apps depending on this package need the same three overrides in
their own pubspec (pub overrides don't propagate)."* Without them `flutter pub get` fails version
solving — appwrite's graph pins win32 5.x while `appbox_kit_core → talker_flutter → share_plus 13`
needs win32 ^6. With them replicated: exit 0, 170 dependencies.

This is a scaffolder obligation that is **not** currently expressed in the Q8 manifest or either
skill: the emitted `pubspec.yaml` must replicate the override block. Any app the scaffolder
produces is dead on arrival without it. Flagged to team-lead.

**F2 — analyze bar.** See verdict 2 above; `analysis_options.yaml` must be emitted or verdict 2
silently tests less than it appears to.

## Run 1 — actual verdicts

`appbox design probe q11-shells` (offline, browserless, no server contact). 1 PASS, 4 BLOCKED/FAIL.
That ratio is the honest state, not a shortfall to be tuned away.

- **V1 PASS** — showcase, 7 shells / 13 surfaces, bidirectional, `unexplained=0 missing=0`.
  The Q8 gate holds: the manifest round-trips the tree it was abstracted from.
  Warn: `showcase_notes_shell/design-system.md` — a non-Dart file inside a shell dir that **no**
  Q8 expansion can produce. Not failed (artifact types describe `.dart`), but the manifest cannot
  fully round-trip the showcase tree. Needs an artifact type or an explicit exclusion.
- **V2 BLOCKED** — no emitted tree (emitter gated on HARD CONSTRAINTS).
- **V3 BLOCKED** — no transliterator.
- **V4 BLOCKED + circular** — see F2/F3 below.
- **V5 FAIL, true positive** — 100 view/viewmodel files checked, 1 non-conforming:
  `showcase_notes_shell_viewmodel.dart` has no `Relationships:` section. Verified by hand and by
  census: **19 of 20** showcase viewmodels carry it. Q5 makes showcase normative and the manifest
  marks `relationships` required for `full` frontmatter — so the structure contract violates
  itself in one file. Fix the file, or the manifest must say trivial viewmodels may omit it.

### A false green, caught and fixed

The first run reported **V2 PASS**. It was an artifact: `tool/spike-q11-shells/golden/` existed but
was empty, and `dart analyze` in an empty directory exits 0 — green having compiled nothing.
`_goldenTree()` now returns non-null only when the tree holds at least one `.dart` **and** a
`pubspec.yaml`, and V2 additionally requires an `analysis_options.yaml`. Recorded because the
failure mode is general: every verdict that shells out to a tool needs a non-emptiness guard, or
absence reads as success.

## Findings for team-lead (F1–F5)

F1 pubspec overrides (above) · F2 no Dart `inspectAttrs` shape exists · F3 no anatomy-node-id
vocabulary exists · F4 showcase exempt-vs-back-stamp is an open decision (scaffolder SKILL.md:270)
· F5 analyze bar needs `analysis_options.yaml`.

F2+F3 are why V4 is reported as **UNRATIFIED** rather than green: inventing both the shape and the
vocabulary and then checking my own output against them would make a pass meaningless.

## Open — blocking, asked of team-lead

The brief's HARD CONSTRAINTS block truncated in the executor's context at
`"- Do NOT add the spike outpu[t]…"`. Placement/commit policy for the generated tree is therefore
unconfirmed. Current working location is `tool/spike-q11-shells/` (outside `kit/` and `skills/`);
nothing staged or committed pending the answer.
