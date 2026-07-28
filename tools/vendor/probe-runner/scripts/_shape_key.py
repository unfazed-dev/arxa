"""Canonical content-free shape-key: an exact mechanism fingerprint of one skeleton
node. Volatile/positional fields (id/parent/bbox/z/sizing.confidence) are excluded by
construction, so two nodes share a key iff they are the SAME content-free structure.
Single source of truth — the G2 sweep-merge engine (_virt) and the cross-route dedup
probe both import this so they cannot drift."""

_KEY_FIELDS = (  # pre-registered field order; volatile keys (id/parent/bbox/z/confidence) excluded
    "role", "aria_role", "layout.mode", "layout.direction", "layout.gap", "layout.pad",
    "layout.justify", "layout.align", "layout.grid_cols", "layout.grid_rows", "sizing.w",
    "sizing.h", "token_ref.bg", "token_ref.fg", "token_ref.border", "font.family", "font.weight",
    "text_len", "pseudo", "substrate",
)


def _node_key(n, drop=()):
    """Exact mechanism fingerprint of ONE node. `drop` blanks named fields -- used ONLY by the
    post-hoc ablation diagnostic; the pre-registered VERDICT path always calls with drop=()."""
    lay = n.get("layout") or {}
    sz = n.get("sizing") or {}
    tr = n.get("token_ref") or {}
    f = n.get("font") or {}
    vals = {
        "role": n.get("role"), "aria_role": n.get("aria_role"),
        "layout.mode": lay.get("mode"), "layout.direction": lay.get("direction"),
        "layout.gap": lay.get("gap"), "layout.pad": lay.get("pad"),
        "layout.justify": lay.get("justify"), "layout.align": lay.get("align"),
        "layout.grid_cols": lay.get("grid_cols"), "layout.grid_rows": lay.get("grid_rows"),
        "sizing.w": sz.get("w"), "sizing.h": sz.get("h"),
        "token_ref.bg": tr.get("bg"), "token_ref.fg": tr.get("fg"), "token_ref.border": tr.get("border"),
        "font.family": f.get("family"), "font.weight": f.get("weight"),
        "text_len": n.get("text_len"), "pseudo": 1 if n.get("pseudo") else 0,
        "substrate": n.get("substrate"),
    }
    return "|".join("" if name in drop else str(vals[name]) for name in _KEY_FIELDS)
