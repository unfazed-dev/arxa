"""Edge-case tests for motion_adapter's bezier-None / incomplete-channel guards.

Self-contained (does not reuse the fixture helpers in test_motion_adapter.py):
pins the invariant that neither adapter can emit a row that assert_contract
rejects, and that main() validates before writing."""
import json
import subprocess
import sys
from pathlib import Path

import motion_adapter as ma

HERE = Path(__file__).parent


def _anim(channels, sel="h1.hero", absY=320):
    return {"movers": [{"sel": sel, "absY": absY, "dominant": next(iter(channels)),
                        "channels": channels}]}


def _good_anim_channel():
    return {"from": -40.0, "to": 0.0, "range": 40.0, "scrollDeterministic": True,
            "activeScroll": [200, 640],
            "easing": {"name": "easeOutCubic",
                       "bezier": "cubic-bezier(0.33,0.0,0.67,1.0)", "rms": 0.012},
            "certified": True}


def _dash_anim_channel():
    # a CERTIFIED channel whose easing fit produced no real curve ("-")
    return {"from": -10.0, "to": 0.0, "range": 10.0, "scrollDeterministic": True,
            "activeScroll": [100, 300],
            "easing": {"name": "custom", "bezier": "-", "rms": 0.2},
            "certified": True}


def _fb(channels, selector=".menu-panel"):
    return {"selector": selector, "recovery": {"channels": channels}}


# ---- web_anim: bezier "-" on a certified channel is skipped, good one survives ----

def test_anim_dash_bezier_channel_skipped():
    out = ma.adapt_web_anim(_anim({"ty": _good_anim_channel(),
                                   "tx": _dash_anim_channel()}))
    names = [r["name"] for r in out]
    assert "h1.hero#ty" in names
    assert "h1.hero#tx" not in names
    assert len(out) == 1


def test_anim_all_output_rows_pass_contract():
    out = ma.adapt_web_anim(_anim({"ty": _good_anim_channel(),
                                   "tx": _dash_anim_channel()}),
                            certified_only=False)
    for r in out:
        ma.assert_contract(r)  # must not raise on anything the adapter emits


# ---- web_flipbook: truthy easing but "-" bezier is skipped; None amp skipped ----

def test_flipbook_dash_bezier_channel_skipped():
    chans = {
        "y": {"easing": "easeInOutQuart",
              "bezier": "cubic-bezier(0.76,0.0,0.24,1.0)", "amp": 300.0, "rms": 0.008},
        "x": {"easing": "customCurve", "bezier": "-", "amp": 120.0, "rms": 0.05},
    }
    out = ma.adapt_flipbook(_fb(chans), anchor=0.0)
    names = [r["name"] for r in out]
    assert ".menu-panel#y" in names
    assert ".menu-panel#x" not in names
    assert len(out) == 1


def test_flipbook_incomplete_channel_skipped():
    chans = {
        "y": {"easing": "easeInOutQuart",
              "bezier": "cubic-bezier(0.76,0.0,0.24,1.0)", "amp": None, "rms": 0.008},
    }
    out = ma.adapt_flipbook(_fb(chans), anchor=0.0)
    assert out == []  # amp=None cannot form a valid contract row


def test_flipbook_all_output_rows_pass_contract():
    chans = {
        "y": {"easing": "easeInOutQuart",
              "bezier": "cubic-bezier(0.76,0.0,0.24,1.0)", "amp": 300.0, "rms": 0.008},
        "x": {"easing": "customCurve", "bezier": "-", "amp": 120.0, "rms": 0.05},
    }
    for r in ma.adapt_flipbook(_fb(chans), anchor=10.0):
        ma.assert_contract(r)


# ---- CLI: --flipbook requires --flipbook-anchor ----

def test_cli_flipbook_requires_anchor(tmp_path):
    fb = tmp_path / "fb.json"
    fb.write_text(json.dumps(_fb({"y": {"easing": "easeInOutQuart",
                  "bezier": "cubic-bezier(0.76,0.0,0.24,1.0)", "amp": 300.0, "rms": 0.008}})))
    out = tmp_path / "motion.json"
    r = subprocess.run([sys.executable, str(HERE / "motion_adapter.py"),
                        "--flipbook", str(fb), "--out", str(out)],
                       capture_output=True, text=True)
    assert r.returncode != 0
    assert "flipbook-anchor" in (r.stdout + r.stderr)
