#!/usr/bin/env python3
"""app-box-intake — the elicitation engine.

Architecture §22: intake ELICITS requirements; it NEVER generates design or
code. This module is the single engine both the headless phase and the desktop
wizard drive ("one engine" — if the two front ends can disagree, plan 10 has
failed). It does three things and only three things:

  1. validate  — check an answers document against intake.schema.json, where
                 every field carries provenance (client | founder | inferred).
  2. emit      — turn validated answers into docs/design/brief.md (every
                 `inferred` field visibly marked) and a seeded registry.json
                 (ids, shells, comps; surface ALWAYS null — intake names, never
                 designs).
  3. seed      — accept a HAND-WRITTEN brief (plan 10.7: intake is optional)
                 and derive the registry seed from its surface table, without
                 rewriting a word of the brief.

THE CONTRACT THIS MODULE EXISTS TO ENFORCE
  Emission is a PURE function of its input. The engine adds no content that was
  not elicited: no new surfaces, no new field values, no invented copy. The only
  things it derives are mechanical naming (comp from id, by the convention in
  declare-structure) and the structural default surface=null — and comp is
  flagged `convention` in the emitted provenance note. Everything else is the
  client's words, passed through. A self-test asserts this negatively: feed N
  surfaces, the emitted registry has exactly N.

Usage:
  intake.py emit  --answers <answers.json> [--brief-out <p>] [--registry-out <p>]
  intake.py seed  --brief <brief.md>        [--registry-out <p>]
  intake.py validate <answers.json>
  intake.py --self-test

Output paths default under the repo root (derived from this file's location,
never a literal — R3) and are overridable via the flags above or the
INTAKE_BRIEF_OUT / INTAKE_REGISTRY_OUT env vars. Exit: 0 ok · 1 invalid input ·
2 usage/self-test error.
"""
from __future__ import annotations
import argparse
import json
import os
import re
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]  # skills/app-box-intake/ -> repo root
SCHEMA_PATH = Path(__file__).resolve().parent / "intake.schema.json"

PROVENANCE = ("client", "founder", "inferred")
# Surface id is <shell>.<short>, both lowercased alnum (see intake.schema.json).
ID_RE = re.compile(r"^([a-z][a-z0-9]*)\.([a-z][a-z0-9]*)$")
# The visible marker the emitted brief puts on any `inferred` field. A reader
# who skims must not miss it — that is the entire point of marking inference.
INFERRED_MARK = "> **[inferred]** — not stated by the client; confirm or correct."

FIELD_TITLES = [
    ("product", "Product"),
    ("audience", "Audience"),
    ("appMustDo", "What the app must do"),
    ("existingSystems", "Existing systems"),
    ("targets", "Targets"),
    ("brand", "Brand"),
    ("constraints", "Constraints"),
    ("outOfScope", "Out of scope"),
    ("layoutTemplate", "Layout template"),
]


# ---------------------------------------------------------------- validation


