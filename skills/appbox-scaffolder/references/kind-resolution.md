# Kind Resolution

## Kind resolution (Q7)

`kind-resolution.registry.json` maps the designer's closed kind vocabulary to real
kit-native widgets (`AppBoxKitNativeAppBar`, `AppBoxKitGlassCard`, `AppBoxKitListTile`,
…). Resolve through that table and nowhere else.

**An unresolvable kind is a FAIL that names the kind and the design node.** There is
no silent `Container()` fallback. A silent fallback yields a scaffold that compiles,
looks plausible, and is wrong — precisely the failure the gate stack exists to catch.
When the kit genuinely lacks a widget, use the registry's escape hatch: it emits, but
it warns with a reason, an owner and an expiry, and an expired escape fails the build.

Not every kind resolves to a single class. Three shapes resolve with `widget: null` —
`composedFrom` (a composition the scaffolder emits explicitly, never collapsing it to
one class), `presentation` (a route/overlay mode, not a subtree — this is what `modal`
is), and `variants`. **Every such shape must be named in `resolution.order`**; a shape
that is not listed falls through to FAIL and turns a correctly-authored kind into a
build break.

The kit-native widgets this table resolves to carry the iOS 26 liquid-glass
mechanics internally — theme-flip cures, popup-trigger construction, and the
rapid-flip settle replay (canon: `docs/plans/native-glass-theme-lag-measured.md`).
That is a second reason resolution through this table is mandatory and a
hand-rolled native widget is never an acceptable fallback: a scaffolded app
gets correct glass **by construction**, not by per-app effort. The vendored
package self-enforces the wiring:
`kit/ui_library/vendor/cupertino_native_better/tool/check_theme_wiring.sh`
fails on any under-wired brightness-handling view.

**Validate after any registry edit** (a real gate — it also rides `appbox gate --all` and CI):

```
appbox gate kind_registry
```

It checks the registry against its two ground truths — the partials directory
(`appbox-designer/starter-partials/widgets/_<kind>.tsx` *is* the vocabulary; never
hand-maintain a second copy of that list) and the real class names under
`kit/ui_library/lib` — and it rejects duplicate kind keys. That last check is not
theoretical: two entries were authored twice, and because `json.load()` silently keeps
the last duplicate, the careful entry vanished with no error and no merge conflict.
Prose review missed it both times.
