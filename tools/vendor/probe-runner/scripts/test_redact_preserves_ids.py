import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import content_firewall as cf


def test_redact_node_preserves_id_and_parent_drops_href():
    node = {"id": 7, "parent": 3, "tag": "A", "href": "https://t/x", "text": "hello",
            "aria_role": "navigation", "bbox": {"x": 0, "y": 0, "w": 1, "h": 1}}
    red = cf.redact_node(dict(node))   # the real per-node redactor used by bundle_writer
    assert red["id"] == 7 and red["parent"] == 3
    assert "href" not in red and red.get("text") in (None, "")
