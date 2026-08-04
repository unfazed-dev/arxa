# UI Library Usage Appendix (SSOT)

Every public symbol of the appbox_kit UI tier — `appbox_kit/ui_library`
plus the `appbox_kit/core` surface it re-exports — and **where each is used**
across this repo. This document is the single source of truth for "what does
the kit ship and who consumes it".

- **Canonical surface:** the barrel `appbox_kit/ui_library/lib/ui_library.dart`
  (41 export files + `export 'package:appbox_kit_core/appbox_kit_core.dart'`).
  Symbols not in the barrel are internal (e.g. `widgets/kit_fab_morph.dart` is
  unexported by design) and are not listed.
- **Snapshot:** 2026-07-18. Line numbers drift; **file paths are the durable
  reference** — re-grep before quoting a line.
- **Method:** verbatim-symbol search over `.dart` files. Not counted as usage:
  ui_library/core self-references, `vendor/`, generated files (`*.g.dart`,
  `app.router.dart`, `app.locator.dart`), `_archive/`, `build/`, docs/playbook
  prose, `appbox_kit/skills` + `appbox_kit/memory` tooling, comment-only
  mentions. Comment-only mentions were individually checked and excluded.
- **Maintenance rule (SSOT):** any PR that adds/removes a barrel export, or
  moves a call site between consumer areas, updates this file in the same PR.
