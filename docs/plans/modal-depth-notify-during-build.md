# Dialog crash: modal depth notified during build

## Symptom (device, 2026-08-11)

Tapping **Show dialog** on the Overlays card (Profile → Components showcase):

```
FlutterError (setState() or markNeedsBuild() called during build.
This CNTextField widget cannot be marked as needing to build because the
framework is already in the process of building widgets. …
The widget on which setState() or markNeedsBuild() was called was: CNTextField
The widget which was currently being built when the offending call was made
was: Builder)
```

## Root cause

`ArxaKitFrostedAlertDialog` brackets its own lifetime, bumping the shared depth
from `initState` (`arxa_kit_native_dialog.dart:180`) and releasing it in
`dispose`. That is the right place for a bracket — it is the only pairing that
survives every exit path — but **the framework runs `initState` during the build
phase**.

`CNTabBarRouteObserver.anyModalDepth` was a plain `ValueNotifier`, which notifies
**synchronously**. So the bump marked every listener dirty mid-build. Those
listeners call `setState`:

| Listener | Site |
|---|---|
| `CNTextField` | `text_field.dart:194-195` |
| `ModalHideMixin` | `modal_hide_mixin.dart:83` |
| `ArxaKitNativeChromeGate` | `arxa_kit_native_chrome_gate.dart:234` |
| `ArxaKitScrollOcclusionGate` | `arxa_kit_scroll_occlusion_gate.dart:118` |

Any of them mounted on the **host page** was built earlier in the same frame, and
dirtying an already-built widget is illegal — the framework throws. The showcase's
Components view has exactly that: an `ArxaKitNativeInputBar` wrapping a
`CNTextField`, sitting on the page the dialog opens over.

**Pre-existing, not a regression.** The listener arrived in `1357b39` and the
`initState` bump in `8db466a`; neither is from the sheet work. It needs a native
text field on the presenting page to fire, which is why it surfaced only now.

## Fix

One change at the choke point rather than a guard on each listener:
`anyModalDepth` is now backed by `_ModalDepthNotifier`
(`vendor/…/components/tab_bar.dart`), which

- updates `value` **synchronously**, so a gate reading it in its own `initState`
  still snapshots the bumped depth as its mount baseline — the behaviour
  `arxaKitShowNativeDialog` relies on and documents; and
- defers `notifyListeners()` to a post-frame callback **only** when the change
  lands during `SchedulerPhase.persistentCallbacks`, coalescing several bumps in
  one frame into a single notification.

A bump from a tap handler or after an async gap — the common path, since both
`arxaKitShowSheet` and `arxaKitShowNativeDialog` mark *before* pushing —
notifies immediately, exactly as before. `dispose` is covered by the same path,
which matters because unmount runs in the build phase too.

Every `_anyModalDepth.value = …` assignment was converted; the analyzer found the
three in the observer's own route bumps that the first pass missed.

## Consequence worth knowing

A host embedding `ArxaKitFrostedAlertDialog` directly (stacked `DialogService`,
`popOnAction: false`) has no preceding mark, so its listeners now react one frame
later. One frame of native chrome staying visible, against a hard crash.

## Verification

`arxa_kit_native_dialog_test.dart` records `SchedulerBinding.schedulerPhase` at
every notification and asserts none arrives during `persistentCallbacks`. It is
phrased against the phase rather than by mounting a `CNTextField` because the
widget at fault is a `UiKitView` that cannot render headless, and the defect is
the notification timing — which endangers all four listeners, not just that one.

Mutation-checked: forcing synchronous notification fails the test. It also
asserts the notification is not merely *absent* (`phases, isNotEmpty`), so a
change that stopped moving the depth entirely cannot pass it vacuously.

`arxa_kit_native_overlay_test.dart` gained
`TestWidgetsFlutterBinding.ensureInitialized()`: its plain `test()`s now reach a
scheduler lookup, and Flutter's own error text prescribes exactly that. No
assertion changed — outside a frame the phase is `idle`, so those tests still
exercise synchronous notification.

Suites: ui_library 305, vendor 121, showcase 120; analyze clean.
