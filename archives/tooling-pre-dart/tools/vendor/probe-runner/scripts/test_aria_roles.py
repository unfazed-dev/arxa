# scripts/test_aria_roles.py
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import web_skeleton as W  # noqa: E402


def test_landmark_roles_filters_to_allowlist():
    ax = {"nodes": [
        {"backendDOMNodeId": 10, "role": {"value": "navigation"}},
        {"backendDOMNodeId": 11, "role": {"value": "link"}},        # not a landmark
        {"backendDOMNodeId": 12, "role": {"value": "contentinfo"}},
    ]}
    assert W.landmark_roles(ax) == {10: "navigation", 12: "contentinfo"}


def test_landmark_roles_skips_ignored_and_missing():
    ax = {"nodes": [
        {"backendDOMNodeId": 1, "role": {"value": "main"}, "ignored": True},
        {"backendDOMNodeId": 2, "role": {"value": "main"}},
        {"role": {"value": "banner"}},                              # no backend id
        {"backendDOMNodeId": 3},                                    # no role
    ]}
    assert W.landmark_roles(ax) == {2: "main"}


def test_landmark_roles_drops_author_custom():
    ax = {"nodes": [{"backendDOMNodeId": 7,
                     "role": {"value": "totally custom marketing widget name"}}]}
    assert W.landmark_roles(ax) == {}


def test_landmark_roles_empty_input():
    assert W.landmark_roles(None) == {}
    assert W.landmark_roles({}) == {}


def test_apply_aria_roles_joins_by_backend():
    nodes = [{"id": 0}, {"id": 1}, {"id": 2}]
    node_backend = {0: 100, 1: 101, 2: 102}
    role_by_backend = {100: "navigation", 102: "contentinfo"}
    W.apply_aria_roles(nodes, node_backend, role_by_backend)
    assert nodes[0]["aria_role"] == "navigation"
    assert "aria_role" not in nodes[1]          # no landmark -> key ABSENT (not null)
    assert nodes[2]["aria_role"] == "contentinfo"


def test_apply_aria_roles_no_backend_for_node():
    nodes = [{"id": 0}]
    W.apply_aria_roles(nodes, {}, {100: "main"})   # node 0 has no backend mapping
    assert "aria_role" not in nodes[0]


def test_apply_aria_roles_none_safe():
    nodes = [{"id": 0}]
    W.apply_aria_roles(nodes, None, None)        # must not raise
    W.apply_aria_roles(nodes, {}, {})
    W.apply_aria_roles(nodes, {0: 1}, {})
    assert "aria_role" not in nodes[0]


def test_enrich_aria_noop_without_sess():
    class FakeEv:        # no .sess attribute -> non-CDP transport
        pass
    nodes = [{"id": 0}]
    W.enrich_aria(nodes, {0: 1}, FakeEv())     # must not raise
    assert "aria_role" not in nodes[0]


def test_enrich_aria_attaches_via_fake_session():
    class FakeSess:
        def send(self, method, params=None):
            if method == "Accessibility.getFullAXTree":
                return {"nodes": [{"backendDOMNodeId": 1, "role": {"value": "main"}},
                                  {"backendDOMNodeId": 2, "role": {"value": "link"}}]}
            return {}
    class FakeEv:
        sess = FakeSess()
    nodes = [{"id": 0}, {"id": 1}]
    W.enrich_aria(nodes, {0: 1, 1: 2}, FakeEv())
    assert nodes[0]["aria_role"] == "main"     # landmark joined
    assert "aria_role" not in nodes[1]         # link is not a landmark


def test_enrich_aria_survives_enable_failure():
    class FakeSess:
        def send(self, method, params=None):
            if method == "Accessibility.enable":
                raise RuntimeError("not supported")     # must be swallowed
            if method == "Accessibility.getFullAXTree":
                return {"nodes": [{"backendDOMNodeId": 9, "role": {"value": "banner"}}]}
            return {}
    class FakeEv:
        sess = FakeSess()
    nodes = [{"id": 0}]
    W.enrich_aria(nodes, {0: 9}, FakeEv())
    assert nodes[0]["aria_role"] == "banner"


def test_enrich_aria_survives_axtree_failure():
    class FakeSess:
        def send(self, method, params=None):
            if method == "Accessibility.getFullAXTree":
                raise RuntimeError("AX domain unavailable")   # must NOT propagate
            return {}
    class FakeEv:
        sess = FakeSess()
    nodes = [{"id": 0}]
    W.enrich_aria(nodes, {0: 1}, FakeEv())     # capture must proceed, no raise
    assert "aria_role" not in nodes[0]
