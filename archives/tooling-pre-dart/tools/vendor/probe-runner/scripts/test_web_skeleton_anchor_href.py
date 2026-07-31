import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import web_skeleton as WK


def _snap():
    # strings table; one <a href="https://t/x"> and one <div>
    strings = ["A", "DIV", "href", "https://t/x", "class", "nav"]
    nodes = {
        "nodeName": [0, 1],                 # node0=A, node1=DIV
        "attributes": [[2, 3, 4, 5], []],   # node0: href=https://t/x, class=nav ; node1: none
        "backendNodeId": [100, 101],
    }
    layout = {
        "nodeIndex": [0, 1],                # both rendered
        "bounds": [[0, 0, 10, 10], [0, 10, 10, 10]],
        "styles": [[], []],
        "text": [],
    }
    return {"strings": strings, "documents": [{"nodes": nodes, "layout": layout}]}


def test_parse_snapshot_extracts_anchor_href_only_for_anchors():
    recs = WK.parse_snapshot(_snap(), [], dpr=1.0)
    a = next(r for r in recs if r["tag"] == "A")
    d = next(r for r in recs if r["tag"] == "DIV")
    assert a["href"] == "https://t/x"
    assert d.get("href") is None
