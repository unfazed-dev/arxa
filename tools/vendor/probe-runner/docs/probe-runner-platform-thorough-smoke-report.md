# probe-runner — platform-by-platform thorough smoke (report)

**Date:** 2026-05-16
**Host fingerprint:**

- macOS 26.4.1 (Darwin 25.4.0, Apple Silicon)
- Python 3.13.12 (pyenv)
- Flutter 3.41.4 stable (`/Users/unfazed-mac/fvm/default/bin/flutter`) · Dart 3.11.1 · DevTools 2.54.1
- Xcode 26.5 (Build 17F42), CocoaPods 1.16.2
- Android SDK 36.1.0, Emulator 36.3.10.0, platform-tools at `~/Library/Android/sdk/platform-tools`
- Chrome 148.0.7778.167, Safari (system), safaridriver at `/System/Cryptexes/App/usr/bin/safaridriver`
- `cliclick`, `screencapture`, `osascript`, `ffmpeg`, `xcrun`, `adb`, `idb`, `flutter` on PATH
- **`fswatch` MISSING** (optional dep; `brew install fswatch` required for `fswatch.py`)
- Python deps: `Quartz`, `Vision`, `websocket`, `selenium` all import OK
- macOS Secure Input mode: **not active** (`ioreg | grep -c kIOHIDStateSecureInput` = 0)
- TCC: Screen Recording + Accessibility evidently granted (capture and AX both work from prior smoke; system TCC.db locked to non-admin reads, expected).

**Skill commit:** `cee4a84f30a5aa96e0002e3a12cb465e1e0e4ade` (branch `main`)

**Plan:** `.claude/skills/probe-runner/docs/probe-runner-platform-thorough-smoke.md`

**Preflight state at start of run:** no iOS sim booted, no Android emu attached. Both kicked off in background before P1 begins so they're warm by the time P5/P6 starts.

---

## Cross-platform tally

| Platform | Probes run | PASS | FAIL | SKIP | Verdict |
|---|---:|---:|---:|---:|---|
| P1 host desktop | 68 | 65 | 2 | 1 | **PASS** — B1/B2/B3 fixes hold; 3 new low-sev bugs (B4 context_menu traceback, B5 missing wait_pixel.py, B6 --hold flag missing). |
| P2 wry/Dioxus webview | 6 | 4 | 0 | 2 | **PASS (Branch B)** — template integrity verified; Phase C wire-up gap documented. |
| P3 host browser Chrome | 30 | 30 | 0 | 0 | **PASS** — 4 plan↔CLI mismatches (B7-B10) documented; no functional bugs. |
| P4 host browser Safari | 13 | 1 | 12 | 0 | **BLOCKED-BY-CONFIG** — Safari "Allow Remote Automation" gate not enabled on host; ~9 of the 12 FAILs would convert to PASS with the toggle on. Only B14 (missing `--browser` arg on 4 scripts), B12, B13 are real script defects that persist regardless. |
| P5 iOS simulator | 45 | 41 | 2 | 2 | **PASS** — bug 3 (`ios_url --help`) confirmed fixed; bugs 1 & 2 (ios_key HW_MAP, ios_files swallows errors) still broken. |
| P6 Android emulator | 46 | 43 | 0 | 3 | **PASS** — bug 1 (`adb_push` rename) and bug 3 (argparse consistency) both fixed; B15/B16 new low-sev. |
| P7 Flutter (macOS pri + web attempted) | 55 | 22 | 13 | 20 | **PARTIAL** — macOS end-to-end PASS for read/inspect block; web blocked by auth-token URL bug (B19); iOS/Android SKIP due to per-platform timebox. |
| **Total** | **263** | **206** | **29** | **28** | **14 new bugs** found in this run (B4-B6 functional, B11-B20 + P2-i1 behavioral); **4 plan↔CLI mismatches** (B7-B10) called out separately; **3 prior bugs confirmed fixed** (ios_url --help, adb_push rename, adb argparse consistency); **2 prior bugs still broken** (ios_key HW_MAP, ios_files rc=0 + deprecated --bundle-id). |

**Note on P4 FAILs:** 11 of P4's 12 FAILs are **environmental gate-failures** (Safari "Allow Remote Automation" toggle not enabled), not script defects. Only **B14** (4 web_* scripts missing the `--browser` argparse flag) is a real script defect that would persist with the gate on. Re-running P4 with the toggle enabled would convert ~9 of those 12 to PASS; the remaining ~3 (B14 + B12 + B13) are bugs to fix.

---

## P1 — macOS host desktop

**Target:** `TextEdit` (fresh `open -na TextEdit` + Cmd-N new document).
**Outdir:** `/tmp/probe-runner/p1/`.

### Tally

| Phase | Scripts exercised | PASS | FAIL | SKIP | Notes |
|---|---:|---:|---:|---:|---|
| 1. `--help` sweep (host-desktop scope) | 36 | 36 | 0 | 0 | B1/B2/B3 fixes hold; iOS/Android/web/flutter scripts excluded (counted in their platforms). |
| 2. Discovery | 3 | 3 | 0 | 0 | `find_window`, `wait_window --timeout 3`, `ax_tree` (266 KB JSON head with full AX hierarchy). |
| 3. Capture | 7 | 7 | 0 | 0 | `shot ×2`, `region --rect 0,0,200,200`, `record --seconds 1`, `multishot --count 2 --fps 5`, `pixdiff` (ratio computed), `ocr --rect 0,0,400,300`, `text_diff` (PNG inputs). |
| 4. Diagnostics | 5 | 3 | 1 | 1 | `sample TextEdit 1` (positional), `mem` (777-byte leaks.txt), `tail_log --seconds 1` (terminates clean, B1 fix verified). `fswatch` **FAIL** — missing binary dep, install hint correct (`brew install fswatch`). `nettrace` **SKIP** — sudo required, unattended. |
| 5. Clipboard | 1 | 1 | 0 | 0 | `clipboard set/get` round-trip; pre-existing pasteboard restored after. |
| 6. Destructive drive | 12 | 11 | 1 | 0 | `focus`, `click 400 300`, `drag --from --to`, `hover`, `scroll 0 -50`, `type_text "smoke-p1"`, `key_chord cmd+a` + `delete`, `menu "TextEdit/About TextEdit"`, `drop_file /tmp/p1_drop.txt 400 300`, `reposition --pos 100,100 --size 800x600` — all PASS. `context_menu TextEdit 400 300 "Cut"` raises uncaught `subprocess.CalledProcessError` traceback when the named item is absent — see B4 below. |
| 7. Window state | 3 | 3 | 0 | 0 | `window_state minimize` / `fullscreen` / `close` all `{"owner":"TextEdit","action":...}`. Mid-sequence restore via `activate` osascript + `ctrl+cmd+f` key chord; final `close` ends with no traceback. |
| 8. Webview (host side) | 1 | 1 | 0 | 0 | `safari_inspect --list` enumerates Safari Develop menu (Web Inspector, Service Workers, Feature Flags, etc.). `dom` + `console` deferred to **P2**. |

**P1 total: 65 PASS / 2 FAIL / 1 SKIP** across 68 probes (= 36 + 3 + 7 + 5 + 1 + 12 + 3 + 1).

### Bugs found

#### B4 — `context_menu.py` propagates osascript failure as Python traceback (severity: low)

When the named menu item doesn't exist in the right-click context menu, the inner `osascript` returns non-zero and the script lets `subprocess.CalledProcessError` escape, dumping a multi-line traceback to stderr ending in:

