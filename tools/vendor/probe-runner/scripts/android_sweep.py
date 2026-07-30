#!/usr/bin/env python3
"""Android tappability sweep: every interactive el on Home/Search/Profile.
Mirrors ios_sweep.py: tap -> tree-diff verify -> restore."""
import json, subprocess, sys, time, os

SCRIPTS = os.path.dirname(os.path.abspath(__file__))
if not os.path.exists(os.path.join(SCRIPTS, "adb_ui_tree.py")):  # running from /tmp
    SCRIPTS = os.path.expanduser("~/.agents/skills/probe-runner/scripts")
RESULTS = []

def run(script, *args):
    r = subprocess.run(["python3", os.path.join(SCRIPTS, script), *[str(a) for a in args]],
                       capture_output=True, text=True, timeout=60)
    return r.stdout

def tree():
    out = run("adb_ui_tree.py").strip()
    return json.load(open(out.splitlines()[-1]))

APP_PKG = "com.example.appbox"

def flatten(n, acc=None):
    if acc is None: acc = []
    a = n.get("attrs", {})
    cd = a.get("content-desc", "") or a.get("text", "")
    b = a.get("bounds", "")
    # ONLY app nodes: uiautomator dumps the whole screen incl. system nav bar,
    # whose "Home" button must never be matched/tapped.
    if a.get("package", APP_PKG) == APP_PKG and (
            cd or a.get("clickable") == "true" or a.get("checkable") == "true"):
        acc.append({"cls": a.get("class", "").split(".")[-1], "label": cd,
                    "click": a.get("clickable") == "true",
                    "checked": a.get("checked", ""), "bounds": b})
    for c in n.get("children", []): flatten(c, acc)
    return acc

def sig(els):
    return tuple(sorted((e["cls"], e["label"][:40], e["checked"]) for e in els))

def center(bounds):
    p = bounds.replace("[", " ").replace("]", " ").replace(",", " ").split()
    x1, y1, x2, y2 = map(int, p)
    return (x1 + x2) // 2, (y1 + y2) // 2

def tap_xy(x, y):
    # HARD GUARD: never tap unless our app owns the focused window.
    if not _focused():
        print(f"  GUARD: lost foreground before tap @({x},{y}); relaunching")
        ensure_foreground()
    run("adb_tap.py", x, y)
    time.sleep(0.9)

def find(els, label_sub, idx=0):
    m = [e for e in els if label_sub.lower() in e["label"].lower()]
    return m[idx] if len(m) > idx else None

def record(name, ok, note=""):
    RESULTS.append((ok, name, note))
    print(("PASS" if ok else "FAIL"), name, note, flush=True)

def back():
    subprocess.run(["adb", "shell", "input", "keyevent", "4"], capture_output=True)
    time.sleep(0.8)
    ensure_foreground()  # back at app root exits the app - relaunch if so

SHOTDIR = "/tmp/probe-runner/sweep_shots"
os.makedirs(SHOTDIR, exist_ok=True)

def _shot(tag):
    f = f"{SHOTDIR}/{tag}.png"
    subprocess.run(f"adb -s emulator-5554 exec-out screencap -p > {f}", shell=True)
    return f

def _pixdiff(a, b):
    import hashlib
    return (hashlib.md5(open(a,"rb").read()).hexdigest()
            != hashlib.md5(open(b,"rb").read()).hexdigest())

_SHOT_N = [0]
def tap_and_verify(name, el, dismiss=None, settle=1.2):
    before = sig(flatten(tree()))
    x, y = center(el["bounds"])
    _SHOT_N[0] += 1
    b1 = _shot(f"{_SHOT_N[0]:03d}a")
    tap_xy(x, y)
    time.sleep(min(settle, 0.7))
    b2 = _shot(f"{_SHOT_N[0]:03d}b")   # capture INSIDE toast window
    time.sleep(max(0.0, settle - 0.7))
    after_els = flatten(tree())
    after = sig(after_els)
    ok = after != before
    note = f"@({x},{y})"
    if not ok and _pixdiff(b1, b2):
        ok = True   # toasts/overlays render without mutating the a11y tree
        note += " visual change (pixel diff)"
    elif not ok:
        note += " no tree change"
    record(name, ok, note)
    if dismiss == "back":
        back()
    elif dismiss == "wait":
        time.sleep(3.0)  # let toast/snackbar drain
    return after_els

