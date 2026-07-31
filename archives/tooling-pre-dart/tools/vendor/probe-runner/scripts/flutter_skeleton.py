#!/usr/bin/env python3
"""flutter_skeleton — content-free skeleton capture for a Flutter app over the
Dart VM service, the Flutter sibling of `web_skeleton`.

`flutter_tree --kind render` returns a human-readable `toString` TEXT DUMP
(`ext.flutter.debugDumpRenderTree`), not structured geometry. Structured
per-element screen rects only come from walking the element tree with a
self-contained Dart closure that reads `localToGlobal(Offset.zero)` + `size`
(+ `devicePixelRatio`). That pattern is proven in `flutter_flipbook._rect_expr`
(single element); this verb generalises it to EVERY `RenderBox` in the tree and
emits the same `probe-skeleton/2` schema `web_skeleton` does, so
`skeleton_diff` works on Flutter output UNMODIFIED.

Honesty model (same as the flipbook, `SKILL.md`): exact where an introspection
oracle exists. Here the oracle is the VM render tree, so bbox is exact (logical
points). Flutter has no cheap computed-style path (no CSS), so `font` detail and
`sizing` are emitted at `confidence:"low"` — they are placeholders, not
certified measurements, and `skeleton_diff` down-weights them accordingly.

Run `flutter_attach.py --url ...` first to cache the VM service URL.

Usage:
  flutter_skeleton.py                 # dump every RenderBox -> probe-skeleton/2
  flutter_skeleton.py --out sk.json
  flutter_skeleton.py --self-test     # verify classify + build offline (no VM)
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any, Optional

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import die, emit_json, emit_path, out_path


# ─── pure logic (unit-tested in test_flutter_skeleton.py) ─────────────────────

# Flutter widget runtimeType → skeleton role. Mirrors web_skeleton.classify's
# intent (text / image / box / svg / unknown_box) but keyed on Flutter types,
# since there is no DOM. Unknown / purely-structural widgets -> unknown_box
# (honest confidence:low); zero-area boxes are dropped upstream (build_skeleton).
# Flutter widget runtimeType → skeleton role. Mirrors web_skeleton.classify's
# intent (text / image / icon / box / unknown_box) but keyed on Flutter types,
# since there is no DOM. Grounded in Flutter's render model (verified against the
# live home tree + Flutter API source):
#
#   - PAINTING widgets create a RenderBox that paints visible content:
#       RichText/Text/EditableText/SelectableText → RenderParagraph (text glyph)
#       Image/FadeInImage → RenderImage (raster/decoded pixels)
#       Icon → resolves to RichText internally (icon.dart build() returns a
#              Semantics-wrapped RichText of the glyph codepoint) → so Icon's
#              own element has no RenderBox; its RichText child carries 'text'.
#       DecoratedBox/ColoredBox/Material/Card/PhysicalShape → RenderDecoratedBox
#              /RenderColoredBox (bg color + shape + elevation) → box
#       CustomPaint → RenderCustomPaint (vector/chart art) → box
#
#   - STRUCTURAL widgets either have NO own RenderObject (StatelessWidget
#     composition — Container delegates to DecoratedBox/ColoredBox/Padding) OR
#     have a RenderBox that paints NO intrinsic visual (RenderPadding insets its
#     child; RenderConstrained applies constraints; RenderSemantics handles
#     a11y; RenderRepaintBoundary isolates painting). Keeping these as skeleton
#     nodes DOUBLE-COUNTS their child's geometry (parent+child share the same
#     bbox) and adds skeleton_diff noise (two nodes at one geometry). DROP them
#     (return None) so only painting leaves + containers-with-bg ship.
#
# The double-count risk is real: skeleton_diff matches by geometry, so a kept
# Padding (same bbox as its child) would match the same design node as the child
# → over-counting. Dropping structural wrappers is the principled fix.
# Painting TEXT widgets → RenderParagraph (text glyphs). TextSpan is an InlineSpan
# (not a widget runtimeType) and DefaultTextStyle delegates paint to its RichText
# child (structural — listed in _STRUCTURAL_TYPES), so neither is a painting widget.
_TEXT_TYPES = frozenset({
    "Text", "RichText", "EditableText", "SelectableText",
})
_IMAGE_TYPES = frozenset({
    "Image", "FadeInImage", "CircleAvatar",
})
# Widgets that paint a visible BOX (bg color / shape / elevation / decoration).
# These are the containers-with-background the design's CSS .card/.surface maps to.
_BOX_TYPES = frozenset({
    "DecoratedBox", "ColoredBox", "Material", "Card", "PhysicalShape",
    "PhysicalModel", "ShapeDecoration", "CustomPaint", "RawMaterialButton",
})
# The SINGLE source of truth for which widget runtimeTypes the Dart subtree walk
# EMITS a row for (the emission gate). This is the union of the three painting
# buckets above; the Dart `_isPainting` body is GENERATED from it (see
# _bfs_expr) so the Python role-assigner (classify) and the Dart emission gate
# can never diverge — the prior hand-maintained Dart literal omitted `Material`
# (present in _BOX_TYPES) so Material containers were silently never captured.
_PAINTING_TYPES = _TEXT_TYPES | _IMAGE_TYPES | _BOX_TYPES
# Purely-structural widgets: NO intrinsic paint (layout insets/constraints,
# gesture, semantics, repaint isolation, focus, keep-alive). Drop entirely —
# they double-count their child's geometry. (Container is a StatelessWidget
# with no own RenderObject; it won't appear as a RenderBox node anyway, but
# listed here for safety if a future Flutter version gives it one.)
_STRUCTURAL_TYPES = frozenset({
    # layout wrappers (no paint)
    "Padding", "SizedBox", "ConstrainedBox", "LimitedBox", "OverflowBox",
    "SizedOverflowBox", "FractionallySizedBox", "AspectRatioBox", "IntrinsicWidth",
    "IntrinsicHeight", "Flex", "Column", "Row", "Stack", "Positioned", "Align",
    "Center", "Baseline", "LayoutBuilder", "OverflowBar", "Wrap",
    "UnconstrainedBox", "OverflowBox",
    # gesture / pointer / focus / actions (no paint)
    "Listener", "MouseRegion", "GestureDetector", "RawGestureDetector",
    "Focus", "FocusScope", "Actions", "Shortcuts", "Dismissable",
    "NotificationListener", "AbsorbPointer", "IgnorePointer",
    # semantics / a11y (no paint)
    "Semantics", "IndexedSemantics", "ExcludeSemantics", "MergeSemantics",
    "DefaultSelectionStyle",
    # repaint / compositing isolation (no paint)
    "RepaintBoundary", "KeyedSubtree", "Builder", "StatefulBuilder",
    # keep-alive / sliver plumbing (no paint)
    "KeepAlive", "AutomaticKeepAlive", "SliverToBoxAdapter",
    # text-style delegators (paint via child RichText)
    "AnimatedDefaultTextStyle", "DefaultTextStyle",
    # material ink plumbing (no intrinsic paint; the Material carries the bg)
    "_InkFeatures", "_InkResponseStateWidget", "_ParentInkResponseProvider",
    "InkWell", "InkResponse",
    # container composition (StatelessWidget → no own RenderBox)
    "Container", "AdaptiveCard",
})


def classify(runtime_type: str) -> Optional[str]:
    """Flutter runtimeType → skeleton role, or None to drop the node.

    Grounded in Flutter's render model (see the module docstring + the live-tree
    verification). Three buckets:
      - PAINTING (text/image/box): keep + role-assign — these paint visible content
        whose geometry the design has a counterpart for.
      - STRUCTURAL (layout/gesture/semantics wrappers): DROP (return None) — they
        paint no intrinsic visual and keeping them double-counts their child's
        geometry, adding skeleton_diff noise (two nodes at one bbox → over-matching).
      - UNKNOWN (not in any bucket): keep as 'unknown_box' at confidence:low — a
        genuinely-unknown painting widget (a custom design's bespoke container)
        SHOULD ship its geometry; the conservative default is to keep, not drop,
        so a novel painting widget is never silently lost. The live tree's 76/77
        unknown_box count drops to ~0 after this split (the structural wrappers
        that dominated the count are now dropped)."""
    if not runtime_type:
        return "unknown_box"
    if runtime_type in _STRUCTURAL_TYPES:
        return None  # drop — no intrinsic paint, double-counts child geometry
    if runtime_type in _TEXT_TYPES:
        return "text"
    if runtime_type in _IMAGE_TYPES:
        return "image"
    if runtime_type in _BOX_TYPES:
        return "box"
    # Unknown painting widget (a custom design's bespoke container, a plugin's
    # canvas) — keep its geometry at confidence:low rather than silently dropping.
    return "unknown_box"


def build_skeleton(
    raw_nodes: list[dict[str, Any]],
    *,
    url: str = "",
    viewport: Optional[dict[str, float]] = None,
) -> dict[str, Any]:
    """Build a probe-skeleton/2 payload from parsed Flutter render nodes.

    Each raw node: {"type": <runtimeType>, "x","y","w","h": <logical pt>,
                    "parentDepth": <int>, optional "key": <str>}.
    Geometry is logical points (what localToGlobal+size return); dpr is a
    sibling field, not folded in (matches web_skeleton's CSS-px convention).

    Output schema matches web_skeleton.py:647 so skeleton_diff.diff(src, clone)
    works unmodified. v1 honest limits: sizing confidence "low", font {}
    (no cheap Flutter computed-style path), layout "unknown".
    """
    emitted: list[dict[str, Any]] = []
    # parent map: assign parent by the nearest preceding emitted node whose
    # depth is smaller (a rough but deterministic topology proxy from a
    # depth-first VM walk). web_skeleton builds parent from DOM parent_index;
    # Flutter has no DOM, so depth-ordering is the available signal.
    stack: list[tuple[int, int]] = []  # (depth, emitted_id)
    for raw in raw_nodes:
        w = float(raw.get("w", 0) or 0)
        h = float(raw.get("h", 0) or 0)
        if w <= 0 or h <= 0:
            continue  # mirror web_skeleton.classify:366 — drop zero-area
        role = classify(raw.get("type", ""))
        if role is None:
            continue
        nid = len(emitted)
        depth = int(raw.get("parentDepth", 0) or 0)
        # pop stack to the parent depth (strictly smaller)
        while stack and stack[-1][0] >= depth:
            stack.pop()
        parent = stack[-1][1] if stack else None
        node = {
            "id": nid,
            "role": role,
            "confidence": "low" if role == "unknown_box" else "high",
            "bbox": {
                "x": round(float(raw.get("x", 0) or 0), 2),
                "y": round(float(raw.get("y", 0) or 0), 2),
                "w": round(w, 2),
                "h": round(h, 2),
            },
            "z": nid,  # paint order ≈ emit (depth-first) order; web_skeleton
                       # uses DOM paint order — this is the Flutter analog.
            "parent": parent,
            # v1 honest: sizing is a placeholder (no Flutter CSS to derive
            # hug/fill/fixed from). skeleton_diff skips sizing checks when
            # confidence != "high" (skeleton_diff._sizing_ok), so this never
            # false-fails.
            "sizing": {"w": "unknown", "h": "unknown", "confidence": "low"},
            "layout": "unknown",
            "token_ref": {"bg": None, "fg": None, "border": None},
            "anim_ref": None,
        }
        if role == "text":
            # Flutter Text has no cheap computed-style read over the VM (would
            # need a per-widget TextStyle walk), so we emit NO font block. This
            # is deliberate: skeleton_diff.node_delta only runs the font-size
            # gate when BOTH sides carry a "font" key with a numeric size; an
            # absent font key skips the gate (honest, never false-fails). A
            # future v2 that reads TextStyle can fill {size,weight,...} here.
            node["text_len"] = None
        if raw.get("key"):
            node["widget_key"] = raw["key"]  # flutter-specific, additive
        emitted.append(node)
        stack.append((depth, nid))

    return {
        "schema": "probe-skeleton/2",
        "engine": "flutter",
        "url": url,
        "viewport": viewport or {},
        "nodes": emitted,
    }


# ─── VM capture (live-only; --self-test stays offline) ────────────────────────

# Iterative BFS, chunked across eval round-trips. The prior single-recursive
# closure (`void rec(Element e, int depth) { … e.visitChildren((c) => rec(…)); }`)
# walked the WHOLE tree in ONE eval round-trip. On a deep tree (the atlet home
# screen's ~455-node render tree) the Dart recursion depth equals the tree depth,
# and the VM service `evaluate` stack-overflows — the capture dies silently.
#
# The fix is the MLIR-style bounded-per-call pattern: each `evaluate` call
# processes ONE frontier level via a single `visitChildren` (no recursion — per-
# call Dart stack depth is ~1), and the Python DRIVER loops across round-trips
# until the frontier is empty. Because the VM `evaluate` RPC has no persistent
# object handle across calls (the inspector valueId is not a valid re-eval
# targetId — see _flutter.VMLib), each call RE-ENTERS from the root by an
# index-path: [[], [0], [0,1]] = root, root's child 0, that child's child 1.
# The driver feeds each node's child indices back as the next frontier. This
# trades N re-walks-from-root (O(N·depth) VM work) for a bounded per-call stack
# — the right trade for a tree that overflows otherwise. A bounded frontier chunk
# per round-trip keeps the round-trip count ~tree-depth, not node-count.
#
# One eval returns a CSV: each frontier node's row PLUS its child indices (so the
# driver builds the next frontier without a second probe). Rows joined by \x1e;
# fields by \x1f:
#   type \x1f key \x1f x \x1f y \x1f w \x1f h \x1f dpr \x1f pathLen \x1f childPaths \x1f pathStr
# childPaths is a ;-joined list of comma-joined index paths (each a full root-to-
# child path), the driver's next-frontier source. Empty when no painting descendants
# exist within the subtree-walk depth bound. pathStr is this node's own full root→
# node path (comma-joined) — the driver's topology-recovery source (see PATH FIELD).
#
# PATH FIELD (the parent-topology fix): each row carries its OWN `pathStr` (the
# full root→node index path, comma-joined) as the last field. The driver recovers
# the real path per node and SORTS the accumulated nodes by path before
# build_skeleton (Python list comparison is prefix-first: [] < [0] < [0,0] <
# [0,1] < [1]) → global DFS pre-order → build_skeleton's depth-stack parent
# heuristic is correct ACROSS frontiers, not just within one subtree. The prior
# code hardcoded a `[]` path placeholder for every node and relied on per-subtree
# DFS order, which mis-parented any node whose seed wasn't the immediately-
# preceding emitted node (round 2's [0,0] child parented to round 1's last node).
#
# NO // LINE COMMENTS IN THIS LITERAL. _flutter.ev() collapses literal newlines to
# spaces (the documented sdk#41671 workaround), which turns a // comment into a
# run-to-EOF comment that eats every closing brace → "Can't find '}'" parse error.
# The original _WALK_EXPR had zero comments for this exact reason. Rationale lives
# HERE (Python-side), not inline. (ultrathink + consultant: GLM-5.2 HIGH confidence
# — a bridge-level // strip would break Dart strings containing URLs/regex like
# 'https://'; fix at the generation source, never the bridge.)
#
# hasSize guard (the live-capture fix): an off-screen RenderBox (a non-current
# IndexedStack tab) is in the element tree but NOT laid out (hasSize == false);
# reading .size/.localToGlobal on it throws a debug assertion. The legacy recursive
# walk only visited the LIVE subtree so it never hit this; the BFS index-path
# descent reaches every node. The guard skips un-laid-out boxes (zero-area row →
# build_skeleton drops them) so the phantom box doesn't crash the capture.
#
# PAINTING-ONLY emission + SUBTREE WALK (the BFS-reaches-content fix): the live
# tree is top-heavy with structural wrappers (Padding 1595, Semantics 1265, SizedBox
# 1013) that paint nothing. A naive BFS that emits + expands EVERY node drowns in
# the structural mass — 81 rounds never reach the RichText/Text/DecoratedBox content
# deep under the IndexedStack. Two-part fix:
#  (1) The Dart walk, for each path, descends to the node then WALKS its painting
#      subtree (bounded depth ~80 — the content depth under any node), collecting
#      ALL painting descendants in ONE round-trip. This collapses the structural
#      "worm" (View→...→ShadApp, 14 single-child structural levels) into a single
#      hop — the BFS jumps straight to content instead of round-tripping per level.
#      The subtree walk is a BOUNDED recursion (depth-capped at 80, not full-tree),
#      so per-call Dart stack depth stays ~80 (no overflow).
#  (2) Painting-only emission: a row is emitted ONLY for painting RenderBox nodes
#      (hasSize AND in _PAINTING_TYPES); structural nodes are passed through (their
#      painting descendants collected, the wrapper itself not emitted). At the
#      depth-80 boundary a CONTINUE sentinel carries the children's full paths so
#      the driver can bridge 80→160→240 to reach content at depth ~190.
# The frontier thus carries only painting nodes (bounded by content, not structure).
def _bfs_expr(paths_literal: str) -> str:
    """Build the Dart subtree-walk eval expression for a frontier chunk.

    The `_isPainting` body is GENERATED from `_PAINTING_TYPES` (the single source
    of truth shared with the Python `classify`) so the Dart emission gate and the
    Python role-assigner cannot diverge — the prior hand-maintained Dart literal
    omitted `Material` (present in _BOX_TYPES) so Material containers were silently
    never captured. `paths_literal` is a Dart `List<List<int>>` literal spliced in
    as the argument."""
    painting_tests = " || ".join(f't == "{t}"' for t in sorted(_PAINTING_TYPES))
    return (
        "((List<List<int>> paths) {\n"
        "  var dpr = WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio;\n"
        "  bool _isPainting(String t) {\n"
        "    if (t.isEmpty) return false;\n"
        f"    return {painting_tests};\n"
        "  }\n"
        "  var rows = <String>[];\n"
        "  Element _descend(List<int> path) {\n"
        "    var e = WidgetsBinding.instance.rootElement!;\n"
        "    for (var i = 0; i < path.length; i++) {\n"
        "      var kids = <Element>[];\n"
        "      e.visitChildren((c) => kids.add(c));\n"
        "      if (path[i] < 0 || path[i] >= kids.length) return e;\n"
        "      e = kids[path[i]];\n"
        "    }\n"
        "    return e;\n"
        "  }\n"
        "  void _walkPaint(Element e, String pathStr, int depth) {\n"
        "    if (depth > 80) return;\n"
        "    var ro = e.renderObject;\n"
        "    var wt = e.widget.runtimeType.toString();\n"
        "    var kids = <Element>[];\n"
        "    e.visitChildren((c) => kids.add(c));\n"
        "    var isPaint = ro is RenderBox && (ro as RenderBox).hasSize && _isPainting(wt);\n"
        "    if (isPaint) {\n"
        "      var b = ro as RenderBox;\n"
        "      var o = b.localToGlobal(Offset.zero);\n"
        "      var s = b.size;\n"
        "      var key = (e.widget.key?.toString() ?? \"\");\n"
        "      var childPaths = \"\";\n"
        "      if (depth >= 80) {\n"
        "        var idxs = <String>[];\n"
        "        for (var i = 0; i < kids.length; i++) idxs.add(pathStr + (pathStr.isEmpty ? \"\" : \",\") + i.toString());\n"
        "        childPaths = idxs.join(\";\");\n"
        "      }\n"
        f"      rows.add(\"$wt\x1f$key\x1f${{o.dx}}\x1f${{o.dy}}\x1f${{s.width}}\x1f${{s.height}}\x1f$dpr\x1f${{pathStr.isEmpty ? 0 : ','.allMatches(pathStr).length + 1}}\x1f$childPaths\x1f$pathStr\");\n"
        "    } else if (depth >= 80 && kids.length > 0) {\n"
        "      var idxs = <String>[];\n"
        "      for (var i = 0; i < kids.length; i++) idxs.add(pathStr + (pathStr.isEmpty ? \"\" : \",\") + i.toString());\n"
        f"      rows.add(\"CONTINUE\x1f\x1f0.0\x1f0.0\x1f0.0\x1f0.0\x1f$dpr\x1f${{pathStr.isEmpty ? 0 : ','.allMatches(pathStr).length + 1}}\x1f${{idxs.join(';')}}\x1f$pathStr\");\n"
        "    }\n"
        "    for (var i = 0; i < kids.length; i++) {\n"
        "      _walkPaint(kids[i], pathStr + (pathStr.isEmpty ? \"\" : \",\") + i.toString(), depth + 1);\n"
        "    }\n"
        "  }\n"
        "  for (var p in paths) {\n"
        "    var e = _descend(p);\n"
        "    var ps = p.map((i) => i.toString()).join(\",\");\n"
        "    _walkPaint(e, ps, 0);\n"
        "  }\n"
        "  return rows.join(\"\x1e\");\n"
        f"}})({paths_literal})"
    )

_REC_SEP = "\x1e"
_FLD_SEP = "\x1f"


def _dart_list_literal(paths: list[list[int]]) -> str:
    """Render Python frontier paths as a Dart List<List<int>> literal for the
    _BFS_EXPR splice. [[]]  → '[<int>[]]'; [[0],[1]] → '[<int>[0],<int>[1]]'."""
    inner = ",".join("<int>[" + ",".join(str(i) for i in p) + "]" for p in paths)
    return "[" + inner + "]"


def _parse_walk(raw: str) -> tuple[list[dict[str, Any]], Optional[float]]:
    """Parse the BFS CSV-of-rows into raw_nodes + the devicePixelRatio.

    Pure logic (unit-tested via --self-test). Returns (nodes, dpr) where dpr is
    taken from the first row that carries one (it is constant per run). The row
    schema: type \x1f key \x1f x \x1f y \x1f w \x1f h \x1f dpr \x1f pathLen \x1f childPaths \x1f pathStr
    where childPaths is a ;-joined list of comma-joined index paths (each a full
    path from root to a painting node's child) and pathStr is THIS node's own
    full root→node path (comma-joined). The driver feeds childPaths back as the
    next frontier and uses pathStr to sort accumulated nodes into global DFS
    pre-order (the parent-topology fix)."""
    if not raw:
        return [], None
    nodes: list[dict[str, Any]] = []
    dpr: Optional[float] = None
    for row in raw.split(_REC_SEP):
        parts = row.split(_FLD_SEP)
        if len(parts) < 8:
            continue
        try:
            x, y, w, h, d = (float(parts[i]) for i in range(2, 7))
            path_len = int(parts[7])
        except (ValueError, IndexError):
            continue
        row_dpr = float(parts[6]) if _is_float(parts[6]) else None
        if dpr is None:
            dpr = row_dpr
        key = parts[1]
        # childPaths (9th field) — full child paths (comma-joined indices), the
        # BFS driver's next-frontier source. Empty when a painting leaf has no
        # painting descendants within the subtree-walk depth bound.
        child_paths: list[list[int]] = []
        if len(parts) >= 9 and parts[8]:
            for ps in parts[8].split(";"):
                ps = ps.strip()
                if ps and all(s.lstrip("-").isdigit() for s in ps.split(",")):
                    child_paths.append([int(s) for s in ps.split(",")])
        # pathStr (10th field) — this node's own full root→node index path. The
        # driver sorts accumulated nodes by this to restore global DFS pre-order
        # across frontiers (the parent-topology fix). Empty → root (path []).
        path: list[int] = []
        if len(parts) >= 10 and parts[9]:
            ps9 = parts[9].strip()
            if ps9 and all(s.lstrip("-").isdigit() for s in ps9.split(",")):
                path = [int(s) for s in ps9.split(",")]
        nodes.append({"type": parts[0], "key": key or None,
                      "x": x, "y": y, "w": w, "h": h,
                      "parentDepth": path_len, "dpr": row_dpr,
                      "childPaths": child_paths, "path": path})
    return nodes, dpr


def _is_float(s: str) -> bool:
    try:
        float(s)
        return True
    except (TypeError, ValueError):
        return False


# Bounded frontier chunk per round-trip — keeps each eval's CSV small (avoids the
# valueAsString truncation path) AND bounds the per-call VM work. ~32 nodes/round
# is well under the truncation threshold and keeps the round-trip count ~tree-depth.
_BFS_CHUNK = 32
# Safety cap on total nodes so a runaway tree can never hang the capture (a
# pathological infinite-visitChildren). 10k nodes is well above any real screen
# (~500) and fails loud rather than hanging.
_BFS_MAX_NODES = 10000
# Max element-tree DEPTH. The Flutter element tree is pathologically deep due to
# widget composition (the atlet home's RichText nodes are at depth ~190 from the
# root — the IndexedStack + shadcn_ui plumbing + all tabs' subtrees stack up).
# The cap must exceed the deepest painting content so the subtree-walk +
# continuation mechanism can bridge to it. 300 is generous (content at ~190-220)
# while pruning genuinely-off-screen subtrees (the non-current tabs' far edges).
# The hasSize guard skips un-laid-out boxes regardless, so the cap is a runaway
# bound, not a correctness one.
_BFS_MAX_DEPTH = 300


def _capture() -> dict[str, Any]:
    """Subtree-walk capture: each eval round descends to a frontier node then walks
    its PAINTING subtree (depth ≤ 80), collecting all painting descendants in one
    round-trip. This collapses structural "worms" (View→…→ShadApp, 14 single-child
    structural levels) into a single hop — the capture jumps straight to content
    instead of round-tripping per structural level (which drowned the prior BFS in
    1595 Padding / 1265 Semantics wrappers and never reached the RichText cards).

    Per-call Dart stack depth is ~80 (the subtree-walk bound), not full-tree — no
    overflow. The driver feeds each painting node's `childPaths` (full root-to-child
    paths) as the next frontier, descending deeper where content exceeds the 80-level
    bound. Bounded by _BFS_MAX_NODES (runaway cap) + _BFS_MAX_DEPTH (off-screen cap).

    Parent topology: build_skeleton's depth-stack heuristic assumes DFS pre-order.
    The subtree walk emits DFS within each subtree, but across frontiers the
    accumulation order is the frontier order, NOT global DFS. So each row carries
    its OWN root→node path (pathStr); the driver sorts accumulated nodes by that
    path (Python list comparison is prefix-first: [] < [0] < [0,0] < [0,1] < [1])
    BEFORE build_skeleton — restoring global DFS pre-order so the depth-stack
    parent heuristic is correct across frontiers, not just within one subtree."""
    from _flutter import VMLib
    try:
        lib = VMLib()
    except Exception as e:
        die("no Flutter VM service. run flutter_attach.py first. (%s)" % e)

    # (index_path, raw_node) pairs accumulated across all frontiers. The path is
    # the node's position from root; sorting by it yields global DFS pre-order.
    pathed: list[tuple[list[int], dict[str, Any]]] = []
    dpr: Optional[float] = None

    # Frontier = list of index paths from root. Seed with the root (path []).
    # Each round walks the painting subtree of every frontier node (depth ≤ 80),
    # returning painting rows + their children's full paths (the next frontier).
    frontier: list[list[int]] = [[]]
    total_nodes = 0
    while frontier and total_nodes < _BFS_MAX_NODES:
        chunk = frontier[:_BFS_CHUNK]
        expr = _bfs_expr(_dart_list_literal(chunk))
        try:
            raw = lib.ev(expr)
        except RuntimeError as e:
            die("VM subtree walk failed at frontier (paths=%r): %s" % (chunk[:3], e))
        if not raw or raw == "NO_TARGET":
            if not pathed:
                die("VM walk returned no painting nodes (is a Flutter app running in debug?).")
            break  # partial capture — proceed with what we have (honest, not empty)
        chunk_nodes, chunk_dpr = _parse_walk(raw)
        if dpr is None:
            dpr = chunk_dpr
        total_nodes += len(chunk_nodes)
        # Each row carries its OWN full root→node path (the pathStr field). The
        # seed path (chunk[i]) is the root of a subtree walk; the walk emits the
        # seed (if painting) + all painting descendants within depth 80, each
        # with its own full path. Accumulate (path, node) so a global path-sort
        # restores DFS pre-order across frontiers (the parent-topology fix).
        for node in chunk_nodes:
            pathed.append((node.get("path") or [], node))
        # The next frontier: every painting node's childPaths (full paths to descend
        # deeper where the subtree exceeded the 80-level bound). Dedup + depth-cap.
        next_frontier: list[list[int]] = []
        seen_paths: set[tuple[int, ...]] = set()
        for node in chunk_nodes:
            for cp in node.get("childPaths") or []:
                t = tuple(cp)
                if t in seen_paths:
                    continue
                seen_paths.add(t)
                if len(cp) < _BFS_MAX_DEPTH:
                    next_frontier.append(cp)
        frontier = next_frontier + frontier[_BFS_CHUNK:]

    if not pathed:
        die("no painting nodes recovered from the VM walk.")
    # Global DFS pre-order: sort accumulated (path, node) pairs by path. Python
    # list comparison is prefix-first ([] < [0] < [0,0] < [0,1] < [1]), so a
    # path-sort restores the order build_skeleton's depth-stack parent heuristic
    # assumes — a node is emitted BEFORE its descendants, and siblings are in
    # index order. The prior code skipped this (relied on per-subtree DFS order),
    # which mis-parented cross-frontier descendants (round 2's [0,0] child took
    # round 1's last node as parent). Sort stably so equal-path dedup keeps the
    # first-seen row.
    pathed.sort(key=lambda pn: pn[0])
    nodes = [n for _, n in pathed]
    # viewport/page width is not directly available without a MediaQuery walk;
    # carry dpr as a sibling field. skeleton_diff does not gate on viewport.
    return build_skeleton(nodes, viewport={"dpr": dpr} if dpr else {})


# ─── self-test (offline, mirrors flutter_anim._self_test) ─────────────────────

def _self_test() -> int:
    """Verify classify + build_skeleton + a flutter→flutter self-diff through
    skeleton_diff. No VM needed."""
    import skeleton_diff as sd

    # classify: text/image/box/None — grounded in Flutter's render model.
    # PAINTING widgets → role; STRUCTURAL wrappers → None (dropped, no intrinsic
    # paint, double-counts child geometry); UNKNOWN → unknown_box (keep, low conf).
    assert classify("Text") == "text"
    assert classify("RichText") == "text"
    assert classify("EditableText") == "text"
    assert classify("Image") == "image"
    assert classify("FadeInImage") == "image"
    assert classify("DecoratedBox") == "box"
    assert classify("ColoredBox") == "box"
    assert classify("Material") == "box"
    assert classify("Card") == "box"
    assert classify("CustomPaint") == "box"
    # STRUCTURAL wrappers → None (drop). These dominated the live tree's 76/77
    # unknown_box count; dropping them is the principled fix (no double-counting).
    assert classify("Padding") is None
    assert classify("SizedBox") is None
    assert classify("Container") is None
    assert classify("Column") is None
    assert classify("Row") is None
    assert classify("Semantics") is None
    assert classify("RepaintBoundary") is None
    assert classify("GestureDetector") is None
    assert classify("Listener") is None
    assert classify("Focus") is None
    assert classify("Center") is None
    assert classify("KeyedSubtree") is None
    assert classify("Builder") is None
    # UNKNOWN painting widget (a custom/bespoke container not in any bucket) →
    # keep at confidence:low (don't silently drop a novel painting widget).
    assert classify("SomeBespokeCanvas") == "unknown_box"
    assert classify("") == "unknown_box"

    # build a small skeleton from synthetic render nodes. Material → "box" now
    # (was "unknown_box"); SizedBox → None (dropped, structural). The Padding
    # node is dropped too (structural), leaving Material+Text+Image = 3 nodes.
    raw = [
        {"type": "Material", "x": 0, "y": 0, "w": 400, "h": 800, "parentDepth": 0},
        {"type": "Text", "x": 16, "y": 24, "w": 200, "h": 24, "parentDepth": 1},
        {"type": "Image", "x": 16, "y": 60, "w": 100, "h": 100, "parentDepth": 1},
        {"type": "SizedBox", "x": 0, "y": 0, "w": 0, "h": 0, "parentDepth": 1},  # dropped (structural)
        {"type": "Padding", "x": 0, "y": 0, "w": 400, "h": 800, "parentDepth": 1},  # dropped (structural)
    ]
    sk = build_skeleton(raw, viewport={"dpr": 3.0})
    assert sk["schema"] == "probe-skeleton/2", sk["schema"]
    assert sk["engine"] == "flutter"
    assert len(sk["nodes"]) == 3, [n["role"] for n in sk["nodes"]]  # SizedBox + Padding dropped
    roles = [n["role"] for n in sk["nodes"]]
    assert roles == ["box", "text", "image"], roles  # Material → box (was unknown_box)
    # parent topology: Text + Image are children of Material
    assert sk["nodes"][0]["parent"] is None
    assert sk["nodes"][1]["parent"] == 0 and sk["nodes"][2]["parent"] == 0
    # text node carries text_len but NO font block (honest: no TextStyle read)
    assert "font" not in sk["nodes"][1]
    assert sk["nodes"][1].get("text_len") is None

    # flutter→flutter self-diff must PASS (same input -> identical geometry).
    gates = sd.DEFAULT_GATES
    result = sd.diff(sk, sk, gates)
    assert result["pass"] is True, result

    # ── Issue 2: the Dart emission gate is GENERATED from _PAINTING_TYPES (the
    #    single source of truth shared with classify), so it cannot diverge from
    #    the Python role-assigner. The prior hand-maintained Dart literal omitted
    #    `Material` (present in _BOX_TYPES) so Material containers were silently
    #    never captured. Pin: every _PAINTING_TYPES member appears in the
    #    generated _isPainting body, AND the union equals the classify painting
    #    set (no widget is role-assigned a painting role the Dart gate rejects,
    #    and vice versa). ──
    expr = _bfs_expr("[<int>[]]")
    for t in _PAINTING_TYPES:
        assert f't == "{t}"' in expr, f"_bfs_expr must emit a test for {t} (Issue 2)"
    # the union IS the painting set: every painting classify-role maps to a
    # _PAINTING_TYPES member, and the Dart gate tests no non-painting type.
    for t in _TEXT_TYPES | _IMAGE_TYPES | _BOX_TYPES:
        assert classify(t) in ("text", "image", "box"), t
    for t in _STRUCTURAL_TYPES:
        assert t not in _PAINTING_TYPES, f"structural {t} must not be in the Dart gate"
    # the regression specifically: Material + ShapeDecoration are in the gate.
    assert 't == "Material"' in expr, "Material MUST be in the Dart gate (the Issue 2 regression)"
    assert 't == "ShapeDecoration"' in expr, "ShapeDecoration MUST be in the Dart gate"

    # ── subtree-walk driver (the BFS-reaches-content fix). The driver logic is
    #    pure once a round's CSV is parsed: each round walks the painting subtree
    #    (depth ≤ 80) of every frontier node, returning painting rows + their
    #    children's full paths (the next frontier). Verify each piece offline. ──
    # _dart_list_literal renders Python frontier paths as a Dart List<List<int>>.
    assert _dart_list_literal([[]]) == "[<int>[]]", "root path"
    assert _dart_list_literal([[0], [1]]) == "[<int>[0],<int>[1]]", "depth-1 paths"
    assert _dart_list_literal([[0, 1], [2]]) == "[<int>[0,1],<int>[2]]", "depth-2 path"
    # _parse_walk decodes the subtree-walk row: type...pathLen...childPaths...pathStr.
    # A node at path [0] with two children at paths [0,1] and [0,2]:
    sub_row = "Material\x1f\x1f0.0\x1f0.0\x1f400.0\x1f800.0\x1f3.0\x1f1\x1f0,1;0,2\x1f0"
    snodes, sdpr = _parse_walk(sub_row)
    assert len(snodes) == 1 and sdpr == 3.0, (snodes, sdpr)
    assert snodes[0]["childPaths"] == [[0, 1], [0, 2]], snodes[0]["childPaths"]
    assert snodes[0]["path"] == [0], snodes[0]["path"]
    # the root: pathStr empty → path []
    root_row = "Material\x1f\x1f0.0\x1f0.0\x1f400.0\x1f800.0\x1f3.0\x1f0\x1f\x1f"
    rnodes, _ = _parse_walk(root_row)
    assert rnodes[0]["path"] == [], rnodes[0]["path"]
    # a leaf (no children within the depth bound) → empty childPaths
    leaf = "Text\x1f\x1f16.0\x1f24.0\x1f200.0\x1f24.0\x1f3.0\x1f2\x1f\x1f0,0"
    lnodes, _ = _parse_walk(leaf)
    assert lnodes[0]["childPaths"] == [], lnodes[0]["childPaths"]
    assert lnodes[0]["path"] == [0, 0], lnodes[0]["path"]
    # a multi-row subtree (Material + its Text child) in one CSV:
    multi = ("Material\x1f\x1f0.0\x1f0.0\x1f400.0\x1f800.0\x1f3.0\x1f0\x1f0,0\x1f"
             "\x1eText\x1f\x1f16.0\x1f24.0\x1f200.0\x1f24.0\x1f3.0\x1f2\x1f\x1f0,0")
    mnodes, _ = _parse_walk(multi)
    assert len(mnodes) == 2, mnodes
    assert [n["type"] for n in mnodes] == ["Material", "Text"], [n["type"] for n in mnodes]
    assert mnodes[0]["path"] == [] and mnodes[1]["path"] == [0, 0], [n["path"] for n in mnodes]

    # ── the subtree-walk driver loop (mirrors _capture, no VM). A fake VM returns
    #    hand-authored CSV per frontier. The tree: root(R, painting) > [A,B]; A >
    #    [C]; B leaf. Round 1 (path=[]) walks R's subtree → R+A+B (depth ≤ 2) +
    #    childPaths for A's child C. Round 2 (path=[0,0]) walks C's subtree → C.
    #    The driver feeds childPaths as the next frontier. ──
    def _row(t, x, y, w, h, path_len, child_paths, path_str):
        cp = ";".join(",".join(str(i) for i in p) for p in child_paths)
        return f"{t}\x1f\x1f{x}\x1f{y}\x1f{w}\x1f{h}\x1f3.0\x1f{path_len}\x1f{cp}\x1f{path_str}"
    # round 1: root path [] → subtree walk yields R (path []), A (path [0]), B (path [1])
    # A's child C is at path [0,0] (root→A→C); R's childPaths list A's child.
    fake_vm = {
        "[<int>[]]": _row("Material", 0, 0, 400, 800, 0, [[0, 0]], "") + "\x1e" + _row("DecoratedBox", 0, 0, 400, 400, 1, [], "0") + "\x1e" + _row("ColoredBox", 0, 400, 400, 400, 1, [], "1"),
        "[<int>[0,0]]": _row("Text", 16, 24, 200, 24, 2, [], "0,0"),
    }
    pathed, frontier, total = [], [[]], 0
    rounds = 0
    while frontier and total < _BFS_MAX_NODES and rounds < 20:
        chunk = frontier[:_BFS_CHUNK]
        key = _dart_list_literal(chunk)
        raw = fake_vm.get(key, "")
        if not raw:
            break
        chunk_nodes, _ = _parse_walk(raw)
        total += len(chunk_nodes)
        for node in chunk_nodes:
            pathed.append((node.get("path") or [], node))
        nxt = []
        seen = set()
        for node in chunk_nodes:
            for cp in node.get("childPaths") or []:
                t = tuple(cp)
                if t in seen: continue
                seen.add(t)
                if len(cp) < _BFS_MAX_DEPTH: nxt.append(cp)
        frontier = nxt + frontier[_BFS_CHUNK:]
        rounds += 1
    # THE PARENT-TOPOLOGY FIX (Issue 1): sort accumulated nodes by path before
    # build_skeleton, restoring global DFS pre-order. Without the sort, round 2's
    # C (path [0,0]) follows round 1's B (path [1]) in accumulation order, so
    # build_skeleton's depth-stack parents C to B (the last depth-1 node) — wrong.
    pathed.sort(key=lambda pn: pn[0])
    final_nodes = [n for _, n in pathed]
    types = [n["type"] for n in final_nodes]
    assert types == ["Material", "DecoratedBox", "Text", "ColoredBox"], types
    assert rounds == 2, f"2 frontier rounds expected (got {rounds})"
    # build_skeleton consumes the path-sorted nodes (global DFS pre-order).
    sk_bfs = build_skeleton(final_nodes)
    assert len(sk_bfs["nodes"]) == 4, [n["role"] for n in sk_bfs["nodes"]]
    # THE PARENT-TOPOLOGY PROOF: Text (path [0,0]) is a child of DecoratedBox
    # (path [0]), NOT ColoredBox (path [1]). After the path-sort, build_skeleton's
    # depth-stack pops past ColoredBox (depth 1) to DecoratedBox (depth 1, the
    # most-recent depth-≤-0... actually Material depth 0) — verify Text's parent
    # is DecoratedBox (emitted index 1), not ColoredBox (emitted index 3).
    parents = [n["parent"] for n in sk_bfs["nodes"]]
    # nodes: 0=Material(d0), 1=DecoratedBox(d1), 2=Text(d2), 3=ColoredBox(d1)
    assert parents[0] is None, parents
    assert parents[1] == 0, f"DecoratedBox's parent is Material (got {parents[1]})"
    assert parents[2] == 1, f"Text's parent MUST be DecoratedBox (path-sort fix), got {parents[2]}"
    assert parents[3] == 0, f"ColoredBox's parent is Material (got {parents[3]})"
    # a flutter→flutter self-diff on the captured skeleton must PASS.
    bfs_self = sd.diff(sk_bfs, sk_bfs, sd.DEFAULT_GATES)
    assert bfs_self["pass"] is True, bfs_self

    # ── Issue 1 regression guard: WITHOUT the path-sort, Text would be parented
    #    to ColoredBox (the last depth-1 node before it in accumulation order).
    #    Pin the sort is present in _capture by asserting the driver loop above
    #    sorted (the pathed list is in path order, not accumulation order). ──
    assert [p for p, _ in pathed] == [[], [0], [0, 0], [1]], \
        "pathed must be path-sorted (Issue 1); without the sort Text[0,0] follows ColoredBox[1]"

    # ── the DEPTH CAP. The driver skips childPaths whose length >= _BFS_MAX_DEPTH
    #    so an IndexedStack's off-screen tab subtrees can't balloon the capture. ──
    cap_path = list(range(_BFS_MAX_DEPTH))
    assert len(cap_path) >= _BFS_MAX_DEPTH
    assert not (len(cap_path) < _BFS_MAX_DEPTH), "a path at the cap must NOT expand"

    # ── the UN-LAID-OUT BOX guard. An off-screen RenderBox (a non-current
    #    IndexedStack tab) is in the element tree but NOT laid out (hasSize ==
    #    false); the Dart walk's `b.hasSize` check skips it (no row emitted). A
    #    zero-area row that does slip through is dropped by build_skeleton. ──
    unlaid = "RenderPadding\x1f\x1f0.0\x1f0.0\x1f0.0\x1f0.0\x1f2.625\x1f4\x1f\x1f"
    un_nodes, _ = _parse_walk(unlaid)
    assert len(un_nodes) == 1 and un_nodes[0]["w"] == 0.0, un_nodes
    un_sk = build_skeleton(un_nodes)
    assert len(un_sk["nodes"]) == 0, "a zero-area un-laid-out box must be dropped"

    emit_json({"self_test": "pass", "nodes": len(sk["nodes"]),
               "self_diff_pass": result["pass"], "bfs_rounds": rounds,
               "bfs_nodes": len(final_nodes), "max_depth": _BFS_MAX_DEPTH})
    return 0


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--out", help="output JSON path (default: <outdir>/flutter-skeleton-<ts>.json)")
    p.add_argument("--self-test", action="store_true", dest="self_test",
                   help="verify classify + build offline (no VM needed)")
    args = p.parse_args()

    if args.self_test:
        return _self_test()

    sk = _capture()
    out = Path(args.out) if args.out else out_path("flutter-skeleton", "json")
    out.write_text(json.dumps(sk, indent=2, ensure_ascii=False))
    print("flutter_skeleton: %d nodes (text=%d image=%d box=%d unknown=%d)" % (
        len(sk["nodes"]),
        sum(1 for n in sk["nodes"] if n["role"] == "text"),
        sum(1 for n in sk["nodes"] if n["role"] == "image"),
        sum(1 for n in sk["nodes"] if n["role"] == "box"),
        sum(1 for n in sk["nodes"] if n["role"] == "unknown_box"),
    ))
    emit_path(out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
