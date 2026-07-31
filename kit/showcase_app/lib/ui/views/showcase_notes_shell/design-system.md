# Showcase Notes Shell — design system

Descriptive, not aspirational: every token below was read out of this shell's
own source. Nothing here is a target the code has yet to meet.

This shell is the kit's worked example of the **self-contained shell** pattern,
and the corpus `kit-feature-implementer/SKILL.md:82,87` and
`kit-reviewer/SKILL.md:45` cite by path. It is the first shell in `showcase_app`
listed in `lib/ui/views/.shell-structure.json`, so `shell_structure_gate.sh`
S1–S9 actually run against it.

## Architecture

Four surfaces under one shell — `showcase_notes` (list), `showcase_note_editor`,
`showcase_notes_folder`, plus the auth pair `showcase_notes_auth` and
`showcase_notes_create_account`. The shell view splits by form factor
(`_view.{mobile,tablet,desktop}.dart`) behind `showcase_notes_shell_view.dart`.

Widget homes, both in use here — this shell is why the split exists:

- `shared/widgets/` — cross-surface: `AuthTextField`, `FormErrorRow`.
- `<surface>/widgets/` — surface-local: `OtpForm` + `PasswordForm` under
  `showcase_notes_auth/`, `CreateAccountForm` under
  `showcase_notes_create_account/`.

Each `widgets/` carries a `widgets.dart` barrel (review check 1n/C); surfaces
import the barrel, never the individual files (1p). A bare
`showcase_notes_shell/widgets/` would be **rejected** by check 1o/D — it leaks
widgets across the shell's surfaces.

## Palette

Theme-derived, not hard-coded: colours come from `Theme.of(context).colorScheme`
— `error` (10 uses, the form-validation surface), `onSurfaceVariant` (7,
secondary text), `primary` (5), plus `onError`, `onPrimary`, `tertiary`,
`onTertiary`. The two kit constants that do appear are `kcWhite` and `kcBlack`,
one use each.

No raw `Color(0x…)` literals — the review gate's raw-colour check owns that.

## Glyphs (kit tokens)

`KitGlyphs.` only, never a bare `Icons.`: `add`, `back`, `camera`, `close`,
`compose`, `delete`, `error`, `folder`, `info`, `mic`, `more`, `newFolder`,
`notes`, `pause`, `photo`, `pin`, `play`, `restore`, `signOut`, `stop`, `unpin`.

## Spacing & shape

Named helpers over magic numbers: `verticalSpace{Tiny,Small,Medium,Large}` and
`horizontalSpace{Tiny,XSmall,Small}` from `kit_ui_helpers.dart`. Fixed
dimensions use the `kSize*` scale (`kSize4` … `kSize80`), never bare doubles.

## Kit surface

Chrome and inputs are kit-native throughout: `KitNativeAppBar`,
`KitNativeTextField`, `KitFieldTextField`, `KitNativeButton`,
`KitNativeIconButton`, `KitNativeSearchBar`, `KitNativeSegmentedControl`,
`KitNativePopupMenu`, `KitNativeFabMenu`, `KitNativeProgress`,
`KitNativeLoadingIndicator`. Content surfaces compose on `KitGlassCard`,
`KitListSection`, `KitListTile`, `KitMenuItem`. Streams render through
`KitStreamBuilder`. Motion is `KitMotionScope`-owned.

## Forbidden (enforced by the gates)

- A bare `<shell>/widgets/` — 1o/D; use `shared/widgets/` or
  `<surface>/widgets/`.
- `ScreenTypeLayout` inside a shared widget (S7) — widgets adapt their internals
  via `getValueForScreenType`; whole-layout dispatch belongs to
  `<surface>_view.dart`.
- A form-factor variant importing another variant (S9) — a variant is one
  layout, not a component library.
- `ui_library` or `flutter/{material,widgets,cupertino}` in a `*viewmodel.dart`
  (check 1m). Toasts fire from the view layer; see
  `showcase_profile_view.mobile.dart:86`.

## Known gaps

The other four showcase shells (`home`, `profile`, `search`, `showcase_shell`)
are **not** listed in `.shell-structure.json`: none has a widget home or a
`design-system.md`, so they have not migrated to this pattern. Listing them
would assert a migration that has not happened — the manifest is deliberately
incremental.
