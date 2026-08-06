# Kit catalog — declaring kit modules in a design

Load this when the brief mentions maps, payments, auth, deploy, or any other
kit capability. It is the designer-side mirror of the kit: what exists, how a
design declares usage, and where the credentials come from.

## What the kit is

The kit is a set of Flutter packages under `kit/` (`auth`, `payments`, `maps`,
`deploy`, `i18n`, …) that the built app wires in. The single source of truth is
`config/kit-registry.json`: each entry carries the kit's `dir` (the name a
design declares), its Dart `package`, its `capabilities`, its `providers` with
**verification tiers** (`stub` → `port-tested` → `device-verified`), and its
playbook. If a capability is not in the registry, it does not exist — do not
design around an imagined module.

## The 24 kits

Generated from `config/kit-registry.json` (`version: 1`). Providers carry a
verification tier: `stub` (declared, not implemented against a real backend),
`port-tested` (real port, tests green, no device surface run), or
`device-verified` (run on simulator/device). A kit with no `providers` entry
has none to tier — it is a plain module, not a provider seam.

| dir | package | capabilities | providers (tier) |
|---|---|---|---|
| `core` | `appbox_kit_core` | MVVM plumbing; error/theme services; design tokens; locator; input formatters; AppBoxKitGlyphs; AppBoxKitPlatform | — |
| `ui_library` | `appbox_kit_ui_library` | AppBoxKit* adaptive port widgets; AppBoxKitNative* widgets; UI-coupled services (navigation / sheet / notifications toast) | — |
| `state` | `appbox_kit_state` | async state vocabulary (idle/loading/error); retry policy; persistence | — |
| `data` | `appbox_kit_data` | repositories; schema descriptors; seed/Supabase/Appwrite backends; canonical IDs; codecs; seeder | — |
| `auth` | `appbox_kit_auth` | email/OAuth auth seam; typed AuthResult; session stream | SeedAuthBackend: port-tested; Apple SignIn: port-tested; Google SignIn: port-tested |
| `forms` | `appbox_kit_forms` | form field state; sync/async validation; AppBoxKitFieldController; error messages | — |
| `permissions` | `appbox_kit_permissions` | OS permissions (camera/location/...); typed permission + status | — |
| `media` | `appbox_kit_media` | camera/photos; audio record; audio+video playback | — |
| `documents` | `appbox_kit_documents` | doc pick; scan (stub); OCR (stub); PDF | — |
| `notifications` | `appbox_kit_notifications` | device push/local notifications; tokens; badge | — |
| `analytics` | `appbox_kit_analytics` | analytics event fan-out | — |
| `payments` | `appbox_kit_payments` | Apple Pay; Google Pay | Stripe: port-tested; PayPal: port-tested; Apple Pay: stub |
| `maps` | `appbox_kit_maps` | native maps; AppBoxKitMapView | OpenStreetMap: port-tested; Mapbox: port-tested |
| `deploy` | `appbox_kit_deploy` | release automation (fastlane/shorebird/CF Pages+Workers/Vercel) | Vercel: port-tested; Cloudflare Pages: port-tested; Cloudflare Workers: port-tested; fastlane: port-tested; Shorebird: port-tested |
| `haptics` | `appbox_kit_haptics` | haptic feedback | — |
| `bluetooth` | `appbox_kit_bluetooth` | bluetooth adapter state; BLE scan/GATT (stub) | — |
| `wifi` | `appbox_kit_wifi` | Wi-Fi state; network info; settings escort | — |
| `support` | `appbox_kit_support` | in-app support; feedback + Talker export; submission sinks | — |
| `security` | `appbox_kit_security` | biometrics; secure storage; crypto; app-lock; device integrity (stub) | — |
| `compliance` | `appbox_kit_compliance` | ToS/privacy/EULA; consent gates; OSS licenses | — |
| `branding` | `appbox_kit_branding` | app icons; native/in-Flutter splash; brand colors (codegen); BrandSplash | — |
| `motion` | `appbox_kit_motion` | entrance/exit choreography; gesture drivers; motion scopes; AppBoxKitWake | — |
| `i18n` | `appbox_kit_i18n` | i18n | — |
| `showcase_app` | `appbox_kit_showcase_app` | integration surface / reference app (proves every kit) | — |

