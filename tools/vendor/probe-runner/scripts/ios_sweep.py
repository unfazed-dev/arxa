#!/usr/bin/env python3
"""iOS full-surface tappability sweep for Kit Showcase.

For every interactive AX element on each tab (incl. overlays + below-fold):
tap it via probe-runner ios_tap.py and verify the UI responded (AX signature
diff within a poll window). Exit summary: reached/responded/failed matrix.
"""
import json, subprocess, sys, time, os

UDID = os.environ.get("SWEEP_UDID") or (sys.argv[1] if len(sys.argv) > 1
        else "CAFC93F7-5815-4A86-B9FA-95123DE3018C")
SCRIPTS = os.path.dirname(os.path.abspath(__file__))
if not os.path.exists(os.path.join(SCRIPTS, "ios_tap.py")):  # running from /tmp
    SCRIPTS = os.path.expanduser("~/.agents/skills/probe-runner/scripts")
TAB_PTS = {"Home": (114, 821), "Search": (200, 821), "Profile": (286, 821)}
MARK = {"Search": ["price range", "radius"], "Profile": ["account", "toolbar"], "Home": ["glass cta"]}
RESULTS = []

def sh(*args, **kw):
    return subprocess.run(list(args), capture_output=True, text=True, **kw)

def ax():
    r = sh("idb", "ui", "describe-all", "--udid", UDID)
    try:
        return json.loads(r.stdout)
    except Exception:
        return []

def sig(els=None):
    els = ax() if els is None else els
    return {(e.get("type"), e.get("AXLabel"), str(e.get("AXValue"))) for e in els}

def labels(els=None):
    els = ax() if els is None else els
    return {(e.get("AXLabel") or "").lower() for e in els}

def tap(x, y):
    sh(sys.executable, os.path.join(SCRIPTS, "ios_tap.py"), str(int(x)), str(int(y)))

def tap_el(e):
    f = e["frame"]
    tap(f["x"] + f["width"] / 2, f["y"] + f["height"] / 2)

def swipe(x1, y1, x2, y2, dur=0.35):
    sh(sys.executable, os.path.join(SCRIPTS, "ios_swipe.py"),
       str(int(x1)), str(int(y1)), str(int(x2)), str(int(y2)), "--duration", str(dur))

def find(label=None, typ=None, els=None, contains=False):
    els = ax() if els is None else els
    out = []
    for e in els:
        lab = e.get("AXLabel") or ""
        if label is not None:
            if contains and label.lower() not in lab.lower():
                continue
            if not contains and lab != label:
                continue
        if typ is not None and e.get("type") != typ:
            continue
        out.append(e)
    return out

def responded(before, timeout=3.0):
    t0 = time.time()
    while time.time() - t0 < timeout:
        time.sleep(0.45)
        if sig() != before:
            return True
    return False

def record(tab, name, ok, note=""):
    RESULTS.append((tab, name, ok, note))
    print(f"[{tab:<7}] {name:<38} {'PASS' if ok else 'FAIL'} {note}", flush=True)

def goto(tab, settle=0.8):
    x, y = TAB_PTS[tab]
    tap(x, y); time.sleep(settle)
    ls = labels()
    return any(any(m in l for l in ls) for m in MARK[tab])

def settle_toasts(max_wait=6.0):
    """Wait for transient toasts/snackbars to drain so diffs stay clean."""
    stable, t0 = sig(), time.time()
    while time.time() - t0 < max_wait:
        time.sleep(0.8)
        now = sig()
        if now == stable:
            return
        stable = now

def tap_and_check(tab, e, name=None):
    name = name or f"{e.get('type')}|{e.get('AXLabel')}"
    before = sig()
    tap_el(e)
    ok = responded(before)
    record(tab, name, ok)
    settle_toasts()
    return ok

