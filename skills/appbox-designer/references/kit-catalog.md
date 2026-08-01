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
