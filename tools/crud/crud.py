#!/usr/bin/env python3
"""crud — the one write path for feature CRUD on the authored layer.

Architecture §18 and docs/plans/feature-crud.md: a feature is a registry entry.
This module writes the AUTHORED layer only:

  models/screens_model/registry.json     the feature list (identity)
  ui/views/<tab>/<short>/                the _view.html + _viewmodel.js pair
  models/screens_model/migrations.json   rename lineage (lazy; renames only)

It NEVER writes structure.json or lib/** — those are GENERATED, emitted
downstream by tools/emit_structure and the scaffolder. Editing generated output
would create a second writer and kill the regenerate-and-diff gate. That is the
whole reason §18 forces every surface (GUI, chat, companion, designer) through
this one path.

Operations
  list   <root>                         Read — the registry IS the feature list.
  show   <root> <id>                    Read one entry.
  create <root> --id --tab --comp [--surface] [--label]
                                       Append entry + view pair. surface:null
                                       (or --surface null) ⇒ entry only, no pair:
                                       a declared exclusion, distinct from delete.
  update <root> <id> [--label TEXT]     Edit non-identity fields. id and surface
                                       are immutable (id is a stable key, §18).
  rename <root> --from --to [--surface] new id + explicit migration. The old pair
                                       is removed only AFTER the new one exists
                                       (never delete-before-write, §18 prior art).
  delete <root> <id> --confirm TOK      remove entry + pair, behind a human-minted
                                       token. Idempotent on the desired end state;
                                       re-running repairs a crash mid-delete.
  verify <root> [--fix --confirm TOK]   orphan sweep: a pair dir whose surfaceId
                                       maps to no live entry is a FAIL (the
                                       authored-layer orphan assertion, §18).

Exit non-zero on any failure. Stdlib only (mirrors tools/vendor/kit_registry).
"""
import argparse
import json
import os
import re
import sys

# ---- authored-layer layout (derived from the design root; never hardcoded) --
REGISTRY_REL = "models/screens_model/registry.json"
MIGRATIONS_REL = "models/screens_model/migrations.json"
VIEWS_REL = "ui/views"

# Entry key order — frozen so round-trips are byte-stable (matches the existing
# registry.json: id, label, surface, tab, comp).
ENTRY_KEYS = ("id", "label", "surface", "tab", "comp")

SURFACEID_RE = re.compile(r"surfaceId\s*=\s*['\"]([^'\"]+)['\"]")


# ---- load / save (atomic writes; a crash never leaves a half-written file) ---
def _path(root, rel):
    return os.path.join(root, rel)


def load_registry(root):
    p = _path(root, REGISTRY_REL)
    if not os.path.isfile(p):
        fail(f"{REGISTRY_REL} not found under {root} — a tool that cannot find "
             f"its input never passes quietly; point --root at a design folder.")
    try:
        with open(p, encoding="utf-8") as f:
            reg = json.load(f)
    except Exception as e:
        fail(f"{REGISTRY_REL} does not parse — {e}")
    if not isinstance(reg, list):
        fail(f"{REGISTRY_REL} must be a JSON array of feature entries")
    return reg


def _atomic_write_json(path, obj):
    """Write obj as deterministically-keyed JSON, temp-file then rename, so a
    crash mid-write cannot corrupt the file. indent=2 + trailing newline matches
    the hand-authored style and keeps round-trips byte-identical."""
    d = os.path.dirname(path)
    os.makedirs(d, exist_ok=True)
    text = json.dumps(obj, indent=2, ensure_ascii=False) + "\n"
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(text)
    os.replace(tmp, path)


def save_registry(root, entries):
    _atomic_write_json(_path(root, REGISTRY_REL), entries)


def load_migrations(root):
    p = _path(root, MIGRATIONS_REL)
    if not os.path.isfile(p):
        return []
    try:
        with open(p, encoding="utf-8") as f:
            m = json.load(f)
        return m if isinstance(m, list) else []
    except Exception:
        return []


def save_migrations(root, events):
    p = _path(root, MIGRATIONS_REL)
    if not events:
        if os.path.isfile(p):
            os.remove(p)
        return
    _atomic_write_json(p, events)


def fail(msg, code=1):
    print(f"crud: {msg}", file=sys.stderr)
    sys.exit(code)


