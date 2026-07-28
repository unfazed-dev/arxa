# scripts/test_site_capture_post.py
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent


def _nav(base, bg):
    # a 2-node navigation landmark (root + link) — dedup-eligible chrome
    return [
        {"id": base, "parent": None, "tag": "nav", "aria_role": "navigation", "z": 0,
         "confidence": 1.0, "token_ref": {"bg": bg, "fg": "f", "border": "b"}},
        {"id": base + 1, "parent": base, "tag": "a", "z": 0, "confidence": 1.0, "text_len": 4},
    ]


_BG_HEX = {"red": "#ff0000", "blue": "#0000ff", "green": "#00ff00"}


def _tokens(bg):
    # a minimal but valid tokens.json surface site_merge can merge into a NON-empty palette
    # (real PALETTE_ROLES role + real hex; a color-name value would reach parse_color and crash).
    # build_design_system reads palette as a {role: hex} DICT (t.get("palette").get(role)); the
    # spec's list-of-dicts shape crashes merge with AttributeError. Empty scalar lists merge
    # cleanly (merge_scalars handles []).
    return {"palette": {"background": _BG_HEX.get(bg, "#888888")}, "type_scale": [], "spacing": []}


def _build_site(tmp_path, n_ok, *, bg=("red", "blue", "green"), skeleton_override=None):
    """Build a capture dir with `n_ok` ok routes (each: skeleton.json + tokens.json),
    plus a content-free site.json manifest. `skeleton_override(i)` lets a test inject a
    malformed/leaky skeleton for route i. Returns the site dir Path."""
    site = tmp_path / "site_out"
    (site / "routes").mkdir(parents=True, exist_ok=True)
    routes = []
    for i in range(n_ok):
        rid = "r%02d" % i
        rd = site / "routes" / rid
        rd.mkdir(parents=True, exist_ok=True)
        skel = skeleton_override(i) if skeleton_override else {"nodes": _nav(i * 100, bg[i % len(bg)])}
        (rd / "skeleton.json").write_text(json.dumps(skel))
        (rd / "tokens.json").write_text(json.dumps(_tokens(bg[i % len(bg)])))
        routes.append({"route_id": rid, "url": "https://example.com/p%d" % i,
                       "bundle": "routes/" + rid, "ok": True, "node_count": 2})
    (site / "site.json").write_text(json.dumps(
        {"schema": "probe-runner/site-manifest@1", "routes": routes,
         "route_count": n_ok, "ok_count": n_ok, "hosts": ["example.com"]}))
    return site


def test_post_processors_run_both_on_two_routes(tmp_path):
    import site_capture as S
    site = _build_site(tmp_path, 2)
    result = S.run_post_processors(site, merge=True, dedup=True)
    assert result["merge"]["status"] == "ok", result
    assert result["dedup"]["status"] == "ok", result
    assert (site / "design_system.json").exists()
    assert (site / "chrome_dedup.json").exists()


def test_dedup_skipped_when_fewer_than_two_routes(tmp_path):
    import site_capture as S
    site = _build_site(tmp_path, 1)               # 1 ok route: merge applicable, dedup not
    result = S.run_post_processors(site, merge=True, dedup=True)
    assert result["merge"]["status"] == "ok", result
    assert result["dedup"]["status"] == "skipped"
    assert result["dedup"]["reason"] == "insufficient_routes"
    assert not (site / "chrome_dedup.json").exists()   # child was never invoked -> no artifact
    assert (site / "design_system.json").exists()


def test_flags_off_are_disabled_not_run(tmp_path):
    import site_capture as S
    site = _build_site(tmp_path, 2)
    result = S.run_post_processors(site, merge=False, dedup=False)
    assert result["merge"]["status"] == "disabled"
    assert result["dedup"]["status"] == "disabled"
    assert not (site / "design_system.json").exists()
    assert not (site / "chrome_dedup.json").exists()


def _leaky_skeleton(i):
    # a content URL the firewall must catch -> child exits 3
    return {"nodes": [
        {"id": i * 100, "parent": None, "tag": "nav", "aria_role": "navigation",
         "z": 0, "confidence": 1.0, "token_ref": {"bg": "red", "fg": "f", "border": "b"},
         "href": "https://example.com/secret-photo.jpg"},
        {"id": i * 100 + 1, "parent": i * 100, "tag": "a", "z": 0, "confidence": 1.0,
         "text_len": 4}]}


def test_firewall_leak_reports_leak(tmp_path):
    # dedup-only: asserts the leak STATUS mapping (exit 3 -> "leak"). The stop-on-leak
    # `break` is not exercised here (dedup is the terminal step); it's a documented
    # posture, and not-breaking would still fail loud, so it's left unguarded by design.
    import site_capture as S
    site = _build_site(tmp_path, 2, skeleton_override=_leaky_skeleton)
    result = S.run_post_processors(site, merge=False, dedup=True)
    assert result["dedup"]["status"] == "leak", result
    assert result["dedup"]["returncode"] == 3
    assert not (site / "chrome_dedup.json").exists()   # child unlinked its flagged artifact


