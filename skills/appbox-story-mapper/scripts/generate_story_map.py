#!/usr/bin/env python3
"""User Story Map HTML Generator — Epic → Feature → Story with MoSCoW + Release swimlanes."""

import argparse
import json
import re
import sys
from html import escape
from datetime import datetime

VALID_PRIORITIES = {"must", "should", "could", "wont"}

PRIORITY_META = {
    "must":   {"label": "Must Have",  "color": "#dc2626", "bg": "#fef2f2", "border": "#fca5a5"},
    "should": {"label": "Should Have","color": "#ea580c", "bg": "#fff7ed", "border": "#fdba74"},
    "could":  {"label": "Could Have", "color": "#2563eb", "bg": "#eff6ff", "border": "#93c5fd"},
    "wont":   {"label": "Won't Have", "color": "#6b7280", "bg": "#f9fafb", "border": "#d1d5db"},
}

EPIC_PALETTE = [
    "#6366f1", "#8b5cf6", "#06b6d4", "#10b981",
    "#f59e0b", "#ef4444", "#ec4899", "#14b8a6",
]


def validate_data(data):
    errors = []
    if not isinstance(data, dict):
        return ["Input must be a JSON object"]
    if not data.get("project"):
        errors.append("Missing required field: 'project'")
    if not isinstance(data.get("releases"), list) or not data["releases"]:
        errors.append("Missing or empty 'releases' array")
    if not isinstance(data.get("epics"), list) or not data["epics"]:
        errors.append("Missing or empty 'epics' array")
    if errors:
        return errors

    release_names = set()
    for i, rel in enumerate(data["releases"]):
        if not isinstance(rel, dict) or not rel.get("name"):
            errors.append(f"releases[{i}]: missing 'name'")
        else:
            release_names.add(rel["name"])

    for ei, epic in enumerate(data["epics"]):
        if not isinstance(epic, dict) or not epic.get("name"):
            errors.append(f"epics[{ei}]: missing 'name'")
            continue
        feats = epic.get("features")
        if not isinstance(feats, list) or not feats:
            errors.append(f"Epic '{epic['name']}': missing or empty 'features'")
            continue
        for fi, feat in enumerate(feats):
            if not isinstance(feat, dict) or not feat.get("name"):
                errors.append(f"Epic '{epic['name']}' features[{fi}]: missing 'name'")
                continue
            for si, story in enumerate(feat.get("stories", [])):
                tag = f"'{feat['name']}' story[{si}]"
                if not isinstance(story, dict) or not story.get("name"):
                    errors.append(f"{tag}: missing 'name'")
                    continue
                pri = story.get("priority", "")
                if pri not in VALID_PRIORITIES:
                    errors.append(f"{tag} '{story['name']}': invalid priority '{pri}'")
                rel = story.get("release", "")
                if rel not in release_names:
                    errors.append(f"{tag} '{story['name']}': unknown release '{rel}'")
    return errors


# --- appbox pipeline handoff -------------------------------------------------
# appbox-story-mapper feeds appbox-designer DIRECTLY (intake.py bypassed).
# The brief emitted here is the traceability source for gates/intake (plan
# 10.7): the gate parses the surface table for <shell>.<short> ids, so every id
# MUST match the registry id pattern — lowercase alnum segments, no hyphens.

ID_RE = re.compile(r"^([a-z][a-z0-9]*)\.([a-z][a-z0-9]*)$")


def slugify(name, used):
    """First ascii word of the name as a [a-z][a-z0-9]* slug (short ids make
    readable comps: user.registration -> UserRegistration); collisions get a
    digit suffix. CJK-only names fall back to 's'."""
    words = re.findall(r"[a-z0-9]+", name.lower())
    slug = next((w for w in words if w[0].isalpha()), "s")
    base, n = slug, 2
    while slug in used:
        slug = f"{base}{n}"
        n += 1
    used.add(slug)
    return slug


PRIORITY_RANK = {"must": 0, "should": 1, "could": 2, "wont": 3}