# ---- derivation ------------------------------------------------------------
def short_of(eid):
    """The directory short-name is the last '.'-segment of the id — a stable,
    documented derivation (contract: ui/views/<tab>/<short>/)."""
    return eid.split(".")[-1]


def pair_rel(entry):
    """Relative pair dir, or None when surface is null (declared exclusion ⇒ no
    pair is ever created or expected)."""
    if not entry.get("surface"):
        return None
    return f"{VIEWS_REL}/{entry['tab']}/{short_of(entry['id'])}"


def find_entry(entries, eid):
    for e in entries:
        if e.get("id") == eid:
            return e
    return None


def live_ids(entries):
    return {e.get("id") for e in entries}


# ---- pair emission ---------------------------------------------------------
PAIR_VIEW = """<!-- {label} — authored view (CRUD writes this; never hand-edit
     generated lib/** output, which is emitted downstream). -->
<section class="view" data-surface="{surface}">{label}</section>
"""

PAIR_VM = """// {label} — authored viewmodel. The surfaceId declaration is what
// removes the fuzzy (tab, short) join: a view resolves to its registry entry by
// assertion, not by name matching (§14 / feature-crud.md Create step 2).
export const surfaceId = '{id}';
"""


def write_pair(root, entry):
    rel = pair_rel(entry)
    if rel is None:
        return None  # surface:null ⇒ declared exclusion, no pair
    d = _path(root, rel)
    os.makedirs(d, exist_ok=True)
    short = short_of(entry["id"])
    label = entry.get("label") or ""
    with open(os.path.join(d, f"{short}_view.html"), "w", encoding="utf-8") as f:
        f.write(PAIR_VIEW.format(label=label, surface=entry["surface"]))
    with open(os.path.join(d, f"{short}_viewmodel.js"), "w", encoding="utf-8") as f:
        f.write(PAIR_VM.format(label=label, id=entry["id"]))
    return rel


def remove_pair(root, entry):
    rel = pair_rel(entry)
    if rel is None:
        return
    _remove_pair_dir(root, rel, short_of(entry["id"]))


def _remove_pair_dir(root, rel, short):
    d = _path(root, rel)
    if not os.path.isdir(d):
        return
    # Remove only the pair we authored; leave siblings untouched.
    for name in (f"{short}_view.html", f"{short}_viewmodel.js"):
        p = os.path.join(d, name)
        if os.path.isfile(p):
            os.remove(p)
    # Walk BOTTOM-UP from the pair dir, dropping now-empty ancestors. A rename
    # that emptied a tab folder must leave no empty dir behind — that empty dir
    # is exactly the debris the orphan assertion would flag forever. Stops at the
    # first non-empty ancestor (other features' dirs are never touched) and never
    # ascends past the design root.
    cur = d
    for _ in range(rel.count("/") + 1):
        try:
            if os.path.isdir(cur) and not os.listdir(cur):
                os.rmdir(cur)
            else:
                break
        except OSError:
            break
        cur = os.path.dirname(cur)


def prune_migrations(events, entries):
    """A migration {from->to} is live only while `to` is still a feature. Once
    the lineage is deleted, the record is stale debris — remove it so round-trips
    stay byte-identical (Done-when #4: rename produces no debris). O(m*n) scan;
    registry scale is tens of entries, not a concern."""
    live = live_ids(entries)
    return [m for m in events if m.get("to") in live]


# ---- orphan sweep (verify) -------------------------------------------------
def scan_pairs(root):
    """Yield (surfaceId, pair_dir_rel) for every _viewmodel.js under ui/views/.
    The surfaceId declaration is the authoritative join back to the registry."""
    base = _path(root, VIEWS_REL)
    if not os.path.isdir(base):
        return
    for dp, _dirs, files in os.walk(base):
        for fn in files:
            if not fn.endswith("_viewmodel.js"):
                continue
            p = os.path.join(dp, fn)
            try:
                with open(p, encoding="utf-8", errors="ignore") as f:
                    src = f.read()
            except OSError:
                continue
            m = SURFACEID_RE.search(src)
            if not m:
                continue
            sid = m.group(1)
            yield sid, os.path.relpath(dp, root)


def orphans(root, entries):
    """Pair dirs whose surfaceId maps to no live entry — the §18 orphan
    assertion, at the authored layer. (The scaffolded-layer orphan assertion,
    over lib/ui/views/, lives in gates/coverage/ — outside this module's fence.)"""
    live = live_ids(entries)
    out = []
    for sid, rel in scan_pairs(root):
        if sid not in live:
            out.append((sid, rel))
    return out


