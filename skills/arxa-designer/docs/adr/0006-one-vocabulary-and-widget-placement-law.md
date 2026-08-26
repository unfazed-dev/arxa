# One vocabulary and the widget placement law

**Widget** is the one term for a reusable UI piece, everywhere: an HTML
macro/partial in the design medium, a Dart class in the build medium — one
concept, two mediums. **Component** is retired from every doc and every path
on both sides of the pipeline (`starter-partials/components/` →
`starter-partials/widgets/`); the drift between the designer's "component"
and the scaffolder's "widget" was the root cause of misaligned chips across
studio shells, not a cosmetic mismatch. A widget lives at the narrowest scope
that covers all its consumers; the include/import graph is the only
authority, checked in both directions — this generalizes gate S10's
sole-consumer overlay rule from the scaffolder to the whole pipeline, design
side included. Originally three tiers, identical shape on both mediums:

| scope | design medium | build medium |
|---|---|---|
| cross-shell (2+ shells) | `ui/common/widgets/` | `lib/ui/widgets/` |
| intra-shell (2+ surfaces) | `ui/views/<shell>/shared/widgets/` | `<shell>/shared/widgets/` |
| per-surface (1 surface) | `<surface>/widgets/` | `<view>/widgets/` |

> **AMENDED — the table above is superseded; do not follow it.**
>
> The three-tier law was written before `kit/showcase_app/lib` was adopted as
> the structure contract (grill decision Q1). The exemplar has **no**
> `ui/common/widgets/`, **no** `<shell>/shared/widgets/` and **no**
> `<view>/widgets/`; those paths are now illegal on both mediums. The law is
> **two tiers**:
>
> | scope | design + build medium |
> |---|---|
> | cross-shell (2+ shells) | `ui/widgets/common/<group>/` |
> | everything else (one feature) | `ui/widgets/<app>_<feature>_widgets/` |
>
> A single-consumer widget stays in its feature's widgets folder — there is no
> per-surface tier to demote it to, so the scaffold-side demotion check
> described below narrows to a promotion check only. Everything else in this
> ADR — one vocabulary, include-graph-as-sole-authority, bidirectional
> checking, no speculative empty tiers — stands unchanged.
> Current law: [`references/showcase-anatomy.md`](../../references/showcase-anatomy.md) §2.

Bare `<shell>/widgets/` is illegal on both sides — it names no graph
authority a widget could be checked against. Empty tiers are never created
speculatively: a widget with one consumer stays with that consumer until a
second consumer earns it promotion.

Panels are the load-bearing case of the law, not an exception to it: the five
roles — header, main, activity, composer, footer — are thin instantiations of
one cross-shell base widget (`_panel.html`), never re-implemented per shell.
A panel owns its own internal UI state; a shell owns its own state plus
panel-level state (which panels are mounted, their sizes), all server-side
per ADR-0004.

Enforcement lives at three checkpoints so the law cannot silently regress at
any one of them: the designer skill's own docs instruct authors where a new
widget belongs before they write it; the design-side W-gate (W1–W6, wired
into `design lint`) hard-fails placement by include-count in both
directions, dead widgets, `.panel-*` markup outside `_panel.html`, and
session-key namespacing; the scaffold-side gate (S6) gains the same
scope-truth check the design side already has — a sole-consumer widget found
in `shared/widgets/` fails and must demote to `<view>/widgets/`. Widget,
panel and shell are the user-facing terms too, not just internal ones; any
arxa-branded alternative name is confined to a presentation-layer brand
glossary table in `VOCABULARY.md` (term → display name) that nothing
mechanical — code, file names, gates, docs — ever reads. Considered and
rejected: keeping "component" for the design medium and "widget" for the
build medium as a permanent two-word system (the drift this ADR fixes was
exactly that split, not a naming preference), and a downward-only placement
rule that lets a widget be pushed to a narrower scope without a consumer
check (leaves placement co-managed by graph and discretion instead of graph
alone).
