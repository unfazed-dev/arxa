# appbox-studio-v2

The appbox studio, rebuilt fresh per the locked decision log
(`docs/plans/designer-scaffolder-grill-decisions.md`, Q-v2-1…5). v1
(`designs/appbox-studio/`) is candidates-only reference and is never copied.

## Recipe → web extension map (Q-v2-4)

The Q8 feature-recipe manifest (`kit/showcase_app/feature-recipe.manifest.json`)
is Dart-only and untouched. The studio *follows* the recipe as discipline. Its
folder/naming grammar is used verbatim **at this artifact root** — the
manifest's `lib/` prefix is a Dart-medium path, translated to the artifact root
by anatomy §1.

| recipe artifact type | Dart | web |
|---|---|---|
| view | `<app>_<surface>_view.dart` | `<app>_<surface>_view.tsx` |
| view, per DERIVED factor | `..._view.<factor>.dart` | `..._view.desktop.tsx` / `.tablet.tsx` / `.mobile.tsx` |
| viewmodel | `..._viewmodel.dart` | `..._viewmodel.js` |
| services / facades | `..._facade_service.dart` | `..._facade.js` |
| barrel | `widgets.dart` | `widgets.js` (category name — never `index`) |

## Vocabulary

**hub > shell > view > widgets.** "screen" and "page" are out of vocabulary
everywhere, including DOM attributes. The emit-time inspect triple is
`data-inspect-view` / `data-inspect-surface` / `data-inspect-widget` (Q-v2-5).

**rung** = one width variant of a view on the viewport ladder
(`rung--desktop` / `rung--tablet` / `rung--mobile`); all three are in the DOM
and CSS displays exactly one. Ratified skill vocabulary
(`.claude/skills/appbox-designer/references/viewport-ladder.md`) — kept after a
rename evaluation (`docs/plans/rung-to-viewport-sweep.md`).

## How a factor variant is selected

The design runtime has **no `<factor>` resolver** — `design_server.dart` serves
artifact files verbatim and there is no design-time codegen step. So a view
composes all three variants and **CSS selects exactly one**, on the Material 3
window-size-class boundaries (`< 600` mobile, `600–839` tablet, `>= 840`
desktop). This is the same mechanism the reference artifact uses to render both
`NavRail` and `BottomNav` and let CSS hide one. Nothing branches in JS; the
artifact stays island-only.

## Active rungs — a recorded, user-ruled override

`config/appbox.config.json` resolves `targets: ["macos"]`, which the viewport
ladder maps to **expanded only**. Q-v2-3 overrides it explicitly and by name:
"**Studio is recipe-conforming — NO desktop-only exception.** Every studio view
emits desktop/mobile/tablet variants like any showcase app (appbox functions
remotely)." So all three rungs are active here. This is a deliberate,
user-confirmed departure from the derived ladder, not an unread config —
recorded because the ladder doc's default reading would emit three files, not
five, per surface.

## Cutover (Q-v2-5)

Ceremony shells (startup, unknown, auth) first, then intake, then the design
shell. There is no flip or toggle: probe green is a *precondition*, and a shell
goes live only on explicit per-shell user validation. v1 is deleted only once
every shell is validated.

**AMENDED 2026-08-16 (owner ruling):** every shell landed **enabled** in one
pass — the staged one-at-a-time cutover was waived by the owner, with the
probe-green precondition satisfied in the same change set (12 lens rungs
clean, selftest green modulo git-tracking). v1 is retained in-tree as the
visual-parity reference rather than deleted; archiving is a later pass.
