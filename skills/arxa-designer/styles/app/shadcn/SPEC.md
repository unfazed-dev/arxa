# shadcn — style SPEC (registry source truth)

> Compiled from energize component-craft.md + component-specs.md; overlay.css
> is the gate-proven implementation. shadcn is gated on ABSOLUTE px — the
> registry IS the component. Registry: shadcn-ui/ui new-york-v4 (Tailwind →
> px at 16px root).

## Tokens

zinc scale: background / foreground, card, popover, muted, accent (zinc-100),
border (zinc-200), primary/primary-foreground, destructive (#DC2626 light /
#F87171 dark), input ring. Radius scale: --radius (0.625rem) → rounded-sm 4 /
md 6 / lg 8 / xl 12. Fonts: Inter/system sans. Dark = token-level variant
(zinc-950 ground), instant swap (R8).

## Numbers (asserted)

| member | class | px |
|---|---|---|
| switch track | h-[1.15rem] w-8 rounded-full | 18.4 × 32 |
| switch thumb | size-4 | 16 round |
| checkbox | size-4 rounded-[4px] | 16, r4 |
| radio | size-4 + size-2 dot | 16 / 8 |
| input | h-9 rounded-md | 36, r6 |
| tabs list / trigger | h-9 rounded-lg / rounded-md | 36, r8 / r6 |
| breadcrumb | icon size-3.5 / ellipsis size-9 | 14 / 36 |
| pagination | size-9 | 36 |
| calendar cell | --cell-size: --spacing(8) | 32 |
| calendar root | p-3 w-fit; month gap 16; week mt-2 8; weekday 12.8 | frame from consumer PopoverContent (no border on root — NOT FOUND, by design) |
| sidebar | 16rem/18rem/3rem | 256 / 288 / 48 |
| menu/popover item | size-8 / size-10, rounded-md | 32 / 40, r6 |
| select content | min-w-8rem, overflow-x-hidden | 128 floor |
| time picker | native <input type=time> in Input classes | 36, r6 — shadcn has NO time component (verified: 65 registry files, zero matching) |

## Families — shadcn truths

- **menus/context** — popover truth: bg-popover, border, shadow-md,
  rounded-md (6px), item rounded-sm hover bg-accent; checkmark item
  indicator in a RESERVED right slot (the SelectItem pattern the R9o
  reserved-slot law generalizes). Menubar flat, item hover bg-accent.
- **select** — SelectTrigger w/ chevron at padding (the R9p pin law's
  source); content min-w-8rem; the check is `absolute right-2` in the
  padded slot.
- **tabs** — list = bg-muted rounded-lg p-1; active trigger = bg-background
  shadow-sm (the "lifted card" tab); underlined variant legal for page tabs.
- **switch** — bg-input track, checked bg-primary, thumb bg-background +
  shadow (16px).
- **checkbox/radio** — 4px rounded border; checked bg-primary + check /
  filled dot.
- **dialogs** — rounded-lg (12), border, shadow-lg, centered; alert same w/
  destructive button. Sheet: slides from edge, border-l, shadow-lg — NOT a
  glass material.
- **calendar** — react-day-picker: 32px cells, selected bg-primary
  text-primary-foreground rounded-md, today bg-accent, range middle bg-accent
  rounded-none, outside days muted.
- **toast** — bg-foreground text-background (inverted), rounded-md,
  shadow-lg; alert/banner = border + bg-background, destructive variant
  border-destructive/50.
- **tooltip** — bg-primary text-primary-foreground rounded-md px-3 py-1.5
  text-xs, **NO arrow in v4** (arrow deprecated).
- **spinner** — the border-top ring is LEGAL here (legacy/tailwind idiom —
  animate-spin border).
- **iconography** — Lucide (shadcn's own set), --ic 16.

## Motion

| class | constant |
|---|---|
| press | 150ms cubic-bezier(0.16, 1, 0.3, 1); scales 0.94/0.96/0.98 |
| move | 200ms same ease-out-expo |
| effects | 180ms linear |
| disclosure | ease only, never springs (no springs exist in this system) |
| direct manipulation | 1:1 pointer |

## Gate contract

Four gates; geometry asserts the ABSOLUTE px table. Every cross-style law
(dropdown ×8, field indicator exclusivity, single-line rows, R9c labels,
theme-instant swap) applies — the lab gates run these identically per style.
