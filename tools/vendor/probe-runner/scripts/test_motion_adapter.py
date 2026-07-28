#!/usr/bin/env python3
"""Tests for motion_adapter — all pure-logic (no browser, no network).

Unit-tested here: parse_bezier, axis_for_channel, adapt_web_anim,
adapt_flipbook, assert_contract, combine, and a round-trip through
bundle_writer.match_motion confirming key contract compatibility.
Live-only (not tested here): main() CLI, file I/O.
"""
from __future__ import annotations

import sys
import os

import pytest

sys.path.insert(0, os.path.dirname(__file__))
import motion_adapter as ma
import bundle_writer as bw

# ─── fixtures ────────────────────────────────────────────────────────────────

MOVER = {
    "rank": 1, "sel": "h1.hero", "tag": "H1", "absY": 320, "txt": "Some text",
    "dominant": "ty",
    "channels": {
        "ty": {
            "from": -40.0, "to": 0.0, "range": 40.0,
            "scrollDeterministic": True,
            "activeScroll": [200, 640],
            "easing": {
                "name": "easeOutCubic",
                "bezier": "cubic-bezier(0.33,0.0,0.67,1.0)",
                "rms": 0.012,
            },
            "certified": True,
        },
        "op": {
            "from": 0.0, "to": 1.0, "range": 1.0,
            "scrollDeterministic": True,
            "activeScroll": [200, 560],
            "easing": {
                "name": "linear",
                "bezier": "cubic-bezier(0.0,0.0,1.0,1.0)",
                "rms": 0.05,
            },
            "certified": False,
            "reason": "curve does not match a standard easing (rms 0.050)",
        },
    },
}

ANIM_OUT = {"movers": [MOVER]}

FLIPBOOK_OUT = {
    "selector": ".menu-panel",
    "mode": "translate",
    "dpr": 2,
    "frames": 24,
    "reproducible": True,
    "recovery": {
        "frames": 24,
        "min_confidence": 0.9,
        "max_confidence": 0.99,
        "entering": False,
        "x_uniform": True,
        # Real analyze_frames channel keys: ty/tx/opacity (+scale w/ --scale).
        # NOT y/x/op — those are the wrong channel names and masked the real
        # _AXIS_MAP behaviour. The scale channel carries the same shape as
        # tx/ty/opacity (amp/samples/reliable) since the _scale_channel fix.
        "channels": {
            "ty": {
                "from": -300.0, "to": 0.0, "amp": 300.0,
                "samples": 22, "reliable": True,
                "easing": "easeInOutQuart",
                "bezier": "cubic-bezier(0.76,0.0,0.24,1.0)",
                "rms": 0.008,
            },
            "opacity": {
                "from": 0.0, "to": 1.0, "amp": 1.0,
                "samples": 24, "reliable": True,
                "easing": None,
                "bezier": "-",
                "rms": None,
            },
        },
    },
}

# ─── parse_bezier ─────────────────────────────────────────────────────────────

class TestParseBezier:
    def test_normal(self):
        r = ma.parse_bezier("cubic-bezier(0.33,0.0,0.67,1.0)")
        assert r == [0.33, 0.0, 0.67, 1.0]

    def test_spaces(self):
        r = ma.parse_bezier("cubic-bezier( 0.33 , 0.0 , 0.67 , 1.0 )")
        assert r == [0.33, 0.0, 0.67, 1.0]

    def test_dash_returns_none(self):
        assert ma.parse_bezier("-") is None

    def test_empty_returns_none(self):
        assert ma.parse_bezier("") is None

    def test_none_returns_none(self):
        assert ma.parse_bezier(None) is None

    def test_garbage_returns_none(self):
        assert ma.parse_bezier("not-a-bezier(1,2)") is None

    def test_result_type(self):
        r = ma.parse_bezier("cubic-bezier(0.76,0.0,0.24,1.0)")
        assert isinstance(r, list) and len(r) == 4
        assert all(isinstance(v, float) for v in r)

# ─── axis_for_channel ─────────────────────────────────────────────────────────