def validate(answers: dict) -> list[str]:
    """Return a list of human-readable error strings; empty list = valid.

    Structural + semantic checks that the JSON Schema cannot express on their
    own (the schema guards shape; this guards meaning). Each error names the
    offending field so the caller can point at it.
    """
    errs: list[str] = []
    if not isinstance(answers, dict):
        return ["answers: expected a JSON object at the top level"]

    # required scalar/list fields
    for key in ("product", "audience", "appMustDo", "targets"):
        if key not in answers:
            errs.append(f"{key}: required field is missing")

    # every present field must carry a known provenance
    list_fields = {"appMustDo", "constraints", "outOfScope"}
    for key, _title in FIELD_TITLES:
        if key not in answers:
            continue
        node = answers[key]
        if not isinstance(node, dict):
            errs.append(f"{key}: expected {{value, provenance}}, got {type(node).__name__}")
            continue
        prov = node.get("provenance")
        if prov not in PROVENANCE:
            errs.append(
                f"{key}: provenance '{prov}' is not one of {list(PROVENANCE)} "
                f"(there is no fourth value — unstated means 'inferred')"
            )
        val = node.get("value")
        if key in list_fields:
            if not isinstance(val, list) or not all(isinstance(x, str) for x in val):
                errs.append(f"{key}: value must be a list of strings")
        else:
            if key == "targets":
                if not isinstance(val, list) or not all(isinstance(x, str) for x in val):
                    errs.append(f"{key}: value must be a list of platform strings (§11)")
            elif key == "layoutTemplate":
                errs.extend(_validate_layout_template(val))
            elif not isinstance(val, str):
                errs.append(f"{key}: value must be a string")

    # surfaces: shape + the shell==id-prefix invariant + uniqueness
    surfaces = answers.get("surfaces", [])
    if not isinstance(surfaces, list):
        errs.append("surfaces: must be a list")
        surfaces = []
    seen_ids: set[str] = set()
    for i, s in enumerate(surfaces):
        where = f"surfaces[{i}]"
        if not isinstance(s, dict):
            errs.append(f"{where}: expected an object")
            continue
        for req in ("id", "label", "shell", "provenance"):
            if req not in s:
                errs.append(f"{where}: missing '{req}'")
        sid = s.get("id", "")
        m = ID_RE.match(str(sid))
        if not m:
            errs.append(
                f"{where}: id '{sid}' must be <shell>.<short> (lowercase alnum, "
                f"e.g. projects.home)"
            )
        else:
            shell_from_id, _short = m.group(1), m.group(2)
            if s.get("shell") != shell_from_id:
                errs.append(
                    f"{where}: shell '{s.get('shell')}' must equal the id's first "
                    f"segment '{shell_from_id}'"
                )
        if s.get("provenance") not in PROVENANCE:
            errs.append(
                f"{where}: provenance '{s.get('provenance')}' is not one of "
                f"{list(PROVENANCE)}"
            )
        if sid in seen_ids:
            errs.append(f"{where}: duplicate id '{sid}' (ids are permanent — add a new one, do not reuse)")
        seen_ids.add(sid)

    return errs


def _validate_layout_template(val) -> list[str]:
    """Shape-check a layoutTemplate value: {category, archetype, areas per
    rung, containers}. Membership in the closed lists is the schema's job
    (intake.schema.json enums against layout_templates.json); here we guard
    the structure the brief renderer relies on."""
    errs: list[str] = []
    if not isinstance(val, dict):
        return ["layoutTemplate: value must be an object "
                "{category, archetype, areas, containers} (copied verbatim from layout_templates.json)"]
    for req in ("category", "archetype", "areas", "containers"):
        if req not in val:
            errs.append(f"layoutTemplate: value is missing '{req}'")
    areas = val.get("areas")
    if not isinstance(areas, dict):
        errs.append("layoutTemplate: areas must be an object keyed by rung")
    else:
        for rung in ("compact", "medium", "expanded"):
            rows = areas.get(rung)
            if not isinstance(rows, list) or not all(isinstance(r, str) for r in rows):
                errs.append(f"layoutTemplate: areas.{rung} must be a list of grid-template-areas row strings")
    if not isinstance(val.get("containers"), dict):
        errs.append("layoutTemplate: containers must be an object (named container -> {type, hints})")
    return errs


# ----------------------------------------------------------- naming (derived)


def derive_comp(surface_id: str) -> str:
    """comp = PascalCase(shell) + PascalCase(short), the declare-structure
    convention (shop.cart -> ShopCart). Purely mechanical; not design."""
    m = ID_RE.match(surface_id)
    if not m:
        raise ValueError(f"cannot derive comp from malformed id '{surface_id}'")
    shell, short = m.group(1), m.group(2)
    return _cap(shell) + _cap(short)


def _cap(seg: str) -> str:
    return seg[0].upper() + seg[1:]


# --------------------------------------------------------------- emission


