# Liquid Glass (iOS 26) — native wiring best practices

Research notes for app-box. Compiled 2026-08-10 from Apple primary sources (developer documentation + WWDC25 session transcripts). Everything below is either a direct quote, a paraphrase of a cited Apple page, or an explicitly labelled repo observation / community report.

**Source legend**

| Tag | Source |
| --- | --- |
| `[ALG]` | [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass) — Technology Overviews |
| `[CUSTOM]` | [Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views) — SwiftUI |
| `[W219]` | WWDC25 219 — [Meet Liquid Glass](https://developer.apple.com/videos/play/wwdc2025/219/) |
| `[W284]` | WWDC25 284 — [Build a UIKit app with the new design](https://developer.apple.com/videos/play/wwdc2025/284/) |
| `[W323]` | WWDC25 323 — [Build a SwiftUI app with the new design](https://developer.apple.com/videos/play/wwdc2025/323/) |
| `[W356]` | WWDC25 356 — [Get to know the new design system](https://developer.apple.com/videos/play/wwdc2025/356/) |
| `[SYMBOL]` | An individual Apple symbol reference page, linked inline at the point of use |
| `[REPO]` | Observed in this repository — not Apple guidance |
| `[COMMUNITY]` | Third-party developer report — **not confirmed by Apple docs** |
| `[INFERENCE]` | Reasoned from Apple material, **not stated by Apple** |

---

## 1. The mental model: glass is a layer, not a texture

Liquid Glass "forms a distinct functional layer for controls and navigation elements" and "applies to the topmost layer of the interface, where you define your navigation." Key navigation elements "float in this Liquid Glass layer to help people focus on the underlying content." `[ALG]`

Apple's design guidance is explicit that this is a *scarcity* rule, not a stylistic one:

> "It's tempting to use Liquid Glass everywhere but it is best reserved for the navigation layer that floats above the content of your app. Consider this tableview: making it Liquid Glass would make it compete with other elements and muddy the hierarchy. So keep it in the content layer instead to ensure clarity." `[W219]`

**Establish a clear navigation hierarchy.** "It's more important than ever for your app to have a clear and consistent navigation structure that's distinct from the content you provide. Ensure that you clearly separate your content from navigation elements, like tab bars and sidebars, to establish a distinct functional layer above the content layer." `[ALG]`

### 1.1 Never glass-on-glass

This is the single most explicit prohibition Apple states:

> "Similarly, always avoid glass on glass. Stacking Liquid Glass elements on top of each other can quickly make the interface feel cluttered and confusing. When placing elements on top of Liquid Glass, avoid applying the material to both layers. Instead, use fills, transparency, and vibrancy for the top elements to make them feel like a thin overlay that is part of the material." `[W219]`

Restated in the docs as: "Check for crowding or overlapping of controls. Prefer to use standard spacing metrics instead of overriding them, and avoid overcrowding or layering Liquid Glass elements on top of each other." `[ALG]`

### 1.2 Why: the sampling mechanism

The mechanism explains most visual bugs. From `[W323]`:

> "The glass material reflects and refracts lights, picking colors from nearby content. **This effect is achieved by sampling content from an area larger than itself. However, glass can not sample other glass**, so having nearby glass elements in different containers will result in inconsistent behavior. Using a glass container allows these elements to share their sampling region, providing a consistent visual result."

Three consequences follow directly:

1. Two glass surfaces near each other but in **different containers** render inconsistently — each samples an area the other occupies, and gets nothing usable there.
2. A glass surface **on top of** another glass surface cannot sample it, so the top surface loses its refraction cue.
3. A **single container** is the fix for both: it makes the enclosed effects share one sampling region.

---

## 2. Containers: correctness first, performance second

### SwiftUI

`GlassEffectContainer` "combines multiple Liquid Glass shapes into a single shape that can morph individual shapes into one another." Apple's instruction: "Use `GlassEffectContainer` when applying Liquid Glass effects on multiple views to achieve the best rendering performance. A container also allows views with Liquid Glass effects to blend their shapes together and to morph in and out of each other during transitions." `[CUSTOM]`

WWDC is blunter about the priority order: "To combine multiple glass elements, use the `GlassEffectContainer`. **This grouping is essential for visual correctness.**" `[W323]`

**Spacing semantics** `[CUSTOM]`:

- "The larger the spacing value on the container, the sooner the Liquid Glass effects behind views blend together and merge the shapes during a transition."
- "A spacing value on the container that's larger than the spacing of an interior `HStack`, `VStack`, or other layout container **causes Liquid Glass effects to blend together at rest** because the views are too close to each other."
- So: container `spacing` > layout `spacing` = merged blobs at rest. Container `spacing` ≈ layout `spacing` = merge only during motion. This is the knob for "why are my two buttons fused into one pill."

**Modifier ordering (easy to get wrong)**: "The `glassEffect(_:in:)` modifier captures the content to send to the container to render. **Apply the `glassEffect(_:in:)` modifier after other modifiers that affect the appearance of the view.**" `[CUSTOM]`

### UIKit

- [`UIGlassEffect`](https://developer.apple.com/documentation/uikit/uiglasseffect) — "A visual effect that renders a glass material." Applied via `UIVisualEffectView(effect:)`. Configurable shape, tint, and `isInteractive`.
- [`UIGlassContainerEffect`](https://developer.apple.com/documentation/uikit/uiglasscontainereffect) — the container analogue. Glass effect views go in the container view's `contentView`; the container effect exposes a `spacing` property with the same semantics as SwiftUI's.

### Unions vs. IDs vs. transitions

Three distinct modifiers, frequently confused `[CUSTOM]`:

| Modifier | Purpose |
| --- | --- |
| [`glassEffectUnion(id:namespace:)`](https://developer.apple.com/documentation/swiftui/view/glasseffectunion(id:namespace:)) | Fuse several views into **one capsule at rest**. "Especially useful when creating views dynamically, or with views that live outside of a layout container." |
| [`glassEffectID(_:in:)`](https://developer.apple.com/documentation/swiftui/view/glasseffectid(_:in:)) | Identity for **morphing during transitions**. "These IDs ensure SwiftUI animates the same shapes correctly when a shape appears or disappears due to view hierarchy changes." |
| [`glassEffectTransition(_:)`](https://developer.apple.com/documentation/swiftui/glasseffecttransition) | Transition *type*: `matchedGeometry` (default, for effects within the container's spacing) or `materialize` (for effects farther apart than the spacing). |

Critical scoping note: "The `glassEffectID(_:in:)` and `glassEffectTransition(_:)` modifiers **only affect their content during view hierarchy transitions or animations**." `[CUSTOM]` They are inert at rest — if you want a fused shape at rest you need `glassEffectUnion`, not `glassEffectID`.

---

## 3. Performance and cost

Apple's complete published performance guidance on this topic is one paragraph `[CUSTOM]`:

> "Creating too many Liquid Glass effect containers and applying too many effects to views outside of containers can degrade performance. Limit the use of Liquid Glass effects onscreen at the same time. Additionally, optimize how your app spends rendering time as people use it."

Referred onward to [Explore UI animation hitches and the render loop](https://developer.apple.com/videos/play/tech-talks/10855/) and [Optimize SwiftUI performance with Instruments](https://developer.apple.com/videos/play/wwdc2025/306/).

**Apple publishes no numeric threshold** — no "max N glass surfaces," no per-surface cost figure, no rasterization or energy budget for glass specifically. Any such number circulating is not from Apple. What Apple *does* commit to:

- Too many **containers** is a cost, not just too many effects. Consolidating into one container is cheaper than many containers, and one container is also what buys visual correctness (§1.2). The two goals point the same way.
- Effects applied to views **outside** any container are called out as the other cost source.
- The scaling advice is qualitative: "Limit the use of Liquid Glass effects onscreen at the same time."

Apple gives no guidance recommending manual rasterization of glass surfaces; the material is dynamic and content-sampling by definition, so caching it defeats its purpose. Treat rasterization tradeoffs as unsupported/undocumented territory.

---

## 4. Bars: let the system own them

### 4.1 Remove custom backgrounds — this is the headline UIKit rule

> "Reduce your use of custom backgrounds in controls and navigation elements. Any custom backgrounds and appearances you use in these elements might overlay or interfere with Liquid Glass or other effects that the system provides, such as the scroll edge effect. Make sure to check any custom backgrounds in elements like split views, tab bars, and toolbars. **Prefer to remove custom effects and let the system determine the background appearance**, especially for the following elements:" `[ALG]`

The enumerated list is: [`NavigationStack`](https://developer.apple.com/documentation/SwiftUI/NavigationStack), [`NavigationSplitView`](https://developer.apple.com/documentation/SwiftUI/NavigationSplitView), [`titleBar`](https://developer.apple.com/documentation/SwiftUI/WindowStyle/titleBar), [`toolbar(content:)`](https://developer.apple.com/documentation/SwiftUI/View/toolbar(content:)), [`UINavigationBar`](https://developer.apple.com/documentation/UIKit/UINavigationBar), [`UITabBar`](https://developer.apple.com/documentation/UIKit/UITabBar), [`UIToolbar`](https://developer.apple.com/documentation/UIKit/UIToolbar), [`UISplitViewController`](https://developer.apple.com/documentation/UIKit/UISplitViewController), `NSToolbar`, `NSSplitView`.

WWDC restates it for toolbars: bars "are now transparent, contain liquid glass buttons, and give more space to your content" `[W284]`; and for sheets, "If you've used the `presentationBackground` modifier to apply a custom background to your sheets, consider removing that and let the new material shine." `[W323]`

`[REPO]` This repo already implements the rule correctly for the tab bar. `kit/ui_library/vendor/cupertino_native_better/ios/cupertino_native_better/Sources/cupertino_native_better/Views/CupertinoTabBarPlatformView.swift:130-137`:

```swift
let appearance: UITabBarAppearance? = {
  // iOS 26+: assigning ANY custom UITabBarAppearance (even transparent-
  // configured) opts the bar out of the system Liquid Glass pill ->
  // opaque legacy rendering. Let UIKit own the appearance entirely.
  if #available(iOS 26.0, *) { return nil }
  if #available(iOS 13.0, *) { return self.makeAppearance() }
  return nil
}()
```

The later `bar.standardAppearance = ap` / `bar.scrollEdgeAppearance = ap` assignments are all guarded by `if let ap = appearance`, so on iOS 26+ nothing is assigned. This is a deliberate, load-bearing workaround that matches Apple's stated guidance — **do not "fix" it by reintroducing a transparent `UITabBarAppearance`.**

### 4.2 `scrollEdgeAppearance` vs `standardAppearance`

[`UINavigationBar.scrollEdgeAppearance`](https://developer.apple.com/documentation/uikit/uinavigationbar/scrolledgeappearance) — "The appearance settings for the navigation bar when the edge of scrollable content aligns with the edge of the navigation bar."

> "When a navigation controller contains a navigation bar and a scroll view, part of the scroll view's content appears underneath the navigation bar. If the edge of the scrolled content reaches that bar, UIKit applies the appearance settings in this property. **If the value of this property is `nil`, UIKit uses the settings found in the `standardAppearance` property, modified to use a transparent background.** If no navigation controller manages your navigation bar, UIKit ignores this property and uses the standard appearance of the navigation bar. […] In iOS 15, this property applies to all navigation bars."

Read that inheritance rule carefully: leaving `scrollEdgeAppearance` as `nil` is not "unconfigured," it is an active instruction to derive a transparent variant of `standardAppearance`. On iOS 26 the correct move per §4.1 is to set **neither** property and let the system supply the glass appearance. Setting both to the same object (a common iOS 15-era idiom) defeats the scroll-edge transition entirely, because there is then no difference between the pinned and scrolled states.

iOS 26 also adds a `scrollEdgeAppearance` property to `UITabBar`, which exists mainly as an opt-*out* to force an opaque look.

### 4.3 Scroll edge effects

This is the mechanism that keeps bar content legible over scrolling content, and it is a system behaviour you enable rather than draw.

> "Elements using Liquid Glass require clear separation from content to maintain legibility. Like in Safari today, controls sit on top of a system material, not directly on content. Without that separation, contrast can suffer. Scroll edge effects reinforce that boundary, replacing hard dividers with subtle blur to reduce clutter and keep UI legible. And remember, **scroll edge effects are not decorative. They don't block or darken like overlays.** They simply clarify where UI and content meet, and shouldn't be used where there aren't any floating UI elements. Scroll views automatically show an edge effect when pinned controls overlap them. You'll see two styles across the system, soft and hard. **You should avoid mixing or stacking them on top of each other.**" `[W356]`

APIs:

- [`ScrollEdgeEffectStyle`](https://developer.apple.com/documentation/swiftui/scrolledgeeffectstyle) — [`automatic`](https://developer.apple.com/documentation/swiftui/scrolledgeeffectstyle/automatic) (default; system picks by platform and context), [`hard`](https://developer.apple.com/documentation/swiftui/scrolledgeeffectstyle/hard) ("a more opaque, clearly defined linear boundary"), [`soft`](https://developer.apple.com/documentation/swiftui/scrolledgeeffectstyle/soft) ("a subtle blurred transition").
- [`scrollEdgeEffectStyle(_:for:)`](https://developer.apple.com/documentation/swiftui/view/scrolledgeeffectstyle(_:for:)) — override the automatic style "when the automatic style the system applies isn't appropriate for your content and controls."
- [`scrollEdgeEffectHidden(_:for:)`](https://developer.apple.com/documentation/swiftui/view/scrolledgeeffecthidden(_:for:)) — "Hides any scroll edge effects for scroll views within this hierarchy"; the `ScrollEdgeEffectStyle` page describes it as removing "the scroll edge effect entirely for an edge you specify."
- **For custom bars**, register the container so the effect knows their shape `[ALG]`:
  - [`safeAreaBar(edge:alignment:spacing:content:)`](https://developer.apple.com/documentation/SwiftUI/View/safeAreaBar(edge:alignment:spacing:content:)) (SwiftUI)
  - [`UIScrollEdgeElementContainerInteraction`](https://developer.apple.com/documentation/UIKit/UIScrollEdgeElementContainerInteraction) (UIKit) — "Add this interaction to a container view of views that overlay the edge of a scroll view. Any descendants of this view that should affect the shape of the edge effect, such as labels, images, glass views, and controls, will automatically do so."

`[COMMUNITY]` A widely repeated tip holds that `ToolbarItem(placement: .bottomBar)` activates the scroll edge effect while `.safeAreaInset(edge: .bottom)` suppresses it. Apple's own documented lever for custom bars is `safeAreaBar` / `UIScrollEdgeElementContainerInteraction`; prefer those.

### 4.4 Tab bar: minimize behavior and bottom accessory

> "With the new design, the tab bar on iPhone floats above the content, and can be configured to minimize on scroll, keeping the focus on your content. To allow the tab bar to minimize on scroll set `tabBarMinimizeBehavior` to the desired direction. Here, the TV app is setting it to `.onScrollDown`. The tab bar re-expands when scrolling in the opposite direction. Above the tab bar, you can have an accessory view like the mini player in the Music app. `UITabBarController` displays the accessoryView above the tab bar, matching its appearance. When the tab bar is minimized, the […]" `[W284]`

| Concern | UIKit | SwiftUI |
| --- | --- | --- |
| Minimize on scroll | `UITabBarController.tabBarMinimizeBehavior` | [`tabBarMinimizeBehavior(_:)`](https://developer.apple.com/documentation/swiftui/view/tabbarminimizebehavior(_:)) taking a [`TabBarMinimizeBehavior`](https://developer.apple.com/documentation/swiftui/tabbarminimizebehavior) |
| Accessory above bar | `UITabBarController.bottomAccessory` + [`UITabAccessory`](https://developer.apple.com/documentation/uikit/uitabaccessory) | [`tabViewBottomAccessory(content:)`](https://developer.apple.com/documentation/swiftui/view/tabviewbottomaccessory(content:)) |
| Collapsed/expanded state | `UITabAccessory.Environment` | `tabViewBottomAccessoryPlacement` environment value |
| Adapt to sidebar | [`UITabBarController.Mode.tabSidebar`](https://developer.apple.com/documentation/UIKit/UITabBarController/Mode-swift.enum/tabSidebar) | [`sidebarAdaptable`](https://developer.apple.com/documentation/SwiftUI/TabViewStyle/sidebarAdaptable) |

Accessory placement `[SYMBOL: tabViewBottomAccessory(content:)]`: "On iPhone, the placement of the bottom accessory depends on the tab bar size: when the tab bar is normal size, the accessory appears above it; when the tab bar is collapsed, the accessory displays inline. Use the […] environment value to adjust the accessory's content based on its placement."

**Values.** SwiftUI's [`TabBarMinimizeBehavior`](https://developer.apple.com/documentation/swiftui/tabbarminimizebehavior) documents exactly four: [`automatic`](https://developer.apple.com/documentation/swiftui/tabbarminimizebehavior/automatic), [`never`](https://developer.apple.com/documentation/swiftui/tabbarminimizebehavior/never), [`onScrollDown`](https://developer.apple.com/documentation/swiftui/tabbarminimizebehavior/onscrolldown), [`onScrollUp`](https://developer.apple.com/documentation/swiftui/tabbarminimizebehavior/onscrollup). For the UIKit property only `never` / `onScrollDown` / `onScrollUp` were confirmed from the sources gathered here; the UIKit symbol page could not be resolved, so do not assume the UIKit value set matches SwiftUI's without checking headers.

Direction choice: `onScrollDown` collapses on downward scroll and is right for top-anchored content; `onScrollUp` is recommended when a scroll view's content is aligned to the bottom.

Note the minimize behaviour only engages when the bar actually overlays scrolling content — it "doesn't minimize with the old (pre-Liquid Glass) design, because it didn't overlay any scrolling content."

### 4.5 Bar stability across pushes — what is and isn't established

Apple documents no special iOS 26 mechanism for keeping bars stable across navigation pushes; the standard `UINavigationController` / `hidesBottomBarWhenPushed` model is unchanged in the docs. The following are **community reports, not Apple guidance**, gathered from search result summaries of Apple Developer Forums threads that could not be fetched directly (the forums are behind a bot check), so they are second-hand and unverified:

- `[COMMUNITY]` [Forum thread 805740](https://developer.apple.com/forums/thread/805740): with `hidesBottomBarWhenPushed`, during an interactive swipe-back the tab bar reappears as soon as the previous view controller becomes visible, and stays visible and interactable briefly even if the gesture is cancelled. Reported as still present on iOS 26.1 RC.
- `[COMMUNITY]` [Forum thread 791643](https://developer.apple.com/forums/thread/791643): a standalone `UITabBar` used **without** a `UITabBarController` does not receive the Liquid Glass blur when scrollable content passes behind it; the effect appears correctly only under `UITabBarController`.

If bar re-creation during route transitions is the symptom being chased, the defensible inference from Apple's own material is narrower: the glass appearance is owned by the system bar controller, so anything that tears down and rebuilds the bar controller (or reassigns its appearance objects mid-transition) forfeits both the glass rendering and the scroll-edge state. Keep one bar controller instance alive across the transition rather than trying to restore its appearance afterwards.

---

## 5. Interaction, tint, and shape

**Interactive glass is *supposed* to move.** "Glass reacts to user interaction by scaling, bouncing, and shimmering, matching the effect provided by toolbar buttons and sliders." `[W323]` `Glass.interactive(_:)` / `UIGlassEffect.isInteractive` opt a custom surface into exactly this. Scale/bounce/shimmer **on touch** is by design and is not a bug.

Genuine artifacts trace to a different, enumerable set of causes:

| Symptom | Documented cause |
| --- | --- |
| Inconsistent look between neighbouring glass surfaces | Nearby glass in **different containers** — they cannot sample each other `[W323]` |
| Cluttered, muddy, low-contrast overlay | **Glass on glass** stacking `[W219]` |
| Mismatched or doubled edge treatment | **Mixing or stacking** soft and hard scroll edge styles `[W356]` |
| Opaque/legacy bar rendering, or edge effect fighting the bar | **Custom background or appearance** on a system bar `[ALG]`, `[REPO]` |
| Shapes fused when they should be separate | Container `spacing` larger than the interior stack's spacing `[CUSTOM]` |
| Glass effect ignoring a modifier | `glassEffect(_:in:)` applied **before** appearance-affecting modifiers `[CUSTOM]` |

**Tint sparingly.** "Review your use of color in controls. Be judicious with your use of [color] in controls and navigation so they stay legible. If you do apply color to these elements, leverage system colors, or define a custom color with light and dark variants, and an increased contrast option for each variant." `[ALG]` Apple frames tint as semantic: "Assign a tint color to suggest prominence." `[CUSTOM]`

**Prefer system button styles over hand-rolled glass.** "Instead of creating buttons with custom Liquid Glass effects, you can adopt the look and feel of the material with minimal code by using one of the following button style APIs" `[ALG]`: [`.glass`](https://developer.apple.com/documentation/SwiftUI/PrimitiveButtonStyle/glass), [`.glassProminent`](https://developer.apple.com/documentation/SwiftUI/PrimitiveButtonStyle/glassProminent), [`glass(_:)`](https://developer.apple.com/documentation/SwiftUI/PrimitiveButtonStyle/glass(_:)), and UIKit's [`UIButton.Configuration.glass()`](https://developer.apple.com/documentation/UIKit/UIButton/Configuration-swift.struct/glass()), [`prominentGlass()`](https://developer.apple.com/documentation/UIKit/UIButton/Configuration-swift.struct/prominentGlass()), [`clearGlass()`](https://developer.apple.com/documentation/UIKit/UIButton/Configuration-swift.struct/clearGlass()), [`prominentClearGlass()`](https://developer.apple.com/documentation/UIKit/UIButton/Configuration-swift.struct/prominentClearGlass()).

**Concentric shapes.** "Across Apple platforms, the shape of the hardware informs the curvature, size, and shape of nested interface elements… Help maintain a sense of visual continuity in your interface by using rounded shapes that are concentric to their containers using these APIs" `[ALG]`: [`rect(corners:isUniform:)`](https://developer.apple.com/documentation/SwiftUI/Shape/rect(corners:isUniform:)), [`ConcentricRectangle`](https://developer.apple.com/documentation/SwiftUI/ConcentricRectangle), [`UIView.cornerConfiguration`](https://developer.apple.com/documentation/UIKit/UIView/cornerConfiguration-7l0ja), [`UICornerConfiguration`](https://developer.apple.com/documentation/UIKit/UICornerConfiguration-swift.struct). `[W356]` gives the rule of thumb: a capsule's radius is half the container height, and "concentric shapes calculate their radius by subtracting padding from the parent's."

**Toolbar item grouping.** `UIBarButtonItem.hidesSharedBackground` — "A boolean value indicating whether the background this item may share with other items in the bar should be hidden." Bar items share one glass background by default; this opts an item out. (SwiftUI's equivalent separator is `ToolbarSpacer`.)

**Edge-to-edge content.** [`backgroundExtensionEffect()`](https://developer.apple.com/documentation/swiftui/view/backgroundextensioneffect()) — "views can extend outside the safe area, without clipping their content. […] The image is mirrored and blurred outside of the safe area, extending the artwork while leaving all its content visible." `[W323]` Use this for hero imagery under a sidebar/inspector rather than manually stretching content.

---

## 6. Accessibility and validation

"Test your interface with a variety of display and accessibility settings. Translucency and fluid morphing animations contribute to the look and feel of Liquid Glass, but can adapt to people's needs. For example, people can choose a preferred look for Liquid Glass in their device's settings, or turn on accessibility settings that reduce transparency or motion in the interface. These settings can remove or modify certain effects. **If you use standard components from system frameworks, this experience adapts automatically. Ensure you test your app's custom elements, colors, and animations with different configurations of these settings.**" `[ALG]`

Concretely: Reduce Transparency, Increase Contrast, Reduce Motion. Every custom glass surface in `kit/` is outside the automatic-adaptation guarantee and must be checked under all three.

`[REPO]` Simulator caveat, from `CupertinoTabBarPlatformView.swift:120-125`:

> "NOTE on the iOS simulator: the simulator renders Liquid Glass with a software rasterizer and positions the pill slightly differently than real Metal hardware. You may see residual top-edge clipping on simulator that is NOT visible on a real iOS 26+ device. Always verify Liquid Glass behaviour on hardware before treating a visual artifact here as a bug."

Treat this as a hard gate: **no Liquid Glass visual bug is confirmed until it is reproduced on device.**

---

## 7. Rules for app-box

### Do

1. **One container per logical cluster of glass.** A toolbar, a tab bar, a button group, a floating island — each gets exactly one `GlassEffectContainer` / `UIGlassContainerEffect`. This is the same move for both visual correctness and rendering performance. `[W323]`, `[CUSTOM]`
2. **Let the system own system bars.** On iOS 26+, assign no `UITabBarAppearance` / `UINavigationBarAppearance` at all. `CupertinoTabBarPlatformView.swift:130-137` already does this deliberately — preserve it. `[ALG]`, `[REPO]`
3. **Keep the bar controller instance alive across route transitions.** Glass appearance and scroll-edge state are system-owned properties of the live bar controller; rebuilding it forfeits both. `[INFERENCE]` — Apple states no iOS 26 rule about bar persistence across pushes; this is reasoned from how bar appearance ownership is described in §4.1–4.2. See §8.
4. **Reach for system button styles first** (`.glass`, `.glassProminent`, `UIButton.Configuration.glass()`) before hand-rolling a glass surface. `[ALG]`
5. **Register custom bars for the scroll edge effect** with `safeAreaBar` (SwiftUI) or `UIScrollEdgeElementContainerInteraction` (UIKit), so descendants shape the effect automatically. `[ALG]`
6. **Order modifiers so `.glassEffect(_:in:)` comes last**, after anything affecting appearance. `[CUSTOM]`
7. **Match container `spacing` to the interior stack's spacing** unless deliberate at-rest fusion is wanted. `[CUSTOM]` `GlassButtonGroupView.swift:175-177` passes `effectiveSpacingForGlass` to the `GlassEffectContainer` while the interior `HStack` uses `viewModel.spacing` — defaults 40 (raised to ≥80 for horizontal bars of ≥2 buttons, line 93) versus 8 (line 66), both overridable from Dart via the `spacingForGlass` / `spacing` keys. That asymmetry is deliberately what fuses the pill, and it is the first lever to check when a group fuses or separates unexpectedly. `[REPO]`
8. **Use `glassEffectUnion` for at-rest fusion and `glassEffectID` for transitions** — they are not interchangeable, and `glassEffectID` does nothing at rest. `[CUSTOM]`
9. **Use system colors or tints with light/dark + increased-contrast variants** for any tinted glass. `[ALG]`
10. **Verify on device** before filing any glass rendering bug. `[REPO]`
11. **Test Reduce Transparency, Increase Contrast, and Reduce Motion** against every custom glass primitive in `kit/`. `[ALG]`

### Don't

1. **Don't stack glass on glass.** For anything layered over a glass surface, use fills, transparency, and vibrancy instead. `[W219]`
2. **Don't put glass in the content layer.** Lists, cards, table rows, and content backgrounds stay non-glass. `[W219]`
3. **Don't assign a custom `UITabBarAppearance`/`UINavigationBarAppearance` on iOS 26+**, not even a transparent-configured one — it opts the bar out of the system glass pill into opaque legacy rendering. `[REPO]`, `[ALG]`
4. **Don't set `scrollEdgeAppearance` and `standardAppearance` to the same object.** That erases the pinned-vs-scrolled distinction the scroll edge effect depends on. `[SYMBOL: UINavigationBar.scrollEdgeAppearance]`, `[INFERENCE]`
5. **Don't mix or stack `hard` and `soft` scroll edge styles** in one hierarchy. `[W356]`
6. **Don't create many small containers.** Apple names "too many Liquid Glass effect containers" as a cost source in its own right. `[CUSTOM]`
7. **Don't apply glass effects to views outside any container.** Named as the other performance cost source. `[CUSTOM]`
8. **Don't cite a numeric glass budget.** Apple publishes none — no max count, no per-surface cost. Any figure in circulation is third-party.
9. **Don't try to rasterize or cache glass.** It samples live content by design; Apple documents no caching approach.
10. **Don't treat interactive scale/bounce/shimmer on touch as a bug.** That is `interactive()` working as specified. `[W323]`
11. **Don't rely on `hidesBottomBarWhenPushed` behaving as it did pre-26** without testing the interactive swipe-back path — reported broken by developers, unconfirmed by Apple. `[COMMUNITY]`
12. **Don't use a standalone `UITabBar` without a `UITabBarController`** and expect glass — reported not to receive the effect. `[COMMUNITY]`

---

## 8. Open questions

- Apple's forums (threads 805740, 791643) are behind a bot check and could not be fetched; both `[COMMUNITY]` claims in §4.5 rest on third-party search summaries and should be reproduced locally before being acted on.
- No Apple source found stating a maximum glass surface count, a GPU/energy cost per surface, or guidance on rasterization tradeoffs. §3 records the absence rather than filling it.
- Apple documents no iOS 26-specific mechanism for bar persistence across navigation pushes; rule 7.3 is an inference from how bar appearance ownership is described, not a quoted instruction.
- The UIKit symbol page for `UITabBarController.tabBarMinimizeBehavior` could not be resolved at any tried path, so its full value set is unconfirmed. SwiftUI's `TabBarMinimizeBehavior` documents `automatic` / `never` / `onScrollDown` / `onScrollUp`; confirm the UIKit enum against headers before relying on `automatic` there.
- All Apple documentation prose here was extracted through the DocC JSON API (`developer.apple.com/tutorials/data/documentation/<path>.json`), resolving inline `reference` nodes against each page's top-level `references` map. The rendered HTML pages are client-rendered and yield no usable text — worth knowing for the next person refreshing this file.