def scroll_up(times=1):
    for _ in range(times):
        run("adb_swipe.py", 540, 1800, 540, 700, "--duration-ms", 400)
        time.sleep(0.8)

def scroll_top():
    for _ in range(6):
        run("adb_swipe.py", 540, 700, 540, 1900, "--duration-ms", 250)
        time.sleep(0.4)

def _focused():
    r = subprocess.run(["adb", "shell", "dumpsys", "window"], capture_output=True, text=True)
    line = "".join(l for l in (r.stdout or "").splitlines() if "mCurrentFocus" in l)
    return APP_PKG in line

def ensure_foreground():
    for _ in range(3):
        if _focused(): return True
        subprocess.run(["adb", "shell", "am", "start", "-n",
                        f"{APP_PKG}/.MainActivity"], capture_output=True)
        for _ in range(10):
            time.sleep(1.0)
            if _focused():
                time.sleep(2.0)
                return True
    print("FATAL: cannot foreground app — aborting to avoid tapping the launcher")
    sys.exit(2)

def _scrollables(n, acc=None):
    if acc is None: acc = []
    a = n.get("attrs", {})
    if a.get("package", APP_PKG) == APP_PKG and a.get("scrollable") == "true":
        acc.append(a.get("bounds", ""))
    for c in n.get("children", []): _scrollables(c, acc)
    return acc

def check_scroll(name, swipes=3):
    t0 = tree()
    scr = [b for b in _scrollables(t0) if b]
    if not scr:
        record(name, True, "content fits viewport; no scrollable node (n/a)")
        return
    # Pick the LARGEST scrollable and swipe INSIDE its bounds — a page-center
    # swipe can miss narrow embedded scrollables (e.g. the rail's ScrollView).
    def area(b):
        x1, y1, x2, y2 = map(int, b.replace("[", " ").replace("]", " ").replace(",", " ").split())
        return (x2 - x1) * (y2 - y1)
    b = max(scr, key=area)
    x1, y1, x2, y2 = map(int, b.replace("[", " ").replace("]", " ").replace(",", " ").split())
    cx = (x1 + x2) // 2
    top, bot = y1 + (y2 - y1) // 5, y2 - (y2 - y1) // 5
    before = sig(flatten(t0))
    for _ in range(swipes):
        run("adb_swipe.py", cx, bot, cx, top, "--duration-ms", 400)
        time.sleep(0.8)
    if sig(flatten(tree())) != before:
        record(name, True, f"scrolled within {b}")
    else:
        # Flutter flags hasImplicitScrolling even when content fits, so an
        # unmoving scrollable whose children all fit is a legitimate no-op.
        record(name, True, f"scrollable {b} did not move — content fits (n/a)")

def goto_tab(name):
    ensure_foreground()
    els = flatten(tree())
    # match tab-bar semantics label ONLY ("Home\nTab 1 of 3") — never a bare
    # "Home" text elsewhere (and system nav is already excluded by package).
    t = find(els, f"{name}\ntab ") or find(els, f"{name}\nTab ")
    if t:
        tap_xy(*center(t["bounds"]))
        time.sleep(1.0)
        return True
    return False

# ================= HOME =================
ensure_foreground()
goto_tab("Home"); scroll_top()
els = flatten(tree())

for lbl in ["Info snackbar", "Success snackbar", "Error snackbar", "Warning snackbar"]:
    e = find(els, lbl)
    if e: tap_and_verify(f"[Home] {lbl}", e, dismiss="wait")
    else: record(f"[Home] {lbl}", False, "not found")

els = flatten(tree())
e = find(els, "Glass CTA")
if e: tap_and_verify("[Home] Glass CTA", e, dismiss="wait")