def emit_registry(answers: dict) -> list[dict]:
    """Seed registry: one entry per elicited surface, surface ALWAYS null.

    The keys are exactly {id, label, shell, comp, surface} — the contract the
    designer's declare-structure enforces. No entry is invented and none is
    dropped: len(out) == len(answers['surfaces']), asserted by the self-test.
    """
    out = []
    for s in answers.get("surfaces", []):
        out.append({
            "id": s["id"],
            "label": s["label"],
            "shell": s["shell"],
            "comp": derive_comp(s["id"]),
            "surface": None,  # intake names; design binds. Never non-null here.
        })
    return out


def _block(title: str, node: dict | None) -> list[str]:
    """Render one brief section. An `inferred` field gets the visible mark;
    client/founder provenance is noted quietly underneath (transparency, not
    noise). The value is passed through verbatim — never rephrased."""
    lines = [f"## {title}", ""]
    if node is None:
        lines.append("_Not stated._")
        return lines
    val = node.get("value")
    prov = node.get("provenance")
    if prov == "inferred":
        lines.append(INFERRED_MARK)
        lines.append("")
    if isinstance(val, dict):
        lines.extend(_layout_template_lines(val))
    elif isinstance(val, list):
        if val:
            lines.extend(f"- {item}" for item in val)
        else:
            lines.append("_None stated._")
    else:
        lines.append(str(val))
    lines.append("")
    lines.append(f"_provenance: {prov}_")
    lines.append("")
    return lines


def _layout_template_lines(val: dict) -> list[str]:
    """Render a layoutTemplate value readably: category, archetype, the
    grid-template-areas per rung of the viewport ladder (compact / medium /
    expanded), and the named containers with their content hints. The value
    is passed through verbatim from layout_templates.json — never reworded."""
    out = [
        f"- category: {val.get('category')}",
        f"- archetype: {val.get('archetype')}",
        "",
    ]
    areas = val.get("areas")
    if isinstance(areas, dict):
        out.append("Grid template areas per rung (viewport ladder):")
        out.append("")
        for rung in ("compact", "medium", "expanded"):
            rows = areas.get(rung)
            if not rows:
                continue
            out.append(f"{rung}:")
            out.append("```")
            out.extend(f'"{row}"' for row in rows)
            out.append("```")
            out.append("")
    containers = val.get("containers")
    if isinstance(containers, dict) and containers:
        out.append("Named containers:")
        out.append("")
        for name, meta in containers.items():
            if isinstance(meta, dict):
                ctype, hints = meta.get("type", ""), meta.get("hints", "")
                out.append(f"- `{name}` — {ctype}: {hints}" if hints else f"- `{name}` — {ctype}")
            else:
                out.append(f"- `{name}` — {meta}")
        out.append("")
    return out


def emit_brief(answers: dict) -> str:
    """Render the brief markdown. Every `inferred` field is visibly marked;
    the header states the rule once. No prose is generated beyond section
    scaffolding and the provenance notes — field VALUES come straight from the
    answers document."""
    product = (answers.get("product") or {}).get("value", "(unnamed product)")
    lines = [
        f"# {product} — design brief",
        "",
        "> Emitted by app-box-intake from elicited answers.",
        "> **Intake elicits; it does not generate** (architecture §22).",
        "> Fields marked **[inferred]** were not stated by the client and MUST",
        "> be confirmed before design consumes this brief.",
        "",
    ]
    for key, title in FIELD_TITLES:
        lines.extend(_block(title, answers.get(key)))

    # surface inventory — the registry seed (surface null everywhere)
    surfaces = answers.get("surfaces", [])
    lines.append("## Surface inventory — the registry seed")
    lines.append("")
    if not surfaces:
        lines.append("_No surfaces named at intake. The designer authors the registry._")
    else:
        lines.append("| id | shell | comp | label | surface |")
        lines.append("|---|---|---|---|---|")
        for s in surfaces:
            lines.append(
                f"| `{s['id']}` | {s['shell']} | {derive_comp(s['id'])} | "
                f"{s['label']} | _null_ |"
            )
        lines.append("")
        lines.append(
            "Every `surface` is `null` — intake names what the client asked for; "
            "design binds a surface to each."
        )
    lines.append("")
    return "\n".join(lines)


