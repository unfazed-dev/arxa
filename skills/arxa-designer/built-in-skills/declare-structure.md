---
name: "declare-structure"
description: "Declare structure\nAuthor the registry and surfaceId while designing, so structure is never back-filled"
---

# Declare structure

**Load this at the start of every design project and keep it open.** It is not
a finishing step. Structure declared after the design is structure *inferred*
from the design, and inference is exactly what the pipeline exists to remove.

Full contract: [`../references/app-architecture.md`](../references/app-architecture.md).

## The loop

For **every** surface you create, in this order:

1. **Add the registry entry first**, before the directory exists.
   ```json
   { "id": "shop.cart", "label": "Cart", "surface": "shop_shell_cart_view",
     "shell": "shop", "comp": "ShopCart", "route": "/cart" }
   ```
2. **Create the directory** at `ui/views/<shell>/<short>/`.
3. **First line of the viewmodel** — before any logic:
   ```js
   export const surfaceId = 'shop.cart';
   ```
4. **Add the routes** to `app.routes.js`. If this is a shell's landing surface,
   add it to `shellRoots` in the same edit.
5. **Design it**, at every rung in the active ladder
   ([`../references/viewport-ladder.md`](../references/viewport-ladder.md)).

Steps 1–4 take under a minute. Doing them after step 5, across thirty surfaces,
takes an afternoon and gets some of them wrong.

## Deciding not to build a surface

Set `surface: null`. Keep the entry, the `id` and the `label`.

```json
{ "id": "shop.wishlist", "label": "Wishlist", "surface": null,
  "shell": "shop", "comp": "ShopWishlist" }
```

Do **not** delete the entry and do **not** create an exclusions file. The
registry must describe the whole intended app, including the parts deliberately
not built — otherwise nothing downstream can tell "not built yet" from
"never existed", and the difference is a roadmap.

### `route` field

Each registry entry may carry a `route` — the URL path the surface lives at.
When absent, it is derived as `/<shell>/<short>`. The prototype's viewer uses
this for prototype-mode navigation (the device chrome iframe opens the focused
view's route). State it explicitly when the path is not the convention.

### `kits` field — declaring kit modules

For each surface, ask: does the **built app** need a kit module here (a login →
`auth`, a checkout → `payments`, a map → `maps`)? If yes, add `kits` to the
registry entry:

```json
{ "id": "shop.locator", "label": "Store Locator", "surface": "shop_shell_locator_view",
  "shell": "shop", "comp": "ShopLocator", "kits": ["maps"] }
```

Names must come from `config/kit-registry.json` (`kits[].dir`) — the emitter
validates them and fails on an unknown name. Declare only on genuine need,
never decoratively: each name becomes wiring the builder must do and possibly
credentials the client must supply. Which kits exist, which have design-time
islands, and how credentials surface:
[`../references/kit-catalog.md`](../references/kit-catalog.md).

### `flows` — declaring journeys as data (optional)

The artifact's output is a triad — views / flows / proto — three lenses
over this one registry (contract:
[`../DESIGN-ARCHITECTURE.md`](../DESIGN-ARCHITECTURE.md) "The output triad").
The flows lens needs no new files: declare the journeys as **data**, an array
of `{from, to, trigger, action}` edges over the registry ids you declared
above — `action` typed `push` (default) | `replace` | `back` | `modal` |
`system`, linear chains only — carried in the model seed whose surface
renders them (e.g. the studio design's
`models/intake_model/intake_seed.*.json`):

```json
{ "id": "flow-signup", "name": "Sign up",
  "edges": [
    { "from": "shop.home", "to": "shop.signup", "trigger": "Create account", "action": "push" },
    { "from": "shop.signup", "to": "shop.cart", "trigger": "Signed up", "action": "system" }
  ] }
```

Every `from`/`to` must be a registry id — declare the endpoints in the
registry first, then the edge. A `system` edge is not user navigation: it
becomes a route guard in the compiled route table. The flows view renders
these edges with a server component (resolving ids to labels via the
facade); never author per-flow markup. Absent = no flows lens, which is
valid for small artifacts.
The freeze threads the array into `structure.json` keyed by the same ids.

## Checking yourself

Run `arxa design selftest <artifact-dir>` — or, by hand, before you call any surface
done:

```sh
# every viewmodel declares a surfaceId
find ui -name '*_viewmodel.js' | while read -r f; do
  grep -q 'export const surfaceId' "$f" || echo "MISSING surfaceId: $f"
done

# every non-null registry surface has a directory, and vice versa
node -e '
const r = require("./models/screens_model/registry.json");
console.log("entries:", r.length,
            "buildable:", r.filter(e => e.surface).length,
            "excluded:",  r.filter(e => !e.surface).length);
'
```

An excluded count of zero on a real app is suspicious, not clean — it usually
means someone deleted entries instead of nulling them.

## Naming

- `id` is `<shell>.<short>`, lowercase, dotted. **It is permanent.** Renaming an
  `id` breaks every downstream reference; add a new entry and null the old one
  instead.
- `<short>` in the path matches the `id`'s second segment exactly.
- `comp` is PascalCase and unique across the app.
- `surface` is `<shell>_<short>_view` (flattened, e.g. a subgrouped surface is
  `stage_shell_proj_home_view`) — but it is a *value the registry
  states*, not a rule anything infers. State it; never let it be guessed.
- `route` is the surface's URL path, `/<shell>/<short>` by convention (the app
  shell's surfaces live at the top level, e.g. `app.cart` → `/cart`). Optional;
  absent = derived from the id. See the `route` field note above.

## Do not

- Do not batch structure declaration to the end of the project.
- Do not rename an `id` to tidy it up.
- Do not create a surface directory that no registry entry declares — the orphan
  check will fail it, correctly.
- Do not write `structure.json` yourself. The freeze generates it from what you
  authored here.
