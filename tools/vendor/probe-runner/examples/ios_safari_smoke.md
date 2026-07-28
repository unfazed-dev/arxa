# Mobile Safari on the iOS simulator

```bash
S=.claude/skills/probe-runner/scripts

# 1. boot a sim
python3 $S/ios_boot.py "iPhone 15"

# 2. drive Mobile Safari
python3 $S/ios_safari.py --url https://example.com --eval "document.title" --shot auto
```

Requires `safaridriver --enable` once and `pip3 install selenium`. The
resulting `--shot` PNG lands in `${PROBE_RUNNER_OUTDIR}`.