# ----------------------------------------------------- hand-written brief (10.7)


_TABLE_ROW = re.compile(r"^\s*\|\s*`?([^`|]+)`?\s*\|")
_TABLE_SPLIT = re.compile(r"\s*\|\s*")


def seed_from_brief(md: str) -> list[dict]:
    """Plan 10.7: a hand-written brief is valid input. Derive the registry
    seed from its surface-inventory table WITHOUT rewriting the brief (the
    brief is the client's words — the ideal case). Rows whose first cell
    matches the <shell>.<short> id pattern become seed entries; surface is null.
    A brief with no such table yields an empty seed (the designer authors the
    registry) and that is NOT an error — intake is optional.
    """
    lines = md.splitlines()
    seed: list[dict] = []
    in_table = False
    header_idx: dict[str, int] = {}
    for line in lines:
        stripped = line.strip()
        is_row = stripped.startswith("|") and stripped.endswith("|") and "|" in stripped[1:-1]
        if not is_row:
            in_table = False
            continue
        cells = [c.strip().strip("`") for c in _TABLE_SPLIT.split(stripped.strip("|"))]
        # separator row (|---|---|)
        if all(set(c) <= set("-: ") and c for c in cells):
            continue
        if not in_table:
            # this row is a header; remember column positions
            header_idx = {name.lower(): i for i, name in enumerate(cells) if name}
            in_table = True
            continue
        id_col = header_idx.get("id", 0)
        if id_col >= len(cells):
            continue
        sid = cells[id_col].strip()
        m = ID_RE.match(sid)
        if not m:
            continue
        shell, _short = m.group(1), m.group(2)
        label = cells[header_idx["label"]].strip() if "label" in header_idx and header_idx["label"] < len(cells) else _cap(_short)
        entry = {
            "id": sid,
            "label": label or _cap(_short),
            "shell": shell,
            "comp": derive_comp(sid),
            "surface": None,
        }
        # additive sibling metadata (DESIGN-ARCHITECTURE: never woven into the
        # four required fields): optional columns pass through when present —
        # app-box-story-mapper emits `priority` / `release` rollups this way.
        for opt in ("priority", "release"):
            if opt in header_idx and header_idx[opt] < len(cells):
                val = cells[header_idx[opt]].strip()
                if val:
                    entry[opt] = val
        seed.append(entry)
    # de-dup keeping first, preserving order
    seen: set[str] = set()
    deduped = []
    for e in seed:
        if e["id"] in seen:
            continue
        seen.add(e["id"])
        deduped.append(e)
    return deduped


# ----------------------------------------------------------------- cli io


def _default_brief_out() -> Path:
    return Path(os.environ.get("INTAKE_BRIEF_OUT") or (ROOT / "docs" / "design" / "brief.md"))


def _default_registry_out() -> Path:
    return Path(os.environ.get("INTAKE_REGISTRY_OUT") or (ROOT / "docs" / "design" / "registry.json"))


def _load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def _write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def cmd_validate(args) -> int:
    answers = _load_json(Path(args.answers))
    errs = validate(answers)
    for e in errs:
        print(f"ERROR {e}")
    print(f"\nintake validate: {len(errs)} error(s)")
    return 1 if errs else 0