class TestAxisForChannel:
    def test_tx(self):   assert ma.axis_for_channel("tx") == "x"
    def test_ty(self):   assert ma.axis_for_channel("ty") == "y"
    def test_sx(self):   assert ma.axis_for_channel("sx") == "scale-x"
    def test_sy(self):   assert ma.axis_for_channel("sy") == "scale-y"
    def test_rot(self):  assert ma.axis_for_channel("rot") == "rotate"
    def test_op(self):   assert ma.axis_for_channel("op") == "opacity"
    def test_tz(self):   assert ma.axis_for_channel("tz") == "translate-z"
    def test_rotX(self): assert ma.axis_for_channel("rotX") == "rotate-x"
    def test_rotY(self): assert ma.axis_for_channel("rotY") == "rotate-y"
    def test_unknown(self): assert ma.axis_for_channel("skew") == "skew"

    def test_depth_channel_row_maps_axis_and_passes_contract(self):
        # a certified tz (depth) mover -> row axis "translate-z", contract-valid.
        mv = {"rank": 0, "sel": "div.card", "tag": "DIV", "absY": 500, "absX": 200,
              "txt": "", "channels": {"tz": {
                  "from": 0.0, "to": 120.0, "range": 120.0, "scrollDeterministic": True,
                  "activeScroll": [0, 700],
                  "easing": {"name": "linear", "bezier": "cubic-bezier(0,0,1,1)", "rms": 0.0},
                  "certified": True}}}
        row = ma.adapt_web_anim({"movers": [mv]})[0]
        assert row["axis"] == "translate-z"
        assert row["name"] == "div.card#0#tz"
        assert row["amplitude"] == 120.0
        ma.assert_contract(row)

# ─── adapt_web_anim ───────────────────────────────────────────────────────────

class TestAdaptWebAnim:
    def _rows(self, **kw):
        return ma.adapt_web_anim(ANIM_OUT, **kw)

    def test_certified_only_default_yields_one_row(self):
        rows = self._rows()
        assert len(rows) == 1

    def test_certified_row_name(self):
        # name embeds the mover rank so two same-selector movers (e.g. mirror
        # hero words) get distinct, non-colliding names.
        row = self._rows()[0]
        assert row["name"] == "h1.hero#1#ty"

    def test_uncertified_dropped_by_default(self):
        rows = self._rows()
        names = [r["name"] for r in rows]
        assert "h1.hero#1#op" not in names

    def test_keep_uncertified_yields_both(self):
        rows = self._rows(certified_only=False)
        assert len(rows) == 2
        names = {r["name"] for r in rows}
        assert names == {"h1.hero#1#ty", "h1.hero#1#op"}

    def test_anchor(self):
        row = self._rows()[0]
        assert row["anchor"] == 320.0

    def test_klass(self):
        row = self._rows()[0]
        assert row["klass"] == "scroll"

    def test_no_class_key(self):
        row = self._rows()[0]
        assert "class" not in row

    def test_window(self):
        row = self._rows()[0]
        assert row["window"] == [200.0, 640.0]
        assert all(isinstance(v, float) for v in row["window"])

    def test_cubic_bezier(self):
        row = self._rows()[0]
        cb = row["cubic_bezier"]
        assert isinstance(cb, list) and len(cb) == 4
        assert all(isinstance(v, float) for v in cb)

    def test_amplitude(self):
        row = self._rows()[0]
        assert row["amplitude"] == 40.0

    def test_axis(self):
        row = self._rows()[0]
        assert row["axis"] == "y"

    def test_source(self):
        row = self._rows()[0]
        assert row["source"] == "web_anim"

    def test_easing(self):
        row = self._rows()[0]
        assert row["easing"] == "easeOutCubic"

    def test_rms(self):
        row = self._rows()[0]
        assert row["rms"] == 0.012

    def test_assert_contract_passes(self):
        for row in self._rows():
            ma.assert_contract(row)  # must not raise

    def test_anchor_x_carried_when_present(self):
        # mover carries absX (REST center-x) -> row gets anchor_x for 2D binding.
        mv = {**MOVER, "absX": 700}
        row = ma.adapt_web_anim({"movers": [mv]})[0]
        assert row["anchor_x"] == 700.0

    def test_anchor_x_omitted_when_absent(self):
        # back-compat: a mover without absX yields no anchor_x key (binder falls
        # back to y-only).
        row = self._rows()[0]
        assert "anchor_x" not in row

    def test_amplitude_signed_negative(self):
        # amplitude is SIGNED (to - from), preserving motion direction. A leftward
        # mirror mover (to < from) must yield a NEGATIVE amplitude, not abs().
        mv = {**MOVER, "channels": {"tx": {
            "from": 216.0, "to": -864.0, "range": 1080.0,
            "scrollDeterministic": True, "activeScroll": [165, 1088],
            "easing": {"name": "ease-out", "bezier": "cubic-bezier(0,0,0.58,1)", "rms": 0.01},
            "certified": True}}}
        row = ma.adapt_web_anim({"movers": [mv]})[0]
        assert row["amplitude"] == -1080.0

    def test_two_same_sel_movers_unique_names(self):
        # the bug that broke kasane: two h1 movers both serialized as "h1#tx".
        # rank in the name keeps them distinct.
        mvL = {"rank": 0, "sel": "h1", "tag": "H1", "absY": 365, "absX": 395,
               "txt": "Handcrafted", "channels": {"tx": {
                   "from": -216.0, "to": -864.0, "range": 648.0,
                   "scrollDeterministic": True, "activeScroll": [165, 1088],
                   "easing": {"name": "ease-out", "bezier": "cubic-bezier(0,0,0.58,1)", "rms": 0.01},
                   "certified": True}}}
        mvR = {**mvL, "rank": 1, "absX": 1053, "txt": "With Urushi",
               "channels": {"tx": {**mvL["channels"]["tx"], "from": 216.0, "to": 864.0}}}
        rows = ma.adapt_web_anim({"movers": [mvL, mvR]})
        names = [r["name"] for r in rows]
        assert names == ["h1#0#tx", "h1#1#tx"]
        by = {r["name"]: r for r in rows}
        assert by["h1#0#tx"]["amplitude"] < 0 < by["h1#1#tx"]["amplitude"]
        assert by["h1#0#tx"]["anchor_x"] == 395.0
        assert by["h1#1#tx"]["anchor_x"] == 1053.0

