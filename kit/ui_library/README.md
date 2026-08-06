# appbox_kit_ui_library

The shared `Kit*` widget surface for `appbox_kit` apps — the UI widgets split
out of `core` in the 2026-07 refactor. A standalone kit.

## Reactive views

- `AppBoxKitStreamBuilder<T>` — thin `StreamBuilder` wrapper that auto-seeds from a
  rxdart `ValueStream.valueOrNull` (no loading flash on `BehaviorSubject`-
  backed kit-data streams) and shares a default loading/error UI.

View bodies render kit-data / async streams via `AppBoxKitStreamBuilder`, never raw
`StreamBuilder` (enforced by review_checklist check 1k + scaffold_gate check
5). Use stacked's stock `StreamViewModel<T>` when the viewmodel itself reacts
to / transforms a single dominant stream; `MultipleStreamViewModel` is banned
(stringly-keyed). Bootstrap exception: a raw `StreamBuilder` wrapping
`MaterialApp.router` stays raw — its loading fallback has no `Directionality`
ancestor.
