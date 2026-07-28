# Safari fallback smoke

```bash
# one-time: enable Develop menu in Safari → Settings → Advanced
# one-time: safaridriver --enable
# pip3 install selenium

S=.claude/skills/probe-runner/scripts

python3 $S/web_launch.py --browser=safari
python3 $S/web_open.py https://example.com --browser=safari
python3 $S/web_eval.py "document.title" --browser=safari
python3 $S/web_shot.py --browser=safari
```

The script paths returning `unsupported` (network intercept, device
emulation) confirm that Safari mode is the lossy fallback — switch back to
Chrome if you need those features.
