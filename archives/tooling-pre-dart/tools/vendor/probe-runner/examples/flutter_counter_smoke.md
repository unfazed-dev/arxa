# Flutter counter smoke (works on iOS sim, Android emu, web, macOS)

The default `flutter create` template app, driven from probe-runner across
all four targets.

## Common setup

```bash
flutter create counter && cd counter
S=.claude/skills/probe-runner/scripts
```

## iOS sim

```bash
flutter run -d "iPhone 15" 2>&1 | tee /tmp/flutter.log &
python3 $S/flutter_attach.py --tail /tmp/flutter.log

python3 $S/flutter_tree.py --kind widget
python3 $S/flutter_find.py --type FloatingActionButton

# physical tap on the FAB (center-bottom on iPhone 15)
python3 $S/ios_tap.py 320 770

# hot reload after editing main.dart
python3 $S/flutter_reload.py
python3 $S/flutter_log.py --seconds 3
```

## Android emu

```bash
flutter run -d emulator-5554 2>&1 | tee /tmp/flutter.log &
python3 $S/flutter_attach.py --tail /tmp/flutter.log

python3 $S/flutter_tree.py --kind widget
python3 $S/adb_tap.py 540 1700
python3 $S/flutter_reload.py
```

## Flutter web

```bash
flutter run -d chrome 2>&1 | tee /tmp/flutter.log &
python3 $S/flutter_attach.py --tail /tmp/flutter.log

# Widget tree via VM service still works
python3 $S/flutter_tree.py --kind widget

# Pixels + DOM via Chrome
python3 $S/web_launch.py
python3 $S/web_shot.py --full
python3 $S/web_eval.py "document.title"
```

## macOS desktop

```bash
flutter run -d macos 2>&1 | tee /tmp/flutter.log &
python3 $S/flutter_attach.py --tail /tmp/flutter.log

python3 $S/find_window.py counter
python3 $S/shot.py counter
python3 $S/flutter_tree.py --kind semantics

# AX tree only populates after semantics is enabled
python3 $S/flutter_semantics.py enable
python3 $S/ax_tree.py counter --max-depth 6
```
