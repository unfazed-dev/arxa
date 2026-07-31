# Icon library + components-first — research and decisions (2026-07-29)

Web research (fan-out, three parallel investigators) plus local exploration that
preceded the appbox-designer **components-first** update: the UI-recipes
catalog, the vendored Lucide set with the `icon()` runtime global, and
`KitGlyphs.lucide` in stacked_kit. Grades: **hot** = seen on the official
page/repo that day · **warm** = official but indirect/stale · **cold** =
unverified. Sources cited inline.

## The question

The designer skill's icons were CSS colored-dot placeholders
(`starter-partials/frames/`: `ios.html` settings rows rendered a hex color as a
rounded square; android/macOS/browser chrome used empty spans and gray
circles — confirmed by reading every frames file). There was no icon primitive
anywhere: no `kit_glyphs.dart` on disk in this repo (only the review-gate
contract naming it), no icon package in `appbox/pubspec.yaml`, zero icon usage
in `examples/hello-hda/`. Two decisions were needed: which icon library to
standardize on, and how it flows HTML → Flutter.

## Candidate comparison (all data gathered 2026-07-29 from official sources)

| library | license | count / style | maintenance | currentColor baked in | verdict |
|---|---|---|---|---|---|
| **Lucide** ([lucide.dev](https://lucide.dev)) | ISC (+MIT for ~100 Feather-derived) — [LICENSE](https://raw.githubusercontent.com/lucide-icons/lucide/main/LICENSE) **hot** | 1,756; 24×24 outline, 2px round-cap stroke, one consistent style **hot** | pushed same day, 23.7k★ **hot** | `stroke="currentColor"` in every raw SVG (verified raw file) **hot** | **chosen** |
| Tabler ([tabler.io/icons](https://tabler.io/icons)) | MIT **hot** | 6,184 + growing filled set **hot** | pushed previous day, weekly releases **hot** | yes (verified) **hot** | strong #2; style near-identical to Lucide |
| Phosphor ([phosphoricons.com](https://phosphoricons.com)) | MIT **hot** | ~1,512 × 6 weights incl. duotone **hot/warm** | last push ~7 months prior **hot** | yes, per weight (verified) **hot** | most stylistic range; slower cadence |
| Heroicons | MIT **hot** | 316 × 4 sets **hot** | stable, Tailwind Labs **hot** | yes **hot** | too small for a general design tool |
| Bootstrap Icons | MIT **hot** | ~2,000 **warm** | steady **hot** | `fill="currentColor"` **hot** | runner-up; less cohesive |
| Iconoir | MIT **hot** | 1,671; 1.5px stroke **hot** | active, small community **hot** | yes **hot** | viable, smaller moat |
| Material Symbols | Apache-2.0 **hot** | 3,000+ **cold** (no official count) | Google-maintained **hot** | **no** — static SVGs ship without fill attr (verified raw) **hot** | rejected: font-first product, no official npm, no baked currentColor |
| Remix Icon | **custom license (Jan 2026), no longer Apache-2.0** — [License](https://raw.githubusercontent.com/Remix-Design/RemixIcon/master/License) **hot** | ~3,000 **warm** | 600 open issues **hot** | yes **hot** | rejected: new license forbids redistributing the complete library without friction — exactly what vendoring does |

## Integration pattern (zero-client-JS, server-rendered, vendored assets)

Compared inline SVG via template macro vs external sprite (`<use href>`) vs
icon webfont, on caching / theming / a11y / htmx-swap behavior / build cost:

- **Inline SVG macro — chosen.** Theming and a11y fully controllable
  (`currentColor`, per-instance `aria-hidden` vs `role="img"`+`<title>`);
  fragments are self-contained under htmx swaps; zero build step. Cost —
  ~200–500 B/icon per response, negligible for fragments
  ([perf comparison](https://joanleon.dev/en/svg-optimization/) **hot/warm**).
- **External sprite** — cacheable, but needs a generation step, cache-busting
  on updates (Chrome has a known stale-sprite bug,
  [Brosset 2026](https://patrickbrosset.com/articles/2026-06-22-whats-missing-from-svg/) **warm**),
  same-origin-only refs, and `<title>` in `<symbol>` is announced
  inconsistently **warm**. Revisit only if one fragment regularly inlines
  >50 icons.
- **Webfont** — legacy: screen-reader ligature/PUA risk, no multi-color,
  baseline fiddling, FOUC ([cagematch](https://css-tricks.com/icon-fonts-vs-svg/) →
  [2026 comparison](https://allsvgicons.com/blog/icon-fonts-vs-svg-sprites-vs-inline-svgs/) **hot**).

## Flutter parity

| set | package | state |
|---|---|---|
| Lucide | [lucide_flutter](https://pub.dev/packages/lucide_flutter) 1.25.0, [lucide_icons_flutter](https://pub.dev/packages/lucide_icons_flutter) | both active (~40 releases/yr for the former) **hot**; `LucideIcons.<camelName>` matches lucide.dev kebab-case 1:1 **hot** — cleanest mapping |
| Phosphor | [phosphor_flutter](https://pub.dev/packages/phosphor_flutter) (official) | ~2 years stale **hot**; community fork maintained **warm** |
| Tabler | [tabler_icons](https://pub.dev/packages/tabler_icons) | 3 years stale **hot**; daily-synced unofficial alternatives **warm** |
| Material Symbols | [material_symbols_icons](https://pub.dev/packages/material_symbols_icons) | CI-regenerated from Google source **hot** |

Neither lucide package ships a name→IconData map (both sources read directly —
`lucide_flutter` has 1,993 static consts; `lucide_icons_flutter` is a 125k-line
file with weight variants). `lucide_flutter` chosen: single-weight API, doc
comments carry the exact lucide.dev kebab names → the kit generates a checked-in
map (`tools/gen_lucide_glyphs.py` → `kit_glyphs_lucide_map.g.dart`, fails the
build if pipeline-critical names vanish upstream).

## Decisions (user-confirmed 2026-07-29)

1. **Components-first workflow.** Every artifact authors its component library
   (macros in `ui/common/` + partials in `ui/widgets|dialogs|bottomsheets/`)
   BEFORE composing surfaces; surfaces compose only from it. The old
   extract-on-second-use rule becomes the floor, not the workflow.
2. **Recipes as doc + partials.** `references/ui-recipes.md` (18 core app-UI
   recipes, Flutter-primitive-aligned) plus drop-ins in
   `starter-partials/components/`.
3. **Lucide, full set vendored** in the skill (`runtime/vendor/lucide/icons/`,
   2,007 SVGs, lucide-static@1.27.0), inlined server-side by the `icon()`
   Nunjucks global. No sprite, no webfont, no CDN, works offline.
4. **Scope: designer + Flutter pipeline.** `KitGlyphs` keeps Material as-is and
   gains namespaced per-library accessors — `KitGlyphs.lucide('arrow-left')`;
   a third library = one generated map + one namespace class.
5. **hello-hda models it** — the reference artifact composes from
   `ui/widgets/components/` and uses `icon()`; `selftest.sh` asserts both.

## What was built, and the evidence

| claim | evidence |
|---|---|
| 2,007 icons vendored; `icon()` global with size/cls/label/strokeWidth, traversal-safe, placeholder+warn on unknown | `ls vendor/lucide/icons \| wc -l` = 2007; `templates.mjs:70`; scratch-render smoke (known/unknown/`../etc` cases) |
| frames placeholders replaced | 11/11 frame-render checks; zero dot-spans left; status-bar signal/battery SVGs kept deliberately (device chrome) |
| recipes + 11 partials lint clean and serve | `lint.mjs` clean; scratch artifact: 28 curl checks (fragments, OOB, 422 flow) all PASS, zero `[icon]` warnings |
| hello-hda composes from the library | `selftest.sh` 23/0 + `--negative` 24/0 (new checks flip under mutation) |
| `KitGlyphs.lucide` + 1,993-entry generated map | `dart analyze` clean; `flutter test` 4/4; map file on disk |
| `generate_view.py` emits `KitGlyphs.lucide('<name>')` | `_icon_for` harness: 13 literal/default + quoted + static-ternary cases |
| gates don't false-positive on `LucideIcons.*` / `KitGlyphs.lucide(...)` | Dart `RegExp(r'\bIcons\.([a-zA-Z0-9_]+)')` probe: no match (control `Icons.play_arrow` matches); enforce_design 105/105, review selftest 16/16 |

## Open follow-ups (owned, not done)

- `tools/vendor/generate_view/generate_view.py` is vendored — the same `_ICON`
  change should go upstream to `factory/flutter-crew` (VENDOR.lock divergence).
- `generate_view.py:~2870` still emits raw `Icons.arrow_back_ios_new_rounded`
  inside an auth template — outside `_ICON`; pipeline owner's call.
- stacked_kit `core` sdk floor bumped `>=3.0.3` → `>=3.8.1` (lucide_flutter
  requires Dart ^3.8.1) — recorded in its AGENTS.md.
- Emitted Flutter views now require `KitGlyphs` in scope via the kit import
  chain (the same contract the review gate's "Use KitGlyphs.*" message assumes).
- `runtime/serve.test.mjs` fails pre-existing: it hardcodes design
  `appbox-app`, absent from this checkout.
