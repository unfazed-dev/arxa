# Post-Scaffold Iteration: How the Industry Handles Design→Code Divergence

Research question: after a deterministic scaffolder turns a frozen design-tool structure (screens,
flows, kits) into generated code, where do post-scaffold feature updates happen, and how do the two
representations (design prototype and generated app) stay in sync — especially with an LLM agent
embedded in the authoring tool?

## 1. Regeneration strategies from classic codegen tooling

**Generation Gap pattern** (Vlissides, *Pattern Hatching*). Generated code and hand-written code are
kept in separate classes linked by inheritance: the generator owns a base class and is free to
overwrite it on every run; a developer subclass carries all customization and is never touched by the
generator. Applicable when generated output can be cleanly encapsulated in whole classes. Downside:
roughly doubles class count with a "technical vehicle" that has no product meaning.
[Wikipedia: Generation gap (pattern)](https://en.wikipedia.org/wiki/Generation_gap_(pattern)) ·
[Generation Gap vs Protected Regions in Xtext MDD](https://emfmodeling.blogspot.com/2011/10/generation-gap-pattern-vs-protected.html)

**Protected regions** (marker comments, e.g. `// BEGIN/END USER CODE <id>`). The generator emits
default content inside the markers and treats the block as regenerable until a human edits it, at
which point it flips to "enabled" and is preserved verbatim on future runs. Keeps class structure
identical to a non-generated codebase, but forces generated files with embedded custom code into
version control, and doesn't survive well if a human deletes or badly nests markers.
[Generation Gap Pattern — Embedded Artistry](https://embeddedartistry.com/fieldmanual-terms/generation-gap-pattern/)

**Three-way merge on regeneration (Copier / Cruft).** This is the closest analog to "design changes,
regenerate, preserve edits." Copier's `copier update` diffs old-template-output vs new-template-output
vs current-project-state and 3-way merges; unresolved hunks get inline git-style conflict markers (or
`.rej` files) for a human (or now, an AI agent) to resolve. Cruft does the same for Cookiecutter
templates and can be scheduled via CI to open a PR weekly. Plain Cookiecutter has no built-in update
path at all — teams fall back to raw `git merge` against the rendered template output.
[Copier: updating a project](https://copier.readthedocs.io/en/stable/updating/) ·
[Cruft](https://cruft.github.io/cruft/) ·
[Cookiecutter update issue #784](https://github.com/cookiecutter/cookiecutter/issues/784)

**OpenAPI Generator / AWS Amplify: overwrite + ignore-list, no merge.** OpenAPI Generator has no
three-way merge; the answer is `.openapi-generator-ignore` (declare which output files are
hands-off) or forking the templates. AWS Amplify codegen's answer is even more one-directional: the
GraphQL schema is the SSOT, and you regenerate statements/types from it — there's no notion of
preserving edits to generated types at all. Fern (a commercial competitor) markets three-way merge
with automatic PRs as a differentiator specifically because OpenAPI Generator lacks it.
[OpenAPI Generator customization docs](https://openapi-generator.tech/docs/customization/) ·
[Fern vs OpenAPI Generator](https://buildwithfern.com/post/openapi-generator-cli-vs-fern)

**Scaffold diffing (Rails `app:update` / `rails-diff`).** Rails re-runs the same generator used by
`rails new` and uses Thor's per-file conflict prompt (keep/overwrite/diff/merge-in-editor via
`THOR_MERGE`). The `rails-diff` gem lets you diff what a generator *would* produce against your repo
on demand, including in CI, without touching files — diffing as a first-class read-only operation
separate from the write/merge step.
[rails-diff](https://github.com/MatheusRich/rails-diff) ·
[Upgrading Rails with rake app:update](https://www.joshmcarthur.com/til/2019/07/25/upgrading-rails-apps-with-rake-appupdate.html)

**Eject-and-own (create-react-app).** A one-time, irreversible escape hatch: eject copies the entire
generator-owned config into the project and deletes the generator dependency. From that point the
project is fully hand-owned and never regenerated again. CRA's own docs and the ecosystem consensus:
eject is a last resort — prefer non-ejecting override tools (`react-app-rewired`, `customize-cra`) or
forking the generator, specifically because ejecting means permanently taking on maintenance of code
you didn't choose to write and can no longer get upgrades for.
[Alternatives to Ejecting — CRA docs](https://create-react-app.dev/docs/alternatives-to-ejecting/) ·
[Laying out the tradeoffs of ejecting](https://h-o-m-e.org/react-eject/)

**Nx sync generators.** A different shape of the same problem — not "regenerate the whole app" but
"keep specific derived files (config, project graph artifacts) correct relative to source." Sync
generators run in `--dry-run` locally (prompt to apply or skip) and hard-fail in CI if files would
change, i.e. drift is caught mechanically rather than resolved by merge.
[Nx: Sync Generators](https://nx.dev/docs/concepts/sync-generators)

## 2. What design-to-code tools actually ship

None of the mainstream commercial design-to-code tools default to true bidirectional round-trip; they
cluster into **one-way with a chosen SSOT**, and the 2025–2026 trend is bidirectionality arriving *at
the workflow level* via git/PRs rather than via live model sync.

- **Figma Code Connect** is explicitly one-way and read-only: it lets Dev Mode show real
  component-library code snippets instead of auto-generated ones, but it does not generate code, does
  not update when code changes, and cannot push Figma changes into the codebase — critics call it "a
  one-way viewer pretending to be a bridge." The genuine bidirectional development in 2026 is at the
  *MCP server* layer: Figma's MCP server now lets an agent (e.g. via GitHub Copilot) push a rendered
  UI from the IDE back into Figma as an editable frame — closing the loop at the tooling level, not
  by keeping a shared live model.
  [Figma Code Connect](https://help.figma.com/hc/en-us/articles/23920389749655-Code-Connect) ·
  [Builder.io: Claude Code to Figma](https://www.builder.io/blog/claude-code-to-figma)

- **Plasmic** makes the SSOT an explicit up-front choice, not a compromise: *Headless API* mode keeps
  Plasmic as the CMS-like SSOT and code never owns the design (recommended default); *Codegen* mode
  flips SSOT to the repo — you run `plasmic sync` to pull design changes into source files that you
  then own, commit, and can hand-edit. There's no attempt to merge both directions simultaneously.
  [Headless API vs. Codegen](https://docs.plasmic.app/learn/loader-vs-codegen/)

- **Builder.io Fusion** sidesteps the SSOT question by making *every* change — visual edit, AI prompt,
  or hand code — land as a normal pull request against the real repo. This keeps a single SSOT (the
  repo) but treats the design surface as just another PR author, relying on ordinary code review to
  catch/resolve divergence instead of an automated merge algorithm.
  [Builder.io Fusion](https://www.builder.io/fusion)

- **Anima** targets continuous one-way sync from Figma into a connected repo (auto-sync on Figma
  change, GitHub integration), explicitly for the handoff problem rather than for surviving deep
  hand-written logic added downstream.
  [Anima: design to code](https://www.animaapp.com/blog/design-to-code/)

- **Google Flutter GenUI / A2UI** is a different problem class (runtime, LLM-generated UI against a
  closed widget catalog, re-composed per-interaction) rather than a design→static-code pipeline, but
  its guiding discipline is instructive: constrain the LLM's output to a fixed, versioned catalog of
  known-good widgets, and re-test whenever the underlying model changes, because open-ended
  regeneration against a moving target reintroduces drift.
  [Flutter GenUI SDK](https://docs.flutter.dev/ai/genui)

## 3. Why round-trip engineering (MDE) mostly failed, and what won instead

Round-trip engineering (RTE) — keeping a UML/diagram model and generated code simultaneously
editable and synchronized — was model-driven engineering's central promise in the 2000s–2010s, and it
largely didn't scale:

- **Reverse-engineering fidelity**: code reversed back into a model is rarely identical to the
  original model unless the tool litters the source with tracing annotations/GUIDs (e.g. Rational
  Software Architect embedded GUID comments per model element specifically to make sync possible).
- **Semantic gaps**: UML concepts like associations and containment don't map cleanly onto most
  programming languages, so round-tripped code and round-tripped models both come out lossy.
- **Concurrent modification**: once architects and developers can each edit "their" artifact with
  different tools at different times, you get the same synchronization problem as any distributed
  system — except most MDE tools never built proper conflict resolution for it.
  [Round-trip engineering — Wikipedia](https://en.wikipedia.org/wiki/Round-trip_engineering)

The practitioner conclusion (LieberLieber, and echoed broadly) is that round-trip of *structural*
stubs (class shapes) is tractable, but round-trip of *behavior* is "a myth" — the recommendation is
forward-only generation for behavior so documentation/model stays honest about what it actually
describes, rather than pretending it's a live mirror of hand-edited logic.
[Code Generation from UML and Round-Trip Engineering](https://blog.lieberlieber.com/2015/06/11/code-generation-from-uml-and-round-trip-engineering/)

**What won**: a hard split between the primary, hand-edited development artifact and everything
derived from it — one direction of truth, one direction of generation, no simultaneous bidirectional
editability of the same concept in two notations. Tools like Umple avoid the problem entirely by
making model and code the *same* artifact (textual UML embedded directly in source) rather than two
synchronized ones. This is the same shape as generation-gap/eject-and-own/copier-update above: pick
what's authoritative, make regeneration one-way from it, and give the other side a narrow, well-marked
place to add things that survive regeneration.

## 4. LLM-era answer: spec-driven development + LLM-mediated merge

2025–2026 tooling (GitHub Spec Kit, AWS Kiro, Tessl, BMAD, Google Antigravity) converges on
**spec-driven development (SDD)**: an executable, versioned spec is the SSOT; code is a continuously
regenerated, disposable output. GitHub's own framing: "the entire development workflow reorganizes
around specifications as the central source of truth, with implementation plans and code as the
continuously regenerated output" — i.e. shifting from "code is truth" to "intent is truth." Kiro
implements this as an IDE workflow (Requirements → Design → Tasks → code) but by its own early
reports still doesn't fully automate keeping spec and code in sync once both have been hand-edited —
the same divergence problem, just moved up a level of abstraction.
[GitHub Blog: spec-driven development](https://github.blog/ai-and-ml/generative-ai/spec-driven-development-with-ai-get-started-with-a-new-open-source-toolkit/) ·
[GitHub Spec Kit](https://github.com/github/spec-kit)

Separately, and directly applicable to a scaffolder with template updates: the emerging 2025–2026
pattern for surviving *template* regeneration is **mechanical 3-way merge (Copier-style) producing
git-style conflict markers, then an LLM agent proposes resolutions for the conflicted hunks, with a
human (or a policy) approving before commit**, guarded by a pre-commit hook that blocks unresolved
markers. This is already how VS Code/Copilot, GitLens, and GitLab Duo handle ordinary git merge
conflicts, and it's the natural place to point an embedded studio agent: not "regenerate everything
and hope," but "produce a mechanical diff, let the LLM reconcile the hunks it's equipped to reason
about, and mark the rest for a human."
[Copier: updating a project](https://copier.readthedocs.io/en/stable/updating/) ·
[The role of AI in merge conflict resolution — Graphite](https://www.graphite.com/guides/ai-code-merge-conflict-resolution)

## Decision matrix

| Strategy | SSOT | Mechanism | Survives divergence? | Failure mode |
|---|---|---|---|---|
| **Design remains SSOT, full regen** | Design/spec | Scaffolder re-emits Flutter from structure every time | No — any hand-edit to Flutter is silently lost on next regen | Developers stop trusting regen, start avoiding it, structure and code quietly diverge anyway (classic RTE failure) |
| **Code becomes SSOT, design frozen** | Flutter code | Design prototype snapshot-frozen at scaffold time, future feature work is Flutter-only | Yes, trivially — because sync is abandoned | Design prototype becomes stale documentation; two people can no longer collaborate through the design tool; defeats the point of an authored-in-studio pipeline |
| **Bidirectional live sync** | Neither / both | Attempt to keep design and code simultaneously and automatically consistent | Historically no (RTE) | Semantic gaps, concurrent-edit conflicts, reverse-engineering fidelity loss; this is the option the MDE literature says doesn't scale past toy cases |
| **Generation-gap / protected-regions boundary** | Design, with a marked escape hatch | Scaffolder owns generated files/regions outright; a fixed set of "owned" files or marked blocks are never touched by regen | Yes, for changes that fit inside the boundary | Anything that needs to cross the boundary (e.g. a new screen needs custom logic *and* structural change) requires manual reconciliation; boundary must be designed well up front |
| **LLM-mediated merge (Copier+AI pattern)** | Design/spec, with mechanical 3-way merge + LLM-assisted conflict resolution on regen | Regen produces a diff against last-known-generated + current repo state; clean hunks auto-apply, conflicting hunks get LLM-proposed resolutions, human/policy approves | Yes, gracefully, for most real edits | Requires investment in tracking "last generated state" per file (a baseline, like Copier's `.copier-answers`) and a conflict-marker convention; agent proposals still need review for anything non-mechanical |

## Recommendation for this pipeline

Given a studio with a real embedded LLM agent, an htmx/JS design prototype that carries actual
structure, and a Flutter scaffolder: **design/structure remains SSOT, with regeneration governed by a
generation-gap-style boundary (clearly marked generated vs. owned Flutter files/regions) as the
default path, escalating to LLM-mediated three-way merge (Copier/Cruft pattern: diff against
last-generated baseline, auto-apply clean hunks, hand conflicting hunks to the studio agent for a
proposed resolution, require review before commit) for the cases that cross the boundary.** This is
the only option with real precedent at scale in both classic MDE (generation gap "won" over live RTE)
and current tooling (Copier/Cruft + AI-assisted conflict resolution is the concrete 2025–2026 analog
for exactly this problem). Pure full-regen and pure code-freeze are both known failure modes; live
bidirectional sync has no successful precedent to point to.