def derive_surfaces(data):
    """Epic -> shell, Feature -> surface. A feature whose stories are ALL 'wont'
    is out-of-scope this cycle, not a surface. Features with no stories stay
    surfaces (named, not yet detailed). Each surface carries a rollup of its
    live (non-wont) stories: strongest priority, earliest release."""
    used_shells, used_ids = set(), set()
    rel_order = {r["name"]: i for i, r in enumerate(data["releases"])}
    surfaces, out_of_scope = [], []
    for epic in data["epics"]:
        shell = slugify(epic["name"], used_shells)
        for feat in epic.get("features", []):
            stories = feat.get("stories", [])
            if stories and all(s.get("priority") == "wont" for s in stories):
                out_of_scope.append((epic["name"], feat["name"]))
                continue
            live = [s for s in stories if s.get("priority") != "wont"]
            surfaces.append({
                "id": f"{shell}.{slugify(feat['name'], used_ids)}",
                "label": feat["name"],
                "epic": epic["name"],
                "stories": stories,
                "priority": min((PRIORITY_RANK[s["priority"]] for s in live), default=None),
                "release": min((s["release"] for s in live),
                               key=lambda r: rel_order.get(r, len(rel_order)), default=""),
            })
    for s in surfaces:
        s["priority"] = next((p for p, r in PRIORITY_RANK.items() if r == s["priority"]), "")
    return surfaces, out_of_scope


def generate_brief(data, surfaces, out_of_scope):
    """docs/design/brief.md — gate-compatible (10.7): the surface table is what
    gates/intake traces the registry against. Stories ride as per-feature
    requirements; priorities/releases stay here as design context."""
    lines = [
        f"# {data['project']} — design brief",
        "",
        "Elicited via appbox-story-mapper; the full story map lives alongside",
        "this brief (`story-map.json`, `story_map.html`). Priorities are MoSCoW,",
        "grouped into release swimlanes. Every registry surface must trace to",
        "the surface inventory table below (gates/intake, plan 10.7).",
        "",
        "## Product",
        "",
        data["project"],
        "",
        "## Releases",
        "",
    ]
    for rel in data["releases"]:
        desc = f" — {rel['description']}" if rel.get("description") else ""
        lines.append(f"- **{rel['name']}**{desc}")
    lines += ["", "## The things the app must do", ""]
    for epic in data["epics"]:
        lines += [f"### {epic['name']}", ""]
        for feat in epic.get("features", []):
            lines += [f"#### {feat['name']}", ""]
            for s in feat.get("stories", []):
                desc = f" — {s['description']}" if s.get("description") else ""
                lines.append(f"- [{s.get('priority', '?')}/{s.get('release', '?')}] {s['name']}{desc}")
            lines.append("")
    lines += ["## Surface inventory", "",
              "| id | label | priority | release |",
              "|----|-------|----------|---------|"]
    for s in surfaces:
        lines.append(f"| `{s['id']}` | {s['label']} | {s['priority']} | {s['release']} |")
    lines.append("")
    if out_of_scope:
        lines += ["## Out of scope", ""]
        for epic_name, feat_name in out_of_scope:
            lines.append(f"- {feat_name} ({epic_name}) — all stories Won't-have this cycle")
        lines.append("")
    return "\n".join(lines)