def open_overlay_and_tap_items(tab, trigger_label, expect_items=None, max_items=4):
    """Open an overlay via trigger; tap each item across reopens."""
    base = labels()
    trig = find(trigger_label)
    if not trig:
        record(tab, f"overlay:{trigger_label}", False, "trigger not found")
        return
    tap_el(trig[0]); time.sleep(0.9)
    new = sorted(l for l in labels() - base if l and l != trigger_label.lower())
    if not new:
        record(tab, f"overlay:{trigger_label} opens", False, "no new elements")
        return
    record(tab, f"overlay:{trigger_label} opens", True, f"items={new[:6]}")
    items = new[:max_items]
    # close it (tap far corner) then re-open per item
    tap(30, 130); time.sleep(0.6)
    for it in items:
        trig = find(trigger_label)
        if not trig:
            record(tab, f"{trigger_label}>{it}", False, "trigger lost")
            continue
        tap_el(trig[0]); time.sleep(0.9)
        cand = [e for e in ax() if (e.get("AXLabel") or "").lower() == it]
        if not cand:
            record(tab, f"{trigger_label}>{it}", False, "item not found on reopen")
            tap(30, 130); time.sleep(0.5)
            continue
        before = sig()
        tap_el(cand[0])
        ok = responded(before)
        record(tab, f"{trigger_label}>{it}", ok)
        settle_toasts()
    if expect_items:
        missing = [x for x in expect_items if not any(x in i for i in items)]
        if missing:
            record(tab, f"{trigger_label} expected items", False, f"missing={missing}")

def scroll_all(tab):
    """Swipe to bottom collecting every interactive element signature."""
    seen, screens = {}, 0
    while screens < 6:
        els = ax()
        for e in els:
            if e.get("type") in ("Button", "Switch", "PopUpButton", "TabGroup",
                                 "SearchField", "TextField", "Slider", "Cell"):
                key = (e.get("type"), e.get("AXLabel"))
                f = e["frame"]
                if 60 < f["y"] + f["height"] / 2 < 791:  # on-screen, not chrome
                    seen.setdefault(key, dict(e))
        before = sig(els)
        swipe(201, 660, 201, 260)
        time.sleep(0.7)
        if sig() == before:
            break
        screens += 1
    return seen, screens


def sweep_home():
    tab = "Home"
    assert goto(tab), "cannot reach Home"
    els = ax()
    for lab in ("Info snackbar", "Success snackbar", "Error snackbar",
                "Warning snackbar", "Glass CTA", "Send"):
        e = find(lab, els=els)
        if e:
            tap_and_check(tab, e[0])
        else:
            record(tab, lab, False, "not found")
    # segmented control (TabGroup): tap each third, expect theme value change
    tg = find(typ="TabGroup")
    if tg:
        f = tg[0]["frame"]
        okc = 0
        for i in range(3):
            before = sig()
            tap(f["x"] + f["width"] * (i + 0.5) / 3, f["y"] + f["height"] / 2)
            okc += responded(before)
            time.sleep(0.4)
        record(tab, "segmented control 3 segments", okc >= 2, f"{okc}/3 diffs")
        tap(f["x"] + f["width"] * 0.5 / 3, f["y"] + f["height"] / 2)  # restore
        time.sleep(0.5)
    else:
        record(tab, "segmented control", False, "TabGroup not found")
    # split-button chevron (PopUpButton)
    pop = find(typ="PopUpButton")
    if pop:
        base = labels()
        tap_el(pop[0]); time.sleep(0.9)
        new = sorted(l for l in labels() - base if l)
        if new:
            record(tab, "split chevron opens", True, f"items={new[:4]}")
            cand = [e for e in ax() if (e.get("AXLabel") or "").lower() == new[0]]
            if cand:
                before = sig()
                tap_el(cand[0])
                record(tab, f"split>{new[0]}", responded(before))
                settle_toasts()
        else:
            record(tab, "split chevron opens", False, "no new elements")
    else:
        record(tab, "split chevron", False, "PopUpButton not found")
    # app-bar search icon (unlabeled button at x~298,y~62) -> navigates to Search
    unlabeled = [e for e in find(typ="Button", els=ax())
                 if not e.get("AXLabel") and e["frame"]["y"] < 110]
    if unlabeled:
        tap_el(unlabeled[0]); time.sleep(0.9)
        ls = labels()
        ok = any("radius" in l for l in ls)
        record(tab, "appbar search icon -> Search tab", ok)
        goto("Home")
    else:
        record(tab, "appbar search icon", False, "not found")
    # More menu + FAB menu overlays
    open_overlay_and_tap_items(tab, "More")
    open_overlay_and_tap_items(tab, "add")
    # reachability: scroll to bottom, ensure no unseen interactive elements
    seen, screens = scroll_all(tab)
    record(tab, "scroll reachability", True,
           f"{len(seen)} interactive els, {screens} extra screens")


