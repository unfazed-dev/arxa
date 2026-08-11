# Bottom-dock handoff: message dock vs. tab bar

## Symptom (device, 2026-08-11)

Profile → Components. The message dock (`AppBoxKitNativeInputBar`) and the
floating tab bar drew on the same pixels — the tab bar's pill covered the
bottom of the input row.

## Root cause

Two independent bars both want the bottom of the screen, and neither knows
about the other:

- the tab bar is `bottomNavigationBar` of the host `Scaffold`
  (`showcase_application_tab_host_widget.dart`), which sets `extendBody: true`
  so the body runs under it;
- Components is a *nested* `Scaffold` inside that body, pinning the input bar
  as its `bottomSheet` — which therefore lands inside the same region.

The old mitigation was a fixed `Padding(bottom: kShowcaseTabBarBlockHeight)`
(64) on the input bar. A constant can only approximate the bar's real block:
on iOS the tab bar + home indicator is closer to 83pt, so 64 leaves the two
overlapping. `Scaffold` never insets its body for a `bottomSheet`, so nothing
else was compensating either.

## Fix (per the user's call: the top dock wins)

The host tab bar yields the slot when the **active tab's top route** pins its
own bar:

```dart
bottomNavigationBar: _docksOwnBar(tabsRouter.topRoute.name)
    ? const SizedBox.shrink()
    : AppBoxKitNativeTabBar(...)
```

and the input bar drops its 64pt lift, so it sits on the bottom edge (its own
`SafeArea` covers the home indicator). The Components list's bottom clearance
drops 160 → 96 for the same reason.

### Why `topRoute`, not a claim counter

The obvious shape — a route bumps a shared "I own the dock" counter while
mounted — is the **C2 shape** from `glass-chrome-root-cause-fixes.md`: tab
bodies live in an `IndexedStack`, so Components stays mounted after a tab
switch and would hold the dock in every tab, stranding the user with no tabs.
`TabsRouter.topRoute` descends into the active tab only
(`stacked/…/routing_controller.dart:457`), so the yield is per-tab **by
construction** rather than by a guard that can be forgotten.

It also dodges the mid-build notification hazard fixed the same day in
`modal-depth-notify-during-build.md`: a counter bumped from `initState` would
notify during the build phase, which is exactly the crash just repaired.

### No listener

`build` re-runs on every nav change already: a nested push calls `notifyAll`,
which notifies the root controller (`routing_controller.dart:79-81`), and the
root delegate rebuilds this subtree. Swapping in a listenable that never fires
left both handoff tests green, so the `ListenableBuilder` first written here
was inert decoration and was removed (`7dc403a`).

## Cost, accepted

- **No tab switching on Components** — back is the only way out. This is the
  direct consequence of the user's "the top one wins" call.
- **The native tab bar is destroyed and re-created** across that boundary
  (`SizedBox.shrink()` unmounts `CNTabBar`), which the kit's own docs say
  "visibly hitches". It happens during the push/pop transition, where the
  chrome gate is hiding the bar anyway.

## Verification

`showcase_bottom_dock_handoff_test.dart` — two tests, both booting the real
router:

1. tab bar up on Home (anti-vacuous) → gone on `/profile/components`, input bar
   present **and its rect reaches the bottom edge**;
2. navigating on to `/home` with Components still on the profile stack brings
   the tab bar back — the per-tab scoping guard.

Mutations run against a committed tree:

| Mutation | Result |
|---|---|
| never yield (`_docksOwnBar(...)` → `false`) | both tests fail ✅ |
| always yield (→ `true`) | both tests fail ✅ |
| restore the input bar's 64pt lift | passed at first — **gap**; fixed by adding the bottom-edge assertion, then fails ✅ |
| listenable that never fires | passed — the listener was inert; code deleted rather than the test weakened |
| "global" scope via `root.isRouteActive` | passed, but it is not a faithful global mutation: auto_route's route-activity is URL-scoped, so it already answers per-active-tab. With a top-down `topRoute` read the cross-tab leak is structurally unreachable — test 2 guards against a future refactor back to a claim counter, not against a reachable state today. |

Suite: showcase 123, analyze clean.

## Found, not fixed (out of scope)

`/profile` **root** overflows by 92px in `AppBoxKitNativeToolbar`
(`appbox_kit_native_toolbar.dart:202`, a `Row`) at phone width (390pt).
Confirmed with a throwaway probe that only navigates to `/profile` and never
enters Components, so it is independent of this change. It is why the handoff
test takes its baseline from Home.