# ─── adapt_flipbook ───────────────────────────────────────────────────────────

class TestAdaptFlipbook:
    def _rows(self, anchor=500.0, **kw):
        return ma.adapt_flipbook(FLIPBOOK_OUT, anchor, **kw)

    def test_null_easing_dropped(self):
        rows = self._rows()
        assert len(rows) == 1

    def test_row_name(self):
        row = self._rows()[0]
        # real channel key is "ty" (analyze_frames), not "y"
        assert row["name"] == ".menu-panel#ty"

    def test_anchor(self):
        row = self._rows(anchor=999.0)[0]
        assert row["anchor"] == 999.0

    def test_klass(self):
        row = self._rows()[0]
        assert row["klass"] == "time"

    def test_no_class_key(self):
        row = self._rows()[0]
        assert "class" not in row

    def test_amplitude(self):
        row = self._rows()[0]
        assert row["amplitude"] == 300.0

    def test_axis(self):
        row = self._rows()[0]
        # real channel "ty" → _AXIS_MAP["ty"] → "y"
        assert row["axis"] == "y"

    def test_easing(self):
        row = self._rows()[0]
        assert row["easing"] == "easeInOutQuart"

    def test_rms(self):
        row = self._rows()[0]
        assert row["rms"] == 0.008

    def test_cubic_bezier(self):
        row = self._rows()[0]
        cb = row["cubic_bezier"]
        assert isinstance(cb, list) and len(cb) == 4

    def test_source(self):
        row = self._rows()[0]
        assert row["source"] == "web_flipbook"

    def test_window_default(self):
        row = self._rows()[0]
        assert row["window"] == [0.0, 1.0]

    def test_window_supplied(self):
        row = self._rows(window=[100.0, 800.0])[0]
        assert row["window"] == [100.0, 800.0]

    def test_assert_contract_passes(self):
        for row in self._rows():
            ma.assert_contract(row)  # must not raise


# ─── adapt_flipbook: scale channel regression (the _scale_channel shape bug) ──

# Real _flipbook._scale_channel output shape (post-fix): same keys as tx/ty/
# opacity — amp/samples/reliable/easing/bezier/rms. Pre-fix it lacked `amp`
# and adapt_flipbook silently dropped every scale recovery via the KeyError
# swallow. This fixture mirrors the fixed shape and asserts a row is emitted.
_FLIPBOOK_OUT_WITH_SCALE = {
    "selector": ".card",
    "recovery": {"channels": {
        "scale": {
            "from": 0.5, "to": 1.0, "amp": 0.5,
            "samples": 14, "reliable": True,
            "easing": "easeOutCubic",
            "bezier": "cubic-bezier(0.33,1.0,0.68,1.0)",
            "rms": 0.02,
        },
    }},
}