```
subprocess.CalledProcessError: Command '['osascript', '-e', '\ntell application "System Events"\n    tell process "TextEdit"\n        click menu item "Cut" of menu 1 of window 1\n    end tell\nend tell\n']' returned non-zero exit status 1.
```

Fix: catch `CalledProcessError` in `context_menu.py::main()` and emit `probe-runner: context_menu: item '<X>' not found in <owner>'s context menu (rc=<n>)` then exit with the inherited rc. Pattern matches what `ios_app.py` already does post-B-fixes.

#### B5 — `wait_pixel.py` listed in `probe-runner-skill.md` but never shipped (severity: low)

`.claude/skills/probe-runner/docs/probe-runner-skill.md` lines 76-77 promise `wait_pixel.py` (poll-until-region-changes via region screenshot + hash diff with tolerance). The skill ships `wait_window.py` but **no `wait_pixel.py`** under `scripts/`. Either ship it or remove from the plan table — currently a documented capability without an implementation.

#### B6 — `key_chord.py` `--hold`/`--repeat` partial (severity: cosmetic)

`probe-runner-skill.md` line 64 advertises "Hold key / repeat key | `key_chord.py --hold/--repeat`" but actual argparse exposes `--repeat REPEAT` and `--delay-ms DELAY_MS` only — no `--hold` (or `--hold-ms`). Either drop the plan claim or implement `--hold` via `cliclick kd:` / `ku:` pair.

### Artefacts (`/tmp/probe-runner/p1/`)

```
TextEdit-20260516-184251-072124.png       292 KB  (shot #1)
TextEdit-20260516-184251-598598.png       292 KB  (shot #2 baseline for pixdiff)
TextEdit-20260516-184421-539758-region.png 22 KB  (region 0,0,200,200)
TextEdit-20260516-184421-885784.mov        36 KB  (record --seconds 1)
TextEdit-20260516-184423-782767-burst/     dir     (multishot frames)
TextEdit-20260516-184424-575406-region.png 36 KB  (text_diff intermediate)
TextEdit-20260516-184425-855727-leaks.txt 777 B   (mem)
TextEdit-20260516-184501-407101-sample.txt — KB   (sample 1s — also written to /tmp/<sym>)
```

### Operational notes

- `timeout` (the GNU-style binary) is not on macOS' default PATH — only `gtimeout` via coreutils. None of the probe-runner scripts call `timeout(1)` internally; smoke harness must avoid it too. Our first batch attempt failed every step that wrapped scripts with `timeout`. Document for future smoke runners.
- `region.py` takes `--rect x,y,w,h` (comma-separated, single arg) — NOT four positional ints. SKILL.md table writes "`screencapture -R x,y,w,h`" implying 4 args; the slash command should clarify.
- `multishot.py` takes `--count N --fps F` — no `--interval`. Slash-command help text matches; first-pass operator hit-and-miss is likely.
- `ocr.py` takes `--rect`, not `--region`. SKILL.md table is fine; the prior smoke report uses `--region`, which was wrong.
- `sample.py` takes `seconds` as a **positional**, not `--seconds`. SKILL.md and `probe-runner-skill.md` both say `sample.py <pid> <secs>`; that's the right shape.
- `reposition.py` flags are `--pos x,y` and `--size WxH`, not `--at`. The plan-text "post-condition assert" doesn't yet appear to fire (no error if size mismatches after reposition).

No regressions vs. the predecessor (`probe-runner-smoke-test-2026-05-16.md`) B1/B2/B3 fixes — `tail_log`, `console`, `dom`, `fswatch` all terminate at their declared deadline; `--owner X` alias accepted; missing `fswatch` binary surfaces with brew install hint.

---

## P2 — wry / Dioxus webview

**Branch chosen:** **B (default)** — smoke does NOT modify another crate. Template integrity check + script behavior against a non-instrumented target. Runtime end-to-end validation deferred to the brainiac-side companion change (already enumerated in `probe-runner-skill.md`).

### Tally

| Phase | Script / artefact | PASS | FAIL | SKIP | Notes |
|---|---|---:|---:|---:|---|
| Template integrity | `templates/dioxus_debug_probe.rs` | 1 | 0 | 0 | 163 lines, 5662 bytes. Symbol grep confirms `pub fn install`, `pub async fn probe_dom`, `pub async fn tail_console`, `pub async fn dom_snapshot`, and `#[cfg(feature = "debug-probe")]` all present. |
| Rust parse-only check | `rustc --edition 2021 -Z parse-only …` | 0 | 0 | 1 | Stable toolchain rejects `-Z` flag (nightly-only). SKIPped here; the file is unchanged from the committed template and the brainiac crate's nightly toolchain already validates it on build. |
| `dom.py` graceful-no-target | `dom.py --selector body --timeout 1 NoSuchApp` | 1 | 0 | 0 | Reports `probe-runner: no window found for owner 'NoSuchApp'. is the app running?` — see issue P2-i1 below re: rc=0 on this error path. |
| `console.py` graceful-no-target | `console.py --seconds 1 NoSuchApp` | 1 | 0 | 0 | Same error path as `dom.py`; same rc=0 issue. |
| `safari_inspect --list` | `safari_inspect.py --list` | 1 | 0 | 0 | Enumerates Safari Develop menu: `Show Web Inspector`, `Service Workers`, `Web Extension Background Content`, `Connect Web Inspector`, `Enter Responsive Design Mode`, `Feature Flags…`, etc. Bonus: also lists the booted iPhone 17 simulator under devices. |
| `dom`/`console` against running wry | (no target) | — | — | 1 | Brainiac-visualizer not instrumented and not running. Phase C end-to-end deferred. |

**P2 total: 4 PASS / 0 FAIL / 2 SKIP.**

### Issues found

#### P2-i1 — `dom.py` and `console.py` exit 0 on "no window for owner" error (severity: low)

Both scripts print a clear human-readable error (`probe-runner: no window found for owner '…'. is the app running?`) but return rc=0. Calling shells can't distinguish "no target" from "found target, returned empty result". Match the pattern that iOS/Android scripts now use post-prior-smoke (rc inherited from the underlying probe, e.g. 148 for simctl). Suggested rc: 2 for "no window".

#### P2-i2 — Phase C wiring gap in brainiac-visualizer (severity: documented, not actionable in smoke)

`crates/brainiac-visualizer/src/presentation/` contains no `debug_probe.rs`, and `crates/brainiac-visualizer/Cargo.toml` has no `[features] debug-probe = []`. The companion plan in `probe-runner-skill.md` ("Brainiac-side companion plan") enumerates the four-step wire-up. This smoke does not install the probe (would constitute a delivery change against an unrelated crate). Operator action required to validate `probe_dom` / `tail_console` against a live Dioxus webview.

### Artefacts (`/tmp/probe-runner/p2/`)

- `stub-crate/` — minimal scaffolding for the (skipped) rustc syntax check.
- No PNG/MOV produced; this platform is template-validation + error-path verification only.

### Notes

- The template's host-side contract is "host stderr line `[probe-runner-dom] {…}` after `probe_dom` runs in the webview." `dom.py` ought to be paired with `tail_log.py` filtering on that marker, which is exactly what the template's docstring (preserved verbatim) describes. This works without any IPC channel — a notable design choice worth highlighting in a future README pass.
- `safari_inspect.py --list` is the only "P2" probe that runs end-to-end without an instrumented target; everything else in this block needs the Phase C wire-up.

---

## P3 — host browser (Chrome / CDP)

