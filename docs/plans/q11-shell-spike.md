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
- **V2 BLOCKED** — no emitted tree; emitter not built (my work, not a team-lead gate).
- **V3 BLOCKED** — no transliterator; same.
- **V4 BLOCKED + circular** — see F2/F3 below.
- **V5 FAIL, true positive** — 100 view/viewmodel files checked, 1 non-conforming:
  `showcase_notes_shell_viewmodel.dart` has no `Relationships:` section. Verified by hand and by
  census: **19 of 20** showcase viewmodels carry it. Q5 makes showcase normative and the manifest
  marks `relationships` required for `full` frontmatter — so the structure contract violates
  itself in one file. Fix the file, or the manifest must say trivial viewmodels may omit it.

## Run 2 — the spike tree exists; all five verdicts report

Emitter + transliterator built, golden tree committed. `appbox design probe q11-shells`,
still offline and browserless. **Zero skips, zero BLOCKED.** 6 PASS, 1 FAIL.

- **V1 PASS** (showcase, unchanged) + **V1b PASS** — spike tree, 5 shells / 8 surfaces,
  `unexplained=0 missing=0`. Both lines run the *same* `_expansionLine()` function; a fork here
  would have made the spike's green prove nothing about the showcase bar.
- **V2 PASS** — `dart analyze` on the emitted tree, exit 0, with the mirrored
  `analysis_options.yaml`. `--no-fatal-warnings` was **removed**: the ruling was the showcase's
  bar, not a weaker default, so warnings are fatal here.
- **V3 PASS** — emitted twice from the frozen `input/design.json` into throwaway temp dirs,
  68 files per run, compared byte-for-byte (base64 of contents, not a digest) against the
  committed tree; `pubspec.lock` + `.dart_tool/` excluded as pub artifacts. The probe never
  re-emits over the tree it is gating. Determinism holds, and the no-timestamps rule in Q5
  frontmatter is what makes it holdable.
- **V4 PASS (UNRATIFIED)** — 13 emitted view files, every one carrying the
  `screenId` / `surfaceId` / `anatomyNodeId` triple. This is internal consistency against a shape
  and a vocabulary **the spike invented**. It is not "Q12 satisfied". See F2/F3 — both still open.
- **V5 FAIL (showcase, unchanged true positive)** + **V5b PASS** — spike tree, 65 files,
  0 non-conforming. The showcase red stays red: forcing it green would delete the finding.

The one remaining FAIL is the pre-existing showcase defect from run 1, not spike output.

### A false green, caught and fixed

The first run reported **V2 PASS**. It was an artifact: `tool/spike-q11-shells/golden/` existed but
was empty, and `dart analyze` in an empty directory exits 0 — green having compiled nothing.
`_goldenTree()` now returns non-null only when the tree holds at least one `.dart` **and** a
`pubspec.yaml`, and V2 additionally requires an `analysis_options.yaml`. Recorded because the
failure mode is general: every verdict that shells out to a tool needs a non-emptiness guard, or
absence reads as success.

### Exactly what V1 and V5 cover (so neither is over-read)

- **V1 scope: `.dart` files only.** The PASS means every `.dart` file under a shell dir is explained
  by a manifest template and every template expansion exists on disk. It does **not** mean the
  manifest round-trips the tree — `design-system.md` is proof it doesn't, hence the warn.
- **V5 scope: one rule of Q5, not Q5.** The checker enforces the presence of the `Relationships:`
  section on view/viewmodel files. It does **not** yet check `Requirements:`, `History:`,
  numbered-requirement form, or comment conventions. So "1 of 100 non-conforming" is *one rule's*
  conformance, not Q5 coverage. The single failure it found is real; the 99 passes are weaker
  evidence than the count suggests.

## Findings for team-lead (F1–F5)

F1 pubspec overrides (above) · F2 no Dart `inspectAttrs` shape exists · F3 no anatomy-node-id
vocabulary exists · F4 showcase exempt-vs-back-stamp is an open decision (scaffolder SKILL.md:270)
· F5 analyze bar needs `analysis_options.yaml`.

F2+F3 are why V4 is reported as **UNRATIFIED** rather than green: inventing both the shape and the
vocabulary and then checking my own output against them would make a pass meaningless.

## A retracted blocker — recorded because the error is instructive

I first reported placement/commit policy as **blocked on team-lead**, because the brief's HARD
CONSTRAINTS block appeared truncated at `"- Do NOT add the spike outpu[t]…"`. That was wrong.
The truncation was a *context-rendering* artifact, not a gap in the message. The verbatim brief is
on disk in the session log and recovers cleanly. Its actual text:

> Emit the spike's generated app tree into an isolated, durable, repo-tracked spike location
> (e.g. a dedicated spike output dir alongside the probe tooling) … tmp/ is wiped between
> sessions — do not put durable evidence there.

`tool/spike-q11-shells/` satisfies this exactly: alongside the probe tooling, repo-tracked, outside
`kit/` and `skills/`, not `tmp/`. **Placement is settled and the tree is committed.**

Generalisable lesson: when input looks elided, check the durable source before declaring a
dependency on a human. A false "blocked on you" is more costly than the work it avoids — it parks
the task and misattributes the cause.

## Genuinely open — needs team-lead ratification (V4 only)

V4 cannot be made meaningful by more work on my side: `inspectAttrs` has **no Dart shape** anywhere
in `kit/` (app-architecture.md:169 defines only the JS form) and the anatomy-node-id vocabulary has
exactly one illustrative value (`anatomy:view.body`, app-architecture.md:172) with no closed set and
no home. Both need ratification + a home (showcase-anatomy.md §3, or the registry). Also open:
whether showcase is exempt from `inspectAttrs` or gets back-stamped (scaffolder SKILL.md:270).

## Remaining spike work — mine, not blocked

V2 and V3 are unfinished, not gated: the emitter and transliterator are not built. V1 and V5 already
run against showcase and produce real signal.