class TestAdaptFlipbookScaleChannel:
    def test_scale_channel_not_silently_dropped(self):
        # REGRESSION: pre-fix, adapt_flipbook read ch_entry["amp"]; _scale_channel
        # never emitted it → KeyError → swallowed → scale row vanished. Now the
        # scale channel carries amp and MUST produce a contract-valid row.
        rows = ma.adapt_flipbook(_FLIPBOOK_OUT_WITH_SCALE, anchor=200.0)
        assert len(rows) == 1, rows
        assert rows[0]["name"] == ".card#scale"
        assert rows[0]["axis"] == "scale"          # passthrough (not in _AXIS_MAP)
        assert rows[0]["amplitude"] == 0.5
        ma.assert_contract(rows[0])

    def test_scale_channel_amp_fallback_when_missing(self):
        # Defensive: if a future channel omits amp, the adapter falls back to
        # (to - from) rather than dropping the channel.
        fb = {"selector": ".x", "recovery": {"channels": {
            "scale": {"from": 0.5, "to": 1.2, "easing": "linear",
                      "bezier": "cubic-bezier(0,0,1,1)", "rms": 0.01}}}}
        rows = ma.adapt_flipbook(fb, anchor=0.0)
        assert len(rows) == 1 and rows[0]["amplitude"] == 0.7, rows

# ─── adapt_flipbook: native payload shapes (no `selector` / no `recovery` wrapper) ─

# Native flipbook CLIs (ios_/adb_/flutter_flipbook) emit `{"recovery": {channels}}`
# with NO `selector` (web-only). The raw `recover_from_video`/`analyze_frames` dict
# is `{"channels": ...}` with NO `recovery` wrapper. Both shapes previously
# KeyErrored in adapt_flipbook (it did `fb_out["selector"]` and
# `fb_out["recovery"]["channels"]`). motion_summary already handled both via
# `payload.get("recovery") or payload`; adapt_flipbook now mirrors that. These
# two fixtures + class are the regression net.

_NATIVE_CLI_FLIPBOOK = {
    # shape emitted by ios_flipbook/adb_flipbook/flutter_flipbook main(): a top-level
    # `recovery` block (recover_from_video output), no web `selector`.
    "engine": "ios",
    "dpr": 3.0,
    "recovery": {
        "frames": 18,
        "channels": {
            "ty": {
                "from": -14.0, "to": 0.0, "amp": 14.0,
                "samples": 16, "reliable": True,
                "easing": "easeOutCubic",
                "bezier": "cubic-bezier(0.33,1.0,0.68,1.0)",
                "rms": 0.015,
            },
        },
    },
}

_RAW_RECOVER_FLIPBOOK = {
    # shape of the raw _native_flipbook.recover_from_video return value: `channels`
    # at the TOP level, no `recovery` wrapper at all.
    "frames": 18,
    "channels": {
        "ty": {
            "from": -14.0, "to": 0.0, "amp": 14.0,
            "samples": 16, "reliable": True,
            "easing": "easeOutCubic",
            "bezier": "cubic-bezier(0.33,1.0,0.68,1.0)",
            "rms": 0.015,
        },
    },
    "video": {"path": "/tmp/x.mov", "fps": 30},
}