def _self_test():
    sample = {
        "project": "Self-Test App",
        "releases": [{"name": "Release 1"}, {"name": "Release 2"}],
        "epics": [
            {"name": "User System", "features": [
                {"name": "Registration & Login", "stories": [
                    {"name": "Phone signup", "priority": "must", "release": "Release 1"},
                ]},
                {"name": "注册", "stories": [
                    {"name": "Phone signup", "priority": "must", "release": "Release 1"},
                ]},
                {"name": "Legacy SSO", "stories": [
                    {"name": "SAML login", "priority": "wont", "release": "Release 2"},
                ]},
            ]},
            {"name": "User System", "features": [
                {"name": "Registration & Login", "stories": []},
            ]},
        ],
    }
    assert not validate_data(sample), "sample must validate"
    surfaces, oos = derive_surfaces(sample)
    ids = [s["id"] for s in surfaces]
    assert all(ID_RE.match(i) for i in ids), f"ids must match gate pattern: {ids}"
    assert len(ids) == len(set(ids)), f"duplicate ids: {ids}"
    assert not any("legacy" in i for i in ids), "all-wont feature must not be a surface"
    assert ("User System", "Legacy SSO") in oos, "all-wont feature must be out-of-scope"
    assert ids[0] == "user.registration", f"first-word slug: {ids[0]}"
    by_id = {s["id"]: s for s in surfaces}
    assert by_id["user.registration"]["priority"] == "must", "rollup: strongest priority"
    assert by_id["user.registration"]["release"] == "Release 1", "rollup: earliest release"
    empty = by_id["user2.registration2"]
    assert empty["priority"] == "" and empty["release"] == "", "no stories -> blank rollup"
    brief = generate_brief(sample, surfaces, oos)
    # simulate the gate's parse: table cells matching ID_RE, first match per row
    found = []
    for line in brief.splitlines():
        s = line.strip()
        if not (s.startswith("|") and s.endswith("|")):
            continue
        cells = [c.strip().strip("`") for c in s.strip("|").split("|")]
        if all(set(c) <= set("-: ") and c for c in cells):
            continue
        for c in cells:
            if ID_RE.match(c):
                found.append(c)
                break
    assert sorted(found) == sorted(set(ids)), f"gate would see {found}, expected {ids}"
    assert "Out of scope" in brief and "Legacy SSO" in brief
    generate_html(sample)  # HTML path must not regress
    print("self-test OK")