# ============================================================================
# operations
# ============================================================================
def op_list(args):
    reg = load_registry(args.root)
    for e in reg:
        surf = e.get("surface")
        tag = "exclude" if not surf else "frozen"
        print(f"  {e.get('id'):28} [{tag}] {e.get('label', '')}")
    print(f"{len(reg)} feature(s)")
    return 0


def op_show(args):
    reg = load_registry(args.root)
    e = find_entry(reg, args.id)
    if e is None:
        fail(f"no entry with id '{args.id}'")
    print(json.dumps(e, indent=2, ensure_ascii=False))
    rel = pair_rel(e)
    print(f"  pair: {rel or '(none — declared exclusion)'}")
    return 0


def _coerce_surface(s):
    if s is None:
        return None
    if s == "null" or s == "":
        return None
    return s


def op_create(args):
    reg = load_registry(args.root)
    if find_entry(reg, args.id) is not None:
        # id-stability (§18): an id may never be reused. A duplicate create would
        # silently re-point every generated artifact that referenced it.
        fail(f"id '{args.id}' already exists — id is a stable key and is never "
             f"reused (§18). Use `rename` to retire it, or pick a new id.")
    surface = _coerce_surface(args.surface)
    entry = {"id": args.id, "label": args.label or "", "surface": surface,
             "tab": args.tab, "comp": args.comp}
    # canonical key order
    entry = {k: entry[k] for k in ENTRY_KEYS}
    reg.append(entry)
    save_registry(args.root, reg)
    rel = write_pair(args.root, entry)
    kind = "declared exclusion (no pair)" if rel is None else f"pair at {rel}/"
    print(f"created {entry['id']} — {kind}")
    return 0


def op_update(args):
    reg = load_registry(args.root)
    e = find_entry(reg, args.id)
    if e is None:
        fail(f"no entry with id '{args.id}'")
    # id and surface are identity — immutable on an existing entry (§18).
    if args.label is not None:
        e["label"] = args.label
    # Re-serialize in canonical order, preserving any extra keys.
    ordered = {k: e.get(k) for k in ENTRY_KEYS if k in e}
    for k, v in e.items():
        if k not in ordered:
            ordered[k] = v
    idx = next(i for i, x in enumerate(reg) if x.get("id") == args.id)
    reg[idx] = ordered
    save_registry(args.root, reg)
    # content edits may require the pair label to refresh
    write_pair(args.root, ordered)
    print(f"updated {args.id}")
    return 0


def op_rename(args):
    reg = load_registry(args.root)
    old = find_entry(reg, args.from_id)
    if old is None:
        fail(f"rename --from '{args.from_id}': no such entry")
    if find_entry(reg, args.to_id) is not None:
        fail(f"rename --to '{args.to_id}' already exists — id is never reused (§18)")
    new_surface = _coerce_surface(args.surface) if args.surface is not None else old.get("surface")

    # --- never delete before the replacement exists (§18 prior art: a fixer ---
    # --- that deleted first once left a project with no service locator). -----
    new = {"id": args.to_id, "label": old.get("label", ""), "surface": new_surface,
           "tab": old.get("tab"), "comp": old.get("comp")}
    new = {k: new[k] for k in ENTRY_KEYS}
    reg.append(new)
    save_registry(args.root, reg)
    write_pair(args.root, new)

    # NOW the old entry is retired and its pair removed — the new pair exists, so
    # the tree is never left without the feature.
    reg = [e for e in reg if e.get("id") != args.from_id]
    save_registry(args.root, reg)
    remove_pair(args.root, old)

    events = load_migrations(args.root)
    events.append({"op": "rename", "from": args.from_id, "to": args.to_id,
                   "surface": old.get("surface")})
    events = prune_migrations(events, reg)
    save_migrations(args.root, events)
    print(f"renamed {args.from_id} -> {args.to_id} (migration recorded)")
    return 0


