# Chrome CDP smoke

```bash
S=.claude/skills/probe-runner/scripts

# 1. ensure Chrome runs with --remote-debugging-port=9222
python3 $S/web_launch.py

# 2. navigate, screenshot, eval, dom, network capture
python3 $S/web_open.py https://example.com
python3 $S/web_shot.py --full
python3 $S/web_eval.py "document.title"
python3 $S/web_dom.py --selector "h1"

# 3. switch to mobile emulation
python3 $S/web_emu.py --device iPhone-12
python3 $S/web_shot.py --full
python3 $S/web_emu.py --reset

# 4. network for 5s
python3 $S/web_open.py https://httpbin.org/delay/1
python3 $S/web_net.py --seconds 5 --filter httpbin

# 5. accessibility tree
python3 $S/web_a11y.py
```
