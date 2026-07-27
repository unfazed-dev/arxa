# Prototype language: HTML/JSX vs Stacked Flutter — measured

p2 has all three producers for the *same* application, built by the same author
inside the same three-day window (2026-07-24 → 2026-07-27). That is an unusually
clean natural experiment, so these are measurements rather than estimates.

| | JSX/React `new` | HTMX `new-htmx` | Stacked Flutter `new-flutter` |
|---|---|---|---|
| screens reached | 83 registry / 47 frozen | 37 frozen | 42 views |
| authoring LOC | 13,181 | 4,350 | 25,032 |
| **LOC per screen** | **159** | **118** | **596** |
| commits to get there | 8 | 4 | **25** |
| compile step | none | none | 5 s analyze warm; minutes cold |
| **reviewable artifacts** | **47 HTML** | **37 HTML** | **0** |
| source size | 11 MB | 11 MB | 2.8 MB + 319 MB build |

## Token cost

Authored LOC is a fair proxy for output tokens. **Flutter costs 3.7× JSX and 5.0×
HTMX per screen.** For a 47-surface app that is roughly 28,000 versus 7,500 lines
of generated code — and the three-directions-first discipline multiplies whatever
the exploration phase costs by three.

The Flutter figure is not padded by scaffolding alone: it includes viewmodels,
services and fixtures that the HTML producers genuinely do not need. But that *is*
the cost of prototyping in the target architecture.

## Time

The compile step is the smaller difference (5 s warm analyze), but it is not the
real cost. The real cost is the **25 commits versus 8** to reach comparable
coverage — 3× the iterations for fewer screens.

## The asymmetry that outranks both

**`new-flutter` produced zero reviewable artifacts.** No frozen surfaces, no
rendered screenshots — only app icons and launch images. To review a Flutter
prototype somebody must build and run it.

This is not incidental. The frozen-design intake contract *is* HTML
(`surfaces/*.html`), so a Flutter producer structurally cannot satisfy it. Either
the contract changes to screenshots, or the Flutter producer is never the frozen
input. For client work this compounds: a client can open 47 HTML files in a
browser on any device. They cannot run a Flutter app.

## The counter-argument, stated fairly

HTML is cheap, fast and reviewable — and then it has to become Dart. That
translation is the single hardest problem measured in this whole assessment:
flutter-crew's translator captured **7 of 112 nodes** on a real p2 surface,
because the JSX was branch-matrixed on `role × state × params.branch`.

Prototyping in Flutter has a translation gap of exactly zero. The prototype *is*
the app. That is worth a great deal, and it is why the 3.7× is not automatically
the wrong trade.

## The resolution the numbers actually point at

The translation gap only exists because something tried to make the HTML
prototype **authoritative**. If the HTML is explicitly throwaway — exploration
only, never translated — the gap disappears rather than being closed.

That suggests: explore in HTML at 118–159 LOC/screen across three directions,
then author the *approved direction only* in Flutter. Nothing is ever translated;
the expensive language is paid for once, on one direction, instead of three.

The cost of that choice is honest and should be stated: the Flutter authoring
stays model-driven, which is exactly where stacked_kit is today, and therefore
carries no determinism. The deterministic-emitter work is not avoided by this —
it is deferred to the phase where the design is already frozen and approved.
