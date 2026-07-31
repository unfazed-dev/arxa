# Can the FSM build a bespoke app from an htmx-designed prototype?

**Yes — 73/73, same as the JSX-designed control.**

Controlled experiment: the same surface (`train_shell_training_library_view`),
two design producers, the same generator (kit-designer), the same judge
(`enforce_design.dart`). The agent authoring from htmx was told not to look at
the JSX-built version.

| | from `new-htmx` | from `new` (JSX, control) |
|---|---|---|
| `enforce_design` | **73/73 PASS** | **73/73 PASS** |
| `flutter analyze` | clean | clean |
| lines emitted | 891 | 1,010 |
| widgets extracted | 7 + barrel | 5 + barrel |

## First: htmx was never worse — it carried an unfixed bug

`new-htmx` had been failing the freeze render gate. Root cause was not the
producer: `emit_htmx.py` had `ASSET_PREFIX = "../new-htmx/assets/"`, the
pre-reorg rule. Since `surfaces/` moved *inside* the producer folder on
2026-07-25, that resolves to `design/new-htmx/new-htmx/assets/` — 404ing every
font and video.

The identical bug was fixed in `emit_playground` earlier in this session
(`../new/assets/` → `../assets/`) and never propagated.

**Why three layers of verification all missed it:**

1. The self-test **asserted the defective prefix** —
   `chk('src="../new-htmx/assets/icon.svg"' in h, …)`. Green because it checked
   for the wrong answer.
2. `assert_assets_rewritten` only looked for URLs the rewrite *missed*. Every URL
   was rewritten — to a path that does not exist. The string moved; the file was
   never there.
3. The freeze render gate did catch it, but its own harness registers
   `pg.on("console", …)` **inside the loop on a shared page**, so handlers
   accumulate and each error is reported once per surface already visited. The
   failure count was inflated ~4×, which made it read like a producer-wide
   collapse rather than one missing prefix.

Fixed 1 and 2 (kit `da5f98e`); 3 is still open — cosmetic, but it makes gate
output untrustworthy for counting.

After the fix: `emit: PASS — 37 surfaces`, `freeze: PASS`.

## Measured producer qualities, same surface

| | `new` (JSX) | `new-htmx` |
|---|---|---|
| inline `style=` attributes | **22** | **7** |
| `class=` attributes | 51 | 34 |
| frozen lines | 937 | 1,554 |
| frozen bytes | 44,046 | **62,983** |
| `prefers-color-scheme` | **0** | 2 |
| `data-theme` hooks | 2 | **7** |
| `prefers-reduced-motion` | **0** | 1 |

Two things fall out:

- **htmx is 3× cleaner on semantic markup.** The authoring agent's words: *"The
  screen itself declares zero style — it only names classes… I never had to
  reverse-engineer intent from inline CSS."* The screen body was ~74 lines inside
  a 1,554-line file; the rest is a shared chassis. Structure and text came across
  **100%, unambiguous**, copy verbatim including a URL-encoded toast payload.
- **htmx carries theming that JSX drops entirely.** Dark-theme variants, seven
  `data-theme` hooks and a reduced-motion block survive into the frozen artifact.
  The JSX producer freezes none of it. Given the stated requirement — *system,
  light + dark, choice of accent colors* — that is design information the JSX
  path loses before the generator ever sees it.

Note the inversion against the earlier LOC table: htmx is **cheaper to author**
(118 LOC/screen vs 159) *and* **richer to hand downstream** (62,983 vs 44,046
bytes). Those are not in tension — the chassis is shared, so per-screen authoring
stays thin while every frozen surface ships the whole system.

## The gap that is real, and is not htmx's fault

The frozen artifact is a **432×906 phone bezel**. I initially read
"tablet/desktop/@media in 37 of 37 surfaces" as responsive input; that was a
loose grep. The `@media` blocks are `prefers-color-scheme` and
`prefers-reduced-motion` — theme and motion, not breakpoints. There are zero
`tablet`/`desktop` hits.

So the authoring agent's caveat stands, and it generalises:

> Two of the four layouts I was required to author had *no input whatsoever* —
> tablet and desktop are entirely my inference from the content's shape.

**No producer in this corpus carries responsive input.** `new` frozen at 432px,
`new-htmx` frozen at 432px, and flutter-crew emits `ScreenTypeLayout` zero times
in 22,738 lines. Yet the deliverable contract demands genuine tablet and desktop
layouts, and `enforce_design` check 1 fails without all five files.

**Half of every surface's layout work is invented, on every path, today.** That is
the largest unaddressed hole in the whole assessment — larger than the emitter
question, because no amount of deterministic emission can emit an input nobody
captured.

## Other judgment calls the generator was forced into

Reported honestly by the authoring agent rather than smoothed over:

- Only one of five scopes is populated in the design, and no empty-state wording
  exists — so the empty copy was invented and declared as such.
- `.lrow` is a `<div>`, not the `<a class="lrow">` every other row idiom uses, so
  where an entry opens is unspecified; `onTap` left null.
- The `.lrow-ic` bolt has no `KitGlyphs` member → substituted `train`.
- The `.appbar` carries a title *and* a caption; `KitNativeAppBar` has one line.

Each is a place the design contract is silent and the deliverable contract is not.
They are cheap to close in the producer (empty states, link semantics, a glyph
audit) and expensive to keep re-deciding per surface.

## Verdict

htmx is the strongest producer measured: cheapest to author, cleanest markup,
richest frozen artifact, carries theming, and clears the FSM's intake and output
gates end to end. It should be appbox's default prototype language.

The phone-only viewport is the thing to fix — in the **producer**, by freezing
each surface at three widths, not in the emitter by inferring two layouts per
surface forever.
