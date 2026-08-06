# appbox_kit_ui_library/ — AGENTS.md

Nested schema for the UI tier. Repo-wide contract: `../AGENTS.md`; the verified
map: `../skills/_kit-system.md`. This file owns the native-first widget rules.
The component inventory is `COMPONENTS.md`; the canonical tier matrix + ban
list is `../core/NATIVE_COMPONENTS.md` — read it before reaching for any
primitive.

## Native-first (the rule)

- Reach for the `AppBoxKitNative*` widget or `appBoxKitShowNative*` function **before** any
  stock Flutter widget — real Liquid Glass on iOS 26, real M3 Expressive on
  Android, a kit-owned fallback elsewhere. The gates enforce every ✅ matrix
  row (`../skills/kit-designer/scripts/enforce_design.dart` 4f/4g,
  `../skills/kit-reviewer/scripts/review_checklist.sh` 1c–1y): a stock
  `AppBar`, `TextField`, `Switch`, `showModalBottomSheet(`, … in an app
  surface fails the gate.
- Content surfaces (tile / card / banner / panel) compose on **`AppBoxKitGlassCard`**
  — never a hand-rolled `Material(color:)` or decorated `Container(` card
  (gate: `no_raw_card_surface`).
- Deliberate plain Flutter opts out per-widget with a
  `// flutter-only: <reason>` comment (→ `wantNative: false`) or per-surface
  with the designer's `--flutter-only`. Native-first is otherwise the default.

## The AppBoxKitNative* wrapping pattern

- Three tiers per widget: iOS (vendored `cupertino_native_better`, self-gates
  real glass on iOS 26) → Android M3E (`m3e_collection`, resolved to the
  vendored `*_m3e` forks via root `dependency_overrides`) → Flutter fallback
  (Cupertino/Material stock). The widget's own doc comment names its tiers.
- Public surfaces are **primitives only** (labels, glyphs, values, callbacks)
  — hosts never import `m3e_collection` or `cupertino_native_better`.
- `wantNative` is the host opt-out; a `null` callback disables the control on
  every tier.
- Icons go through `glyph: AppBoxKitGlyphs.<x>` — one token pairing the Material
  icon with its SF Symbol; raw `icon:`/`sfSymbol:` are per-call overrides.
- No native tier exists → the widget is named `Kit*`, **never** `AppBoxKitNative*`
  (the `no_invented_native_widgets` allowlist; `AppBoxKitImage` is the example).

## Vendored forks — never consumed directly

`vendor/` holds six packages (ADR-0002): `cupertino_native_better` and
`text_field_m3e` (path deps) plus `fab_m3e`, `split_button_m3e`,
`toolbar_m3e`, `navigation_rail_m3e` (reached transitively through the
`m3e_collection` umbrella via root `dependency_overrides`). Consume them
**only** through the `AppBoxKitNative*` family — never by direct import, never by
path-dep'ing a fork from an app.

## Theme

Host apps take light/dark themes from `appBoxKitLightTheme()` / `appBoxKitDarkTheme()`
(`../core/lib/common/appbox_kit_colors.dart`) driven by `AppBoxKitThemeService`
(`../core/lib/services/theme/appbox_kit_theme_service.dart`); M3E motion cascades
from the expressive theme set once at the app top. Do not hand-build
`ThemeData` in a kit app.

## Adding a native surface

One row in `../core/NATIVE_COMPONENTS.md` **and** one ban row in
`_nativeSurfaceBans` (`enforce_design.dart`) — matrix and guard stay in
lockstep — plus the widget, the `lib/appbox_kit_ui_library.dart` barrel export, and a
`COMPONENTS.md` row.

## AppBoxKitAction — the operation convention (opinionated)

Every async operation in a kit app runs through the `action(name, operation)`
helper (from `AppBoxKitViewModel` / the `AppBoxKitActionOwner` mixin) — no hand-rolled
`setBusy`/try-catch guards in viewmodels, no bare `Timer` debounces, no
hand-managed `StreamSubscription`s where `watch` fits, and **no hand-written
widgetId strings or `owner: this` at call sites**.

- **Ownership:** the `AppBoxKitActionOwner` mixin (on `AppBoxKitViewModel`, `AppBoxKitDataFacade`,
  and adapters/services via `with AppBoxKitActionOwner`) passes `owner: this` for
  you. Ops take a short name label (`'save'`; entity ops append the id:
  `mutate(..., name: 'pin', entity: note.id)` on facades,
  `action('save.$noteId', ...)` elsewhere). The registry key derives as
  `RuntimeType#identityHash.name` — the identity hash keeps two live instances
  of the same VM class (a view pushed twice) from sharing a guard. The static
  `AppBoxKitAction.run(() => ..., widgetId: ...)` form is for ownerless boot ops
  (`main()`) only.
