#!/usr/bin/env python3
"""DE-RISK harness (NOT a pytest; manual, headless, ~10s). Mechanism gate for the
"broader form-state family" rung: does CDP CSS.forcePseudoState actually APPLY the
validity/attribute-derived pseudo-classes (:invalid/:valid/:required/:read-only/
:placeholder-shown) so a FORM_PROPS computed-style delta appears? :checked/:disabled
already work; the validity set is derived from validity/attribute state, not freely
toggled like :hover/:focus, so support is NOT guaranteed. Falsify before any build.

Run: python3 scripts/derisk_form_state_validity.py   (needs Chrome + websocket-client)
"""
from __future__ import annotations
import json
import subprocess
import sys
import tempfile
import time
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _web import chrome_binary, CDPSession  # noqa: E402

# One DEDICATED input per candidate, each crafted so its BASE state does NOT already match the
# target pseudo (else force can't move a prop that already matches — the v1 confound). Each rule
# styles ONE distinct prop; a successful force flips that prop from base.
#   id          base-not-matching-because        styled prop / sentinel
#   #invalid    valid value, not required        background-color rgb(255,0,0)
#   #valid      required+empty -> :invalid        background-color rgb(0,255,0)
#   #required   no required attr                  color rgb(0,0,255)
#   #readonly   read-write (no readonly attr)      opacity 0.25
#   #placeholder has value -> not placeholder-shown border-top-color rgb(200,100,50)
CANDIDATES = [
    ("invalid", "#invalid", "background-color", "rgb(255, 0, 0)"),
    ("valid", "#valid", "background-color", "rgb(0, 255, 0)"),
    ("required", "#required", "color", "rgb(0, 0, 255)"),
    ("read-only", "#readonly", "opacity", "0.25"),
    ("placeholder-shown", "#placeholder", "border-top-color", "rgb(200, 100, 50)"),
]
# REALISTIC inputs (r_*): each carries the attribute/validity state a REAL form ships, so the pseudo
# matches at BASE. This is the validate-real-artifact pass — the capability fixture above is a PROXY
# (base deliberately non-matching); a real input has the state baked in, and forcePseudoState forces
# ON only (never OFF, never suppresses the natural match). Expect: force-on-natural-match = NO-OP
# (delta already in the base skeleton), and forcing the opposite = a physically-impossible chimera.
REALISTIC = [
    ("required", "#r_req", "color", "rgb(0, 0, 255)"),            # has required attr
    ("read-only", "#r_ro", "opacity", "0.25"),                   # has readonly attr
    ("placeholder-shown", "#r_ph", "border-top-color", "rgb(200, 100, 50)"),  # empty + placeholder
    ("valid", "#r_val", "background-color", "rgb(0, 255, 0)"),    # has valid value
]
FIXTURE = """<!doctype html><meta charset=utf-8><title>fs</title><style>
  input { color: rgb(10,10,10); background-color: rgb(20,20,20); opacity: 1;
          border-top-color: rgb(30,30,30); }
  #invalid:invalid               { background-color: rgb(255,0,0); }
  #valid:valid                   { background-color: rgb(0,255,0); }
  #required:required             { color: rgb(0,0,255); }
  #readonly:read-only            { opacity: 0.25; }
  #placeholder:placeholder-shown { border-top-color: rgb(200,100,50); }
  #r_req:required                { color: rgb(0,0,255); }
  #r_ro:read-only                { opacity: 0.25; }
  #r_ph:placeholder-shown        { border-top-color: rgb(200,100,50); }
  #r_val:valid                   { background-color: rgb(0,255,0); }
  #r_val:invalid                 { background-color: rgb(255,0,0); }
</style>
<input id=invalid value="ok">
<input id=valid required value="">
<input id=required>
<input id=readonly>
<input id=placeholder value="hasval" placeholder="ph">
<input id=r_req required>
<input id=r_ro readonly value="x">
<input id=r_ph placeholder="ph">
<input id=r_val value="ok">"""
PROPS = ["color", "background-color", "opacity", "border-top-color"]


