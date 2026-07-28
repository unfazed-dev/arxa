# probe-runner iOS smoke test

**Date:** 2026-05-16
**Host:** macOS Darwin 25.4.0, Python 3.13.12 (pyenv)
**Sim:** iPhone 17 (`3340DCE5-FCA3-45E5-B7AA-F2C190840A06`), iOS 26.5
**idb:** `~/.local/bin/idb` (pipx); `idb_companion` via Homebrew
**Skill under test:** `.claude/skills/probe-runner/scripts/ios_*.py` (19 scripts)
**Outdir:** `/tmp/probe-runner/`

## Result matrix

| # | Script | Verbs/args exercised | Verbs untested | Result | Notes |
|---|---|---|---|---|---|
| 1 | `ios_list.py` | (none) | — | PASS | `simctl list devices --json`; 1050 lines |
| 2 | `ios_boot.py` | boot, `--booted` | `--shutdown`, `--erase` | PASS | Boots; `--booted` echoes UDID |
| 3 | `ios_app.py` | `list`, `launch`, `terminate` | `install`, `uninstall` (need .app) | PASS | All exercised verbs work |
| 4 | `ios_url.py` | `https://example.com` | — | PASS | Opens Mobile Safari to URL |
| 5 | `ios_push.py` | `com.apple.mobilesafari payload.json` | — | PASS | `simctl push` accepts |
| 6 | `ios_status_bar.py` | `override --time 9:41 …`, `clear` | — | PASS | Both verbs |
| 7 | `ios_appearance.py` | `dark`, `light` | — | PASS | Both transitions |
| 8 | `ios_privacy.py` | `grant`, `revoke` (location) | `reset` | PASS | Two of three verbs |
| 9 | `ios_location.py` | `37.7749 -122.4194`, `clear` | — | PASS | Set and clear |
| 10 | `ios_shot.py` | (none) | — | PASS | 452 KB PNG written |
| 11 | `ios_record.py` | `--start` / `--stop`, `--seconds 3` | — | PASS | Both flows produce .mp4 |
| 12 | `ios_ui_tree.py` | (none) | — | PASS | `idb ui describe-all`; rc=1 propagates on companion failure |
| 13 | `ios_tap.py` | `200 400` | — | PASS | idb ui tap |
| 14 | `ios_swipe.py` | `200 600 200 200 --duration 0.3` | — | PASS | idb ui swipe |
| 15 | `ios_type.py` | `"smoke"` | — | PASS | idb ui text |
| 16 | `ios_key.py` | `home`, `HOME` | (HW_MAP broken for all hw keys) | **FAIL** | See bug 1 |
| 17 | `ios_log.py` | `--seconds 2` | — | PASS | `simctl spawn log stream`; 29 lines |
| 18 | `ios_files.py` | `push` (real file), `pull`, `push` (negative) | — | **FAIL** | See bug 2 (silent rc=0 on idb errors) |
| 19 | `ios_safari.py` | `--url --eval --shot` | — | PASS | Selenium + safaridriver; PNG + title="Example Domain" |

Score: **17 / 19 functional PASS**, 2 bugs. Two scripts have partial verb coverage
(`ios_boot --shutdown/--erase` and `ios_app install/uninstall` not exercised
because destructive on a working sim).

## Artefacts produced

```
/tmp/probe-runner/
├── ios-20260516-162013-270363.png       # ios_shot
├── ios-20260516-162026-847003.mp4       # ios_record (interrupted run)
├── ios-20260516-162627-421689.mp4       # ios_record --start/--stop
├── ios-20260516-162633-772372.mp4       # ios_record --seconds 3
└── ios-safari-20260516-162603-422641.png # ios_safari --shot auto
```

## Bugs found

### Bug 1 — `ios_key.py` HW_MAP wrong case (FUNCTIONAL)

`HW_MAP` maps friendly names to lowercase strings, but `idb ui button` accepts only:
`{APPLE_PAY, HOME, LOCK, SIDE_BUTTON, SIRI}`. Both invocation paths in the script
are broken:

- **HW_MAP path** (`home` / `lock` / `volup` / `voldown` / `power`): friendly
  name is in HW_MAP, so script calls `idb ui button <mapped>`. Mapped values are
  lowercase or unsupported. Fails: `invalid choice: 'home'`.
- **Fallthrough path** (`HOME` / anything else): not in HW_MAP, so script calls
  `idb ui key HOME` — but `ui key` is a text-character send, not a hardware
  button. Fails with different exit code (2 vs 1).

Current source:
```python
HW_MAP = {
    "home": "home", "lock": "lock",
    "volup": "volumeup", "voldown": "volumedown",
    "power": "power",
}
```