- **Awaitable builder:** `AppBoxKitActionBuilder` implements `Future` — awaiting
  the chain executes it, so app code has **no `.execute()` terminal**:
  `await action('signIn', () => _auth.signIn(...)).completeOnError('...')`.
  `.execute()` remains for fire-and-forget handles inside non-async methods.
  The reactive/cancellable forms are single-call terminals: `.toStream()` /
  `.toCancellable()`.
- **Error API — two jobs, two names:** `.completeOnError('msg', withValue: v)`
  decides the OUTCOME (completes with the fallback instead of throwing; `msg`
  feeds the log/snackbar/state stream). `.handleError((error) => ...)` is a
  side-effect tap (single param; the stack trace is already logged by the
  error service).
- **Auto-dispose:** viewmodels extend `AppBoxKitViewModel` (not `BaseViewModel`
  directly) — its `dispose()` calls `disposeKitActions()`, killing every
  subscription and state subject the VM's ops created. Services with their
  own `dispose()` (adapters, facades) call `disposeKitActions()` there
  (`AppBoxKitDataFacade.dispose` already does).
- **Re-entry guard is default-on** per op key (the Flutter Command /
  command_it rule): an overlapping execution on the same key is dropped —
  silently when the chain has `completeOnError`, else it throws
  `AppBoxKitGuardedException`. Opt out per chain with `.withParallelExecution()`.
- **Facade mutations go through `AppBoxKitDataFacade.mutate`** with the
  notification policy as params: `mutate(() => ..., name:, entity:, error:,
  success:)` — `error:` on EVERY mutation (errors always surface),
  `success:` only for destructive / confirm-worthy ops, `fallback:` to
  swallow with an error identity (completeOnError parity). It dispatches on
  the facade's action hub and returns a hot observation handle
  (`Future<T>`) — already running, awaiting optional.
- **Busy/error state is a stream:** inside a viewmodel use the
  `actionState$('<name>')` helper; views bind it with `AppBoxKitStreamBuilder`.
  `.withLoading(setBusy)` remains for stacked-busy consumers but new code
  binds the stream.
- **Debounce:** `.withDebounce(...)` — always pair it with
  `completeOnError`, or each superseded call completes with an error.
- **Streams:** `watch(name, streams:, callback:)` is for VM-internal side
  effects (navigation triggers, resetting UI-state subjects) — never to feed
  view data (views bind streams directly). Dependent re-subscription
  (session → data) composes with rxdart `switchMap` into ONE stream first —
  never nest listeners.
- **Boot order:** `appBoxKitLocator<AppBoxKitErrorService>().initialize()` must run before
  any AppBoxKitAction error path can fire (its Talker is late-initialized) — see
  the showcase app's `main.dart`.
- **Tests:** register `FakeAppBoxKitNotificationService` **as** `AppBoxKitNotificationService`
  (`registerLazySingleton<AppBoxKitNotificationService>(...)` — getIt keys on the
  explicit type) and never the real one; the real service's CNToast path needs
  a mounted navigator context.

## Streams-only views (opinionated)

Views/viewmodels are built with **streams only** (operator override
excepted): viewmodels expose `Stream`/`ValueStream` getters — facade
pass-throughs, rxdart compositions, seeded `BehaviorSubject`s for UI-owned
state — and never call `notifyListeners`. Views keep `StackedView<VM>` with
`@override bool get reactive => false;` and bind every live value with
`AppBoxKitStreamBuilder<T>` at the subtree that needs it. `AppBoxKitStreamBuilder` seeds
from `ValueStream.hasValue` (no loading flash, even for seeded-null) and
treats emitted null as data once the stream is active. Stacked's
`StreamViewModel`/`ReactiveViewModel` are NOT the convention (they rebuild
the whole tree via `notifyListeners` internally); `MultipleStreamViewModel`
stays banned (stringly-keyed). **MVVM boundary:** a view file imports only
its viewmodel (plus kit packages and sibling view/widget files) — the
viewmodel re-exports every payload type the view must name.

The showcase app (`../showcase_app`) is the reference implementation.

## Testing

`lib/appbox_kit_testing.dart` ships scriptable fakes — `FakeAppBoxKitNotificationService`,
`FakeAppBoxKitBottomSheetService`, `FakeAppBoxKitNavigationControllerService`. Register
them in the appBoxKitLocator; tests never touch a navigator, an `Overlay`, or platform
channels.