class TestAdaptFlipbookNativeShapes:
    def test_native_cli_shape_no_selector(self):
        # REGRESSION: pre-fix, `fb_out["selector"]` KeyErrored on native payloads.
        rows = ma.adapt_flipbook(_NATIVE_CLI_FLIPBOOK, anchor=120.0)
        assert len(rows) == 1, rows
        # `selector` is web-only; native falls back to "mover" in the name.
        assert rows[0]["name"] == "mover#ty"
        assert rows[0]["axis"] == "y"
        assert rows[0]["amplitude"] == 14.0
        assert rows[0]["source"] == "web_flipbook"
        ma.assert_contract(rows[0])

    def test_raw_recover_shape_no_recovery_wrapper(self):
        # REGRESSION: pre-fix, `fb_out["recovery"]["channels"]` KeyErrored on the
        # raw recover_from_video dict (channels live top-level).
        rows = ma.adapt_flipbook(_RAW_RECOVER_FLIPBOOK, anchor=120.0)
        assert len(rows) == 1, rows
        assert rows[0]["name"] == "mover#ty"
        ma.assert_contract(rows[0])

    def test_native_round_trips_through_bundle_writer(self):
        # the end-to-end value: native motion can now enter the bundle's motion.json.
        rows = ma.adapt_flipbook(_NATIVE_CLI_FLIPBOOK, anchor=120.0)
        nodes = [{"id": "n_native", "bbox": {"y": 120.0}}]
        result = bw.match_motion(nodes, rows)
        assert len(result) == 1
        assert result[0]["class"] == "time"
        assert result[0]["node_id"] == "n_native"

    def test_web_shape_still_works_after_native_fix(self):
        # back-compat: the existing web_flipbook shape (selector + recovery.channels)
        # must not regress.
        rows = ma.adapt_flipbook(FLIPBOOK_OUT, anchor=500.0)
        assert len(rows) == 1
        assert rows[0]["name"] == ".menu-panel#ty"   # web selector preserved
        ma.assert_contract(rows[0])


# ─── assert_contract ──────────────────────────────────────────────────────────

class TestAssertContract:
    def _good(self):
        return {
            "name": "h1#ty", "anchor": 320.0, "easing": "easeOutCubic",
            "cubic_bezier": [0.33, 0.0, 0.67, 1.0],
            "amplitude": 40.0, "axis": "y",
            "window": [200.0, 640.0], "klass": "scroll",
            "source": "web_anim", "rms": 0.012,
        }

    def test_good_row_passes(self):
        ma.assert_contract(self._good())  # must not raise

    def test_missing_key_raises(self):
        row = self._good()
        del row["name"]
        with pytest.raises((AssertionError, KeyError)):
            ma.assert_contract(row)

    def test_bad_klass_raises(self):
        row = self._good()
        row["klass"] = "bad"
        with pytest.raises(AssertionError):
            ma.assert_contract(row)

    def test_cubic_bezier_wrong_length(self):
        row = self._good()
        row["cubic_bezier"] = [0.33, 0.0, 0.67]
        with pytest.raises(AssertionError):
            ma.assert_contract(row)

    def test_cubic_bezier_not_list(self):
        row = self._good()
        row["cubic_bezier"] = "0.33,0.0,0.67,1.0"
        with pytest.raises(AssertionError):
            ma.assert_contract(row)

    def test_window_wrong_length(self):
        row = self._good()
        row["window"] = [200.0]
        with pytest.raises(AssertionError):
            ma.assert_contract(row)

    def test_amplitude_not_numeric(self):
        row = self._good()
        row["amplitude"] = "40"
        with pytest.raises(AssertionError):
            ma.assert_contract(row)

    def test_anchor_not_numeric(self):
        row = self._good()
        row["anchor"] = "320"
        with pytest.raises(AssertionError):
            ma.assert_contract(row)

# ─── combine ─────────────────────────────────────────────────────────────────

class TestCombine:
    def test_order_anim_first(self):
        anim_rows = ma.adapt_web_anim(ANIM_OUT)
        fb_rows = ma.adapt_flipbook(FLIPBOOK_OUT, 500.0)
        combined = ma.combine(anim_rows, fb_rows)
        assert len(combined) == len(anim_rows) + len(fb_rows)
        # anim rows come first
        for i, row in enumerate(anim_rows):
            assert combined[i] is row
        # flipbook rows follow
        for j, row in enumerate(fb_rows):
            assert combined[len(anim_rows) + j] is row

    def test_empty_inputs(self):
        assert ma.combine([], []) == []

    def test_anim_only(self):
        rows = ma.adapt_web_anim(ANIM_OUT)
        assert ma.combine(rows, []) == rows

    def test_flipbook_only(self):
        rows = ma.adapt_flipbook(FLIPBOOK_OUT, 100.0)
        assert ma.combine([], rows) == rows

# ─── adapt_web_anim: bad bezier skipped ──────────────────────────────────────