Suggested fix:
```python
HW_MAP = {
    "home": "HOME", "lock": "LOCK",
    "side": "SIDE_BUTTON", "siri": "SIRI",
    "applepay": "APPLE_PAY",
}
```
Drop `volup` / `voldown` / `power` — `idb` exposes no volume/power button for
sims; current entries are dead weight that fail with confusing errors. The
fallthrough `idb ui key <code>` path is only valid for keyboard scancodes, not
hw buttons — document that in the slash-command spec.

### Bug 2 — `ios_files.py` swallows idb errors (FUNCTIONAL)

`ios_files.py push` and `pull` exit with rc=0 even when the underlying `idb
file push`/`pull` operation fails. Examples observed:

- Push: `idb file push /tmp/x com.apple.mobilesafari /tmp/dest` reports
  `Could not copy from … "The file 'x' doesn't exist"` but script exits 0 and
  emits `{"pushed": ..., "to": ...}` as if it succeeded.
- Pull: `idb file pull com.apple.mobilesafari /tmp/x /tmp/local` reports
  `Source path does not exist` but script exits 0.

Root cause: `idb file push/pull` itself exits 0 on operational failures, only
logging the error to stderr. `idb_run(...)` in the skill doesn't grep stderr or
look at idb's `--json` output for an error field. So script trusts the rc.

Also surfaced: `--bundle-id` is deprecated in current idb; idb now wants
`--application` prefix on the path. Probe-runner should switch.

Suggested fix:
1. Run idb with `--json` and parse the response for `"error"` / nonzero status.
2. Or post-check: `idb file list --application <bundle-id> <remote>` to confirm
   the push landed.
3. Migrate from `--bundle-id <bid>` to the new path-prefix form.

### Bug 3 (cosmetic) — `ios_url.py` has no argparse

`python3 ios_url.py --help` raises `CalledProcessError` because `--help` is
passed straight to `simctl openurl booted --help`. Wrap in argparse with a
single positional `url`.

### Note: `ios_ui_tree` does NOT mask errors (corrected)

Earlier draft claimed `ios_ui_tree.py` swallowed idb failures. Verified false:
when run without `| head`, the script exits 1 and writes the companion-connection
error to stderr. The "exit=0" I saw came from `| head -3` (head exits 0
regardless of upstream). Same caveat: `ios_list`, `ios_log`, and the retry of
`ios_ui_tree` were piped through `head` in the matrix and the exit code reflects
`head`, not the python script. All three were re-verified rc=0 without pipes.

## Operational gotcha (skill-level, not a script bug)

When `idb_companion` is left running against a previously-booted sim (different
UDID), every idb-based script (`ios_tap`, `ios_swipe`, `ios_type`, `ios_key`,
`ios_ui_tree`, `ios_files`) fails with:

```
Failed to connect to companion at address DomainSocketAddress(
  path='/tmp/idb/<old-UDID>_companion.sock'): [Errno 61] Connection refused
```

The SKILL.md "Failure modes" section covers "iOS sim not booted" but not "idb
companion bound to non-booted UDID." Suggested remediation:

1. `_common.py::idb_run` could call `idb connect $(simctl booted-udid)` if the
   socket path mismatches the booted UDID.
2. Or document in SKILL.md: "if idb scripts hang/refuse, run
   `pkill -f idb_companion && idb connect $(xcrun simctl list devices booted -j | jq -r ...)`".

I went with (2) for this session — killing stale companions and calling
`idb connect <booted-udid>` once made all idb-based scripts pass.

## Reproduction commands

```bash
S=.claude/skills/probe-runner/scripts

# Boot + idb prep
python3 $S/ios_boot.py "iPhone 17"
BOOTED=$(xcrun simctl list devices booted -j | python3 -c \
  "import sys,json;d=json.load(sys.stdin);print([u['udid'] for v in d['devices'].values() for u in v if u['state']=='Booted'][0])")
pkill -f idb_companion; sleep 1
idb connect $BOOTED

# Sample scripts
python3 $S/ios_shot.py
python3 $S/ios_appearance.py dark
python3 $S/ios_tap.py 200 400
python3 $S/ios_record.py --start
sleep 3
python3 $S/ios_record.py --stop
python3 $S/ios_safari.py --url https://example.com --eval 'document.title' --shot auto
```

## Follow-ups

- [ ] Patch `ios_key.py` HW_MAP — uppercase values, drop volup/voldown/power (bug 1).
- [ ] Patch `ios_files.py` — parse idb `--json` output or use post-check `idb file list`; migrate `--bundle-id` → `--application` path prefix (bug 2).
- [ ] Add argparse to `ios_url.py` (bug 3).
- [ ] Add idb-companion UDID-mismatch failure mode to `SKILL.md` (operational gotcha above).
- [ ] Optionally: `_common.py::idb_run` auto-reconnects on `Connection refused` to the wrong-UDID socket.
- [ ] Cover the destructive verbs not exercised here: `ios_boot --shutdown` / `--erase`, `ios_app install` / `uninstall` (run against a throwaway sim).