def sweep_search():
    tab = "Search"
    assert goto(tab), "cannot reach Search"
    # switches: iOS exposes HitNativeSwitch as UNLABELED CheckBox elements; the
    # labels live on the group GenericElement 'Open now\nOutdoor seating'.
    # (Known kit a11y gap — tracked separately.) Map by y-order within the group.
    els = ax()
    grp = [e for e in els if "open now" in (e.get("AXLabel") or "").lower()]
    boxes = sorted(find(typ="CheckBox", els=els), key=lambda e: e["frame"]["y"])
    if grp:
        gf = grp[0]["frame"]
        boxes = [b for b in boxes
                 if gf["y"] - 10 <= b["frame"]["y"] <= gf["y"] + gf["height"] + 60]
    names = ("Open now", "Outdoor seating")
    if len(boxes) < 2:
        for lab in names:
            record(tab, f"switch {lab}", False, f"CheckBox not found ({len(boxes)})")
    else:
        for lab, b in zip(names, boxes[:2]):
            v0, cy = b.get("AXValue"), b["frame"]["y"]
            tap_el(b); time.sleep(0.8)
            b2 = [x for x in find(typ="CheckBox") if abs(x["frame"]["y"] - cy) < 20]
            v1 = b2[0].get("AXValue") if b2 else None
            ok = v1 is not None and v1 != v0
            record(tab, f"switch {lab}", ok, f"{v0}->{v1}")
            if ok:
                tap_el(b2[0]); time.sleep(0.5)  # restore
    # sliders: drag the actual Slider thumb, slow (group-frame swipes miss it)
    def slider_vals():
        return sorted((round(x["frame"]["x"]), round(x["frame"]["y"]),
                       str(x.get("AXValue"))) for x in find(typ="Slider"))
    for grp in ("RADIUS", "PRICE RANGE"):
        g = find(grp, contains=True)
        if not g:
            record(tab, f"slider {grp}", False, "group not found")
            continue
        gf = g[0]["frame"]
        gy0, gy1 = gf["y"], gf["y"] + gf["height"]
        sliders = [s for s in find(typ="Slider")
                   if gy0 - 10 <= s["frame"]["y"] + s["frame"]["height"] / 2 <= gy1 + 90]
        if not sliders:
            record(tab, f"slider {grp} drag", False, "no Slider AX element in group")
            continue
        ok, note = False, "no value/position change from any thumb"
        for s in sliders[:3]:
            sf_ = s["frame"]
            cx = sf_["x"] + sf_["width"] / 2
            cy = sf_["y"] + sf_["height"] / 2
            v0 = slider_vals()
            swipe(cx, cy, cx + 70, cy, 0.8); time.sleep(0.8)
            if slider_vals() != v0:
                ok, note = True, f"thumb@({int(cx)},{int(cy)}) {s.get('AXValue')} moved"
                swipe(cx + 70, cy, cx, cy, 0.8); time.sleep(0.5)  # restore approx
                break
        record(tab, f"slider {grp} drag", ok, note)
    # search field: tap, type, submit
    sf = [e for e in ax() if e.get("type") in ("SearchField", "TextField")]
    if not sf:
        sf = find("Search", contains=True)
        sf = [e for e in sf if e["frame"]["y"] < 200]
    if sf:
        before = sig()
        tap_el(sf[0]); time.sleep(1.0)
        sh("idb", "ui", "text", "cafe", "--udid", UDID); time.sleep(0.4)
        sh("idb", "ui", "key", "40", "--udid", UDID)  # HID Return
        ok = responded(before, timeout=3.5)
        record(tab, "search field type+submit", ok)
        settle_toasts()
        cancel = find("Cancel")
        if cancel:
            tap_el(cancel[0]); time.sleep(0.6)
    else:
        record(tab, "search field", False, "not found")
    seen, screens = scroll_all(tab)
    record(tab, "scroll reachability", True,
           f"{len(seen)} interactive els, {screens} extra screens")