def test_invoked_child_nonzero_is_error_not_skipped(tmp_path):
    # site.json says 2 ok routes (gate passes -> dedup IS invoked), but both skeletons are
    # malformed (not node lists) so site_chrome drops to <2 readable and dies exit 2.
    # That invoked exit-2 MUST map to "error", proving exit-2 is never silently "skipped".
    import site_capture as S
    site = _build_site(tmp_path, 2, skeleton_override=lambda i: {"nodes": "not-a-list"})
    result = S.run_post_processors(site, merge=False, dedup=True)
    assert result["dedup"]["status"] == "error", result
    assert result["dedup"]["returncode"] != 0
    assert not (site / "chrome_dedup.json").exists()


def test_main_folds_post_status_and_exit_code(tmp_path, monkeypatch, capsys):
    import site_capture as S
    site = _build_site(tmp_path, 2)
    manifest = json.loads((site / "site.json").read_text())
    # bypass the CDP capture path: capture_site returns the prebuilt manifest, writes nothing
    monkeypatch.setattr(S, "capture_site", lambda urls, out, transport, sweep=None, crawl=None: manifest)
    monkeypatch.setattr(sys, "argv",
        ["site_capture.py", "--urls", "https://example.com/p0", "--out", str(site),
         "--merge", "--dedup"])
    rc = S.main()
    payload = json.loads(capsys.readouterr().out)
    assert rc == 0
    assert payload["ok"] is True
    assert payload["post"]["merge"]["status"] == "ok"
    assert payload["post"]["dedup"]["status"] == "ok"


def test_main_returns_nonzero_when_post_step_leaks(tmp_path, monkeypatch, capsys):
    import site_capture as S
    site = _build_site(tmp_path, 2, skeleton_override=_leaky_skeleton)
    manifest = json.loads((site / "site.json").read_text())
    monkeypatch.setattr(S, "capture_site", lambda urls, out, transport, sweep=None, crawl=None: manifest)
    monkeypatch.setattr(sys, "argv",
        ["site_capture.py", "--urls", "https://example.com/p0", "--out", str(site),
         "--dedup"])
    rc = S.main()
    payload = json.loads(capsys.readouterr().out)
    assert rc == 3
    assert payload["ok"] is False
    assert payload["post"]["dedup"]["status"] == "leak"


def test_main_returns_one_when_post_step_errors(tmp_path, monkeypatch, capsys):
    # gate passes (2 ok routes) so dedup IS invoked, but malformed skeletons make site_chrome
    # die exit 2 -> status "error" -> main() folds to ok=False and return 1 (distinct from the
    # firewall leak's return 3). Closes the 0/1/3 exit matrix at the main() level.
    import site_capture as S
    site = _build_site(tmp_path, 2, skeleton_override=lambda i: {"nodes": "not-a-list"})
    manifest = json.loads((site / "site.json").read_text())
    monkeypatch.setattr(S, "capture_site", lambda urls, out, transport, sweep=None, crawl=None: manifest)
    monkeypatch.setattr(sys, "argv",
        ["site_capture.py", "--urls", "https://example.com/p0", "--out", str(site),
         "--dedup"])
    rc = S.main()
    payload = json.loads(capsys.readouterr().out)
    assert rc == 1
    assert payload["ok"] is False
    assert payload["post"]["dedup"]["status"] == "error"


# ---------------------------------------------------------------------------
# Task 5: _sweep_argv helper + threading verification
# ---------------------------------------------------------------------------
from types import SimpleNamespace


def test_sweep_flags_forwarded_to_web_skeleton():
    import site_capture as sc
    on = SimpleNamespace(sweep=True, sweep_steps=6)
    off = SimpleNamespace(sweep=False, sweep_steps=8)
    assert sc._sweep_argv(on) == ["--sweep", "--sweep-steps", "6"]
    assert sc._sweep_argv(off) == []


def test_sweep_threaded_to_skeleton_only(tmp_path, monkeypatch):
    """Verify --sweep appears in web_skeleton argv but NOT in web_tokens/bundle_writer."""
    import site_capture as sc

    cmds_seen = []

    def fake_run(cmd):
        cmds_seen.append(cmd)
        # Return code 0 so each step proceeds; skeleton.json read will fail harmlessly.
        class R:
            returncode = 0
        return R()

    monkeypatch.setattr(sc, "_run", fake_run)
    route_dir = tmp_path / "r00"
    sc.capture_route("https://example.com/", route_dir, transport=[], sweep=["--sweep", "--sweep-steps", "6"])

    # web_skeleton.py call: must contain --sweep
    sk_cmd = next(c for c in cmds_seen if "web_skeleton.py" in c)
    assert "--sweep" in sk_cmd, f"sweep flag missing from web_skeleton argv: {sk_cmd}"

    # web_tokens.py call: must NOT contain --sweep
    tok_cmd = next((c for c in cmds_seen if "web_tokens.py" in c), None)
    if tok_cmd is not None:
        assert "--sweep" not in tok_cmd, f"sweep flag incorrectly forwarded to web_tokens: {tok_cmd}"

    # bundle_writer.py call: must NOT contain --sweep
    bw_cmd = next((c for c in cmds_seen if "bundle_writer.py" in c), None)
    if bw_cmd is not None:
        assert "--sweep" not in bw_cmd, f"sweep flag incorrectly forwarded to bundle_writer: {bw_cmd}"