# Mover with two CERTIFIED channels: one valid bezier, one bezier="-"
_MOVER_BAD_BEZIER = {
    "rank": 2, "sel": "p.hero", "tag": "P", "absY": 100, "txt": "hi",
    "dominant": "ty",
    "channels": {
        "ty": {
            "from": -20.0, "to": 0.0, "range": 20.0,
            "scrollDeterministic": True,
            "activeScroll": [100, 400],
            "easing": {
                "name": "easeOutCubic",
                "bezier": "cubic-bezier(0.33,0.0,0.67,1.0)",
                "rms": 0.01,
            },
            "certified": True,
        },
        "op": {
            "from": 0.0, "to": 1.0, "range": 1.0,
            "scrollDeterministic": True,
            "activeScroll": [100, 400],
            "easing": {
                "name": "custom",
                "bezier": "-",
                "rms": 0.2,
            },
            "certified": True,
        },
    },
}

_ANIM_OUT_BAD_BEZIER = {"movers": [_MOVER_BAD_BEZIER]}


class TestAdaptWebAnimBadBezier:
    def _rows(self):
        return ma.adapt_web_anim(_ANIM_OUT_BAD_BEZIER)

    def test_bad_bezier_channel_dropped(self):
        # op channel has bezier="-" → parse_bezier returns None → must be skipped
        rows = self._rows()
        names = [r["name"] for r in rows]
        assert "p.hero#2#op" not in names

    def test_good_bezier_channel_still_emitted(self):
        # ty channel has a valid bezier → must still appear (rank 2 in this fixture)
        rows = self._rows()
        names = [r["name"] for r in rows]
        assert "p.hero#2#ty" in names

    def test_exactly_one_row(self):
        rows = self._rows()
        assert len(rows) == 1

    def test_all_emitted_rows_pass_contract(self):
        # blanket invariant: adapter must never emit a contract-invalid row
        for row in self._rows():
            ma.assert_contract(row)  # must not raise


# ─── adapt_flipbook: bad bezier skipped ───────────────────────────────────────

# Flipbook with two channels: one valid bezier, one bezier="-" but truthy easing
_FLIPBOOK_OUT_BAD_BEZIER = {
    "selector": ".nav",
    "mode": "translate",
    "dpr": 2,
    "frames": 24,
    "reproducible": True,
    "recovery": {
        "frames": 24,
        "min_confidence": 0.9,
        "channels": {
            "ty": {
                "from": -200.0, "to": 0.0, "amp": 200.0,
                "easing": "easeInOutQuart",
                "bezier": "cubic-bezier(0.76,0.0,0.24,1.0)",
                "rms": 0.005,
            },
            "tx": {
                "from": -50.0, "to": 0.0, "amp": 50.0,
                "easing": "customCurve",   # truthy — passes the easing guard
                "bezier": "-",             # unparseable → must be skipped
                "rms": 0.03,
            },
        },
    },
}


class TestAdaptFlipbookBadBezier:
    def _rows(self, anchor=400.0, **kw):
        return ma.adapt_flipbook(_FLIPBOOK_OUT_BAD_BEZIER, anchor, **kw)

    def test_bad_bezier_channel_dropped(self):
        rows = self._rows()
        names = [r["name"] for r in rows]
        assert ".nav#tx" not in names

    def test_good_bezier_channel_still_emitted(self):
        rows = self._rows()
        names = [r["name"] for r in rows]
        assert ".nav#ty" in names

    def test_exactly_one_row(self):
        rows = self._rows()
        assert len(rows) == 1

    def test_all_emitted_rows_pass_contract(self):
        for row in self._rows():
            ma.assert_contract(row)  # must not raise


# ─── CLI: --flipbook without --flipbook-anchor exits non-zero ─────────────────

class TestCLIFlipbookAnchorRequired:
    def test_flipbook_without_anchor_exits_nonzero(self, tmp_path):
        import subprocess, sys, json as _json
        # write a minimal valid flipbook JSON so file-open doesn't fail first
        fb = tmp_path / "fb.json"
        fb.write_text(_json.dumps(_FLIPBOOK_OUT_BAD_BEZIER))
        out = tmp_path / "out.json"
        result = subprocess.run(
            [sys.executable, __file__.replace("test_motion_adapter.py", "motion_adapter.py"),
             "--flipbook", str(fb), "--out", str(out)],
            capture_output=True, text=True,
        )
        assert result.returncode != 0
        assert "flipbook-anchor" in result.stderr or "flipbook-anchor" in result.stdout


