# Showcase Notes Shell — design system

Descriptive, not aspirational: every token below was read out of this shell's
own source. Nothing here is a target the code has yet to meet.

This shell was the kit's worked example of the **self-contained shell** pattern
until 2026-08-05, when the pattern was retired: every widget moved to the
central `lib/ui/widgets/showcase_notes_widgets/` home (with its own
`widgets.dart` barrel) and the shell was removed from
`lib/ui/views/.shell-structure.json`.

## Architecture

Four surfaces under one shell — `showcase_notes` (list), `showcase_note_editor`,
`showcase_notes_folder`, plus the auth pair `showcase_notes_auth` and
`showcase_notes_create_account`. The shell view splits by form factor
(`_view.{mobile,tablet,desktop}.dart`) behind `showcase_notes_shell_view.dart`.

Widget home — the in-shell split (`shared/widgets/` + `<surface>/widgets/`)
was retired on 2026-08-05 in favor of the central widgets home:

- `lib/ui/widgets/showcase_notes_widgets/` — all of the shell's widgets:
  cross-surface (`ShowcaseNotesAuthTextFieldWidget`, `ShowcaseNotesFormErrorRowWidget`), surface composites
  (`ShowcaseNotesOtpFormWidget` + `ShowcaseNotesPasswordFormWidget`, `ShowcaseNotesCreateAccountFormWidget`), and the rows/delegates
  extracted from the mobile views (`ShowcaseNotesRowWidget` / `ShowcaseNotesFolderRowWidget`
  / `ShowcaseNotesAdminFolderRowWidget`, `ShowcaseNotesPinnedSearchBarWidget` /
  `ShowcaseNotesNoteRowWidget`, `ShowcaseNoteEditorBodyWidget` / `ShowcaseNotePhotoStripWidget` /
  `ShowcaseNoteAudioRowWidget` / `ShowcaseNoteEditorBottomToolbarWidget` /
  `ShowcaseNoteRecordingRowWidget`).

The home carries a `widgets.dart` barrel; surfaces import the barrel, never the
individual files.

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

- In-shell widget homes — the `shared/widgets/` / `<surface>/widgets/` split
  is retired; widgets live in `lib/ui/widgets/showcase_notes_widgets/`.
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
were never listed in `.shell-structure.json`: none has a widget home or a
`design-system.md`. With the self-contained pattern retired (2026-08-05) the
manifest's `selfContained` list is now empty — no shell carries in-shell
widgets.
