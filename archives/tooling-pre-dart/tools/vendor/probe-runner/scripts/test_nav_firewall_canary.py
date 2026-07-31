"""Firewall canary for the nav_edges field. SCOPE (be honest): `audit_bundle` is only a
PARTIAL backstop for hrefs — it catches MEDIA/font-extension URLs (`_CONTENT_URL`) and long
prose runs, but a bare page href like `https://e.com/login` or `?token=...` passes it clean.
So these tests prove `nav_edges` is IN the audit's scan scope (a media-shaped leak there trips),
NOT that the audit gates arbitrary hrefs. The REAL content-free guarantee is that
`_nav.resolve_edges` constructs each edge from a literal `{src, dst, src_node, chrome}` dict and
can never place an href in it (pinned by exact-equality in test_nav.py), plus the end-to-end
href-free assertion in test_site_capture_nav_e2e.py."""
import sys, json
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import content_firewall as cf


def test_seeded_media_url_in_site_json_trips_audit(tmp_path):
    # A media-shaped (.png) URL seeded into nav_edges must trip the audit, proving the new field
    # is in audit scope (NOT exempt). This is scope coverage, not a general href gate (see module docstring).
    site = tmp_path / "site.json"
    site.write_text(json.dumps({
        "routes": [{"route_id": "r00", "url": "https://x.com/", "ok": True}],
        "nav_edges": [{"src": "r00", "dst": "r01", "src_node": 5, "chrome": True,
                       "leak": "https://cdn.example.com/secret.png"}],   # seeded media URL
    }))
    viol = cf.audit_bundle(str(tmp_path))
    assert viol, "audit must flag a media URL seeded into nav_edges"


def test_clean_nav_edges_pass_audit(tmp_path):
    site = tmp_path / "site.json"
    site.write_text(json.dumps({
        "routes": [{"route_id": "r00", "url": "https://x.com/", "ok": True}],
        "nav_edges": [{"src": "r00", "dst": "r01", "src_node": 5, "chrome": True}],
    }))
    assert cf.audit_bundle(str(tmp_path)) == []