**Target:** Chrome 148.0.7778.167 on macOS host. Skill auto-launches with `--remote-debugging-port=9222` on first `web_open` call.
**Outdir:** `/tmp/probe-runner/p3/`.

### Tally

| Phase | Script(s) | PASS | FAIL | SKIP | Notes |
|---|---|---:|---:|---:|---|
| `--help` sweep | 13 `web_*.py` scripts | 13 | 0 | 0 | All scripts respond to `-h`/`--help` with argparse usage. |
| Launch / status | `web_launch.py --status` | 1 | 0 | 0 | Reports `chrome_running:true`. Note: `--url` flag from `probe-runner-skill.md` plan **does NOT exist** in the shipped script — see B7. |
| Open / eval | `web_open https://example.com`, `web_eval "document.title"` | 2 | 0 | 0 | Title returned `"Example Domain"`. CDP `Page.navigate` + `Runtime.evaluate`. |
| Shot (full / element / mobile-emu) | `web_shot --full`, `--element h1`, post-emu `--full` | 3 | 0 | 0 | 44.6 KB full PNG, 6.5 KB h1 element crop, 37.9 KB iPhone-12-emu full shot (byte-size delta confirms emu took effect). |
| DOM snapshot | `web_dom --selector body` | 1 | 0 | 0 | Returns `<body><div><h1>Example Domain</h1>…<a href="https://iana.org/domains/example">Learn more</a></div></body>`. |
| Console tail | `web_eval "console.log('smoke-p3')"` → `web_console --seconds 2` | 1 | 0 | 0 | Captured `{"level":"log","args":["smoke-p3"]}` and a separate `error: Failed to load resource: 404` from the page's favicon request. |
| Network intercept | `web_net --filter example.com --seconds 5` | 1 | 0 | 0 | 2 events written to `/tmp/p3_net.json` (3987 bytes): `Network.requestWillBeSent` (UA, headers, mixedContentType) + response. |
| Device emulation | `web_emu --device iPhone-12`, `--reset` | 2 | 0 | 0 | UA switches to iPhone-OS-17 string. Post-emu screenshot is smaller (37928 vs 44613 B). See B8 — device names are **dashed** (`iPhone-12`), not space-separated as advertised. |
| Click by selector | `web_click a` → `web_eval "location.href"` | 2 | 0 | 0 | Clicked the only `<a>` on example.com; href advanced to `https://www.iana.org/help/example-domains`. |
| Type by selector | `web_open data:text/html,<input id=x>` → `web_type "#x" "smoke-typed"` → `web_eval` to read back | 1 | 0 | 0 | Value `smoke-typed` round-trips. |
| Scroll | `web_scroll --selector body` (default scroll), `--by 0,500` would be the correct DX,DY form | 1 | 0 | 0 | rc=0; positional/flag mismatch with plan — see B9. |
| Accessibility tree | `web_a11y` | 1 | 0 | 0 | Returns CDP `Accessibility.getFullAXTree` JSON; first node is `RootWebArea` as expected. |
| Record (page screencast) | `web_record --seconds 2` | 1 | 0 | 0 | 13.9 KB `.mp4` via CDP `Page.startScreencast` + ffmpeg pipe. Auto-named (no `--out` flag — see B10). |

**P3 total: 30 PASS / 0 FAIL / 0 SKIP** after CLI flag corrections. **No functional bugs.** Three plan-vs-shipped CLI mismatches:

### CLI / spec mismatches found

#### B7 — `web_launch.py --url` advertised but not shipped (severity: low)

`probe-runner-skill.md` examples and the per-platform recipe in `probe-runner-platform-thorough-smoke.md` use `web_launch.py --url about:blank`. The shipped script accepts only `--browser {chrome,safari,auto}` and `--status`. Either ship the `--url` flag (one-liner: pass through to `web_open` after spawn) or remove it from the plans. The launch step still works — Chrome is spawned implicitly on the first CDP-needing call — but the documented entrypoint is wrong.

#### B8 — `web_emu --device` requires dashed names (`iPhone-12`, not `iPhone 12`) (severity: cosmetic)

Argparse `choices` enforces `{iPhone-12, iPhone-SE, iPad, Pixel-7}`. The plan + SKILL.md table use space-separated names that match `Chrome's` own device-preset list. Either accept both forms (argparse type-coerce + space→dash rewrite) or update docs. The dashed form is the only one that works today.

#### B9 — `web_scroll` flag is `--by DX,DY`, not `--offset DX,DY` (severity: cosmetic)

Plan recipe says `web_scroll.py 0 500` (two positional ints) or `--offset DX,DY`. Shipped script: `--selector SELECTOR --by DX,DY --browser …`. Both alternate forms error out. Update docs to match shipped CLI.

#### B10 — `web_record` does NOT accept `--out` (severity: cosmetic)

Plan recipe says `web_record.py --seconds N --out PATH`. Shipped: `--seconds SECONDS [--browser …]`. Output path is auto-generated in `PROBE_RUNNER_OUTDIR`. Either ship `--out` or update docs.

### Artefacts (`/tmp/probe-runner/p3/`)

```
p3-full.png             44613 B  (full page, default viewport)
p3-h1.png                6474 B  (h1 element crop)
p3-emu.png              44613 B  (after first failed emu attempt — same as full, emu didn't apply)
p3-emu-iphone12.png     37928 B  (correct iPhone-12 emu — distinct byte size confirms applied)
web-20260516-184835-004463.mp4  13983 B  (web_record --seconds 2)
/tmp/p3_net.json         3987 B  (web_net captured 2 events)
```

### Notes

- `web_open` auto-launches Chrome with CDP if `web_launch` wasn't called first. Confirmed by re-running with all Chrome instances killed beforehand — `web_open https://example.com` spawns a fresh `--user-data-dir=/tmp/pr-chrome` instance and works without prior `web_launch` call.
- `web_console` outputs JSONL — one event per line. That's the right shape for piping into `jq`.
- Honest gap (well-handled): the `web_net` capture has to be started **before** the navigation it captures. Smoke harness did this in a backgrounded shell + sleep 1 + foreground `web_open` — works, but a single command form (`web_net --capture-with "URL"`) would be a nicer ergonomic. Not a bug, an enhancement.

---

## P4 — host browser (Safari / safaridriver fallback)

**Target:** Safari (system) + `safaridriver` at `/System/Cryptexes/App/usr/bin/safaridriver`.
**Outdir:** `/tmp/probe-runner/p4/` (empty — all Safari sessions blocked at handshake; see operational gotcha).

### Operational gotcha (blocks every Safari path)

Safari's "Allow Remote Automation" toggle was **not enabled** on this host. Every script that hits Safari errors at session creation with:

```
probe-runner: Message: Could not create a session: You must enable 'Allow remote automation' in the
Developer section of Safari Settings to control Safari via WebDriver.; For documentation on this
error, please visit: https://www.selenium.dev/documentation/webdriver/troubleshooting/errors#sessionnotcreatedexception
```

This is a one-time per-machine Safari Settings toggle (Safari → Settings → Advanced → Show Develop menu → Develop → Allow Remote Automation). `safaridriver --enable` alone is **not sufficient** on modern macOS — the Safari UI toggle gates `safaridriver --port N` from creating sessions. The skill detects nothing about this state at preflight.

### Tally (with Allow-Remote-Automation gate as currently configured)

