# Tauri smoke — proves the host-block is framework-agnostic

```bash
# spawn a fresh Tauri app
brew install rust deno
cargo install create-tauri-app
create-tauri-app tauri-smoke
cd tauri-smoke
npm install
npm run tauri dev &        # launches the wry window

S=.claude/skills/probe-runner/scripts
APP="tauri-smoke"          # adjust to your app's window owner

# discovery + capture
python3 $S/find_window.py "$APP"
python3 $S/shot.py "$APP"
python3 $S/ax_tree.py "$APP" --max-depth 4
```

No Tauri-specific code; the skill treats it identically to any other
wry-based macOS window.
