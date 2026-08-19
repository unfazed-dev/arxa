// stage_readmes — the per-stage README templates repo-mode init writes.
//
// Tool-owned like the emit manifest: `appbox project init --repo` (re)writes
// them on every run, so they can never drift from the skills they describe.
// Hand edits are welcome for repo flavor but will be overwritten on re-init —
// put durable guidance in the repo's AGENTS.md instead.
//
// Every template gets the project id and kind ('site' | 'app'); the text
// explains what the stage IS and what it needs to START — an empty stage
// folder is a promise, not an absence.

/// README text for one stage of a [kind] ('site' | 'app') project [name].
String stageReadme(String stage, String kind, String name) {
  final k = kind == 'site' ? _site : _app;
  final body = switch (stage) {
    'intake' => _intake,
    'moodboard' => _moodboard,
    'design' => _design,
    'scaffold' => k.scaffold,
    'build' => k.build,
    'test' => k.test,
    'review' => _review,
    'deploy' => k.deploy,
    _ => throw ArgumentError('unknown stage "$stage"'),
  };
  return '# $name — $stage\n\n$body\n';
}

const _intake = '''
This stage holds the intake chain: `answers.json`, `brief.md`,
`registry.json`, `flows.json`, `personas.json`, `direction.json`,
`moodboard.json`, plus the story-map outputs.

What starts it: a client conversation (the `appbox-intake` skill elicits
requirements; `appbox-story-mapper` emits the brief). The answers are the
founder-stated source of truth — targets, locales, and `kind: site | app`
sync from here into `appbox.json` at the app-dir root.

Run `appbox intake` stages from this directory; outputs land here and are
committed like any other repo file.''';

const _moodboard = '''
This stage holds the visual references: one markdown board per epic under
`boards/`, screenshots under `shots/`, and the scored record in
`../intake/moodboard.json`.

What starts it: the story map existing in `../intake/` (it defines the
slices). The `appbox-moodboarder` skill fans out one gathering subagent per
epic, captures key screens with the appbox lens, then SCORES every
reference 0-5 against the intake-derived criteria (founder adjectives and
locked requirements weighted highest) and records the scores. Selection is
a human gate: the highest-scoring slice, approved or overridden by you,
becomes the designer's visual mandate. A locked intake criterion (e.g.
"animated 3D backgrounds") with no reference scoring >= 3 fails the record
check.''';

const _design = '''
This stage holds the design artifact: server-rendered htmx prototype,
genuine MVVM, client JS only in the three legal ADR-0009 forms (vendored
libraries, first-party islands, artifact app modules), authored at every
viewport of the active ladder.

What starts it: `commission.md` at this stage's root — the compiled mandate
(brief + intake direction + ONLY the selected, scored moodboard references
+ style tokens). The `appbox-designer` skill consumes the commission as a
binding contract before authoring anything; locked intake requirements are
non-deferrable. Serve with `appbox design serve <this-dir>`; verify with
`appbox design lint` and the lens. When intake locks motion, the lens must
capture this artifact at two settle states and the stills must differ.''';

const _review = '''
This stage holds pre-release QC evidence: the deterministic contract
validator (arch_guard), the over-engineering review (ponytail-review), and
the manifest hash check.

What starts it: a built target (build/ is green). The `appbox-reviewer`
skill runs both reviews and emits a green/red verdict here. Red verdicts
name the file and the rule — fix the code, never the reviewer.''';

class _KindText {
  final String scaffold, build, test, deploy;
  const _KindText(this.scaffold, this.build, this.test, this.deploy);
}

const _site = _KindText(
  '''
This stage IS the site source root. The designer's eject lands here:
server-rendered htmx + islands, client JS only in the three legal ADR-0009
forms — categorized vendored libraries, named first-party islands, and
artifact app modules (assets/app/*.js) — never inline handlers or orphan
scripts.

What starts it: a frozen design in `../design/`. The `appbox-scaffolder`
skill ejects the design artifact into runnable site code at this path;
`structure.json` and the emit manifest record what was ejected. Later
stages (build, deploy) run against this directory, not the design.''',
  '''
This stage holds the built site: island behavior wired in (WebGL/three.js
motion, analytics, real integrations), assets bundled, evidence of the
build recorded.

What starts it: a scaffolded site in `../scaffold/`. The `appbox-builder`
skill fills the extension points with named, vendored islands — the
design's poster-first degradation is the contract every island must
honor.''',
  '''
This stage holds visual + smoke evidence for the site: lens captures at
every rung of the viewport ladder, console-clean checks, route probes,
locale and state-branch coverage.

What starts it: a served site (design or build). The `appbox-tester`
skill drives the lens against it; captures land here as the goldens.''',
  '''
This stage holds deployment evidence and config for the web target
(Cloudflare Pages/Workers or Vercel).

What starts it: a green build + review in the previous stages. The
`appbox-deployer` skill owns the mechanics. A live domain is PRODUCTION:
it is never touched without an explicit go.''',
);

const _app = _KindText(
  '''
This stage holds the Flutter scaffold evidence: `structure.json`, the emit
manifest, and per-surface coverage records. The Dart itself lands in the
app dir's `lib/ui/views/` — the app-dir root IS the Flutter project
(pubspec.yaml, `flutter run` from there), so tooling sees a normal project.

What starts it: a frozen design in `../design/`. The `appbox-scaffolder`
skill emits the per-surface file set (3 files/surface for macOS, 4 for
iOS/Android) — never empty stubs.''',
  '''
This stage holds normal Flutter build evidence for every target
(iOS/Android/macOS/web): analyzer output, build logs, per-target results.

What starts it: a scaffolded app with views filled by the `appbox-builder`
skill (views compose the adaptive primitive layer; the per-platform native
family lives in the primitives, not the views).''',
  '''
This stage holds the test evidence: mocktail unit tests against the
repository Ports, lens captures for visual/smoke, Patrol for native E2E.

What starts it: a buildable app. The `appbox-tester` skill owns all three
layers; results land here.''',
  '''
This stage holds store-deployment evidence: fastlane lanes and receipts for
TestFlight/App Store and Play internal/production, plus Shorebird OTA patch
records.

What starts it: a released-green review in `../review/`. The
`appbox-deployer` skill owns the mechanics; stores are production and are
never touched without an explicit go.''',
);
