import web_vectors as wv


def test_crop_rect_scales_by_dpr():
    node = {"id": 7, "role": "svg", "bbox": {"x": 100, "y": 200, "w": 50, "h": 40}}
    rect = wv.crop_rect(node, dpr=2.0)
    assert rect == {"left": 200, "top": 400, "width": 100, "height": 80}


def test_svg_nodes_filters_role():
    nodes = [{"id": 0, "role": "svg", "bbox": {"x": 0, "y": 0, "w": 1, "h": 1}},
             {"id": 1, "role": "image", "bbox": {"x": 0, "y": 0, "w": 1, "h": 1}},
             {"id": 2, "role": "svg", "bbox": {"x": 0, "y": 0, "w": 1, "h": 1}}]
    assert [n["id"] for n in wv.svg_nodes(nodes)] == [0, 2]