# ─── round-trip through bundle_writer.match_motion ───────────────────────────

class TestRoundTrip:
    """Verify that produced rows are consumable by bundle_writer.match_motion
    without KeyError, and that the output carries "class" (not "klass")."""

    def test_anim_row_round_trip(self):
        rows = ma.adapt_web_anim(ANIM_OUT)
        # anchor==320.0; place node bbox.y within band (400px)
        nodes = [{"id": "n1", "bbox": {"y": 320.0}}]
        result = bw.match_motion(nodes, rows)
        assert len(result) == 1
        r = result[0]
        # match_motion renames klass → class
        assert "class" in r
        assert "klass" not in r
        # verify all expected keys present
        for k in ("node_id", "name", "easing", "cubic_bezier", "amplitude",
                   "axis", "window", "class", "source", "rms"):
            assert k in r, f"missing key: {k}"

    def test_flipbook_row_round_trip(self):
        rows = ma.adapt_flipbook(FLIPBOOK_OUT, anchor=500.0)
        nodes = [{"id": "n2", "bbox": {"y": 500.0}}]
        result = bw.match_motion(nodes, rows)
        assert len(result) == 1
        r = result[0]
        assert "class" in r
        for k in ("node_id", "name", "easing", "cubic_bezier", "amplitude",
                   "axis", "window", "class", "source", "rms"):
            assert k in r, f"missing key: {k}"

    def test_combined_round_trip(self):
        anim_rows = ma.adapt_web_anim(ANIM_OUT)
        fb_rows = ma.adapt_flipbook(FLIPBOOK_OUT, anchor=500.0)
        combined = ma.combine(anim_rows, fb_rows)
        nodes = [
            {"id": "n1", "bbox": {"y": 320.0}},
            {"id": "n2", "bbox": {"y": 500.0}},
        ]
        result = bw.match_motion(nodes, combined)
        assert len(result) == 2


def test_adapt_web_anim_segmented_channel_emits_one_row_per_segment():
    mv = {"sel": "div", "rank": 0, "absY": 200.0, "channels": {
        "tx": {"certified": True, "segments": [
            {"from": 0.0, "to": 400.0, "activeScroll": [0.0, 1000.0],
             "easing": {"name": "easeOut", "bezier": "cubic-bezier(0,0,0.58,1)", "rms": 0.02}, "certified": True},
            {"from": 400.0, "to": 0.0, "activeScroll": [1000.0, 2000.0],
             "easing": {"name": "easeIn", "bezier": "cubic-bezier(0.42,0,1,1)", "rms": 0.03}, "certified": True},
        ]}}}
    rows = ma.adapt_web_anim({"movers": [mv]})
    assert len(rows) == 2, rows
    assert rows[0]["window"] == [0.0, 1000.0] and rows[0]["amplitude"] == 400.0
    assert rows[1]["window"] == [1000.0, 2000.0] and rows[1]["amplitude"] == -400.0
    assert rows[0]["name"] != rows[1]["name"]
    for r in rows:
        ma.assert_contract(r)
        assert r["klass"] == "scroll" and r["axis"] == "x"


def test_adapt_web_anim_segment_certified_only_filter():
    # Mixed channel: one certified segment, one uncertified (both valid beziers).
    mv = {"sel": "div", "rank": 0, "absY": 200.0, "channels": {
        "tx": {"certified": True, "segments": [
            {"from": 0.0, "to": 400.0, "activeScroll": [0.0, 1000.0],
             "easing": {"name": "easeOut", "bezier": "cubic-bezier(0,0,0.58,1)", "rms": 0.02}, "certified": True},
            {"from": 400.0, "to": 0.0, "activeScroll": [1000.0, 2000.0],
             "easing": {"name": "easeIn", "bezier": "cubic-bezier(0.42,0,1,1)", "rms": 0.20}, "certified": False},
        ]}}}
    only = ma.adapt_web_anim({"movers": [mv]})                  # certified_only=True (default)
    assert len(only) == 1 and only[0]["amplitude"] == 400.0, only   # uncertified seg dropped
    allrows = ma.adapt_web_anim({"movers": [mv]}, certified_only=False)
    assert len(allrows) == 2, allrows                           # filter off -> both segments emitted
    for r in allrows:
        ma.assert_contract(r)