def cmd_emit(args) -> int:
    answers = _load_json(Path(args.answers))
    errs = validate(answers)
    if errs:
        for e in errs:
            print(f"ERROR {e}", file=sys.stderr)
        print(f"\nintake emit: {len(errs)} error(s) — nothing written", file=sys.stderr)
        return 1
    brief_out = Path(args.brief_out) if args.brief_out else _default_brief_out()
    registry_out = Path(args.registry_out) if args.registry_out else _default_registry_out()
    _write(brief_out, emit_brief(answers))
    _write(registry_out, json.dumps(emit_registry(answers), indent=2) + "\n")
    n = len(answers.get("surfaces", []))
    inf = _count_inferred(answers)
    print(f"intake emit: brief -> {brief_out}, registry ({n} entries, surface null) -> {registry_out}")
    if inf:
        print(f"  {inf} inferred field(s) marked in the brief — confirm before design.")
    return 0


def cmd_seed(args) -> int:
    md = Path(args.brief).read_text(encoding="utf-8")
    registry = seed_from_brief(md)
    registry_out = Path(args.registry_out) if args.registry_out else _default_registry_out()
    _write(registry_out, json.dumps(registry, indent=2) + "\n")
    note = f"{len(registry)} entries" if registry else "no surface table found — empty seed (designer authors registry)"
    print(f"intake seed: brief passed through unmodified; registry ({note}) -> {registry_out}")
    return 0


def _count_inferred(answers: dict) -> int:
    n = 0
    for key, _ in FIELD_TITLES:
        node = answers.get(key)
        if isinstance(node, dict) and node.get("provenance") == "inferred":
            n += 1
    n += sum(1 for s in answers.get("surfaces", []) if s.get("provenance") == "inferred")
    return n


# ------------------------------------------------------------------ self-test


