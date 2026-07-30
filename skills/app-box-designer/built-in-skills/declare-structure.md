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
     "shell": "shop", "comp": "ShopCart" }
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

## Checking yourself

Run `./selftest.sh <artifact-dir>` — or, by hand, before you call any surface
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

## Do not

- Do not batch structure declaration to the end of the project.
- Do not rename an `id` to tidy it up.
- Do not create a surface directory that no registry entry declares — the orphan
  check will fail it, correctly.
- Do not write `structure.json` yourself. The freeze generates it from what you
  authored here.
