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
| `core` | `appbox_kit_core` | MVVM plumbing; error/theme services; design tokens; locator; input formatters; KitGlyphs; KitPlatform | — |
| `ui_library` | `ui_library` | Kit* adaptive port widgets; KitNative* widgets; UI-coupled services (navigation / sheet / notifications toast) | — |
| `state` | `appbox_kit_state` | async state vocabulary (idle/loading/error); retry policy; persistence | — |
| `data` | `appbox_kit_data` | repositories; schema descriptors; seed/Supabase/Appwrite backends; canonical IDs; codecs; seeder | — |
| `auth` | `appbox_kit_auth` | email/OAuth auth seam; typed AuthResult; session stream | SeedAuthBackend: port-tested; Apple SignIn: port-tested; Google SignIn: port-tested |
| `forms` | `appbox_kit_forms` | form field state; sync/async validation; KitFieldController; error messages | — |
| `permissions` | `appbox_kit_permissions` | OS permissions (camera/location/...); typed permission + status | — |
| `media` | `appbox_kit_media` | camera/photos; audio record; audio+video playback | — |
| `documents` | `appbox_kit_documents` | doc pick; scan (stub); OCR (stub); PDF | — |
| `notifications` | `appbox_kit_notifications` | device push/local notifications; tokens; badge | — |
| `analytics` | `appbox_kit_analytics` | analytics event fan-out | — |
| `payments` | `appbox_kit_payments` | Apple Pay; Google Pay | Stripe: port-tested; PayPal: port-tested; Apple Pay: stub |
| `maps` | `appbox_kit_maps` | native maps; KitMapView | OpenStreetMap: port-tested; Mapbox: port-tested |
| `deploy` | `appbox_kit_deploy` | release automation (fastlane/shorebird/CF Pages+Workers/Vercel) | Vercel: port-tested; Cloudflare Pages: port-tested; Cloudflare Workers: port-tested; fastlane: port-tested; Shorebird: port-tested |
| `haptics` | `appbox_kit_haptics` | haptic feedback | — |
| `bluetooth` | `appbox_kit_bluetooth` | bluetooth adapter state; BLE scan/GATT (stub) | — |
| `wifi` | `appbox_kit_wifi` | Wi-Fi state; network info; settings escort | — |
| `support` | `appbox_kit_support` | in-app support; feedback + Talker export; submission sinks | — |
| `security` | `appbox_kit_security` | biometrics; secure storage; crypto; app-lock; device integrity (stub) | — |
| `compliance` | `appbox_kit_compliance` | ToS/privacy/EULA; consent gates; OSS licenses | — |
| `branding` | `branding` | app icons; native/in-Flutter splash; brand colors (codegen); BrandSplash | — |
| `motion` | `appbox_kit_motion` | entrance/exit choreography; gesture drivers; motion scopes; KitWake | — |
| `i18n` | `appbox_kit_i18n` | i18n | — |
| `showcase_app` | `appbox_kit_showcase_app` | integration surface / reference app (proves every kit) | — |

This table is checked against the registry by `kitCatalogMirrorCheck`
(`appboxd/lib/design_selftest_kit_catalog_mirror.dart`) — every `dir` in
`config/kit-registry.json` must appear here as `` `dir` ``, or the check
fails. Add a kit to the registry, add its row here in the same change.

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