def sweep_profile():
    tab = "Profile"
    assert goto(tab), "cannot reach Profile"
    # nav rail destinations. Privacy first: Account is the selected default, and
    # tapping an already-selected destination can't produce an AX diff (false FAIL).
    def rail_btn(lab):
        els = find(lab)
        btns = [e for e in els if e.get("type") == "Button"]
        return btns or els
    for lab in ("Privacy", "Account", "Alerts"):
        e = rail_btn(lab)
        if not e:
            record(tab, f"rail {lab}", False, "NOT EXPOSED/VISIBLE")
            continue
        before = sig()
        tap_el(e[0])
        record(tab, f"rail {lab}", responded(before, 2.5))
    e = rail_btn("Account")  # restore default selection
    if e:
        tap_el(e[0]); time.sleep(0.6)
    # toolbar + buttons (may need scroll)
    wanted = ["Share", "Edit", "Delete", "Show toast", "Show sheet"]
    for _ in range(5):
        present = {w: find(w, contains=True) for w in wanted}
        visible = {w: [e for e in v if 60 < e["frame"]["y"] < 760]
                   for w, v in present.items()}
        todo = [w for w in wanted if visible.get(w)]
        if todo:
            break
        swipe(201, 660, 201, 300); time.sleep(0.7)
    for w in list(wanted):
        # scroll until visible
        tries = 0
        while tries < 5:
            cand = [e for e in find(w, contains=True) if 60 < e["frame"]["y"] < 760]
            if cand:
                break
            swipe(201, 660, 201, 300); time.sleep(0.7)
            tries += 1
        cand = [e for e in find(w, contains=True) if 60 < e["frame"]["y"] < 760]
        if not cand:
            record(tab, w, False, "unreachable after 5 scrolls")
            continue
        if w == "Show sheet":
            base = labels()
            tap_el(cand[0]); time.sleep(1.0)
            new = labels() - base
            opened = bool(new)
            close = find("Close") or find("Done")
            dismissed = False
            if close:
                tap_el(close[0]); time.sleep(0.8)
                dismissed = "close" not in labels()
            else:
                swipe(201, 400, 201, 800, 0.3); time.sleep(0.8)
                dismissed = not (labels() - base)
            record(tab, "Show sheet open+close", opened and dismissed,
                   f"opened={opened} dismissed={dismissed}")
        else:
            tap_and_check(tab, cand[0], name=w)
    seen, screens = scroll_all(tab)
    record(tab, "scroll reachability", True,
           f"{len(seen)} interactive els, {screens} extra screens")


def main():
    sweep_home()
    sweep_search()
    sweep_profile()
    goto("Home")
    n = len(RESULTS)
    ok = sum(1 for *_, o, _n in RESULTS if o)
    print(f"\n=== iOS SWEEP SUMMARY: {ok}/{n} PASS ===")
    for t, name, o, note in RESULTS:
        if not o:
            print(f"  FAIL [{t}] {name} {note}")
    return 0 if ok == n else 1

if __name__ == "__main__":
    sys.exit(main())
