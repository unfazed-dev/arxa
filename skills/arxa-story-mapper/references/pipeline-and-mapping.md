# Intake ownership and the epic/feature/story mapping

### Intake owns the surface inventory; stories ATTACH

When answers are present, the surface inventory is **the intake-declared
surfaces**, not a derivation. A feature pins a declared surface by carrying an
explicit `id` field equal to that surface's id — the feature's stories then
attach to that surface. A feature whose `id` (explicit or slug-derived) matches
**no** declared intake surface is derived as before and flagged ` — [inferred]`
in the unified brief's surface table, so a reader can tell client-declared
scope from mapper-derived scope at a glance.

### The mapping (enforced by the script, not by prose)

| Story map | arxa | Rule |
|---|---|---|
| Epic | shell | slugified from its first ascii word, lowercase (`User System` → `user`) |
| Feature | surface | **with intake answers:** an explicit `id` field equal to a declared intake surface id pins (attaches to) that surface. **Without a match (or standalone):** derived as before — `id = <epic-slug>.<feature-slug>` (`shop.cart` → comp `ShopCart`); ids match `^([a-z][a-z0-9]*)\.([a-z][a-z0-9]*)$`; unmatched derived surfaces are flagged ` — [inferred]` in the brief's surface table |
| Story | requirement | listed under its feature in the brief — what that screen must satisfy |
| MoSCoW + release | sibling metadata | rolled up per surface (strongest live priority, earliest live release) into the table's `priority` / `release` columns; `arxa intake seed` carries them into the registry as additive fields (the four-field canon is untouched) |
| all-`wont` feature | out-of-scope | excluded from the surface table, listed in the brief's Out of scope |