This table is checked against the registry by `kitCatalogMirrorCheck`
(`appboxd/lib/design_selftest_kit_catalog_mirror.dart`) — every `dir` in
`config/kit-registry.json` must appear here as `` `dir` ``, or the check
fails. Add a kit to the registry, add its row here in the same change.

## Kit → surface-state map (D12)

A kit implies a **floor**, not a ceiling: the minimum `surfaceStates`
(`appboxd/lib/intake.dart:59` — `loading | empty | error`) a surface
declaring that kit must have, whether or not the registry entry says so
explicitly. This is the source appbox-designer reads for D10 ("Feedback &
state placement" in `DESIGN-ARCHITECTURE.md`) to decide which state regions
a surface needs, without the brief naming any of them. It never caps what
can be authored — a state with no kit behind it at all is simply authored,
not derived (see `startup` below), and derive+confirm marks only the
derived ones `inferred`.

Verified against portalo's real registry (`~/.appbox/projects/portalo/intake/registry.json`),
screen → declared states / kits:

| screen | declared | kits | derived (this map) | under-declares? |
|---|---|---|---|---|
| `splash` | 0 | — | — | no (nothing to derive) |
| `startup` | 1 | — | — | **no kit produces this state** — see below |
| `auth` | 1 | `auth` | `error` | no — matches exactly |
| `home` | 2 | `data` | `loading,empty,error` | yes |
| `category` | 2 | `data` | `loading,empty,error` | yes |
| `product` | 2 | `data,media` | `loading,empty,error` | yes |
| `cart` | 1 | `data` | `loading,empty,error` | yes |
| `checkout` | 2 | `payments,data` | `loading,empty,error` | yes |
| `orders` | 1 | `data` | `loading,empty,error` | yes |
| `account` | **0** | `auth,data` | `loading,empty,error` | yes — worst case, 2 kits imply the full triad and 0 are declared |

That's 7 of 10 screens under-declaring relative to the derived floor
(`home`, `category`, `product`, `cart`, `checkout`, `orders`, `account`) —
matches the measured figure exactly. `auth` matches its own floor with no
gap. `splash` has no kits, derives nothing, trivially matches its 0.

**`startup` is the case this map cannot — and must not try to — explain.**
It declares 1 state with zero kits attached. No kit→state rule can produce
that state, because it isn't derived from a kit at all: an asset-preload or
splash-animation loading state exists before any kit call happens. This is
the derive+confirm point exactly (see D9) — the map derives a floor;
whatever a human authors on top of or outside that floor is simply
authored, never overwritten, and never something a "the map failed to
predict this" complaint applies to.

| kit | implies | why |
|---|---|---|
| `data` | `loading`, `empty`, `error` | any repository read can be slow, return nothing, or fail — all three every time |
| `auth` | `error` | a credential check fails or succeeds; nothing to load, nothing to be empty |
| `payments` | `loading`, `error` | a charge is a network round-trip that can fail; no empty reading |
| `media`, `permissions` | `error` | device/OS access can be denied or unavailable; no server round-trip to be `loading`/`empty` |
| `security` | `error` | biometric/app-lock checks fail or succeed, same shape as `auth` |
| `maps` | `loading`, `error` | tile/geocode fetch is a round-trip that can fail; no empty reading (an empty map is still a map) |

`payments`, `media`, `security`, `maps` are reasoned by analogy to the
`data`/`auth` shapes above, not independently measured against portalo (which
declares no screens with those kits) — treat those four rows as a starting
rule, not ground truth, until a design with those kits is measured.

A kit not listed here (`core`, `ui_library`, `state`, `forms`,
`documents`, `notifications`, `analytics`, `deploy`, `haptics`, `bluetooth`,
`wifi`, `support`, `compliance`, `branding`, `motion`, `i18n`,
`showcase_app`) implies no surface state on its own — it's plumbing, a
device sensor with no async surface, or a build-time concern.

**Flag, not fixed here:** `intake.dart:59` closes `surfaceStates` to three
values in Dart; `skills/appbox-intake/intake.schema.json` (owned by another
agent) does not enforce the same closed set. This map assumes the Dart
enum is the real contract — the schema-owning agent should either close the
schema to match or this table drifts from what intake actually accepts.

## How a design declares kit usage

Add the optional `kits` key to the surface's registry entry — an array of kit
dir names:

```json
{ "id": "shop.locator", "label": "Store Locator",
  "surface": "shop_shell_locator_view", "shell": "shop",
  "comp": "ShopLocator", "route": "/locator", "kits": ["maps"] }
```

The pipeline takes it from there: `appbox emit structure` validates the names
against `config/kit-registry.json` and threads them into `structure.json`;
the scaffolder records them in each stub's header
(`//   kits (builder wires): maps`) and in `.shell-structure.json`; the builder
wires the real providers per the kit's playbook. **The designer declares; the
pipeline wires.** You never write Dart, pick a provider, or touch a pubspec.

Declare only on real need — a login screen gets `auth`, a checkout gets
`payments`, a map surface gets `maps`. A decorative declaration makes the
builder wire a module nobody uses and can demand credentials the client does
not have.

## Credentials

Declared kits often need API keys. `config/credentials.catalog.json` is the
single source: per `module` (e.g. `kit/payments`) and `provider` it lists each
`key` name, whether it is `required`, its `kind`, where to obtain it (`url`),
and a `simulator_note`. When a design declares a kit whose catalog rows are
required, **surface those key names in the design's brief/notes for the
client** so they can be collected before the build stage.

Rules:

- **Never hardcode a key in the design.** Designs reference keys by name only
  (e.g. "requires `STRIPE_PUBLISHABLE_KEY`"), never by value.
- Keys are managed outside the design: the `appbox credentials list` /
  `appbox credentials check` CLI reports what each declared module needs and
  what is present in the environment/credential store.

## Visual islands vs declaration-only

Some kit capabilities have a design-time island so the prototype can show the
real interaction; others are declaration-only — plain server-rendered forms
and buttons in the design, real wiring in the built app.

**Design-time islands** (data-attribute driven, first-party glue in
`runtime/vendor/`):

- **media / 3D** — `<model-viewer>`, dotlottie (`dotlottie_island.js`), Rive
  (`rive_island.js`), three.js (`three_island.js`) vendor islands.
- **maps** — `map_island.js` (vendor: Leaflet). Data-attribute driven like the
  other first-party islands: the view template renders a `div` carrying the
  center/zoom/markers as `data-*` attributes and the island mounts the map.
  Use it for map surfaces; still declare `"kits": ["maps"]` so the built app
  wires the real map provider.

**Declaration-only** — no island, design the flow with ordinary htmx:

- **auth** — a login/signup surface is a server-rendered form + buttons.
- **payments** — a checkout is a summary + pay button posting to the server.

In both cases the `kits` declaration is what carries the intent downstream.

## Worked example

A store-locator surface that shows an interactive map in the prototype and
needs the maps kit in the built app:

1. Registry entry (as above): `"kits": ["maps"]` on `shop.locator`.
2. View template: a map container the island mounts:
   ```html
   <div data-island="map" data-center-lat="52.23" data-center-lng="21.01"
        data-zoom="13" data-markers='[{"lat":52.23,"lng":21.01,"label":"Flagship"}]'>
   </div>
   ```
3. Notes for the client: the maps kit's providers read
   `config/credentials.catalog.json` (module `kit/maps`) — name any required
   keys (e.g. a Mapbox token) in the brief; never embed one.

That is the whole designer-side job: declare, render the island, name the
keys. The emitter, scaffolder, and builder do the rest.
