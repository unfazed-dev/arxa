# Device frames — use `assets/`, never hand-roll

> Ported from huashu. Hard-binding: when you mock an app/site in a device, **read the matching
> `assets/<frame>.jsx` and slot your screen inside it**. Hand-rolling a status bar / Dynamic Island /
> device bezel produces positioning bugs 99% of the time (status-bar icons crushed by the island,
> wrong content top-padding, wrong corner radius). The frames are spec-aligned; your ad-hoc version isn't.

## The frames (one per form factor)
| Asset | Use for | Key specs |
|---|---|---|
| `assets/ios_frame.jsx` | iOS app mockup | iPhone 15 Pro (393×852 logical); Dynamic Island 124×36 @ top:12 centered; status bar (time/signal/wifi/battery) with island-avoidance; home indicator; content from top:54 |
| `assets/android_frame.jsx` | Android app mockup | Pixel 8-class (412×892); punch-hole camera centered; status bar; gesture nav bar |
| `assets/macos_window.jsx` | desktop app mockup | macOS window chrome + traffic lights (close/minimize/maximize) + title bar |
| `assets/browser_window.jsx` | website in a browser | Chrome-style tab row + URL bar + traffic lights |

## Usage (strict three steps)
```jsx
// 1. Read assets/ios_frame.jsx
// 2. Inline the iosFrameStyles constant + IosFrame component into your <script type="text/babel">
// 3. Wrap your screen; don't touch island/status bar/home indicator
<IosFrame time="9:41" battery={85} darkMode>
  <YourScreen />   {/* content renders from top:54; you don't manage the status bar */}
</IosFrame>
```
Each frame self-mounts to `window.*` (`window.IosFrame`, etc.) — so it's parity-mountable like any
screen component.

## What you must NEVER hand-write in your HTML/shards
- `.dynamic-island` / `.island` / a centered black rounded rect at `top: ~12px, width: ~120`
- `.status-bar` with hand-drawn time/signal/battery
- `.home-indicator` / the bottom home bar
- iPhone bezel corner radius + black border + shadow
- macOS traffic lights / browser tab+URL chrome

These are **all** in the frame assets, spec-aligned. Re-implementing them re-introduces the bugs the
frames were built to fix.

## Exceptions (narrow)
Only override when the user explicitly asks for a non-standard device:
- "iPhone 14 non-Pro notch" → modify `ios_frame.jsx`'s constants, don't fork in your HTML.
- "Android, not iOS" → use `android_frame.jsx`.
- "custom device form" → edit the frame constants; keep one source of truth.

## Overview vs. flow-demo (decide before building)
Two standard multi-screen deliveries — **ask which first** (see `jsx-prototype-patterns.md`):
- **Overview** (design-review default): all screens side-by-side, each in its own frame, static.
- **Flow demo** (one clickable device): a single frame with an `AppPhone` state machine routing
  between screens on tap. Use for onboarding/purchase-flow demos.

For the crew's pipeline, the **shell mounts every screen on `window.*`** regardless — that's the
parity gate (`parity.py --all`), separate from the user-facing overview/flow choice.

## Dark screens (the status-bar-bg token)
A dark screen needs a status bar that tracks it. `IosFrame darkMode` flips the status-bar text to
white, but the **reactive overlay** (`color.status-bar-bg` token, see `tokens.md`) is what makes the
bar background match the screen. Author that token for any dark screen — otherwise the bar clashes.