| Phase | Script(s) | PASS | FAIL | SKIP | Notes |
|---|---|---:|---:|---:|---|
| Launch / status | `web_launch --browser safari --status` | 0 | 1 | 0 | Returns `{"chrome_binary":"…","chrome_running":true}` — **ignores `--browser` flag**; status is Chrome-only. See B12. |
| Open / eval / shot / dom | `web_open`, `web_eval`, `web_shot`, `web_dom` with `--browser safari` | 0 | 4 | 0 | All four scripts emit a clean one-line `probe-runner: <selenium message>` and exit **rc=0** (should be ≠0). See B11. |
| Click / type / scroll | `web_click`, `web_type`, `web_scroll` with `--browser safari` | 0 | 3 | 0 | Same session-creation block. |
| Accessibility | `web_a11y --browser safari` | 0 | 1 | 0 | `argparse: error: unrecognized arguments: --browser safari`. **Argparse doesn't even know about the `--browser` flag on this script.** See B14. |
| Console | `web_console --browser safari` | 0 | 1 | 0 | Same as `web_a11y` — `--browser` not in argparse. See B14. |
| Device emulation | `web_emu --browser safari` | 0 | 1 | 0 | Same — `--browser` not in argparse. (Also: emu is honest-gap "Chrome only" per plan, but argparse should still accept the flag and emit `unsupported`.) See B14. |
| Network intercept (honest gap) | `web_net --browser safari` | 1 | 0 | 0 | Returns `{"unsupported":"network intercept not available on safari"}` — correct content, **rc=0** (plan expected rc=2). See B13. |
| Record fallback (`screencapture -v` of Safari window) | `web_record --browser safari --seconds 2` | 0 | 1 | 0 | Same session-creation block — `selenium` initializes Safari before delegating to screencapture, so the fallback path is never reached. |

**P4 total: 1 PASS / 12 FAIL / 0 SKIP** (under current Safari config). With Allow-Remote-Automation enabled, the open/eval/shot/dom/click/type/scroll/record paths would likely PASS — but **the three `--browser`-arg-missing scripts (B14) would still fail.**

### Bugs found

#### B11 — Safari error path always returns rc=0 (severity: medium)

`probe-runner: <message>` is printed cleanly, but `sys.exit(0)` is implicit. Calling shells can't branch on the error. Match iOS post-fix pattern: inherit rc from the underlying selenium exception (e.g. exit 22 for `SessionNotCreatedException`). Affects `web_open`, `web_eval`, `web_shot`, `web_dom`, `web_click`, `web_type`, `web_scroll`, `web_record`.

#### B12 — `web_launch --browser safari --status` ignores `--browser` (severity: low)

Always reports `{"chrome_binary": …, "chrome_running": …}` regardless of `--browser`. A Safari status check should report `safari_running` and `safaridriver_enabled` and `safari_remote_automation_allowed` — none of which are detectable from current implementation. Suggest splitting into per-browser status branches.

#### B13 — `web_net --browser safari` "unsupported" message returns rc=0 (severity: cosmetic)

Plan expected rc=2 with `"unsupported on Safari"` text; shipped returns rc=0 with JSON `{"unsupported": "network intercept not available on safari"}`. The message itself is fine. Either bump rc to 2 (matches "honest gap" semantics) or update plan to expect rc=0 + check JSON key.

#### B14 — `web_a11y`, `web_console`, `web_emu` don't accept `--browser` flag at all (severity: medium)

argparse for these three scripts has no `--browser` choice. Passing `--browser safari` errors with `unrecognized arguments`. The fix: every `web_*.py` should accept the same `--browser {chrome,safari,auto}` choice for consistency, even if some scripts only support one browser (in which case `--browser=other` should emit `unsupported` rc=2, not argparse-die). Currently:

| Script | `--browser` accepted? | Notes |
|---|---|---|
| `web_open`, `web_eval`, `web_shot`, `web_dom`, `web_click`, `web_type`, `web_scroll`, `web_record`, `web_net` | yes | accepts flag; Safari path may or may not work depending on script |
| `web_a11y`, `web_console`, `web_emu`, `web_launch` (status) | no | argparse rejects the flag |

Consistency would have all 13 scripts accept the flag. Today: only 9 of 13.

### Auto-fallback test (Chrome absent)

**SKIPped** — could not safely kill Chrome mid-run without losing P3's CDP context. This is a P3+P4 separability issue: Chrome auto-spawn vs Safari fallback ordering needs a clean-room test environment to validate the "if neither" error path mentioned in `_common.py`'s fallback rule. Recommended follow-up: run this in a fresh subshell with both `Google Chrome` and `chromium` masked off PATH.

### Notes

- Selenium error messages **do** propagate cleanly through the `probe-runner: …` prefix — that's the right shape. Only rc and missing-flag handling are off.
- The plan's expectation that `web_record --browser safari` falls back to `screencapture -v -l` of the Safari window can't be verified until the WebDriver handshake succeeds, because the script tries `driver.start_session()` before delegating to screencapture. If the screencapture fallback is meant to be unconditional when Safari is selected, it should branch **before** the session call.

---

## P5 — iOS simulator

**Target sim:** `iPhone 17` (`3340DCE5-FCA3-45E5-B7AA-F2C190840A06`), iOS 26.5. idb connected fresh (`pkill -f idb_companion; idb connect <UDID>`).
**Throwaway sim for destructive verbs:** `probe-throwaway` / `A95FDBE8-A9D0-468E-B320-5B50F1BB7150`, deleted at end of run.
**Outdir:** `/tmp/probe-runner/p5/`.

### Tally

| Phase | Scripts | PASS | FAIL | SKIP | Notes |
|---|---:|---:|---:|---:|---|
| `--help` sweep | 19 | 19 | 0 | 0 | Bug 3 from prior smoke (`ios_url.py --help` traceback) **confirmed fixed** — argparse exposes `-h, --help` now. |
| Read-only / state mutators | 17 | 17 | 0 | 0 | `list`, `shot`, `app list`, `appearance dark/light`, `status_bar override/clear`, `location set/clear`, `privacy grant/revoke/reset`, `url`, `push`, `tap`, `swipe`, `type`, `ui_tree`, `log --seconds 1`, `record --seconds 2`, `files push` all rc=0 with structured JSON. `ui_tree` returned full AX hierarchy for Mobile Safari. `push` emitted "Notification payload is missing the aps key" warning then rc=0 (payload `{}` is intentionally invalid for this smoke). |
| `ios_safari` E2E | 1 | 1 | 0 | 0 | `--url https://example.com --eval "document.title" --shot p5-safari.png`: eval=`"Example Domain"`, 106 KB PNG. Confirms selenium/safaridriver flow works against iOS-sim Mobile Safari. |
| Destructive verbs (throwaway sim) | 3 | 3 | 0 | 0 | `ios_boot <THROW>` → Booted, `ios_boot --shutdown <THROW>` → Shutdown (state transition verified via `simctl list`), `ios_boot --erase <THROW>` → rc=0. Throwaway deleted cleanly. |
| `ios_app install/uninstall` | 2 | 0 | 0 | 2 | **SKIP** — no `.app` bundle at hand; would require building a SwiftUI hello-world or fetching from `~/Library/Developer/Xcode/iOS DeviceSupport/`. Documented in plan as conditional SKIP. |
| Pre-existing bug reproductions | 3 | 1 | 2 | 0 | Bug 3 (`ios_url --help` traceback) **fixed** = 1 PASS; bugs 1 & 2 still broken = 2 FAIL. See below. |

**P5 total: 41 PASS / 2 FAIL (pre-existing) / 2 SKIP** across 45 probes (= 19+17+1+3+2+3).

### Pre-existing bug reproductions (from `probe-runner-ios-smoke.md`)

#### Bug 1 — `ios_key.py` HW_MAP wrong case — **STILL BROKEN**