- **Consumer-area legend:** **p2 lib/** (feature shell named), **p2 test/**,
  **showcase lib/** + **showcase test/** (`appbox_kit/showcase_app`), **kit
  packages** (other `appbox_kit/<package>` — named per hit).

Internal kit consumers are noted in *italics* where they explain why a symbol
with no external usage still exists.

---

## A. Chrome & navigation widgets

### `widgets/kit_tab_bar.dart`

- **`KitTab`** — one bottom-nav tab; `icon` drives the Flutter fallback,
  `sfSymbol` the iOS 26 native tier.
  - p2 lib/ · application_shell: `lib/ui/views/application_shell/application_shell_view.mobile.dart:48,49,50`
  - p2 test/: `test/kit/widgets/kit_bottom_nav_test.dart:24,25,75,76,97,98`
  - showcase lib/: `showcase_shell/showcase_shell_view.mobile.dart:40,41,42,43`
- **`KitNativeTabBar`** — adaptive bottom tab bar (iOS 26 glass / Android M3E /
  Flutter fallback).
  - p2 lib/ · application_shell: `application_shell_view.mobile.dart:44`
  - p2 test/: `test/kit/widgets/kit_bottom_nav_test.dart:95`
  - showcase lib/: `showcase_shell_view.mobile.dart:38`

### `widgets/kit_bottom_nav_scaffold.dart`

- **`KitExtendBodyFabLift`** — wraps the body of a `Scaffold(extendBody: true)`
  hosting nested Scaffolds with FABs.
  - p2 lib/ · application_shell: `application_shell_view.mobile.dart:37`
  - showcase lib/: `showcase_shell_view.mobile.dart:31`
- **`KitBottomNavScaffold`** — fully-automated bottom-nav scaffold (owns index,
  lazy stack, mounts `KitNativeTabBar`).
  - p2 test/: `test/kit/widgets/kit_bottom_nav_test.dart:21,40,72`
  - No p2 lib/ usage — the app composes the pieces manually in
    `application_shell_view.mobile.dart`.

### `widgets/kit_native_app_bar.dart`

- **`KitNativeAppBar`** — adaptive fixed top app bar (Android M3E / iOS
  Cupertino / Material fallback). **The ONE app bar across both apps**
  (one-app-bar consolidation, 2026-07-18) — always in `Scaffold.appBar`.
  - p2 lib/ · ui/widgets: `lib/ui/widgets/shared_chrome_app_bar.dart:40`
    (`SharedChromeAppBar` — the shared chrome every application-shell tab
    mounts: Train / Support / Community)
  - p2 lib/ · train_shell: `train_shell/train_workout_detail/train_workout_detail_view.mobile.dart:14`
  - p2 lib/ · account_shell (all `Scaffold.appBar`): `account_home/account_home_view.mobile.dart:13`,
    `account_payments/account_payments_view.mobile.dart:14`,
    `account_terms/account_terms_view.mobile.dart:13`,
    `account_technical_support/account_technical_support_view.mobile.dart:15`,
    `account_shipping/account_shipping_view.mobile.dart:14`,
    `account_plan/account_plan_view.mobile.dart:13`,
    `account_privacy/account_privacy_view.mobile.dart:14`,
    `account_preferences/account_preferences_view.mobile.dart:14`
  - showcase lib/: `ui/widgets/common/showcase_gallery_chrome/showcase_gallery_chrome.dart:24`,
    `showcase_profile_shell/showcase_motion/showcase_motion_view.mobile.dart:30`,
    `showcase_notes_shell/showcase_notes/showcase_notes_view.mobile.dart:43`,
    `showcase_notes_shell/showcase_notes_folder/showcase_notes_folder_view.mobile.dart:34`,
    `showcase_notes_shell/showcase_note_editor/showcase_note_editor_view.mobile.dart:40`
  - p2 test/: `test/app/shared_chrome_avatar_test.dart` (import + `find.byType`
    assertions on the shared chrome)
- **`KitNativeAppBar.sliver`** (static) — sliver variant delegating to
  `KitNativeSliverAppBar`, kept for back-compat. **No external usage.**

### `widgets/kit_native_sliver_app_bar.dart`

- **`KitNativeSliverAppBar`** — adaptive sliver app bar; first sliver of a
  `CustomScrollView`. Sample-shaped `background` slot builds
  `FlexibleSpaceBar(title, background)` at expanded height 160.
  **No external usage** — library inventory. Both apps standardize on
  `KitNativeAppBar` (one-app-bar consolidation, 2026-07-18): the p2 shared
  chrome (`SharedChromeAppBar`) and the showcase notes/folder surfaces moved
  to `Scaffold.appBar`. Kept in the catalog for hosts needing a collapsing
  sliver header; the pipeline no longer scaffolds it for app surfaces.

### `widgets/kit_native_toolbar.dart`

- **`KitToolbarAction`** — one toolbar action (primitives only:
  label/icon/sfSymbol/onPressed/isDestructive).
  - p2 test/: `test/kit/widgets/kit_native_toolbar_fork_test.dart:27,28,29,52,67`
  - showcase lib/: `showcase_profile_shell/showcase_profile/showcase_profile_view.mobile.dart:74,79,84`
- **`KitNativeToolbar`** — adaptive top action toolbar (M3E / iOS glass pill /
  Material fallback).
  - p2 test/: `kit_native_toolbar_fork_test.dart:25,50,65`
  - showcase lib/: `showcase_profile_view.mobile.dart:72`

### `widgets/kit_native_navigation_rail.dart`

- **`KitRailDestination`** — one rail stop (icon + label).
  - p2 lib/ · application_shell: `application_shell_view.tablet.dart:28,29,31`,
    `application_shell_view.desktop.dart:29,30,32`
  - showcase lib/: `showcase_profile_view.mobile.dart:47,49,51`
- **`KitNativeNavigationRail`** — adaptive navigation rail (M3E / kit-owned
  Cupertino / Material fallback); tablet/desktop chrome.
  - p2 lib/ · application_shell: `application_shell_view.tablet.dart:24`,
    `application_shell_view.desktop.dart:24`
  - showcase lib/: `showcase_profile_view.mobile.dart:43`

### `widgets/kit_native_chrome_gate.dart`

- **`KitChromeHideMode`** (enum: keepAlive / unmount) — **no external usage.**
- **`KitNativeChromeGate`** — hides a platform-view subtree while a
  full-screen Flutter overlay is up. **No external usage** — *consumed
  internally by `KitNativeTabBar`.*

### `widgets/kit_scroll_occlusion_gate.dart`

- **`KitScrollOcclusionGate`** — scroll-driven occlusion guard for glass
  surfaces. No direct constructor calls — reached via the extension below.
- **`KitScrollOcclusionX`** (`.scrollOcclusion()`) — call-site sugar matching
  kit_motion's `.wake(order: n)` style.
  - showcase lib/: `showcase_notes_folder_view.mobile.dart:72`

### `widgets/kit_lazy_indexed_stack.dart`

- **`KitLazyIndexedStack`** — lazy keep-alive index switch. **No external
  usage** — *consumed internally by `KitBottomNavScaffold`.*

### `widgets/kit_directional_tab_transition.dart`

- **`KitDirectionalTabTransition`** — direction-aware slide+fade for
  `StackedTabsRouter` tab switches (router-animation-driven). **Legacy —
  superseded by `KitAnimatedTabStack` as the pipeline default.** Pure-Flutter
  tab bodies only — over native chrome the fade ghosts platform views
  (flutter#24164/#148639; review check 1c2). **No external usage.**
- **`KitDirectionalTabTransition.timelineOf`** (static) — tab-switch timeline
  for descendants. **No external usage.**

### `widgets/kit_animated_tab_stack.dart`

- **`KitAnimatedTabStack`** — the pipeline-default kept-alive tab stack:
  self-driving PAIRED direction-aware switch (220ms, 18% width, easeOutCubic) —
  the outgoing tab's LIVE element slides out the opposite edge while the
  incoming slides in (router-safe per-slot `GlobalKey` reparenting; zero
  duplicate inflation of `NestedRouter`/`StackedView` subtrees). Lazy
  first-visit inflation, state preserved across switches, RTL-mirrored.
  Fade is opt-in and OFF by default — opacity-animating platform-view
  subtrees ghosts (flutter#24164).
  - p2 lib/ · application_shell: `application_shell_view.mobile.dart`,
    `.tablet.dart`, `.desktop.dart`

### `widgets/kit_tab_switch_transition.dart`

- **`KitTabSwitchTransition`** — **Legacy fallback**: entrance-only
  direction-aware slide for kept-alive tab stacks you don't own (superseded by
  `KitAnimatedTabStack`; tracks the previous index itself, RTL-mirrored).
  Fade is opt-in and OFF by default (flutter#24164).
  - No external usage.
  - showcase lib/: `showcase_shell_view.mobile.dart`

---

## B. Action & input widgets

### `widgets/kit_native_button.dart`

- **`KitNativeButton`** — adaptive CTA (CNButton Liquid Glass on iOS/macOS 26+,
  M3E on Android).
  - p2 lib/: `ui/bottom_sheets/notice/notice_sheet.dart:46`;
    `onboarding/shared/widgets/onboarding_form.dart:67,72`;
    `authentication_shell/authentication_home/widgets/sign_in_form.dart:60,69,75`;
    `account_shell/account_profile/widgets/profile_form.dart:59,64`
  - p2 test/: `test/kit/widgets/kit_native_button_test.dart:17,32`
  - showcase lib/: `showcase_home/showcase_home_view.mobile.dart:72`;
    `showcase_profile/showcase_profile_view.mobile.dart:103,115,146`;
    `showcase_motion/showcase_motion_view.mobile.dart:187,192`;
    `showcase_notes_create_account/widgets/create_account_form.dart:41,52`;
    `showcase_notes_auth/showcase_notes_auth_view.mobile.dart:111,122,131`;
    `showcase_notes_auth/widgets/password_form.dart:45,55`;
    `showcase_notes_auth/widgets/otp_form.dart:40`
- **`KitButtonStyle`** (enum) — kit-owned mirror of `CNButtonStyle`.
  - showcase lib/ only: `create_account_form.dart:43,54`;
    `showcase_notes_auth_view.mobile.dart:115,124,133`;
    `password_form.dart:47,57`; `otp_form.dart:42`

### `widgets/kit_native_icon_button.dart`

- **`KitNativeIconButton`** — adaptive icon button (IconButtonM3E on Android,
  CNButton.icon elsewhere).
  - showcase lib/ only: `showcase_gallery_chrome.dart:27`;
    `showcase_home_view.mobile.dart:26`; `showcase_motion_view.mobile.dart:31`;
    `showcase_notes_folder_view.mobile.dart:23,50`;
    `showcase_notes_view.mobile.dart:62`;
    `showcase_note_editor_view.mobile.dart:41,49,54,224,276,324,330,335,369,401`
  - No p2 usage — *used internally by ui_library (`kit_native_popup_menu.dart`,
    `kit_native_sliver_app_bar.dart`).*

### `widgets/kit_native_fab.dart`

- **`KitNativeFab`** — adaptive FAB (M3E Fab on Android, prominent-glass
  CNButton elsewhere). **No external usage** (only `KitNativeFabMenu` is
  consumed).

### `widgets/kit_native_fab_menu.dart`

- **`KitNativeFabMenu`** — adaptive FAB that morphs into a menu (FabMenuM3E /
  glass CNPopupMenuButton).
  - p2 test/: `test/kit/widgets/kit_native_fab_menu_fork_test.dart:27,67`
  - showcase lib/: `showcase_gallery_chrome.dart:50`;
    `showcase_notes_folder_view.mobile.dart:126`

### `widgets/kit_native_popup_menu.dart`

- **`KitNativePopupMenu`** — adaptive popup menu (Material showMenu on
  Android, CNPopupMenuButton elsewhere).
  - p2 lib/ · ui/widgets: `shared_chrome_app_bar.dart:63` (shared
    account overflow menu)
  - p2 test/: `test/app/shared_chrome_avatar_test.dart:21,47,48`;
    `test/kit/widgets/kit_menu_alignment_test.dart:36,45,48,172,177,179`
  - showcase lib/: `showcase_gallery_chrome.dart:31`;
    `showcase_notes_view.mobile.dart:66`

### `widgets/kit_native_split_button.dart`

- **`KitNativeSplitButton`** — adaptive split button (SplitButtonM3E /
  CNSplitButton / Material Row).
  - p2 test/: `test/kit/widgets/kit_menu_alignment_test.dart:102,117,220,234,284,298,345,359`
  - showcase lib/: `showcase_home_view.mobile.dart:118`

### `widgets/kit_menu_item.dart`

- **`KitMenuItem`** — one item in a native menu (popup / FAB-menu /
  split-button).
  - p2 lib/ · ui/widgets: `shared_chrome_app_bar.dart:66,67,68,78`
  - p2 test/: `test/app/shared_chrome_avatar_test.dart:21,50`;
    `kit_native_fab_menu_fork_test.dart:19,20,21,72`;
    `kit_menu_alignment_test.dart:20,21,22,53,106,107,108,224,225,226,288,289,290,349,350,351`
  - showcase lib/: `showcase_gallery_chrome.dart:34,35,36,53,54,55`;
    `showcase_home_view.mobile.dart:132,133,134`;
    `showcase_notes_folder_view.mobile.dart:129,130,131`;
    `showcase_notes_view.mobile.dart:69`

### `widgets/kit_native_switch.dart`

- **`KitNativeSwitch`** — adaptive toggle wrapping CNSwitch (no M3E branch by
  design).
  - showcase lib/ only: `ui/common/showcase_tabs_shared.dart:48`;
    `showcase_motion_view.mobile.dart:72`

### `widgets/kit_native_slider.dart`

- **`KitNativeSlider`** — adaptive slider (SliderM3E on Android, CNSlider
  elsewhere).
  - showcase lib/ only: `showcase_search/showcase_search_view.mobile.dart:37`

### `widgets/kit_native_range_slider.dart`

- **`KitNativeRangeSlider`** — adaptive range slider (RangeSliderM3E /
  CNRangeSlider on iOS 26+).
  - showcase lib/ only: `showcase_search_view.mobile.dart:51`

### `widgets/kit_native_segmented_control.dart`

- **`KitNativeSegmentedControl`** — adaptive segmented control (iOS-26 native /
  M3E connected group / Cupertino-Material fallback).
  - p2 test/: `test/kit/widgets/kit_native_segmented_control_test.dart:25,49,64`
  - showcase lib/: `showcase_tabs_shared.dart:104`;
    `showcase_motion_view.mobile.dart:58`;
    `showcase_notes_auth_view.mobile.dart:73`

---

## C. Content & feedback widgets

### `widgets/kit_native_loading_indicator.dart`

- **`KitNativeLoadingIndicator`** — adaptive spinner (M3E / Cupertino /
  Material).
  - p2 lib/: `authentication_home/widgets/sign_in_form.dart:58`;
    `onboarding/shared/widgets/onboarding_form.dart:65`
  - showcase lib/: `showcase_home_view.mobile.dart:104`;
    `showcase_notes_auth/widgets/otp_form.dart:52`;
    `showcase_notes_auth/widgets/password_form.dart:67`;
    `showcase_notes_create_account/widgets/create_account_form.dart:60`;
    `showcase_note_editor_view.mobile.dart:70,185`

### `widgets/kit_native_progress.dart`

- **`KitNativeProgress`** (`.linear` / `.circular`) — adaptive progress
  indicator (M3E vs Flutter fallback).
  - showcase lib/ only: `showcase_home_view.mobile.dart:99,102`

### `widgets/kit_native_search_bar.dart`

- **`KitNativeSearchBar`** — adaptive search bar (M3 `SearchBar` / iOS-26
  `CNSearchBar`).
  - showcase lib/ only: `showcase_search_view.mobile.dart:20`;
    `showcase_notes_folder_view.mobile.dart:69`

### `widgets/kit_native_textfield.dart`

- **`KitNativeTextField`** — adaptive text field (CNTextField capsule /
  Material M3 TextField).
  - p2 lib/: `ui/widgets/kit_field_text_field.dart:72` (app-side
    `KitFieldController` bridge wraps it);
    `onboarding/shared/widgets/onboarding_form.dart:31,38,44,50,57`;
    `authentication_home/widgets/sign_in_form.dart:33,40`
  - p2 test/: `test/app/sign_in_flow_test.dart:21,83`;
    `test/app/account_profile_flow_test.dart:22,118`;
    `test/app/onboarding_flow_test.dart:23,99,150,215`
  - showcase lib/: `showcase_notes_shell/shared/widgets/auth_text_field.dart:39`

### `widgets/kit_glass_card.dart`

- **`KitGlassCard`** — adaptive glass/card surface (iOS-26
  LiquidGlassContainer / Material Card).
  - showcase lib/ only: `showcase_home_view.mobile.dart:88,111`;
    `showcase_profile_view.mobile.dart:27,95,138`;
    `showcase_motion_view.mobile.dart:44,87,106,153`;
    `showcase_search_view.mobile.dart:26,60`;
    `showcase_notes_auth_view.mobile.dart:143`;
    `showcase_note_editor_view.mobile.dart:271`

### `widgets/kit_image.dart`

- **`KitImage`** — bundled-asset image with placeholder-glyph fallback +
  `ClipRRect` radius. **No external usage** (p2 binds brand/product imagery
  via plain `Image.asset`, e.g. `startup_view.dart`).

### `widgets/kit_native_sheet.dart`

- **`kitShowNativeSheet<T>()`** — platform-adaptive modal bottom sheet
  (`showModalBottomSheet` on Android, `CNBottomSheet.show` elsewhere).
  **No direct external usage** — reached indirectly: both apps register
  stacked's `BottomSheetService` with ui_library's `KitBottomSheetService`,
  which calls it in-package (`services/sheet/kit_bottom_sheet_service.dart:54,132`).

### `widgets/kit_stream_builder.dart`

- **`KitStreamBuilder<T>`** — `StreamBuilder` with `ValueStream` initial-data
  seeding + shared loading/error UI.
  - showcase lib/ only: `showcase_tabs_shared.dart:93`;
    `showcase_note_editor_view.mobile.dart:287`
  - Plan-vs-code gap: `docs/plans/shop-kitstreambuilder-cutover.md` plans a p2
    shop_shell cutover; p2 code has zero occurrences at snapshot.

---

## D. Services, overlay & KitAction (ui_library)

### `services/notifications/kit_notification_service.dart`

- **`KitNotificationService`** — platform-routed transient feedback (CNToast
  on iOS, SnackbarService on Android/with action).
  - p2 lib/ · app: `lib/app/app.dart:96` (registration)
  - p2 test/: `test/kit/services/kit_notification_toast_sequencing_test.dart:39-40`
  - showcase lib/: `app/app.dart:82`;
    `showcase_gallery_chrome.dart:41,57`;
    `showcase_home_view.mobile.dart:29,75,121,125,137`;
    `showcase_profile_view.mobile.dart:77,82,88,106`;
    `showcase_search_view.mobile.dart:22`;
    `showcase_note_editor_view.mobile.dart:340`
  - showcase test/: `test/services/notes_service_test.dart:42`;
    `test/services/seed_user_notes_wiring_test.dart:57`
- **`KitNotificationKind`** (enum) — severity for `.show`.
  - p2 test/: `kit_notification_toast_sequencing_test.dart:40`
  - showcase lib/: `showcase_home_view.mobile.dart:22,53,56,59,62,123,127`;
    `showcase_profile_view.mobile.dart:90,108`;
    `showcase_note_editor_view.mobile.dart:342`
- **`KitToastPosition`** (enum) — iOS CNToast screen position.
  - showcase lib/ only: `showcase_home_view.mobile.dart:24,63,77`

### `services/navigation/kit_navigation_controller_service.dart`

- **`KitNavigationControllerService`** — web→router / mobile→CupertinoPageRoute
  helper. Registration/resolution only — **no `.navigate()` call sites
  anywhere**:
  - p2 lib/ · app: `lib/app/app.dart:99`;
    p2 test/: `test/kit/services/kit_services_resolve_test.dart:35-36`;
    showcase lib/: `app/app.dart:85`

### `services/navigation/kit_platform_pages.dart`

- **`KitPlatformPages`** — re-wraps generated StackedPage as cupertino on iOS /
  material elsewhere. No direct usage — invoked via the mixin.
- **`KitPlatformPagesMixin`** — applies the above as router pageBuilder.
  - p2 lib/ · app: `lib/app/kit_platform_router.dart:2,14` (`KitPlatformRouter`
    — exercised throughout `test/app/*`: `sign_in_flow_test.dart:61`,
    `guard_fanout_and_eviction_test.dart:59`, `account_profile_flow_test.dart:94`,
    `onboarding_flow_test.dart:77`, `shared_chrome_avatar_test.dart:77`,
    `account_guard_redirect_test.dart:66`)
  - showcase lib/: `app/kit_platform_router.dart:1,11`

### `services/sheet/kit_bottom_sheet_service.dart`

- **`KitBottomSheetService`** — presents stacked sheets via
  `kitShowNativeSheet`. Consumed through stacked's `BottomSheetService` type:
  - p2 lib/ · app: `lib/app/app.dart:88`;
    showcase lib/: `app/app.dart:74`

### `extensions/kit_overlay_extension.dart`

- **`KitOverlayExtension`** (`.withOverlay`) — managed overlay surface.
  - p2 test/: `test/kit/widgets/kit_render_test.dart:63`
- **`KitOverlayService`** — reactive open/close/toggle for named overlays.
  - p2 lib/ · app: `lib/app/app.dart:100`;
    p2 test/: `test/kit/services/kit_services_resolve_test.dart:37`;
    showcase lib/: `app/app.dart:86`
- **`KitOverlayOptions`**, **`KitOverlayControlPosition`** — **no external
  usage.**

### `utils/kit_native_overlay.dart`

- **`withNativeChromeHidden()`** — hides CN* platform views for an overlay's
  lifetime (iOS z-order fix). **No external usage** — *ui_library internal
  (notification service).*

### `utils/kit_action/`

- **`KitAction`** (`kit_action.dart`) — fluent operation facade
  (error/loading/snackbar/stream automation).
  - p2 test/: `test/kit/services/kit_services_resolve_test.dart:50`
  - kit packages · **data**: `appbox_kit/data/lib/facades/kit_data_facade.dart:46`
- **`KitSnackbarType`** (`kit_snackbar_type.dart`) — snackbar variants for
  auto-process notifications.
  - p2 test/: `test/kit/widgets/kit_render_test.dart:34`
- **`setupKitSnackbars()`** (`kit_snackbar_setup.dart`) — registers a
  SnackbarConfig per variant.
  - p2 lib/ · startup: `lib/main.dart:15,50`;
    p2 test/: `kit_render_test.dart:24`;
    showcase lib/: `main.dart:5,21`

### `enums/` (ui_library)

- **`KitNativeComponent`** (`kit_native_component.dart`) — doc-mirror registry
  of native-chrome components.
  - p2 test/: `test/kit/widgets/kit_native_button_test.dart:41,44-64`
- **`kit_widgets_enum.dart`** (KitButtonType, KitButtonLoaderDuration,
  KitButtonLoaderState, KitIconButtonShape,
  KitAnimatedNavbarContainerHeightState, KitBlockPanelExpanded,
  KitBlockPanelAlignment, KitContainerExpandDirection,
  KitContainerExpansionLimit, KitContainerRetractButtonPosition + extension) —
  **all: no external usage.**

---

## E. Core re-export: platform, locator, services

### `core/kit_locator.dart`

- **`locator`** — the kit's handle on the host's `StackedLocator` singleton.
  - p2 test/ (direct import): `test/models/profile_test.dart:4`;
    `test/kit/services/kit_notification_toast_sequencing_test.dart:3`
  - showcase lib/ (direct import): `showcase_notes/showcase_notes_viewmodel.dart:4`;
    `showcase_notes_folder/showcase_notes_folder_viewmodel.dart:4`;
    `showcase_notes_auth/showcase_notes_auth_viewmodel.dart:4`;
    `showcase_notes_create_account/showcase_notes_create_account_viewmodel.dart:2`;
    `showcase_note_editor/showcase_note_editor_viewmodel.dart:6`
  - kit packages · **data**: `lib/facades/kit_data_facade.dart:26,30` (via
    barrel); `test/kit/kit_data_initialize_test.dart:4`
  - Note: p2 lib/ resolves `locator` from its own generated `app.locator.dart`
    (same `StackedLocator.instance`, not an import of this file).

### `core/platform/kit_platform.dart`

- **`KitPlatform`** — SSOT for platform + native-chrome capability gating.
  - p2 lib/ · authentication_shell: `authentication_home/widgets/sign_in_form.dart:68`
  - p2 test/: `test/kit/platform/kit_platform_test.dart`;
    `kit_menu_alignment_test.dart:14,16`;
    `kit_native_segmented_control_test.dart:22,46,62`;
    `kit_native_fab_menu_fork_test.dart:16,33,62`;
    `kit_bottom_nav_test.dart:12,17,68,90`;
    `kit_native_toolbar_fork_test.dart:15,22,46,62`;
    `kit_native_button_test.dart:11,27`
  - showcase lib/: `showcase_notes_shell/shared/widgets/auth_text_field.dart:38`
  - *ui_library is the biggest consumer — every `kit_native_*` widget gates on
    it (internal, not counted).*
- **`KitPlatformOverride`** — test override forcing identity/iOS major/
  TargetPlatform. Same p2 test files as above.
- **`KitTier`** (enum) — **no usage anywhere**, not even inside ui_library
  (definition-only; likely reserved for future widget gating).

### `core/services/error/kit_error_service.dart`

- **`KitErrorService`** — reactive error handling/logging (Talker-backed).
  - p2 lib/ · app: `lib/app/app.dart:95`;
    p2 test/: `kit_services_resolve_test.dart:33`;
    showcase lib/: `app/app.dart:81`;
    showcase test/: `notes_service_test.dart:38`,
    `seed_user_notes_wiring_test.dart:53`
  - *Internal: kit_overlay_extension + all KitAction managers.*
- **`ErrorType`**, **`ErrorSeverity`** (enums) — **no external usage.**

### `core/services/theme/kit_theme_service.dart`

- **`KitThemeService`** — ThemeMode persistence + reactive streams +
  system-UI overlay sync.
  - p2 lib/ · startup: `lib/main.dart:15,47,59-63` (`themeMode$` drives
    MaterialApp); · app: `lib/app/app.dart:98`
  - p2 test/: `kit_services_resolve_test.dart:40`
  - showcase lib/: `main.dart:5,20,60`; `app/app.dart:84`;
    `ui/common/showcase_tabs_shared.dart:92`

---

## F. Core re-export: design tokens

### `core/common/kit_app_constants.dart` (token families)

Families enumerated from the file: `kEnableVerboseLogging`; `kd*` device
constraints; `kDefault*` (radius, hover opacities, button/tab/textfield
metrics); `kAppBarHeight`; `kButton*`; `kTextField*`; `kOtpSlot*`; `kCheckbox*`;
`kPad*`; `kFont*` (numeric + semantic); `kRad*`; `kSize*`; `kOpacity*`;
`kElev*`; `kGap*`; `kSigma*`; `kOffset*`; `kPercent*`.

External usage per family:

- **`kSize*`** — p2 lib/: `ui/bottom_sheets/notice/notice_sheet.dart:25`.
  showcase lib/: `showcase_tabs_shared.dart:112`;
  `showcase_home_view.mobile.dart:39`; `showcase_search_view.mobile.dart:15`;
  `showcase_profile_view.mobile.dart:20-23`;
  `showcase_motion_view.mobile.dart:42,46,89,155,177,179,191`;
  `showcase_notes_view.mobile.dart` (13 sites);
  `showcase_notes_auth_view.mobile.dart:38-41,54,100,148`;
  `showcase_notes_create_account_view.mobile.dart:29,30,38`;
  `showcase_notes_folder_view.mobile.dart` (8 sites);
  `showcase_note_editor_view.mobile.dart:131,222,223,273,318,378`;
  `shared/widgets/form_error_row.dart:21,26`
- **`kFont*`** (semantic only) — p2 lib/: `notice_sheet.dart:33`
  (`kFontXXLarge`); showcase lib/: `showcase_home_view.mobile.dart:45`
  (`kFontXXXLarge`). Numeric `kFont2–80`: no external usage.
- **`kButton*`** — all hits are `kButtonHeightMedium`: p2 lib/
  `notice_sheet.dart:44`; showcase `showcase_home_view.mobile.dart:71`;
  `showcase_profile_view.mobile.dart:102,114,145`;
  `showcase_notes_auth_view.mobile.dart:110,121,130`; `otp_form.dart:39`;
  `password_form.dart:44,54`; `create_account_form.dart:40,51`
- **`kRad*`** — showcase only: `showcase_notes_shared.dart:16` (direct core
  import); `showcase_tabs_shared.dart:68,115`;
  `showcase_note_editor_view.mobile.dart:194,381`
- **No external usage:** `kGap*`, `kPad*`, `kElev*`, `kSigma*`, `kOffset*`,
  `kPercent*`, `kOpacity*`, `kDefault*`, `kd*`, `kAppBarHeight`, `kTextField*`,
  `kOtpSlot*`, `kCheckbox*`, `kEnableVerboseLogging`, `kButtonPadding*` /
  `kButtonIconSize*`. (*`kGap8` and friends are used inside ui_library itself —
  e.g. the sliver app bar's action spacing — which is not counted here.*)

### `core/common/kit_colors.dart`

- **`KitColors`** — showcase lib/ only: `showcase_tabs_shared.dart:24`;
  `showcase_home_view.mobile.dart:52,55,58,61`. (*Also internal:
  `kit_snackbar_setup.dart`.*)
- **`KitDarkColors`** — **no external usage** (comment-only reference in
  `lib/ui/common/generated/brand_colors.dart:31`).
- **`kitAccentOptions`** — **no external usage.**
- **`kitLightTheme()`** — p2 lib/: `lib/main.dart:15,73`; showcase lib/:
  `main.dart:5,77`; p2 test/: `kit_native_segmented_control_test.dart:16`
- **`kitDarkTheme()`** — p2 lib/: `lib/main.dart:15,74`; showcase lib/:
  `main.dart:5,78`
- **`KitAccentRoles` / `KitAccentSwatch` / `kitAccentByName` /
  `kitDefaultAccent`** — **no external usage yet.** The 5-role accent bundles
  (designer five, mirroring `models/theme.json` `swatches`); read a swatch only
  via `forBrightness()`.
- **`fontFamily:` param on `kitLightTheme()` / `kitDarkTheme()`** — **no
  external usage yet.** Applies a face across `textTheme` +
  `primaryTextTheme`; an unbundled family name falls back silently.

### `core/common/kit_fonts.dart`

*New surface — nothing consumes it yet; it exists so the pipeline and the kit
name the same faces. The catalogue is inert until a host bundles the binaries.*

- **`kitFontOptions` / `KitFontFamily` / `KitFontRole`** — **no external
  usage.** The catalogue: `lexend` (default), `grotesk`, `lora`, `mono`.
  Mirrors `designs/appbox-studio/models/fonts.json`, which Increment 4 authors
  — that file is not in the repo yet.
- **`kitFontById` / `kitFontForRole` / `kitDefaultFont`** — **no external
  usage.** `kitFontById` falls back to the default for an unknown id.
- **`kitFontIsBundled`** — **no external usage.** The honest test for whether a
  face's binary is actually present; false for every face today.
- **`registerKitFontLicenses`** — **no external usage.** A host calls this once
  it bundles the OFL binaries, to register the licences with Flutter.

### `core/common/kit_glyphs.dart`

- **`KitGlyph`** (type) — showcase lib/: `showcase_home_view.mobile.dart:20`;
  `showcase_notes_view.mobile.dart:269`
- **`KitGlyphs.`** — p2 lib/: `ui/widgets/shared_chrome_app_bar.dart:64,66,67,70`;
  `ui/bottom_sheets/notice/notice_sheet.dart:48`;
  `application_shell/application_shell_view.tablet.dart:28,30,32`,
  `.desktop.dart:29,31,33`, `.mobile.dart:48,49,50`.
  showcase lib/: `showcase_gallery_chrome.dart` (9 sites);
  `showcase_shell_view.mobile.dart:40,41,42,43`;
  `showcase_home_view.mobile.dart` (9 sites);
  `showcase_profile_view.mobile.dart` (7 sites);
  `showcase_motion_view.mobile.dart:32`;
  `showcase_notes_view.mobile.dart` (10 sites);
  `showcase_notes_folder_view.mobile.dart` (10 sites);
  `showcase_note_editor_view.mobile.dart` (10 sites);
  `showcase_notes_auth_view.mobile.dart:53,147`;
  `showcase_notes_create_account_view.mobile.dart:37`;
  `shared/widgets/form_error_row.dart:25`

### `core/common/kit_ui_helpers.dart`

- **Used:** `horizontalSpaceTiny` (showcase
  `showcase_notes_folder_view.mobile.dart:293`); `horizontalSpaceXSmall`
  (showcase `showcase_note_editor_view.mobile.dart:388`);
  `horizontalSpaceSmall` (showcase: `showcase_home_view.mobile.dart:54,57,60`,
  `form_error_row.dart:27`, `showcase_notes_view.mobile.dart:285,323`,
  `showcase_note_editor_view.mobile.dart` ×5); `verticalSpaceXSmall` (showcase
  `showcase_tabs_shared.dart:109`); `verticalSpaceSmall` (p2
  `notice_sheet.dart:35` + 12 showcase files); `verticalSpaceMedium` (p2
  `notice_sheet.dart:42` + 9 showcase files); `verticalSpaceLarge` (3 showcase
  files).
- **No external usage:** `horizontalSpaceMedium/Large/Massive`,
  `verticalSpaceTiny` (p2/showcase hits resolve to local copies),
  `verticalSpaceMassive`, `spacedDivider`, `verticalSpace()`, `screenWidth`,
  `screenHeight`, `screen*Fraction`, `half/third/quarterScreenWidth`,
  `getResponsiveHorizontalSpaceMedium`, all `getResponsive*FontSize`.

---

## G. Core re-export: formatters, mouse transforms, extensions, enums

- **`utils/kit_time_utils.dart` — `KitTimeUtils`**: no usage anywhere.
- **`utils/formatters/` (`KitEmailInputFormatter`,
  `KitMobileAusInputFormatter`, `KitMobileNumberInputFormatter`,
  `KitOtpCodeInputFormatter`)**: all — no external usage.
- **`utils/mouse_transforms/` (`FillOnHover`, `OutlineOnHover`,
  `ScaleOnHover`, `TranslateOnHover`)**: all — no external usage. p2 and
  showcase_app define their own local copies (`lib/ui/widgets/mouse_transforms/`,
  `showcase_app/lib/ui/widgets/mouse_transforms/`); nothing imports the kit
  classes.
- **`extensions/kit_dismiss_keyboard_extension.dart`
  (`KitDismissKeyboardExtension`)**: no external usage.
- **`extensions/kit_hover_extensions.dart` (`HoverExtensions`)**: no external
  usage — p2/showcase call identically-named members on their local copies
  (`lib/extensions/hover_extensions.dart`).
- **`extensions/kit_selectable_extension.dart`**: `SelectablePosition`,
  `KitSelectableOptions` — no external usage. **`KitSelectableService`** — p2
  `lib/app/app.dart:101`; p2 test `kit_services_resolve_test.dart:38`;
  showcase `app/app.dart:87`. **`KitSelectableExtension`** (`.withSelectable`)
  — p2 test `kit_render_test.dart:64`.
- **`extensions/kit_to_title_case_extension.dart` (`KitStringExtension`)**: no
  external usage (core-internal only, in `KitThemeService`).
- **`enums/kit_app_common_enum.dart` (`KitAppCommonEnumSafeArea`,
  `KitAppCommonDuration` + ext, `KitBlurEffect` + values)**: no external usage
  (only ui_library's overlay options consume the duration/blur enums).
- **`enums/kit_icon_position.dart` (`KitIconPosition`)**: no external usage.

---

## H. Findings

### Dead surface (no consumer outside the defining package)

| Area | Symbols |
|---|---|
| Widgets | `KitNativeSliverAppBar` (library inventory since the one-app-bar consolidation), `KitNativeFab`, `KitImage`, `KitNativeAppBar.sliver`, `KitNativeChromeGate` + `KitChromeHideMode`, `KitLazyIndexedStack`, `KitDirectionalTabTransition.timelineOf` (last four internal-consumed) |
| ui_library enums | all of `kit_widgets_enum.dart`, `KitOverlayOptions`, `KitOverlayControlPosition` |
| Services/utils | `withNativeChromeHidden`, `KitTimeUtils`, all 4 input formatters, all 4 mouse transforms, `KitDismissKeyboardExtension`, `HoverExtensions`, `toTitleCase`, `KitIconPosition`, `KitAppCommonEnumSafeArea`, `KitAppCommonDuration`, `KitBlurEffect`, `ErrorType`, `ErrorSeverity`, `kitAccentOptions`, `KitDarkColors`, `SelectablePosition`, `KitSelectableOptions` |
| Core | `KitTier` — zero references **anywhere**, including the kit itself |
| Token families | `kGap*`, `kPad*`, `kElev*`, `kSigma*`, `kOffset*`, `kPercent*`, `kOpacity*`, `kDefault*`, `kd*`, `kAppBarHeight`, `kTextField*`, `kOtpSlot*`, `kCheckbox*`, numeric `kFont*` (external only; several are kit-internal) |

Registration-only services (registered in `app.dart`, resolved in tests, no
feature call sites): `KitNavigationControllerService`, `KitSelectableService`,
`KitOverlayService`.

### Structural notes

- **Token shadow copies.** p2 (`lib/ui/common/app_constants.dart`,
  `lib/ui/common/ui_helpers.dart`, `lib/extensions/hover_extensions.dart`,
  `lib/ui/widgets/mouse_transforms/`) and showcase_app (same relative paths)
  carry **local copies** of the kit's constants / ui-helpers / hover /
  mouse-transform files. Most token references in both apps resolve locally,
  so the kit's own token files see light direct use (p2: one file,
  `notice_sheet.dart`). Any token change must be mirrored or the copies
  deleted — this is the top duplication risk in the repo.
- **p2 consumes the kit narrowly.** Feature shells (train / shop / support /
  community / account / onboarding / startup) touch no kit symbols directly
  except through `ui/widgets` (`shared_chrome_app_bar.dart`,
  `kit_field_text_field.dart`), `ui/bottom_sheets/notice_sheet.dart`, the
  auth sign-in form, onboarding form, `lib/app/app.dart` registrations, and
  `lib/main.dart`. Everything else reaches kit widgets through those shared
  wrappers.
- **One app bar everywhere (2026-07-18).** Every app surface in p2 and the
  showcase app mounts `KitNativeAppBar` in `Scaffold.appBar` — p2 tabs via
  `SharedChromeAppBar`, the train/account surfaces and the showcase notes
  surfaces directly. `KitNativeSliverAppBar` stays in the catalog as
  inventory (collapsing-header capability with the sample-shaped `background`
  slot) but has no app usage and is no longer pipeline-scaffolded.
- **`KitBottomNavScaffold` is unused by p2** — the application shell composes
  `KitExtendBodyFabLift` + `KitAnimatedTabStack` + `KitNativeTabBar`
  manually (mirroring the showcase shell).
- **`kitShowNativeSheet` has no direct callers** — both apps reach it through
  the `BottomSheetService` → `KitBottomSheetService` registration.
- **Other kit packages barely consume the UI tier.** Only `appbox_kit/data`
  does (`KitAction.run` in its facade, `locator`); `appbox_kit/notifications`
  ships its own distinct plural-named service and mentions
  `KitNotificationService` in comments only.
- **Planned, not landed:** `docs/plans/shop-kitstreambuilder-cutover.md`
  describes a p2 shop_shell `KitStreamBuilder` cutover with no code at
  snapshot.