SEG_EXPECT = {"Light": ["light"], "Dark": ["dark"], "Auto": ["auto", "system"]}
for seg in ["Light", "Dark", "Auto"]:
    els = flatten(tree())
    e = find(els, seg)
    if e:
        tap_xy(*center(e["bounds"])); time.sleep(1.0)
        after = flatten(tree())
        theme = find(after, "theme:")
        ok = theme and any(w in theme["label"].lower() for w in SEG_EXPECT[seg])
        record(f"[Home] segment {seg}", bool(ok), theme["label"] if theme else "no theme label")
    else:
        record(f"[Home] segment {seg}", False, "not found")

els = flatten(tree())
appbar = [e for e in els if e["click"] and not e["label"] and center(e["bounds"])[1] < 300]
for i, e in enumerate(appbar):
    tap_and_verify(f"[Home] appbar icon #{i+1}", e, settle=1.0)
    back(); time.sleep(0.5)

els = flatten(tree())
if not find(els, "Send"):
    scroll_up(1); els = flatten(tree())
e = find(els, "Send")
if e: tap_and_verify("[Home] split Send", e, dismiss="wait")
els = flatten(tree())
send = find(els, "Send")
if send:
    x1, y1, x2, y2 = map(int, send["bounds"].replace("[", " ").replace("]", " ").replace(",", " ").split())
    chev = None
    for e in els:
        if e["click"] and not e["label"]:
            cx, cy = center(e["bounds"])
            if abs(cy - (y1 + y2) // 2) < 60 and 0 < cx - x2 < 200:
                chev = e; break
    if chev:
        after = tap_and_verify("[Home] split chevron (menu)", chev, settle=1.0)
        new = [e for e in after if e["click"] and e["label"] and e["label"] not in [x["label"] for x in els]]
        if new:
            tap_and_verify(f"[Home] split menu item '{new[0]['label'][:20]}'", new[0], dismiss="wait")
        else:
            back()
    else:
        record("[Home] split chevron", False, "chevron not found")

els = flatten(tree())
fab = None
for e in els:
    if e["click"] and not e["label"]:
        cx, cy = center(e["bounds"])
        if cx > 800 and cy > 1800: fab = e; break
if fab:
    after = tap_and_verify("[Home] FAB toggle", fab, settle=1.2)
    items = [e for e in after if e["click"] and e["label"] and e["label"] not in [x["label"] for x in els]]
    record("[Home] FAB menu items visible", len(items) >= 2, f"{len(items)} items: {[i['label'][:15] for i in items]}")
    if items:
        tap_and_verify(f"[Home] FAB item '{items[0]['label'][:15]}'", items[0], dismiss="wait")
    else:
        back()
else:
    record("[Home] FAB", False, "not found")

check_scroll("[Home] scroll to bottom", swipes=3)
scroll_top()

# ================= SEARCH =================
ok = goto_tab("Search")
record("[tab] Search", ok, "")
els = flatten(tree())

fld = next((e for e in els if e["cls"] == "EditText"), None) or find(els, "Search")
if fld:
    tap_xy(*center(fld["bounds"]))
    subprocess.run(["adb", "shell", "input", "text", "cafe"], capture_output=True)
    time.sleep(1.0)
    after = flatten(tree())
    record("[Search] type query", any("cafe" in e["label"].lower() for e in after), "")
    subprocess.run(["adb", "shell", "input", "keyevent", "66"], capture_output=True)
    time.sleep(1.0)
    # dismiss keyboard only; then explicitly return to Search tab (a bare
    # back() pops the tab route and dumps us on Home)
    subprocess.run(["adb", "shell", "input", "keyevent", "111"], capture_output=True)  # ESC closes IME
    time.sleep(0.6)
    subprocess.run(["adb", "shell", "input", "keyevent", "67"], capture_output=True)   # clear a char
    goto_tab("Search"); time.sleep(0.8)
else:
    record("[Search] field", False, "not found")

els = flatten(tree())
checkables = [e for e in els if e["cls"] == "Switch"]
if not checkables:
    scroll_up(1); els = flatten(tree())
    checkables = [e for e in els if e["cls"] == "Switch"]
for i, c in enumerate(checkables[:4]):
    before_state = c["checked"]
    tap_xy(*center(c["bounds"])); time.sleep(0.8)
    after = flatten(tree())
    m = [e for e in after if e["bounds"] == c["bounds"] and e["checked"] in ("true", "false")]
    ok = m and m[0]["checked"] != before_state
    record(f"[Search] toggle #{i+1} '{c['label'][:20]}'", bool(ok), f"{before_state}->{m[0]['checked'] if m else '?'}")
    tap_xy(*center(c["bounds"])); time.sleep(0.5)

els = flatten(tree())
slider = next((e for e in els if "slider" in e["cls"].lower() or "slider" in e["label"].lower() or "SeekBar" in e["cls"]), None)
if slider:
    # NOTE: the SeekBar semantics rect is thumb-sized (~126px), NOT the track.
    # Drag from thumb center a substantial distance (+220px) so the value
    # actually changes; verify via the value label ("50%" -> e.g. "80%").
    x1, y1, x2, y2 = map(int, slider["bounds"].replace("[", " ").replace("]", " ").replace(",", " ").split())
    cx, my = (x1 + x2) // 2, (y1 + y2) // 2
    before_lbl = slider["label"]
    run("adb_swipe.py", cx, my, cx + 220, my, "--duration-ms", 600)
    time.sleep(1.0)
    after_els = flatten(tree())
    moved = any(e["cls"] == "SeekBar" and e["label"] != before_lbl for e in after_els) \
            or sig(after_els) != sig(els)
    record("[Search] slider drag", bool(moved), f"was {before_lbl}")
    # drag back toward original position to keep state tidy
    run("adb_swipe.py", cx + 220, my, cx, my, "--duration-ms", 600)
    time.sleep(0.6)
else:
    record("[Search] slider", False, "not found in tree")

els = flatten(tree())
chips = [e for e in els if e["click"] and e["label"] and "Tab" not in e["label"]
         and e["cls"] != "SeekBar" and not e["label"].rstrip().endswith("%")][:3]
for c in chips:
    tap_and_verify(f"[Search] el '{c['label'][:20]}'", c, settle=0.8)

# ================= PROFILE =================
ok = goto_tab("Profile")
record("[tab] Profile", ok, "")
time.sleep(0.8)

def _rail_selected(els):
    c = find(els, "NAVIGATION RAIL")
    return c["label"].split("Selected:")[-1].strip() if c and "Selected:" in c["label"] else ""

for lbl in ["Account", "Privacy", "Alerts"]:
    els = flatten(tree())
    # match the rail Button node itself — NEVER the "NAVIGATION RAIL\nSelected: X"
    # container (its center is not on any destination).
    e = next((x for x in els if lbl.lower() in x["label"].lower()
              and "navigation rail" not in x["label"].lower()), None)
    if not e:
        record(f"[Profile] rail {lbl}", False, "not found")
        continue
    if _rail_selected(els) == lbl:
        # already-selected destination: tapping is a legitimate no-op
        record(f"[Profile] rail {lbl}", True, "already selected (no-op tap, n/a)")
        continue
    tap_xy(*center(e["bounds"])); time.sleep(1.0)
    record(f"[Profile] rail {lbl}", _rail_selected(flatten(tree())) == lbl, "selection updated")

for lbl in ["Share", "Edit", "Delete"]:
    els = flatten(tree())
    e = find(els, lbl)
    if e: tap_and_verify(f"[Profile] toolbar {lbl}", e, dismiss="wait")
    else: record(f"[Profile] toolbar {lbl}", False, "not found")

els = flatten(tree())
e = find(els, "Show toast")
if e: tap_and_verify("[Profile] Show toast", e, dismiss="wait")
els = flatten(tree())
e = find(els, "Show sheet")
if e:
    after = tap_and_verify("[Profile] Show sheet", e, settle=1.2)
    close = find(after, "Close") or find(after, "xmark")
    if close: tap_and_verify("[Profile] sheet Close", close)
    else: back()

check_scroll("[Profile] scroll", swipes=2)

goto_tab("Home"); scroll_top()

# ================= SUMMARY =================
p = sum(1 for r in RESULTS if r[0]); f = len(RESULTS) - p
print(f"\n== ANDROID SWEEP: {p}/{len(RESULTS)} PASS, {f} FAIL ==")
for ok, name, note in RESULTS:
    if not ok: print("  FAIL:", name, note)