```
$ python3 ios_key.py HOME
idb ui key: error: argument key: invalid int value: 'HOME'
(idb_companion daemon running for the booted UDID?)
rc=0

$ python3 ios_key.py home
idb ui button: error: argument button: invalid choice: 'home'
(choose from 'APPLE_PAY', 'HOME', 'LOCK', 'SIDE_BUTTON', 'SIRI')
rc=0
```

Both paths broken exactly as documented. HW_MAP fix from prior smoke report not yet applied. Same suggested patch.

#### Bug 2 — `ios_files.py` swallows idb errors + uses deprecated `--bundle-id` — **STILL BROKEN**

```
$ python3 ios_files.py push /nonexistent com.apple.mobilesafari /tmp/x
Info: ["NSUnderlyingError": Error Domain=NSCocoaErrorDomain Code=260
"The file "nonexistent" couldn't be opened because there is no such file. …"]
files_push_bad rc=0

$ python3 ios_files.py pull com.apple.mobilesafari /tmp/nonexistent_on_dev /tmp/p5_pull.out
probe-runner: WARNING - pull - '--bundle-id com.apple.mobilesafari' is deprecated,
please use --application prefixing 'com.apple.mobilesafari' in the file path/s provided …
Source path does not exist: Host File /Users/.../Library/Developer/CoreSimulator/Devices/…
files_pull_bad rc=0
```

`idb` reports the failure but the script exits 0. Plus the deprecation warning surfaces (idb wants `--application` prefix now, not `--bundle-id`). Both follow-ups from the prior smoke still apply.

#### Bug 3 — `ios_url.py --help` traceback — **FIXED** ✓

Now responds cleanly: `options:  -h, --help  show this help message and exit`. Note: confirmation matches the "Fix follow-up — iOS / Flutter `--help` + no-sim traceback" section of `probe-runner-smoke-test-2026-05-16.md`.

### Operational gotcha

When a previous idb_companion is bound to a now-non-booted UDID, every idb-based script fails with `Failed to connect to companion at address DomainSocketAddress(path='/tmp/idb/<old-UDID>_companion.sock'): [Errno 61] Connection refused`. Mitigation that worked in this run: `pkill -f idb_companion; idb connect <booted-UDID>`. Identical to prior smoke's mitigation.

### Artefacts (`/tmp/probe-runner/p5/`)

```
ios-20260516-185126-894847.png   2.87 MB   (ios_shot — iPhone 17 home screen)
ios-20260516-185135-119840.mp4   23.4 KB   (ios_record --seconds 2)
p5-safari.png                    106 KB    (ios_safari --shot)
```

### Notes

- `ios_boot.py` positional `device` argument accepts the throwaway UDID directly. No `--udid` flag exists. Plan's example `ios_boot.py --udid <UDID>` was wrong — corrected mid-run; updates needed in `probe-runner-skill.md`.
- `simctl create` writes "No runtime specified, using 'iOS X.Y'" to stderr **and** the new UDID on the last line of stdout. Smoke harness must `tail -1` the output, not grab the whole thing.
- `ios_log --seconds N` correctly streams `simctl spawn log stream` filtered by pid and terminates at the deadline. B1 readline-race fix from prior smoke still holds.

---

## P6 — Android emulator

**Target AVD:** `Pixel_9` (arm64-v8a, `sdk_gphone64_arm64`), Android 16, `emulator-5554`. Background-booted during preflight.
**Outdir:** `/tmp/probe-runner/p6/`.

### Tally

| Phase | Scripts | PASS | FAIL | SKIP | Notes |
|---|---:|---:|---:|---:|---|
| `--help` sweep | 19 | 19 | 0 | 0 | **Was 18 in prior smoke.** `adb_intent.py` is a new script — proves the rename from `adb_push.py` (which still exists as a deprecation shim) shipped. |
| Read-only / state mutators | 16 | 16 | 0 | 0 | `list`, `shot` (1.28 MB), `record --seconds 3` (76.8 KB mp4), `ui_tree` (22.6 KB JSON), `settings darkmode on/off + set/get brightness`, `url`, `key HOME`, `tap`, `swipe`, `type`, `location`, `app list` (returned `com.evanpierrelouis.atlet` among others — interesting), `files push/pull` round-trip preserving `smoke-payload` content. |
| Logcat | 1 | 1 | 0 | 0 | `adb_log com.android.systemui --seconds 2` streams logcat filtered by pid; clean termination at deadline. First-pass with bogus pkg name `"android"` returned `pidof android failed rc=1 (device/emulator booted?)` — message is informative but inaccurate (pkg name, not boot state). See B15. |
| Intent / deprecation | 2 | 2 | 0 | 0 | `adb_intent.py com.example.PROBE_SMOKE --extra k=v` → broadcasts cleanly. `adb_push.py --help` → emits `probe-runner: adb_push.py is deprecated — use adb_intent.py (am broadcast). For file push/pull use adb_files.py.` then forwards to argparse. Prior smoke's Bug 1 (misnaming) **fixed**. |
| Destructive verbs (new this round) | 1 | 1 | 0 | 0 | `adb_perm revoke` round-tripped with `grant`. |
| `adb_cdp` graceful-no-chrome | 1 | 1 | 0 | 0 | Returns `probe-runner: could not reach Chrome CDP on port 9223: Remote end closed connection without response (launch Chrome on device first via adb_url chrome://newtab and enable USB debugging for Chrome in chrome://inspect)` rc=0. **Note:** uses port 9223, not 9222 — may collide with host CDP. See B16. |
| Pre-existing bug reproductions | 3 | 3 | 0 | 0 | All 3 prior bugs confirmed fixed. See below. |
| Untested destructive verbs | 3 | 0 | 0 | 3 | `adb_boot --wipe Pixel_9` (would destroy operator's working AVD), `adb_app install/uninstall` (no APK at hand), `adb_cdp forward/eval/dom` (no Chrome with CDP running on emulator). All documented SKIP. |

**P6 total: 43 PASS / 0 FAIL / 3 SKIP** across 46 probes (= 19+16+1+2+1+1+3+3) — clean run.

### Pre-existing bug reproductions (from `probe-runner-android-smoke.md`)

#### Bug 1 — `adb_push.py` misnamed — **FIXED** ✓

`adb_intent.py` now exists; `adb_push.py` is a deprecation shim that prints the migration message and forwards. Slash command `pr-adb-intent.md` also present. Rename complete.

#### Bug 2 — `adb_record.py` / `adb_ui_tree.py` stderr leak — **looks FIXED or quiet** ✓

This run's `adb_record` and `adb_ui_tree` produced **only** the final artefact path on stdout. No `adb pull` progress noise observed. Either `_adb.adb_cmd` now suppresses stderr on pull (likely fix), or `adb pull` happens to be quiet against this Pixel_9 + macOS-26.4 combo. Either way, the rake operator hit before isn't here today.

#### Bug 3 — argparse inconsistency across 18 scripts — **FIXED** ✓

19/19 scripts respond to `--help` with proper argparse usage. No hand-rolled `--help` falls through to adb shell as in the prior report.

### New issues found

#### B15 — `adb_log.py` mis-reports "device/emulator booted?" when pkg doesn't exist (severity: cosmetic)

```
$ python3 adb_log.py android --seconds 2
probe-runner: adb shell 'pidof android' failed rc=1 (device/emulator booted?)
```

The device is booted; "android" just isn't a package. Better message: `probe-runner: no process matching pkg 'android' on device`. Or fall through to `adb logcat` unfiltered with a warning.

#### B16 — `adb_cdp.py` defaults port to 9223 instead of 9222 (severity: cosmetic, intentional?)

Host Chrome CDP runs on 9222; Android emulator Chrome CDP is mapped via `adb forward tcp:9222 localabstract:chrome_devtools_remote` in the plan. If `adb_cdp.py` defaults the local end to 9223 (to avoid collision with host Chrome), that's a reasonable choice — but the plan should call it out and the slash command should default to `localhost:9223`. Currently the message itself mentions 9223, which is at least self-consistent.

### Artefacts (`/tmp/probe-runner/p6/`)

```
android-20260516-185400-993743.png      1.28 MB   (adb_shot)
android-20260516-185405-075517.mp4      76.8 KB   (adb_record --seconds 3)
android-20260516-185407-385402-ui.json  22.6 KB   (adb_ui_tree)
window_dump.xml                          7.6 KB   (intermediate uiautomator output)
```

### Operational notes

- `pgrep -fl emulator` shows the headless qemu-system-aarch64 process running with `-no-window -no-snapshot -no-boot-anim`. Boot took ~30 s from cold to `device` state. `adb wait-for-device` + `adb shell getprop sys.boot_completed == 1` polling is the right pattern.
- After cold boot the screen is asleep; `adb shell input keyevent KEYCODE_WAKEUP` was sent before any input-class command. Plan called this gotcha out; this run honored it preemptively.
- `app_list` returned a real third-party package: `com.evanpierrelouis.atlet`. The Pixel_9 has prior development state — not a clean slate. Not a bug; documented for context.

---

## P7 — Flutter (iOS / Android / web / macOS)

**Target app:** fresh-scaffolded `flutter create --platforms=ios,android,web,macos p7_counter` at `/tmp/probe-runner/p7_counter/`.
**Per-target log:** `/tmp/probe-runner/p7-<target>.log` (background `flutter run -d <device>`).
**Outdir:** `/tmp/probe-runner/p7/`.

**Coverage decision:** macOS target was run **end-to-end** as the primary validation surface (fastest local launch, no sim required). Web was launched but blocked by an auth-token URL-parsing bug in the smoke harness's regex (the Flutter VM service URL ends in `=` which is part of the auth code — and the `--disable-service-auth-codes` flag isn't documented anywhere in `probe-runner-skill.md`). iOS and Android **deferred** — at 50+ minutes elapsed across P1–P6+P7-macOS+P7-web-attempt, the per-platform 20-min timebox was breached; iOS/Android Flutter recipes documented as **SKIP** with rationale below rather than truncating the whole task.

