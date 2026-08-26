# Genuine MVVM artifact structure

Artifacts use a faithful MVVM transliteration (Razor Views PageModel is the surviving precedent): View = dumb template; ViewModel = stateless per-request server module (context builders + handlers) co-located with its view under `ui/views/<shell>_shell/<surface>/`; Model = shapes + fixtures under `models/`; Services = `repositories/` + `facades/`, with ViewModels touching facades only. Surface-private swap targets are Named Fragments inside the view file (Template Fragments essay); `_partial.html` files only for genuinely shared widgets; the Shell is the layout tier between `base.html` and surfaces; a central `app.routes.js` keeps the URL inventory greppable. Form-factor file variants are dropped in favor of one template + responsive CSS. Considered and rejected: fully declarative artifacts + generic engine (a manifest DSL contorts real business logic — payout tie-outs, role exclusions), declarative core + `.py` plugins (two authoring modes, plugin-boundary FAQ).

## Addendum — 2026-08-16: the five-file factor split supersedes the one-template clause

The paragraph above's "form-factor file variants are dropped in favor of one
template + responsive CSS" clause is **superseded** by the five-file factor
split canon: every studio view carries a base `<surface>_view.tsx` plus one
DERIVED variant per active rung (`_view.desktop.tsx`, `_view.tablet.tsx`,
`_view.mobile.tsx`) plus its `_viewmodel.js`, with CSS — not a `<factor>`
resolver — selecting exactly one rung in the DOM (Q-v2-3; the scaffolder's
per-factor derivation is the Dart-medium mirror). Sources:
`skills/arxa-designer/SKILL.md` (five-file set),
`designs/arxa-studio-v2/intake/emit-findings.md` (translation table), and
the Q-v2-3 no-desktop-only-exception ruling. Everything else in this ADR —
the MVVM tiers, the co-location law, the Named-Fragment swap targets, the
routes inventory — stands unchanged.