def generate_html(data):
    project = escape(data["project"])
    releases = data["releases"]
    epics = data["epics"]
    now = datetime.now().strftime("%Y-%m-%d %H:%M")

    features = []
    for ei, epic in enumerate(epics):
        for feat in epic.get("features", []):
            features.append((ei, feat))
    total_cols = len(features) or 1
    col_w = 210

    story_lookup = {}
    all_stories = []
    for fi, (ei, feat) in enumerate(features):
        for story in feat.get("stories", []):
            key = (fi, story.get("release", ""))
            story_lookup.setdefault(key, []).append(story)
            all_stories.append(story)

    total_stories = len(all_stories)
    total_points = sum(s.get("points", 0) for s in all_stories)

    def _stats_html():
        parts = [f'<span class="stat-item"><b>{total_stories}</b> Stories</span>']
        if total_points:
            parts.append(f'<span class="stat-item"><b>{total_points}</b> Points</span>')
        parts.append('<span class="stat-sep">|</span>')
        for p in ["must", "should", "could", "wont"]:
            m = PRIORITY_META[p]
            cnt = sum(1 for s in all_stories if s.get("priority") == p)
            pts = sum(s.get("points", 0) for s in all_stories if s.get("priority") == p)
            badge = f'{cnt}' if not pts else f'{cnt} ({pts}pt)'
            parts.append(
                f'<span class="stat-badge" style="background:{m["bg"]};color:{m["color"]};'
                f'border:1px solid {m["border"]}">{escape(m["label"])} {badge}</span>'
            )
        parts.append('<span class="stat-sep">|</span>')
        for rel in releases:
            rn = escape(rel["name"])
            cnt = sum(1 for s in all_stories if s.get("release") == rel["name"])
            parts.append(f'<span class="stat-item">{rn}: <b>{cnt}</b></span>')
        return "\n".join(parts)

    def _epic_row():
        cells = []
        for ei, epic in enumerate(epics):
            span = len(epic.get("features", []))
            if span == 0:
                continue
            color = EPIC_PALETTE[ei % len(EPIC_PALETTE)]
            w = span * col_w
            cells.append(
                f'<div class="epic-cell" style="width:{w}px;background:{color}">'
                f'{escape(epic["name"])}</div>'
            )
        return "".join(cells)

    def _feature_row():
        cells = []
        for fi, (ei, feat) in enumerate(features):
            color = EPIC_PALETTE[ei % len(EPIC_PALETTE)]
            cells.append(
                f'<div class="feat-cell" style="width:{col_w}px;border-top:3px solid {color}">'
                f'{escape(feat["name"])}</div>'
            )
        return "".join(cells)

    def _story_card(story):
        pri = story.get("priority", "must")
        m = PRIORITY_META.get(pri, PRIORITY_META["must"])
        name = escape(story.get("name", ""))
        desc = escape(story.get("description", ""))
        pts = story.get("points")
        pts_html = f'<span class="card-pts">{pts} pt</span>' if pts else ""
        desc_html = f'<div class="card-desc">{desc}</div>' if desc else ""
        title_attr = f' title="{desc}"' if desc else ""
        return (
            f'<div class="story-card" style="border-left:4px solid {m["color"]};background:{m["bg"]}"'
            f'{title_attr}>'
            f'<div class="card-title">{name}</div>'
            f'{desc_html}'
            f'<div class="card-footer">'
            f'<span class="card-pri" style="color:{m["color"]}">{escape(m["label"])}</span>'
            f'{pts_html}'
            f'</div></div>'
        )

    def _release_sections():
        sections = []
        for ri, rel in enumerate(releases):
            rname = rel["name"]
            rdesc = rel.get("description", "")
            label = escape(rname)
            if rdesc:
                label += f' <span class="rel-desc">— {escape(rdesc)}</span>'

            cols = []
            for fi in range(total_cols):
                stories = story_lookup.get((fi, rname), [])
                cards = "".join(_story_card(s) for s in stories)
                if not cards:
                    cards = '<div class="empty-slot"></div>'
                cols.append(f'<div class="story-col" style="width:{col_w}px">{cards}</div>')

            sections.append(
                f'<div class="release-section">'
                f'<div class="release-divider">'
                f'<div class="release-line"></div>'
                f'<div class="release-badge">{label}</div>'
                f'</div>'
                f'<div class="map-row stories-row">{"".join(cols)}</div>'
                f'</div>'
            )
        return "".join(sections)

    map_w = total_cols * col_w

    html = f'''<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>{project} — User Story Map</title>
<style>
*,*::before,*::after{{box-sizing:border-box;margin:0;padding:0}}
body{{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,"Helvetica Neue",Arial,
"Noto Sans SC","PingFang SC","Microsoft YaHei",sans-serif;background:#f1f5f9;color:#1e293b;
line-height:1.5;min-height:100vh}}
.container{{max-width:100%;padding:20px}}
header{{display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;
margin-bottom:16px;gap:12px}}
h1{{font-size:1.5rem;font-weight:700;color:#0f172a}}
.meta{{font-size:.8rem;color:#64748b}}
.legend{{display:flex;gap:10px;flex-wrap:wrap;align-items:center}}
.legend-item{{display:flex;align-items:center;gap:4px;font-size:.78rem}}
.legend-dot{{width:12px;height:12px;border-radius:3px}}
.stats-bar{{display:flex;flex-wrap:wrap;gap:8px;align-items:center;padding:10px 16px;
background:#fff;border-radius:8px;margin-bottom:16px;box-shadow:0 1px 3px rgba(0,0,0,.06);
font-size:.82rem}}
.stat-item b{{color:#0f172a}}
.stat-sep{{color:#cbd5e1;margin:0 2px}}
.stat-badge{{padding:2px 8px;border-radius:4px;font-size:.78rem;font-weight:500}}
.map-scroll{{overflow-x:auto;padding-bottom:16px}}
.map-inner{{min-width:{map_w}px}}
.map-row{{display:flex}}
.epic-cell{{color:#fff;font-weight:700;font-size:.92rem;padding:10px 12px;text-align:center;
border-radius:6px 6px 0 0;margin-right:1px}}
.feat-cell{{background:#fff;font-weight:600;font-size:.82rem;padding:8px 10px;text-align:center;
border-right:1px solid #e2e8f0;margin-bottom:0}}
.release-section{{margin-top:0}}
.release-divider{{position:relative;display:flex;align-items:center;margin:14px 0 8px}}
.release-line{{flex:1;height:2px;background:repeating-linear-gradient(
90deg,#94a3b8 0,#94a3b8 6px,transparent 6px,transparent 12px)}}
.release-badge{{position:absolute;left:0;background:#fff;padding:2px 14px;border-radius:12px;
font-size:.82rem;font-weight:700;color:#334155;border:2px solid #94a3b8;white-space:nowrap}}
.release-badge .rel-desc{{font-weight:400;color:#64748b;font-size:.78rem}}
.stories-row{{gap:1px}}
.story-col{{padding:4px 4px 8px;min-height:40px;display:flex;flex-direction:column;gap:6px}}
.story-card{{border-radius:6px;padding:8px 10px;cursor:default;transition:box-shadow .15s,
transform .15s;box-shadow:0 1px 2px rgba(0,0,0,.05)}}
.story-card:hover{{box-shadow:0 4px 12px rgba(0,0,0,.1);transform:translateY(-1px)}}
.card-title{{font-size:.82rem;font-weight:600;color:#1e293b;margin-bottom:2px}}
.card-desc{{font-size:.72rem;color:#64748b;margin-bottom:4px;display:-webkit-box;
-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden}}
.card-footer{{display:flex;justify-content:space-between;align-items:center}}
.card-pri{{font-size:.7rem;font-weight:600}}
.card-pts{{font-size:.7rem;color:#475569;background:#f1f5f9;padding:1px 6px;border-radius:3px}}
.empty-slot{{min-height:20px}}
.print-btn{{position:fixed;bottom:20px;right:20px;padding:8px 20px;background:#6366f1;color:#fff;
border:none;border-radius:8px;font-size:.85rem;cursor:pointer;box-shadow:0 2px 8px rgba(99,102,241,.3);
z-index:100}}
.print-btn:hover{{background:#4f46e5}}
@media print{{
  body{{background:#fff;-webkit-print-color-adjust:exact;print-color-adjust:exact}}
  .container{{padding:8px}}
  .print-btn{{display:none}}
  .map-scroll{{overflow:visible}}
  @page{{size:A3 landscape;margin:10mm}}
}}
</style>
</head>
<body>
<div class="container">
<header>
  <div>
    <h1>{project}</h1>
    <div class="meta">User Story Map &middot; Generated {now}</div>
  </div>
  <div class="legend">
    {"".join(
        f'<span class="legend-item"><span class="legend-dot" style="background:{m["color"]}"></span>{escape(m["label"])}</span>'
        for m in PRIORITY_META.values()
    )}
  </div>
</header>
<div class="stats-bar">
{_stats_html()}
</div>
<div class="map-scroll">
<div class="map-inner">
  <div class="map-row epic-row-wrap">{_epic_row()}</div>
  <div class="map-row feat-row-wrap">{_feature_row()}</div>
  {_release_sections()}
</div>
</div>
</div>
<button class="print-btn" onclick="window.print()">&#128424; Print</button>
</body>
</html>'''
    return html