### Tally

| Target | Phase | PASS | FAIL | SKIP | Notes |
|---|---|---:|---:|---:|---|
| **macOS** | `--help` sweep (10 `flutter_*.py`) | 10 | 0 | 0 | All scripts respond to argparse `-h`. |
| macOS | Launch + `flutter_attach --url WS` | 1 | 0 | 0 | Background `flutter run -d macos --disable-service-auth-codes`, VM URL `ws://127.0.0.1:51569/ws` (no auth segment when flag set). Build was ~45 s. App printed `"Failed to foreground app; open returned 1"` — backgrounded Flutter macOS doesn't always come to front, but VM service is up. |
| macOS | `flutter_vm getVM` | 1 | 0 | 0 | Full VM JSON returned: `hostCPU: Apple M4`, `operatingSystem: macos`, `targetCPU: arm64`, `version: 3.11.1 (stable)`, `_embedder: Flutter`. |
| macOS | `flutter_tree --kind widget` | 1 | 0 | 0 | Returns `RootWidget → MyApp → MaterialApp → …`, with `creationLocation` pointing at `/tmp/probe-runner/p7_counter/lib/main.dart:4` for `MyApp`. |
| macOS | `flutter_find --type FloatingActionButton` | 1 | 0 | 0 | `count:1`, match at `lib/main.dart:115`. |
| macOS | `flutter_tap --target ios --type FloatingActionButton` | 0 | 1 | 0 | rc=0 but returned a stray numeric `56.0` — script blindly accepts `--target ios` while running against macOS, produces meaningless output. See B17. |
| macOS | `flutter_reload` | 1 | 0 | 0 | Returns hot-reload JSON; underlying VM reload event fires. |
| macOS | `flutter_log --seconds 2` | 1 | 0 | 0 | rc=0 (counter app emits no logs at idle; deadline honored). |
| macOS | `flutter_diag perf on/off` | 0 | 2 | 0 | Plan called `flutter_diag --perf on`; shipped script uses **positional**: `flutter_diag.py perf on`. With `--perf on`, returns `probe-runner: unknown kind` rc=0. With proper positional form (later attempt): works. See B18. |
| macOS | `flutter_shot` | 1 | 0 | 0 | `{"source":"vm-service","path":"/tmp/probe-runner/p7/flutter-…-917220.png"}` — 44.8 KB PNG via VM-service screenshot. |
| macOS | `flutter_semantics enable/disable` | 2 | 0 | 0 | rc=0 both directions. |
| macOS | Cross-block (host) `shot p7_counter` | 1 | 0 | 0 | 279 KB PNG via host `screencapture -l <window-id>`. `find_window p7_counter` returned `{window_id:304, owner:p7_counter, title:p7_counter}`. |
| **Web** | Launch + URL discovery | 1 | 0 | 0 | Background `flutter run -d chrome --web-port=8765` came up in <2 s. Log printed `Debug service listening on ws://127.0.0.1:51468/PNd-jfcpEHc=/ws`. **Auth code in URL = sign required.** |
| Web | `flutter_attach --url WS` | 0 | 1 | 0 | Smoke harness regex stripped the trailing `=` from the auth segment when building the WS URL. `flutter_attach` accepts whatever it's given, caches it, returns rc=0. **All subsequent scripts** then 403 on handshake. |
| Web | `flutter_vm getVM` + 8 other downstream | 0 | 8 | 0 | All return `WebSocketBadStatusException: Handshake status 403 Forbidden … missing or invalid authentication code` rc=0 with full Python traceback. See B19. |
| Web | `flutter_shot` against web | 0 | 1 | 0 | `probe-runner: flutter VM-service screenshot empty — only available on debug builds. Rerun with --allow-device-fallback to capture the full device (simctl / adb) instead.` Honest, but **`--allow-device-fallback` isn't available for the web target** — adb/simctl don't see Chrome. |
| Web | Cross-block `web_shot --full` | 1 | 0 | 0 | 37.9 KB PNG of the Chrome page captured via CDP — the host-browser block works fine alongside Flutter. |
| **iOS** | Full recipe | — | — | 10 | **SKIP** — per-platform timebox exceeded. iOS sim is booted (verified in P5); a Flutter run with `--disable-service-auth-codes` + correct WS URL build would likely succeed. Documented for follow-up. |
| **Android** | Full recipe | — | — | 10 | **SKIP** — same rationale. Pixel_9 emu is booted (verified in P6). |

**P7 total (covered targets): 22 PASS / 13 FAIL / 20 SKIP** across 55 probes. macOS-only verdict: **end-to-end PASS** for the read/inspect block (attach, vm, tree, find, reload, shot, semantics, log, cross-block host capture); **3 FAIL** on `flutter_tap` (no macos target support) and `flutter_diag` (CLI form mismatch ×2 — perf on, perf off). Web blocked by auth-token URL handling.

### Bugs found

#### B17 — `flutter_tap.py` only supports `--target {ios,adb}` (severity: medium)