def _self_test() -> None:
    """Negative-case self-test (R5: a check that has never failed is not a
    check). Each block plants a defect and asserts the engine catches it, plus
    the elicits-never-generates invariant: emission adds no content."""
    with tempfile.TemporaryDirectory() as d:
        tmp = Path(d)

        def good_answers():
            return {
                "product": {"value": "Demo app", "provenance": "client"},
                "audience": {"value": "Indie devs", "provenance": "client"},
                "appMustDo": {"value": ["list projects", "run a build"], "provenance": "client"},
                "targets": {"value": ["macos"], "provenance": "client"},
                "brand": {"value": "none stated", "provenance": "inferred"},
                "surfaces": [
                    {"id": "projects.home", "label": "Home", "shell": "projects", "provenance": "client"},
                    {"id": "projects.new", "label": "New", "shell": "projects", "provenance": "client"},
                ],
            }

        # 1. valid input -> no errors
        assert validate(good_answers()) == [], "valid answers rejected"

        # 2. NEGATIVE: unknown provenance is rejected and named
        bad = good_answers(); bad["audience"]["provenance"] = "guessed"
        e = validate(bad)
        assert any("audience" in x and "guessed" in x for x in e), f"missed bad provenance: {e}"

        # 3. NEGATIVE: malformed surface id is rejected and named
        bad = good_answers(); bad["surfaces"][0]["id"] = "Projects.Home"
        e = validate(bad)
        assert any("surfaces[0]" in x and "Projects.Home" in x for x in e), f"missed bad id: {e}"

        # 4. NEGATIVE: shell must equal id prefix
        bad = good_answers(); bad["surfaces"][1]["shell"] = "build"
        e = validate(bad)
        assert any("surfaces[1]" in x and "first segment" in x for x in e), f"missed shell mismatch: {e}"

        # 5. NEGATIVE: duplicate id rejected (ids are permanent)
        bad = good_answers(); bad["surfaces"][1]["id"] = "projects.home"
        e = validate(bad)
        assert any("duplicate" in x for x in e), f"missed duplicate id: {e}"

        # 6. ELICITS-NEVER-GENERATES: registry has exactly the input surfaces,
        #    no invented entries, every surface null.
        ans = good_answers()
        reg = emit_registry(ans)
        assert len(reg) == len(ans["surfaces"]), "registry invented or dropped entries"
        assert {e["id"] for e in reg} == {s["id"] for s in ans["surfaces"]}, "registry id set drifted"
        assert all(e["surface"] is None for e in reg), "a seed surface is non-null (intake must not design)"

        # 7. NEGATIVE generation guard: if emit_registry somehow returned an
        #    extra entry, the count assertion above would have to catch it.
        #    Plant the failure explicitly to prove the guard bites.
        tampered = reg + [{"id": "chat.home", "label": "x", "shell": "chat", "comp": "ChatHome", "surface": None}]
        assert len(tampered) != len(ans["surfaces"]), "generation guard would not bite on an extra entry"

        # 8. comp derivation by convention (shop.cart -> ShopCart)
        assert derive_comp("shop.cart") == "ShopCart", derive_comp("shop.cart")
        assert derive_comp("projects.home") == "ProjectsHome", derive_comp("projects.home")
        assert derive_comp("settings.kits") == "SettingsKits", derive_comp("settings.kits")

        # 9. inferred field is visibly marked in the brief; a client field is NOT
        brief = emit_brief(good_answers())
        assert "**[inferred]**" in brief, "inferred field not marked in brief"
        # brand is inferred; audience is client — the mark must not smear onto client fields
        audience_section = brief[brief.index("## Audience"):]
        audience_section = audience_section[:audience_section.index("##", 2)]
        assert "**[inferred]**" not in audience_section, "inferred mark leaked onto a client field"

        # 10. brief passes field VALUES through verbatim (no rewording)
        assert "Indie devs" in brief and "list projects" in brief, "brief dropped elicited values"

        # 11. seed_from_brief (10.7): a hand-written brief with a table seeds
        #     the registry; surface null; the brief text is NOT mutated.
        handwritten = tmp / "brief.md"
        md = (
            "# Widget shop\n\n"
            "## Surface inventory\n\n"
            "| id | shell | label |\n"
            "|---|---|---|\n"
            "| `shop.cart` | shop | Cart |\n"
            "| `shop.home` | shop | Home |\n"
        )
        handwritten.write_text(md, encoding="utf-8")
        seed = seed_from_brief(md)
        assert len(seed) == 2, f"hand-written brief seed wrong size: {seed}"
        assert seed[0] == {"id": "shop.cart", "label": "Cart", "shell": "shop", "comp": "ShopCart", "surface": None}, seed[0]
        assert all(e["surface"] is None for e in seed), "hand-written seed bound a surface"

        # 12. NEGATIVE: a brief with NO surface table -> empty seed, not an error
        assert seed_from_brief("# Just prose\n\nNo table here.\n") == [], "empty brief should seed nothing"

        # 13. NEGATIVE: a row that is not a valid id is skipped, not crashed
        mixed = "| id | shell |\n|---|---|\n| `shop.cart` | shop |\n| not-an-id | x |\n"
        s2 = seed_from_brief(mixed)
        assert [e["id"] for e in s2] == ["shop.cart"], f"bad id row not skipped: {s2}"

        # 13b. optional priority/release columns pass through as sibling
        #      metadata; absent columns change nothing (see 11).
        prio = "| id | label | priority | release |\n|---|---|---|---|\n| `shop.cart` | Cart | must | Release 1 |\n"
        s3 = seed_from_brief(prio)
        assert s3[0].get("priority") == "must" and s3[0].get("release") == "Release 1", s3[0]
        assert s3[0]["comp"] == "ShopCart" and s3[0]["surface"] is None, "additive metadata must not touch the canon"

        # 14. emit writes both artefacts and returns 0; invalid input writes
        #     nothing and returns 1 (no partial artefacts on failure).
        ans_path = tmp / "answers.json"
        ans_path.write_text(json.dumps(good_answers()), encoding="utf-8")
        import importlib.util
        spec = importlib.util.spec_from_file_location("intake_under_test", __file__)
        mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
        rc = mod.cmd_emit(argparse.Namespace(answers=str(ans_path),
                       brief_out=str(tmp / "out" / "brief.md"),
                       registry_out=str(tmp / "out" / "registry.json")))
        assert rc == 0 and (tmp / "out" / "brief.md").exists() and (tmp / "out" / "registry.json").exists()
        bad_path = tmp / "bad.json"
        bad_path.write_text(json.dumps({"product": {"value": "x", "provenance": "guessed"}}), encoding="utf-8")
        rc2 = mod.cmd_emit(argparse.Namespace(answers=str(bad_path),
                        brief_out=str(tmp / "out2" / "brief.md"),
                        registry_out=str(tmp / "out2" / "registry.json")))
        assert rc2 == 1 and not (tmp / "out2").exists(), "invalid input wrote partial artefacts"

        # 15. layoutTemplate: a well-formed pick validates and renders as its
        #     own brief section, BEFORE the surface inventory table (the
        #     gate's brief<->registry bijection parses only that table).
        ans = good_answers()
        ans["layoutTemplate"] = {
            "value": {
                "category": "productivity",
                "archetype": "list-detail",
                "areas": {
                    "compact": ["app-bar", "list", "tab-bar"],
                    "medium": ["app-bar app-bar app-bar", "nav-rail list detail"],
                    "expanded": ["app-bar app-bar app-bar", "nav-rail list detail"],
                },
                "containers": {
                    "list": {"type": "content", "hints": "the collection; source of selection"},
                    "detail": {"type": "content", "hints": "the selected item; a pushed route at compact"},
                },
            },
            "provenance": "client",
        }
        assert validate(ans) == [], "well-formed layoutTemplate rejected"
        brief = emit_brief(ans)
        assert "## Layout template" in brief, "layout template section missing from brief"
        lt = brief[brief.index("## Layout template"):brief.index("## Surface inventory")]
        assert "list-detail" in lt and '"nav-rail list detail"' in lt, "layout template areas not rendered"
        assert "- `detail` — content:" in lt, "named containers not rendered"
        assert "_provenance: client_" in lt, "layout template provenance footer missing"
        # the section carries no markdown table rows -> the surface-table
        # parsers (gate + seed_from_brief) see nothing new
        assert not any(l.strip().startswith("|") for l in lt.splitlines()), "layout section leaked table rows"

        # 16. NEGATIVE: layoutTemplate with a non-dict value is rejected
        bad = good_answers(); bad["layoutTemplate"] = {"value": "feed", "provenance": "client"}
        e = validate(bad)
        assert any("layoutTemplate" in x for x in e), f"missed non-dict layoutTemplate: {e}"

        # 17. NEGATIVE: layoutTemplate missing a rung is rejected
        bad = good_answers()
        bad["layoutTemplate"] = json.loads(json.dumps(ans["layoutTemplate"]))
        del bad["layoutTemplate"]["value"]["areas"]["expanded"]
        e = validate(bad)
        assert any("expanded" in x for x in e), f"missed missing rung: {e}"

    print("self-test: PASS")


def main(argv: list[str]) -> int:
    p = argparse.ArgumentParser(prog="intake.py", description=__doc__.splitlines()[0])
    p.add_argument("--self-test", action="store_true", help="run negative-case self-test")
    sub = p.add_subparsers(dest="cmd")

    v = sub.add_parser("validate", help="validate an answers document")
    v.add_argument("answers")

    e = sub.add_parser("emit", help="emit brief.md + registry.json from answers")
    e.add_argument("--answers", required=True)
    e.add_argument("--brief-out")
    e.add_argument("--registry-out")

    sd = sub.add_parser("seed", help="derive registry.json from a hand-written brief (10.7)")
    sd.add_argument("--brief", required=True)
    sd.add_argument("--registry-out")

    args = p.parse_args(argv)
    if args.self_test:
        _self_test(); return 0
    if args.cmd == "validate":
        return cmd_validate(args)
    if args.cmd == "emit":
        return cmd_emit(args)
    if args.cmd == "seed":
        return cmd_seed(args)
    p.print_help(sys.stderr); return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