def main():
    parser = argparse.ArgumentParser(description="Generate an interactive User Story Map HTML file.")
    parser.add_argument("--input", "-i", help="Input JSON file path (reads stdin if omitted)")
    parser.add_argument("--output", "-o", help="Output HTML file path")
    parser.add_argument("--data-out", help="Write the validated story-map data JSON here (docs/design/story-map.json)")
    parser.add_argument("--brief-out", help="Write the gate-compatible design brief here (docs/design/brief.md)")
    parser.add_argument("--self-test", action="store_true", help="Run the handoff self-check and exit")
    args = parser.parse_args()

    if args.self_test:
        _self_test()
        return
    if not args.output:
        parser.error("--output is required (unless --self-test)")

    try:
        if args.input:
            with open(args.input, "r", encoding="utf-8") as f:
                data = json.load(f)
        else:
            data = json.load(sys.stdin)
    except json.JSONDecodeError as e:
        print(f"JSON parse error: {e}", file=sys.stderr)
        sys.exit(1)
    except FileNotFoundError:
        print(f"File not found: {args.input}", file=sys.stderr)
        sys.exit(1)

    errors = validate_data(data)
    if errors:
        for err in errors:
            print(f"Validation error: {err}", file=sys.stderr)
        sys.exit(1)

    html = generate_html(data)
    with open(args.output, "w", encoding="utf-8") as f:
        f.write(html)
    print(f"Story map generated: {args.output}")

    if args.data_out:
        with open(args.data_out, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
            f.write("\n")
        print(f"Story-map data written: {args.data_out}")

    if args.brief_out:
        surfaces, out_of_scope = derive_surfaces(data)
        with open(args.brief_out, "w", encoding="utf-8") as f:
            f.write(generate_brief(data, surfaces, out_of_scope))
        print(f"Design brief written: {args.brief_out} "
              f"({len(surfaces)} surfaces, {len(out_of_scope)} out-of-scope)")


if __name__ == "__main__":
    main()