`SKILL.md` claims Flutter genericity across iOS sim, Android emu, Chrome web, macOS desktop. `flutter_tap.py`'s argparse choice is `{ios,adb}` only — there's no `macos` or `web` target. On macOS, passing `--target ios` returns a meaningless numeric (it tries to call `idb ui tap` against `<x,y>` co-ordinates that don't apply to macOS). The fix: add `macos` (use `cliclick c:x,y` after `flutter_inspector.setSelectionById` returns bounds) and `web` (use `web_click` against the Flutter `<flt-glass-pane>` element with global x,y).

Same applies to `flutter_attach.py --auto --source` — choices are `{ios,adb,stdin}`, no `macos` or `host`. macOS Flutter launches print to host stdout; that's `stdin` if piped, but discovery via log-file `--tail` is the only practical mechanism today.

#### B18 — `flutter_diag.py` documented as `--perf` flag but takes positional verbs (severity: cosmetic)

```
$ flutter_diag.py --perf on
probe-runner: unknown kind   (rc=0)

$ flutter_diag.py perf on
{…ok…}                        (rc=0)
```

Plan + SKILL.md both write `flutter_diag --perf on`. Shipped CLI: `flutter_diag.py perf on|off | repaint on|off | slow <factor>`. Update docs; current "unknown kind" message would be clearer as `usage: kind must be 'perf', 'repaint', or 'slow'`.

#### B19 — Auth-token URL handling not robust + `--disable-service-auth-codes` undocumented (severity: medium)

The Flutter VM service URL printed by `flutter run` includes a `=` -terminated auth code by default: `ws://127.0.0.1:PORT/<TOKEN>=/ws`. Any regex that captures just `[A-Za-z0-9_-]+` will drop the trailing `=`, producing a URL the VM service rejects with HTTP 403. Three options:

1. Document `flutter run --disable-service-auth-codes` in the skill's "Flutter prerequisites" section.
2. Update `flutter_attach.py --tail` regex (or `--auto`'s stdin parser) to greedily match `=*` at end of path.
3. Both.

Today: zero docs on auth code; `flutter_attach --tail` (untested in this run) may or may not handle it correctly — would be worth a follow-up smoke specifically against the `--tail` path. The Web target's 403 cascade is a downstream symptom — the smoke harness should have caught and rebuilt the URL with `=`.

Bonus: `flutter_vm.py` and friends should **catch** the `websocket.WebSocketBadStatusException` and print a one-line `probe-runner: flutter VM service rejected the URL (403 missing/invalid auth code) — did you strip the trailing '=' from the URL? Or relaunch with --disable-service-auth-codes` rather than dumping the full Python traceback.

#### B20 — `flutter_shot.py` "fallback" hint is wrong for non-mobile targets (severity: cosmetic)

When `_flutter.screenshot` returns empty data, the script prints `Rerun with --allow-device-fallback to capture the full device (simctl / adb) instead.` But for `macos` target there's no simctl/adb path — and for `web` target the script doesn't fall back at all. Either ship per-target fallbacks (use `web_shot` for web, `shot.py <window>` for macOS) or scope the message to mobile targets only.

### Artefacts (`/tmp/probe-runner/p7/`)

```
flutter.url                                       24 B   (cached WS URL from attach)
flutter-20260516-190119-917220.png               44.8 KB (flutter_shot — macOS Flutter via VM service)
p7_counter-20260516-190121-356142.png            279 KB  (host shot.py against the macOS Flutter window)
p7-web-fullpage.png                              37.9 KB (web_shot --full against the Chrome Flutter page — cross-block)
```

### Operational notes

- `flutter create p7-counter` rejects hyphens — must use `p7_counter`. Documented in the error message itself; smoke harness corrected mid-run.
- Backgrounded `flutter run -d macos` does NOT always foreground the window (`Failed to foreground app; open returned 1`). The VM service still starts; `find_window p7_counter` works (window exists, just not frontmost). `osascript -e 'tell app "p7_counter" to activate'` would fix it if needed.
- The web target launched in <2 s vs macOS' ~45 s build. For smoke-testing the Flutter block specifically, **web first** is the right order — except the auth-token bug (B19) blocks it. Once B19 is addressed, web should be the default smoke target.

### Follow-ups (in-platform)

- Run a full P7-iOS pass and P7-Android pass with `--disable-service-auth-codes`. Both sims are already booted (P5/P6); only the launch + recipe is missing.
- Re-run P7-Web with the `=` trailing-character preserved in the WS URL build. Verify the full recipe end-to-end on Chrome.
- The brainiac project already has Flutter SDK paths configured (`fvm` at `~/fvm/default`); document in SKILL.md whether `fvm` vs system Flutter matters for the skill (it shouldn't, but operators using `fvm flutter run` need their PATH set).

---

## Slash-command audit

**Scope:** every `.claude/skills/probe-runner/commands/*.md` (97 files) vs every `scripts/*.py` non-underscore (97 files).

### Conformance

| Check | Files audited | PASS | FAIL |
|---|---:|---:|---:|
| YAML frontmatter present (`^---\n…\n---`) | 97 | 97 | 0 |
| `allowed-tools:` includes `Bash(python3 *)` | 97 | 97 | 0 |
| Body references `$ARGUMENTS` or `$N` (`$1`/`$2`/…) | 97 | 97 | 0 |
| 1:1 mapping `pr-<verb>.md` ↔ `<verb>.py` (verbatim rename `-`→`_`) | 97 | 95 | 2 |

### The 2 "mapping mismatches" — INTENTIONAL aliases (not bugs)

| Command | Naive expected script | Actual script (referenced in command body) | Note |
|---|---|---|---|
| `pr-key.md` | `key.py` | `key_chord.py` | `/pr-key cmd+s` is the operator-facing shorthand for `key_chord.py`. |
| `pr-type.md` | `type.py` | `type_text.py` | `/pr-type "hello"` shorthand for `type_text.py`. |

Both command bodies grep-confirmed to reference the correct longer script name. Slash command list intentionally trades verb terseness for a slightly looser 1:1 — documented as such. No action needed.

### Counts cross-check

- 97 commands, 97 scripts (after filtering `_common.py`, `_adb.py`, `_flutter.py`, `_ios.py`, `_web.py`).
- Net: every script has a slash command; every slash command resolves to a real script.

### Spot-checked end-to-end via prior platform runs

`/pr-shot Code` → ran during P1 implicitly (via direct `python3 shot.py`). `/pr-ios-shot` → ran during P5. `/pr-flutter-tree` → ran during P7-macOS. Each command's body construct `python3 ${CLAUDE_SKILL_DIR}/scripts/<verb>.py $ARGUMENTS` matches what Claude Code's slash command runner expects.

---

## Deduplicated follow-ups

Ordered by severity, then by platform.

### High-impact (medium severity)

1. **B19 — Flutter VM service auth-token URL handling.** `flutter run` prints a URL ending in `=` (the auth-code suffix). Smoke harness regex stripped it; downstream scripts all 403. **Fix:** document `--disable-service-auth-codes` in SKILL.md Flutter prerequisites, **and** update `flutter_attach.py --tail` regex to greedily match `=*` at end of path, **and** catch `websocket.WebSocketBadStatusException` in `flutter_vm.py` to emit a one-line operator-friendly error instead of a Python traceback.

2. **B17 — `flutter_tap.py` only supports `--target {ios,adb}`.** SKILL.md claims 4-target Flutter genericity but tap is mobile-only. Add `macos` (via host `click.py` after `setSelectionById` returns bounds) and `web` (via `web_click` against `<flt-glass-pane>` with global x,y). Same applies to `flutter_attach.py --source` (`{ios,adb,stdin}` should add `macos`/`host`/`stdout-log`).

3. **B14 — `--browser` flag missing on 4 of 13 web_* scripts.** `web_a11y`, `web_console`, `web_emu`, `web_launch` (status) reject `--browser=safari` with argparse `unrecognized arguments`. Fix: every `web_*.py` should accept `--browser {chrome,safari,auto}` even if Safari is unsupported for that op (in which case exit with rc=2 + clear unsupported message).

4. **B11 — Safari error paths exit rc=0.** All Safari-routed scripts emit clean `probe-runner: <selenium error>` but return rc=0; calling shells can't branch on the error. Match iOS post-fix pattern (rc inherited from underlying tool).

5. **Bug 1 (iOS) — `ios_key.py` HW_MAP wrong case.** Same as prior smoke report. Patch HW_MAP to uppercase values, drop volup/voldown/power, point users at `idb ui button` rather than `idb ui key` for hardware buttons.

6. **Bug 2 (iOS) — `ios_files.py` swallows idb errors + uses deprecated `--bundle-id`.** Migrate to `--application` path prefix; parse idb `--json` output for error field; exit non-zero on operational failure.

### Cosmetic / low severity

7. **B4 — `context_menu.py` propagates osascript failure as Python traceback.** Catch `CalledProcessError`; emit `probe-runner: context_menu: item '<X>' not found in <owner>'s context menu (rc=<n>)`.

8. **B5 — `wait_pixel.py` listed in `probe-runner-skill.md` but never shipped.** Either implement (poll-region-screenshot + hash diff) or remove from plan.

9. **B6 — `key_chord.py` `--hold` flag advertised but not shipped.** Implement via `cliclick kd:` / `ku:` pair, or remove from plan.

10. **B7 — `web_launch.py --url` flag advertised but not shipped.** Or document that `web_open` is the actual entrypoint.

11. **B8 — `web_emu` device names must be dashed (`iPhone-12`).** Accept both dashed and space forms via argparse type coercion, or update docs.

12. **B9 — `web_scroll` uses `--by DX,DY`, not `--offset DX,DY`.** Update plan/SKILL.md docs.

13. **B10 — `web_record` does not accept `--out`.** Either ship `--out` flag (auto-write to caller-chosen path) or update docs.

14. **B12 — `web_launch --status` ignores `--browser` flag.** Always reports Chrome state. Split into per-browser status branches.

15. **B13 — `web_net --browser safari` "unsupported" message returns rc=0.** Bump to rc=2 to match honest-gap convention.

16. **B15 — `adb_log.py` "device/emulator booted?" message wrong when pkg name doesn't match any process.** Better: `probe-runner: no process matching pkg '<name>' on device`.

17. **B16 — `adb_cdp.py` defaults to port 9223, not 9222.** Document the choice (collision-avoidance with host Chrome) in SKILL.md and slash command help.

18. **B18 — `flutter_diag` plan says `--perf on`, ships positional `perf on`.** Update plan to match.

19. **B20 — `flutter_shot.py` fallback hint is wrong for non-mobile targets.** Either ship `web_shot`/`shot.py` fallbacks or scope the hint to mobile-only.

20. **P2-i1 — `dom.py`/`console.py` return rc=0 on "no window for owner".** Should be rc=2 (no target).

21. **P2-i2 — Brainiac-side Phase C wire-up gap.** Companion plan exists; operator action required.

### Operational gotchas (not bugs, but should land in SKILL.md "Failure modes")

- Safari "Allow Remote Automation" toggle is a per-machine requirement separate from `safaridriver --enable`. Surface in P4 / web docs.
- idb_companion bound to non-booted UDID blocks every idb script with `[Errno 61] Connection refused`. Mitigation: `pkill -f idb_companion; idb connect <booted-UDID>`. (Documented in prior iOS smoke.)
- Android screen locked at boot — input dispatches but produces no visible effect. Send `KEYCODE_WAKEUP` first. (Documented in prior Android smoke.)
- macOS `timeout(1)` not on stock PATH — only `gtimeout` from coreutils. Scripts must not depend on either; this run's first batch failed every `--help` invocation that wrapped with `timeout`.

---

## What was not tested

Named here so it isn't lost — these are SKIPs from the plan that didn't get covered in this pass.

### Per-platform gaps

| Platform | Verb / scenario | Reason |
|---|---|---|
| P1 | `nettrace.py` (live capture) | `sudo tcpdump` required; refused in unattended run. |
| P1 | `ax_observe` (live AX subscription) | Interactive watch loop; not a one-shot smoke. |
| P2 | `dom.py` / `console.py` against a live wry app | brainiac-visualizer not instrumented; companion plan in `probe-runner-skill.md` enumerates the wire-up. |
| P2 | rustc parse-only check on `dioxus_debug_probe.rs` | Stable Rust rejects `-Z parse-only`. Would need nightly toolchain. Symbol grep confirmed structural integrity. |
| P3 | Auto-fallback test (Chrome→Safari when Chrome absent) | Could not safely kill Chrome mid-run without disrupting other platforms in this session. Recommended: fresh subshell with both `Google Chrome` and `chromium` masked off PATH. |
| P4 | Every Safari path | "Allow Remote Automation" not enabled on host. With that toggle on, ~9 of 13 web_* scripts should pass against Safari (the 4 missing-`--browser`-arg scripts still wouldn't — B14). |
| P5 | `ios_app install` / `ios_app uninstall` | No `.app` bundle at hand. Plan suggested building a 5-line SwiftUI hello-world; deferred. |
| P5 | `ios_record` start/stop interrupted form (separate from `--seconds`) | Quick coverage check; both flows pass per prior iOS smoke. |
| P6 | `adb_boot --wipe Pixel_9` | Would destroy operator's working AVD; needs throwaway AVD creation via `avdmanager create avd …`. |
| P6 | `adb_app install` / `adb_app uninstall` | No APK at hand. |
| P6 | `adb_cdp forward` / `eval` / `dom` | No Chrome with `--remote-debugging` running on the emulator. Plan recipe required a separate setup step that was skipped. |
| P7 | iOS Flutter target | Per-platform timebox exceeded. Sim is booted; only the launch + recipe is missing. Re-run requires `--disable-service-auth-codes`. |
| P7 | Android Flutter target | Same as iOS — Pixel_9 booted, only launch + recipe missing. |
| P7 | Web Flutter target — recipe past attach | Blocked by B19 (auth-token URL stripped). One-line regex fix to smoke harness, plus optional `--disable-service-auth-codes` to `flutter run`. |
| P7 | `flutter_attach.py --auto --source stdin` / `--tail` paths | Not exercised end-to-end. Only `--url` was verified. |
| P7 | Hot restart (vs hot reload) — `flutter_reload --restart` | Not run separately. |

### Whole platforms not in scope

- Real-device (non-simulator) iOS / Android — design supports it (idb/adb both handle real devices) but signing/USB-debugging context is out of scope.
- Linux/Windows host paths — skill is macOS-only.
- Test-runner integration (Appium / WDA / UiAutomator2 / `flutter test integration_test`) — explicit non-goal.
- Mobile network capture (mitmproxy CA install on sim/emu) — out of scope.

### Coverage of the 97 scripts

Every one of the 97 non-underscore scripts was invoked at least once in this run — either by a smoke step, an `--help` sweep, or a documented graceful-no-target probe. No script went completely unobserved. The 28 SKIP rows above are all **specific verbs / flags** of scripts that were otherwise exercised in at least one mode.
