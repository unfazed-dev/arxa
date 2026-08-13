# Showcase-wide liquid-glass law application

Ratified 2026-08-13. Mandate: apply THE liquid-glass law (`docs/liquid-glass-allowlist.md`)
to every showcase view/shell, fanning out subagents. Android/M3E is deferred to a later
session by explicit user instruction.

## Baseline

Compliant already: the gallery chrome (`showcase_gallery_chrome_widget.dart` →
`AppBoxKitChromeScaffold`) and the three tab-root lists under it
(home/search/profile `*_view.mobile.dart`, `extendBehindTopBar: true`).

Non-compliant surface: six files still assemble their own `appBar:`:

1. `showcase_notes_shell/showcase_notes/showcase_notes_view.mobile.dart`
2. `showcase_notes_shell/showcase_notes_folder/showcase_notes_folder_view.mobile.dart`
3. `showcase_notes_shell/showcase_note_editor/showcase_note_editor_view.mobile.dart`
4. `showcase_profile_shell/showcase_components/showcase_components_view.mobile.dart`
5. `showcase_profile_shell/showcase_motion/showcase_motion_view.mobile.dart`
6. `showcase_profile_widgets/showcase_maps_body_widget.dart`

## Phases

- **S1 Survey (agent `law-survey`)** — classify each file: shell/tab root vs pushed
  route; native glass in scroll content; scrollable type; law-pass greps 1/2/4 over
  showcase lib; routing map (which views sit under the gallery chrome).
- **S2 Migrate (parallel agents, clustered by shell)** — shell/tab roots →
  `AppBoxKitChromeScaffold`; their lists → `AppBoxKitEdgeAwareListView` with
  `extendBehindTopBar: true` + `MediaQuery.paddingOf(context).top` padding. Pushed
  routes: lawful boxed bar stays IF no native glass rides the scroll; otherwise demote
  the in-scroll glass per the informed allowlist or record `// glass-law-exempt:`.
  The scaffold has no leading slot (v1) — pushed routes are NOT migrated to it.
- **S3 Gate** — showcase test suite + kit law gate + lint law-pass greps green;
  single-line commit.

## Survey verdicts (S1, agent law-survey, 2026-08-13)

- Notes shell returns a bare NestedRouter (no gallery chrome) — the tab root view
  migrates to `AppBoxKitChromeScaffold` at the VIEW level ("Folders" title), which
  also avoids handing folder/editor the gallery double-bar stack. Bar-less auth
  branches are lawful and stay untouched.
- Folder view (#2): lawful as-is (boxed bar + Flutter-only scroll; pinned search
  bar is chrome per §1). Maps (#6): lawful (no scrollable). Editor (#3): lawful —
  SingleChildScrollView clips, never sliver-culls, so rule 4 cannot fire; recorded
  as a `glass-law-exempt` comment at the scaffold shell.
- Components (#4): rule 4 (plain ListView cull seam under boxed bar) + rule 5 HIT
  (fixed native input-bar bottomSheet over in-scroll native buttons' travel path).
- Motion (#5): rule 4 + rule 1 HIT (`.wakeAll()` FadeTransition — spec.fade
  defaults true — over the replay card's two native buttons). Fix is targeted
  fade-off for that scope, never a kit-default change.
- Greps: saveLayer over platform views — zero hits; no glass-law-exempt comments
  existed anywhere in showcase before this pass.
- Headroom under a boxed NATIVE bar is lawful (native chrome covers overdraw by
  UIView z-order); the #86787 flash applies only to Flutter-drawn bars.

## S2 assignments

- fix-notes-root → #1 chrome-scaffold migration. DONE (analyzer clean, 14/14).
- fix-components → #4 rule 5 fixed (`AppBoxKitNativeInputBar.wantNative: false`,
  icon buttons stay native per the rule 5 carve-out); rule 4 correctly REFUSED —
  see correction below. DONE otherwise (6/6).
- fix-motion → #5 rule 1 fixed (three wakeAll segments; `spec.copyWith(fade:
  false)` on slots 4-8, covering BOTH the replay card's native buttons and the
  spec-controls segmented control); rule 4 refused likewise. DONE (2/2).
- Inline → #3 exemption comment (done).

## Correction (S2): AppBoxKitNativeAppBar is Flutter-drawn

Both fix agents independently established the brief's premise wrong: the boxed
bar renders CupertinoNavigationBar (pure Flutter; law §1 row agrees), so
`extendBehindTopBar` under it would land overdraw ON screen — the clip 13-32
flash class. Rule 4 therefore stayed open on components + motion.

## S3 ruling (user, 2026-08-13): ratify the floating back affordance

Chosen over exemption and over demoting §2-allowlisted buttons. Work:

1. Agent kit-leading-slot: `leading` slot on AppBoxKitNativeFloatingBar (does
   NOT tuck under minimize — back stays reachable, Apple parity; hides under
   hide) + `leading`/`bottomSheet` on AppBoxKitChromeScaffold (boxed tier:
   `automaticallyImplyLeading: false`); doc comments updated (pushed-route
   scoping superseded); tests; full ui_library suite.
2. Re-task fix-components / fix-motion: migrate their views to
   AppBoxKitChromeScaffold(leading: back) with full-bleed bodies →
   `extendBehindTopBar: true` now lawful + glass-tier top padding.
3. Follow-through: law §1 table row for the scaffold's leading, registry note
   ("bare widget for pushed routes" is superseded), gate/docs/tests, commit.

## Device-pass watch items (from S3 agents)

- Long titles overflow the floating bar's non-flex title pill row (pre-existing;
  the leading slot makes it 52px worse). Fixing means deciding what "2.0x own
  width" tuck offset means under Flexible — geometry call against a device clip.
- `extendBehindTopBar` is unconditional on the migrated views (matches the
  ratified gallery pattern), so BOXED tiers paint 64px overdraw under an opaque
  Flutter bar — check Android/pre-26 iOS for 13-32-class artifacts.
- Components input bar demoted via `wantNative: false` renders the Material
  capsule (solid), not a frosted pill — restyle only if the device pass objects.
- MediaQuery padding under the chrome must be read BELOW the scaffold (Builder
  wrap) — the floating chrome raises padding.top for its body subtree only.
