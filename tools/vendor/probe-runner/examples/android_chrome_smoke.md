# Chrome on Android emulator via CDP

```bash
S=.claude/skills/probe-runner/scripts

# 1. list / boot an emulator
python3 $S/adb_list.py
python3 $S/adb_boot.py boot Pixel_8_API_34

# 2. launch Chrome on the device
python3 $S/adb_app.py launch com.android.chrome
python3 $S/adb_url.py https://example.com

# 3. forward CDP to localhost:9223 and eval
python3 $S/adb_cdp.py forward
python3 $S/adb_cdp.py eval "document.title"
python3 $S/adb_cdp.py dom --selector "h1"

# 4. screenshot + UI tree at the OS level (sees only the Chrome chrome
#    + WebView surface)
python3 $S/adb_shot.py
python3 $S/adb_ui_tree.py
```
