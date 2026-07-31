#!/usr/bin/env python3
"""Shadow-DOM SPLIT test (the one high-value arch absent on awwwards → known reference).
Hypothesis: web_skeleton (DOMSnapshot.captureSnapshot — pierces OPEN shadow roots at CDP
level) captures shadow content, but web_tokens (document.querySelectorAll('*') — light DOM
only) MISSES it. Same page, measured three ways to avoid cross-pipeline confusion:
  light = querySelectorAll('*')                 (what web_tokens samples)
  deep  = recursive shadowRoot-descending walk  (true element count incl. shadow)
  raw   = DOMSnapshot nodes                      (what web_skeleton's parse sees)
deep >> light AND raw ~ deep  => skeleton pierces shadow, tokens is blind => SPLIT proven."""
import json, os, sys, time, subprocess, urllib.request
from types import SimpleNamespace
from pathlib import Path
SCRIPTS = os.environ.get("PROBE_RUNNER_SCRIPTS", str(Path(__file__).resolve().parents[2] / "scripts"))
sys.path.insert(0, SCRIPTS)
OUT = Path(__file__).resolve().parent / "out"; OUT.mkdir(exist_ok=True)
URL = "https://shoelace.style/"
PORT = 9334
for _ in range(60):
    try:
        urllib.request.urlopen("http://127.0.0.1:%d/json/version" % PORT, timeout=1).read(); break
    except Exception:
        time.sleep(0.5)
from _web_eval import resolve_web_eval, navigate
import web_skeleton as ws

args = SimpleNamespace(browser="chrome", url=URL, android=False, ios=False, cdp_port=PORT, serial=None)
engine, ev, dev = resolve_web_eval(args)


def rt(expr):
    try:
        r = ev.sess.send("Runtime.evaluate", {"expression": expr, "returnByValue": True, "awaitPromise": False})
        return None if "exceptionDetails" in r else r.get("result", {}).get("value")
    except Exception:
        return None


navigate(ev, engine, URL)
prev, stable, t0 = -1, 0, time.time()
while time.time() - t0 < 12:
    n = rt("document.querySelectorAll('*').length") or 0
    if n == prev and n > 10:
        stable += 1
        if stable >= 3:
            break
    else:
        stable = 0
    prev = n
    time.sleep(0.5)
time.sleep(1.0)

light = rt("document.querySelectorAll('*').length")
deep = rt(r"""(function(){var n=0;function walk(r){var e=r.querySelectorAll('*');n+=e.length;
  for(var i=0;i<e.length;i++){if(e[i].shadowRoot)walk(e[i].shadowRoot);}}walk(document);return n;})();""")
hosts = rt("[].slice.call(document.querySelectorAll('*')).filter(function(e){return !!e.shadowRoot;}).length")
host_kinds = rt(r"""(function(){var k={};[].slice.call(document.querySelectorAll('*')).forEach(function(e){if(e.shadowRoot)k[e.tagName.toLowerCase()]=1;});return Object.keys(k).slice(0,12);})();""")

# raw DOMSnapshot (web_skeleton path) — pierces open roots
ev.sess.send("DOMSnapshot.enable", {})
snap = ev.sess.send("DOMSnapshot.captureSnapshot",
                    {"computedStyles": ws.WANT_STYLES, "includeDOMRects": True, "includePaintOrder": True})
docs = snap.get("documents", [])
raw = sum(len(d["nodes"]["nodeName"]) for d in docs)

# real verbs (fresh-nav, same Chrome)
def run(name, extra):
    try:
        r = subprocess.run([sys.executable, name + ".py", "--browser", "chrome", "--cdp-port", str(PORT),
                            "--url", URL] + extra, cwd=SCRIPTS, capture_output=True, text=True, timeout=90)
        return r.returncode
    except Exception as e:
        return "err:" + str(e)[:80]

skf = str(OUT / "shoelace_sk.json"); tokf = str(OUT / "shoelace_tok.json")
rc_sk = run("web_skeleton", ["--out", skf])
rc_tok = run("web_tokens", ["--out", tokf])
sk_nodes = tok_pal = tok_type = None
try:
    sk_nodes = len(json.loads(Path(skf).read_text()).get("nodes", []))
except Exception:
    pass
try:
    tj = json.loads(Path(tokf).read_text())
    tok_pal = len(tj.get("palette", tj.get("colors", []) if isinstance(tj.get("colors", []), list) else []))
    tok_type = len(tj.get("type_scale", tj.get("font_sizes", []) or []))
except Exception:
    pass

res = dict(url=URL, light=light, deep=deep, shadow_hosts=hosts, host_kinds=host_kinds, raw_domsnapshot=raw,
           verb_skeleton_nodes=sk_nodes, rc_sk=rc_sk, rc_tok=rc_tok, tok_palette=tok_pal, tok_type=tok_type)
Path(OUT / "shadow_ref.json").write_text(json.dumps(res, default=str, indent=2))

shadow_hidden = (deep or 0) - (light or 0)
print("SHADOW-DOM SPLIT TEST — %s" % URL)
print("  shadow_hosts=%s kinds=%s" % (hosts, host_kinds))
print("  light (querySelectorAll, =web_tokens scope) = %s" % light)
print("  deep  (shadow-descending walk, true count)   = %s   (shadow-hidden = %s)" % (deep, shadow_hidden))
print("  raw   (DOMSnapshot, =web_skeleton scope)      = %s" % raw)
print("  VERB web_skeleton nodes=%s (rc=%s) | web_tokens rc=%s palette=%s type=%s" % (
    sk_nodes, rc_sk, rc_tok, tok_pal, tok_type))
verdict = ("SPLIT CONFIRMED: skeleton/DOMSnapshot pierces shadow (raw~deep), tokens light-only is blind"
           if (deep and light and deep > light * 1.2 and raw and raw > light * 1.2)
           else "INCONCLUSIVE: shadow not heavy on this page (host count low) — note + pick richer ref")
print("  >>> %s" % verdict)
ev.close()