def op_delete(args):
    if not args.confirm:
        # delete is the one operation behind a human confirm — removing authored
        # code is not recoverable by re-running a stage (§18). With no token, the
        # delete path refuses to run unattended and changes nothing.
        fail(f"refusing to delete '{args.id}' without --confirm — removal is not "
             f"recoverable by re-running a stage (§18). Mint a token at the gate.")
    reg = load_registry(args.root)
    entry = find_entry(reg, args.id)

    # Idempotent on the DESIRED END STATE, not on 'was this touched': a crash
    # mid-delete (registry written, pair not yet removed) must be repaired by the
    # next run. So we converge regardless of starting point.
    reg = [e for e in reg if e.get("id") != args.id]
    save_registry(args.root, reg)

    # Remove the pair the entry points at...
    if entry is not None:
        remove_pair(args.root, entry)
    # ...AND sweep any orphaned pair whose surfaceId is now dead (covers the
    # crash case where the entry was already gone but the pair lingers).
    for sid, rel in orphans(args.root, reg):
        _remove_pair_dir(args.root, rel, short_of(sid))

    events = prune_migrations(load_migrations(args.root), reg)
    save_migrations(args.root, events)
    print(f"deleted {args.id}" + ("" if entry is not None else " (swept orphan pair)"))
    return 0


def op_verify(args):
    reg = load_registry(args.root)
    events = load_migrations(args.root)
    bad = orphans(args.root, reg)
    stale = [m for m in events if m.get("to") not in live_ids(reg)]

    if args.fix:
        if not args.confirm:
            fail("verify --fix removes authored files — requires --confirm (§18)")
        for sid, rel in bad:
            _remove_pair_dir(args.root, rel, short_of(sid))
        events = prune_migrations(events, reg)
        save_migrations(args.root, events)
        if bad:
            print(f"verify --fix: removed {len(bad)} orphan pair(s)")
        if stale:
            print(f"verify --fix: pruned {len(stale)} stale migration(s)")
        if not bad and not stale:
            print("verify --fix: nothing to repair (tree is clean)")
        return 0

    errs = 0
    for sid, rel in bad:
        print(f"FAIL: orphan pair {rel}/ declares surfaceId '{sid}' but no registry "
              f"entry has that id — the authored-layer orphan assertion (§18).",
              file=sys.stderr)
        errs += 1
    for m in stale:
        print(f"FAIL: stale migration {m.get('from')} -> {m.get('to')} whose target "
              f"is no longer a feature — rename debris.", file=sys.stderr)
        errs += 1
    if errs:
        return 1
    print(f"verify OK — {len(reg)} feature(s), no orphans, no stale migrations")
    return 0


# ============================================================================
def main(argv=None):
    ap = argparse.ArgumentParser(prog="crud", description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)

    def root_arg(p):
        p.add_argument("root", help="design root (folder containing models/screens_model/)")

    p = sub.add_parser("list", help="list features (Read)")
    root_arg(p); p.set_defaults(func=op_list)

    p = sub.add_parser("show", help="show one feature (Read)")
    root_arg(p); p.add_argument("id"); p.set_defaults(func=op_show)

    p = sub.add_parser("create", help="append a feature + its view pair")
    root_arg(p)
    p.add_argument("--id", required=True)
    p.add_argument("--tab", required=True)
    p.add_argument("--comp", required=True)
    p.add_argument("--surface", default=None,
                   help="surface id; 'null'/omitted ⇒ declared exclusion (no pair)")
    p.add_argument("--label", default="")
    p.set_defaults(func=op_create)

    p = sub.add_parser("update", help="edit non-identity fields (label)")
    root_arg(p)
    p.add_argument("--id", required=True)
    p.add_argument("--label")
    p.set_defaults(func=op_update)

    p = sub.add_parser("rename", help="new id + migration; old pair removed after write")
    root_arg(p)
    p.add_argument("--from", dest="from_id", required=True)
    p.add_argument("--to", dest="to_id", required=True)
    p.add_argument("--surface", default=None, help="override surface on the new id")
    p.set_defaults(func=op_rename)

    p = sub.add_parser("delete", help="remove a feature (behind --confirm)")
    root_arg(p)
    p.add_argument("--id", required=True)
    p.add_argument("--confirm", default="", help="human-minted token; required")
    p.set_defaults(func=op_delete)

    p = sub.add_parser("verify", help="orphan sweep (the §18 assertion)")
    root_arg(p)
    p.add_argument("--fix", action="store_true", help="remove orphans (requires --confirm)")
    p.add_argument("--confirm", default="")
    p.set_defaults(func=op_verify)

    args = ap.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
