# Late-binding practices for deferred capability decisions in multi-stage pipelines

Research question: in a pipeline where an early stage (design/prototype) deliberately runs on
fakes/seeds and a later stage (production build) must bind real integrations, where should the
"which real services does this app use" decision live?

## 1. Seams and fakes — ports and adapters (hexagonal architecture)

The pattern is well established: the application core exposes **ports** (interfaces); **adapters**
are swappable implementations of those ports, and a fake/in-memory adapter is a first-class
adapter, not a lesser stand-in. The recommended discipline is "one port, two adapters" — every
port gets a real adapter and a fake/test adapter, proving the domain logic is independent of
infrastructure before infrastructure exists. Real adapters can be built and bound at any later
point without touching the application, because the application only ever depended on the port.

A concrete late-binding case: a frontend team ran entirely on static fake adapters while waiting
on backend APIs. When the real "standings" endpoint shipped, they flipped **one toggle in an
adapter registry** — no component code changed, and the page started running on real data. The
fakes stayed in the repo afterward for tests and Storybook, so the fake path never actually goes
away — it becomes the permanent dev/test lane, and production is a registry entry pointing at the
real adapter instead of a phase you graduate out of.

**Implication for the kit pipeline:** the decision of *which concrete adapter backs a port* is a
runtime/config binding (a registry entry, a DI wiring, an env-selected implementation), not a
decision baked into the design-stage artifact. The design stage should only need to know *which
ports it depends on*, never *which adapters back them*.

