import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import _site


def test_build_site_manifest_includes_nav_edges():
    rows = [{"route_id": "r00", "url": "https://x.com/", "bundle": "routes/r00", "ok": True},
            {"route_id": "r01", "url": "https://x.com/a", "bundle": "routes/r01", "ok": True}]
    edges = [{"src": "r00", "dst": "r01", "src_node": 5, "chrome": True}]
    m = _site.build_site_manifest(rows, nav_edges=edges)
    assert m["nav_edges"] == edges
    # back-compat: default arg keeps callers that pass no edges working, emits []
    assert _site.build_site_manifest(rows)["nav_edges"] == []