def _launch(udd: str, fixture_url: str):
    bin_ = chrome_binary()
    if not bin_:
        print("FATAL no-chrome-binary"); sys.exit(2)
    p = subprocess.Popen(
        [bin_, "--headless=new", "--remote-debugging-port=0", "--remote-allow-origins=*",
         "--no-first-run", "--no-default-browser-check", f"--user-data-dir={udd}", fixture_url],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    portfile = Path(udd) / "DevToolsActivePort"
    for _ in range(100):
        if portfile.exists():
            txt = portfile.read_text().splitlines()
            if txt:
                return p, int(txt[0])
        time.sleep(0.1)
    p.terminate(); print("FATAL no-DevToolsActivePort"); sys.exit(2)


def _computed(sess, node_id):
    recs = sess.send("CSS.getComputedStyleForNode", {"nodeId": node_id})["computedStyle"]
    m = {r["name"]: r["value"] for r in recs}
    return {p: m.get(p) for p in PROPS}


def main():
    with tempfile.TemporaryDirectory() as udd, tempfile.NamedTemporaryFile(
            "w", suffix=".html", delete=False) as fx:
        fx.write(FIXTURE); fx.flush()
        fixture_url = "file://" + fx.name
        proc, port = _launch(udd, fixture_url)
        try:
            ws = None
            for _ in range(50):
                try:
                    with urllib.request.urlopen(f"http://127.0.0.1:{port}/json", timeout=2) as r:
                        tgts = [t for t in json.loads(r.read()) if t.get("type") == "page"]
                    if tgts and tgts[0].get("webSocketDebuggerUrl"):
                        ws = tgts[0]["webSocketDebuggerUrl"]; break
                except Exception:
                    pass
                time.sleep(0.1)
            if not ws:
                print("FATAL no-page-target"); return
            sess = CDPSession(ws, timeout=10.0)
            try:
                sess.send("DOM.enable", {}); sess.send("CSS.enable", {})
                time.sleep(0.3)
                root = sess.send("DOM.getDocument", {"depth": -1})["root"]["nodeId"]
                results = {}
                for pseudo, sel, prop, want in CANDIDATES:
                    nid = sess.send("DOM.querySelector",
                                    {"nodeId": root, "selector": sel})["nodeId"]
                    base = _computed(sess, nid)
                    sess.send("CSS.forcePseudoState",
                              {"nodeId": nid, "forcedPseudoClasses": [pseudo]})
                    time.sleep(0.2)
                    cur = _computed(sess, nid)
                    sess.send("CSS.forcePseudoState",
                              {"nodeId": nid, "forcedPseudoClasses": []})
                    delta = {p: (base[p], cur[p]) for p in PROPS if base[p] != cur[p]}
                    # APPLIES only if base did NOT already match (clean) AND force produced the
                    # sentinel value on the styled prop.
                    base_clean = base[prop] != want
                    hit = cur[prop] == want
                    verdict = "APPLIES" if (base_clean and hit) else (
                        "BASE-DIRTY" if not base_clean else "NO-OP")
                    results[pseudo] = verdict
                    print(f"{pseudo:18s} {verdict:10s} base[{prop}]={base[prop]!r} "
                          f"-> forced={cur[prop]!r} (want {want!r}) all_delta={json.dumps(delta)}")
                applied = [k for k, v in results.items() if v == "APPLIES"]
                print("\nCAPABILITY-SUMMARY (proxy fixture) applies=", applied,
                      " other=", {k: v for k, v in results.items() if v != "APPLIES"})

                # --- REALISTIC regime (validate-real-artifact): inputs carry the real state at BASE.
                print("\n--- REALISTIC regime: force the pseudo on an input that ALREADY matches it"
                      " (real form) ---")
                noop = []
                for pseudo, sel, prop, _want in REALISTIC:
                    nid = sess.send("DOM.querySelector",
                                    {"nodeId": root, "selector": sel})["nodeId"]
                    base = _computed(sess, nid)
                    sess.send("CSS.forcePseudoState",
                              {"nodeId": nid, "forcedPseudoClasses": [pseudo]})
                    time.sleep(0.2)
                    cur = _computed(sess, nid)
                    sess.send("CSS.forcePseudoState",
                              {"nodeId": nid, "forcedPseudoClasses": []})
                    delta = {p: (base[p], cur[p]) for p in PROPS if base[p] != cur[p]}
                    is_noop = not delta
                    if is_noop:
                        noop.append(pseudo)
                    print(f"  {pseudo:18s} base[{prop}]={base[prop]!r} "
                          f"{'NO-OP (already matches at base -> nothing to capture)' if is_noop else 'delta='+json.dumps(delta)}")
                # chimera: force :invalid on the naturally-:valid input -> matches BOTH (impossible state)
                nid = sess.send("DOM.querySelector",
                                {"nodeId": root, "selector": "#r_val"})["nodeId"]
                vbase = _computed(sess, nid)["background-color"]
                sess.send("CSS.forcePseudoState",
                          {"nodeId": nid, "forcedPseudoClasses": ["invalid"]})
                time.sleep(0.2)
                vforced = _computed(sess, nid)["background-color"]
                sess.send("CSS.forcePseudoState", {"nodeId": nid, "forcedPseudoClasses": []})
                print(f"  CHIMERA  naturally-:valid input forced :invalid -> bg {vbase!r} -> {vforced!r}"
                      f"  (input now matches :valid AND :invalid simultaneously — physically impossible)")
                print("\nREALISTIC-SUMMARY: force-on-natural-match no-ops =", noop,
                      "\n  => the validity family is STATIC/already-at-base (required/read-only/valid)"
                      " or needs-OFF-which-force-cannot-do (placeholder-shown); no clean dynamic delta"
                      " like :checked/:disabled. Capability != real capture path.")
            finally:
                sess.close()
        finally:
            proc.terminate()
            try:
                proc.wait(timeout=5)
            except Exception:
                proc.kill()


if __name__ == "__main__":
    main()
