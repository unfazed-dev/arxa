# custom — style SPEC (energize creme / editorial — ours to define)

> Compiled from energize component-craft.md + the base lab.css skin. The
> custom style IS the base skin: no overlay file — the artifact's base
> widgets.css carries it (`?style=custom` = no overlay linked). Numbers
> here are CHOSEN, not sourced — legitimate for a house style; the gates
> pin them so they stay stable.

## Tokens

- color-craft one-hue OKLCH neutrals at H≈81 (creme grounds anchor):
  field #E5E2DD / field-alt #F3EDE3 / surface #FBF8F3; ink #120F09 /
  ink-soft #67635A; hairline = ink 10%.
- accent steps hold the seed hue H≈195, lightness-only moves: accent
  #0FA3A3 / accent-text #006F6F / accent-hover #0C8C8C / accent-soft
  #D2ECEC. Amber trio for warnings.
- radii: r-card 12 / r-ctl 8 / pill 9999. Shadow-1 = 0 1px 2px 7% ink.
- Type: Fraunces display (500/600, opsz 9..144) + Source Sans 3 body
  (400/600/700); 15px body, 1.5 line-height; headings text-wrap balance.

## Families — custom truths

- pills for chips/CTAs; 12px cards / 8px controls; uppercase overline
  labels w/ .07em tracking; accent-soft selection.
- menus: surface card + shadow-1, 8px corners, items highlight accent-soft.
- calendar: day cells round, selection solid accent w/ accent-ink, today =
  hairline ring; month title in Fraunces.
- dialogs: 12px card on surface, shadow-1, Fraunces title; sheet 16px top
  corners; toast = ink-filled pill (dark on light, light on dark — the
  editorial inversion); banner = left accent border + soft fill.
- chevron rotates 180° (down→up) — the non-iOS idiom is correct here.
- Dark: the monotonic light ladder holds for every raised surface
  (menu/dialog/sheet sit on --surface, never darker than their backdrop —
  the 2026-08-24 invisible-cards bug class).

## Motion

press 150ms / move 250ms cubic-bezier(0.2, 0.6, 0.2, 1); effects 180ms
linear; disclosure ease-only. See motion.css.

## Gate contract

Four gates; geometry asserts OUR pinned values (the base skin's). All
cross-style laws apply identically.
