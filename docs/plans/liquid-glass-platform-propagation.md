# Liquid-glass law — platform propagation (ratified 2026-08-13)

Everything the clip-0813 saga proved (native top chrome, informed allowlist,
materialization headroom, glass-on-glass, slide-never-fade) becomes reusable
arxa platform surface instead of showcase-local assembly. Grill rulings:

1. **Reuse unit = kit scaffold widget** `ArxaKitChromeScaffold` — one
   Scaffold-level widget (title/actions/body/fab/behavior in, ratified chrome
   out) with the tier branch INSIDE, because tier is runtime, not
   scaffold-time. Branches: Liquid Glass tier → `ArxaKitFloatingChrome`
   (full-bleed body, minimize default); Android → boxed
   `ArxaKitNativeAppBar` (renders `AppBarM3E` natively — M3 Expressive is
   first-class, not a fallback); other tiers → boxed Material bar.
2. **Law enforced as kit gates + lint rules** (gates-not-docs discipline):
   the kit's mechanical gate-test family grows a liquid-glass-law gate;
   `arxa-lint`'s playbook gains app-side rules. The law doc stays the
   rationale record the gates cite.
3. **Vocabulary**: the ruleset is the **liquid-glass law**
   (docs/liquid-glass-allowlist.md remains its SSOT file, retitled); the
   widget term is **chrome scaffold**. A sibling **M3E law** is opened for
   Android Material 3 Expressive with the kit's existing M3E findings as
   seed; it grows on device evidence like the liquid-glass law did.

## Phases

**P1 — kit widget (this session):** `ArxaKitChromeScaffold` + tests
(`debugForceGlassTier` seam for the glass branch; the boxed branch is the
test-env default), barrel export; showcase gallery chrome becomes a thin
consumer (dogfood proof). Scope note: v1 is for shell/tab-root surfaces —
no `leading`/back affordance on the glass branch; pushed routes keep
`Scaffold` + `ArxaKitNativeAppBar` until a floating back pattern is
device-ratified.

**P2 — law surfaces:** retitle the allowlist doc as the liquid-glass law;
INDEX.md row; VOCABULARY.md entries (liquid-glass law, chrome scaffold,
floating chrome, informed allowlist, tuck, materialization headroom);
open docs/m3e-law.md seeded from kit M3E findings.

**P3 — enforcement:** kit gate test (liquid-glass-law gate: saveLayer
widgets confined to their platform-view-safe homes) alongside the existing
transition gate; arxa-lint LINT_playbook liquid-glass section (app-side
rules: no BackdropFilter/partial-alpha over platform-view subtrees, chrome
via chrome scaffold, edge-aware lists with headroom under floating chrome).

**P4 — skills:** scaffolder kind registry note (appbar resolution gains the
shell-level chrome-scaffold pointer), scaffolder/builder playbook
cross-refs to the law. Each skill edit passes the SSOT gate check first.

## Sources
The law doc's evidence trail (clips 08-24 → 13-53-b), Flutter SDK
sliver_multi_box_adaptor.dart:739, engine FlutterPlatformViewsController.mm
(~:1011), Apple HIG Materials, WWDC25 219/284/356.