Sources: [Optivem — Hexagonal Architecture: Ports and Adapters](https://journal.optivem.com/p/hexagonal-architecture-ports-and-adapters), [Gui Ferreira — Understanding Hexagonal Architecture](https://guiferreira.me/archive/2026/understanding-hexagonal-architecture-a-guide-to-ports-and-adapters/), [Saad Hasan — Ports and Adapters with Two Real Codebases](https://saadh393.github.io/blog/adapter-port-architecture-two-cases), [Juan Manuel Garrido de Paz — Hexagonal Architecture](https://jmgarridopaz.github.io/content/hexagonalarchitecture.html)

## 2. Last responsible moment (LRM) and set-based concurrent engineering

From Poppendieck's *Lean Software Development*: delay commitment until **the moment at which
failing to decide eliminates an important alternative** — not later (default-by-inaction) and not
earlier (premature commitment on conjecture instead of fact). The nuance that matters most here:
LRM applies to **irreversible or costly-to-change** decisions; anything already reversible through
encapsulation/abstraction doesn't need this ceremony because it was never a real commitment point.

Set-Based Concurrent Engineering (Toyota/Lean Construction) generalizes this to design itself:
keep multiple design alternatives alive simultaneously, narrow only when an alternative is proven
inferior or infeasible, and make the final selection using explicit criteria (Choosing by
Advantages, cost/benefit, stakeholder feedback) at the point of maximum information — not upfront.

**Caveat surfaced in the research (important, not just a footnote):** LRM is frequently misused to
justify procrastination. The Ben Morris piece is explicit that LRM should resolve genuine
*uncertainty*, not defer a decision the team already has enough information to make. Applied here:
if a kit already knows at design time which integration a template requires (e.g., "this seed
requires an LLM provider" is knowable from the seed itself), deferring that decision isn't LRM —
it's just latency. The identity of *ports* can be decided early (design time, since the seed
defines them); only the identity of the *bound adapter* is genuinely uncertain until the user or
environment supplies it, so that's the piece that should defer.

Sources: [Coding Horror — The Last Responsible Moment](https://blog.codinghorror.com/the-last-responsible-moment/), [Effective Software Design — Lean Software Development: Before and After the LRM](https://effectivesoftwaredesign.com/2014/03/27/lean-software-development-before-and-after-the-last-responsible-moment/), [Ben Morris — LRM should address uncertainty, not justify procrastination](https://www.ben-morris.com/lean-developments-last-responsible-moment-should-address-uncertainty-not-justify-procrastination/), [Lean Construction Institute — Set-Based Design](https://leanconstruction.org/lean-topics/set-based-design/), [Lean Enterprise Institute — Set-Based Concurrent Engineering](https://www.lean.org/lexicon-terms/set-based-concurrent-engineering/)

## 3. Design-to-code tools: how binding actually happens post-design

**Figma Dev Mode** never binds live integrations at all — it exports visual specs (CSS, tokens,
measurements) and increasingly treats handoff as continuous collaboration (Storybook/Jira
integrations) rather than a single moment. Figma's model doesn't have a "which backend" decision
because Figma isn't a runtime; it's out of scope for this comparison except as a negative case
(design tools that never touch integration binding at all).

**Plasmic** is the closer analogy and the strongest pattern of the three: the *design-first,
bind-later* workflow. A designer builds a template against placeholder elements/slots with named
overrides; a developer later renders that same template via a component API and substitutes real
dynamic data — same visual artifact, swapped data source, no redesign. Plasmic's "code
components" formalize this further: a code component can fetch from arbitrary data sources
(including the app's own production API) and is registered once, then reused across designs
without the designer needing to know which concrete API backs it.

**Builder.io** takes a more CMS-centric approach — data binding happens through an explicit "Data
tab" / "Element data bindings" panel where a field is bound to a content entry, with a toggle to
"use existing data" instead of typing values inline directly in the visual editor.

**Implication:** both tools separate *the placeholder/slot the design declares* from *the concrete
data source wired to it later*, and both give the binder (not the designer) an explicit,
inspectable step (a props override / a data-binding panel) rather than silently inferring it.

Sources: [Plasmic — Using Plasmic with dynamic data sources](https://docs.plasmic.app/learn/using-with-data-sources/), [Plasmic — Querying data with code components](https://docs.plasmic.app/learn/data-code-components/), [Plasmic — Dynamic data-driven pages with code components](https://docs.plasmic.app/learn/dynamic-pages-code/), [Builder.io — Bind Data](https://www.builder.io/c/docs/data-binding-entries), [Figma — Guide to developer handoff](https://www.figma.com/best-practices/guide-to-developer-handoff/)

## 4. Installer/wizard UX: detected vs. recommended vs. manual

The literature converges on a **three-tier reconciliation pattern**, which is the most directly
applicable prior art for "detected + suggested + user-picked":

1. **Auto-detect and pre-fill whatever the system can determine with confidence** (Vercel/Netlify
   framework detection from repo contents; Krystal Higgins' point that most systems no longer need
   a wizard step at all *because* detection covers it — e.g. mobile app installs need no wizard
   because the OS mediates everything).
2. **Present a "recommended" default path that works via next→next→finish** for the common case,
   without requiring the user to understand the underlying mechanism (Vercel: detected framework
   silently sets build command + output directory; user never opens the override panel unless
   something's wrong).
3. **Offer an explicit, clearly-labeled override/manual branch** for the cases detection gets
   wrong or the user has non-default needs — critically, this is framed as an **escape hatch**, not
   a parallel first-class flow: Vercel falls back to "Other" + an enabled override toggle only when
   detection fails; a GitHub Discussion on the Vercel CLI notes real user friction when *no*
   override exists at deploy time and users are forced into the web UI settings panel instead.

Two design warnings apply directly to a kit-selection screen: (a) wizards should not "help" users
with things they already know how to do — support the power-user escape hatch explicitly, don't
force everyone through the guided path; and (b) never present a wizard purely to explain a
concept — users treat wizard screens as a task to complete, not documentation to read, so the
detected/recommended/manual choice needs to be a real decision point with consequences, not an
FYI screen.

Sources: [LogRocket — Creating a setup wizard (and when you shouldn't)](https://blog.logrocket.com/ux-design/creating-setup-wizard-when-you-shouldnt/), [Krystal Higgins — The design of setup wizards](https://www.kryshiggins.com/the-design-of-setup-wizards/), [UX Planet — Wizard Design Pattern](https://uxplanet.org/wizard-design-pattern-8c86e14f2a38), [Vercel — Configuring a Build](https://vercel.com/docs/builds/configure-a-build), [Vercel — Project Configuration](https://vercel.com/docs/project-configuration), [Netlify — Build configuration overview](https://docs.netlify.com/build/configure-builds/overview/), [GitHub Discussion — override framework when Vercel CLI can't read it](https://github.com/vercel/vercel/discussions/5198)

## 5. Terraform plan/apply as a review-before-commit analogy for derived changes

Terraform's core discipline is **write → plan → apply**, where `plan` computes a declarative diff
between current and desired state before anything is touched. The safety pattern that matters most
here is the **saved-plan discipline**: `terraform plan -out=tfplan`, review the saved plan (often
attached to a PR), then `terraform apply tfplan` — applying the *exact reviewed plan*, not a fresh
plan computed at apply time, because state can drift between the two moments. A frequently cited
failure mode is letting `plan` become "just another CI log entry nobody reads," which defeats the
review checkpoint entirely — the fix used in practice is an explicit manual-approval gate between
plan and apply, not just visibility.

**Implication:** the analog for a kit pipeline is a **derived-plan artifact** — something like "kit
resolve" that computes and displays exactly which adapters/services would be bound, as a reviewable
diff, before the production build step consumes it. Whatever the design stage infers (detected +
recommended selections) should produce this artifact rather than being silently re-derived at
build time, and the build step should consume the *reviewed* artifact, not re-run detection itself
— otherwise the same drift-between-plan-and-apply risk Terraform users are warned about applies
here too.

Sources: [HashiCorp — Overview of the core Terraform workflow](https://developer.hashicorp.com/terraform/intro/core-workflow), [DevOps.dev — Implementing Manual Approval in GitHub Terraform Pipelines](https://blog.devops.dev/implementing-manual-approval-in-github-terraform-pipelines-7c01e6946ead), [OneUptime — How to Test Terraform Plans Before Applying](https://oneuptime.com/blog/post/2026-02-23-how-to-test-terraform-plans-before-applying/view), [OneUptime — Plan and Apply Stages in CI/CD](https://oneuptime.com/blog/post/2026-02-23-how-to-implement-plan-and-apply-stages-in-cicd-for-terraform/view)

## Synthesis: where the "which real services" decision should live

Putting the five threads together, the decision decomposes into two separable decisions that the
research consistently keeps apart:

- **Which ports exist** (what capabilities a seed/template needs — e.g. "needs an LLM provider,"
  "needs a datastore") is knowable from the design artifact itself and should be declared **at
  design time**, in the design/seed artifact. This is not a deferrable decision — the LRM
  literature's own caveat says deferring a decision you already have the information to make isn't
  discipline, it's procrastination.
- **Which concrete adapter backs each port** is the genuinely uncertain, environment-dependent
  piece, and every pattern surveyed defers *this* piece specifically: hexagonal architecture defers
  it to a registry/DI binding; Plasmic defers it to a post-design render-time override; Terraform
  defers it to `apply` time but only against a previously reviewed `plan`; installer wizards defer
  it to an explicit but overridable "detected → recommended → manual" screen.

The strongest reconciliation pattern is the same across all five areas: **detect what you can,
propose a default that requires zero decisions from the common-case user, and always expose an
inspectable, overridable manual path** — and, per Terraform, capture the *result of that
reconciliation as a reviewable artifact* consumed verbatim by the later production stage, rather
than re-inferring it at build time. Concretely for this pipeline: the design/prototype stage
declares ports and runs on fakes; a "resolve" step (analogous to `terraform plan`) computes
detected/recommended adapter bindings as a reviewable, user-editable artifact; the production build
stage consumes that artifact as-is (analogous to `terraform apply tfplan`), never re-detecting on
its own. That is where the "which real services" decision lives: in the resolve artifact, decided
once between design and build, not smeared across either stage.
