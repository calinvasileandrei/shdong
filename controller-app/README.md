# shdong Controller app

macOS app for the Controller Mac. Design and milestones: [PLAN.md](PLAN.md).

## Build and run

```sh
swift build
swift run Shdong                 # unbundled, fine for development
scripts/bundle.sh                # build/Shdong.app (ad-hoc signed; SIGN_ID=... for Developer ID)
scripts/test.sh                  # unit tests (works with only the Command Line Tools installed)
```

Open `Package.swift` in Xcode to work in the IDE.

Permissions: only **Camera** (the capture stick is a UVC camera). Keys are read in-app while the
window is focused, so no Accessibility permission is needed; shortcuts macOS handles first (⌘Tab,
⌘Space) stay local — send them from the Input menu.

Install without admin rights (no Gatekeeper prompt, since curl doesn't quarantine):

```sh
mkdir -p ~/Applications && curl -L https://github.com/calinvasileandrei/shdong/releases/download/v1.2/Shdong-1.2-macOS.zip | ditto -x -k - ~/Applications && open ~/Applications/Shdong.app
```

## Without hardware

```sh
swift run shdong-mock-bridge             # prints a /dev/ttysNNN path, answers PINGs, logs frames
SHDONG_BRIDGE_PORT=/dev/ttysNNN swift run Shdong
```

Options: `--caps` (Caps Lock LED on), `--unmounted` (Sharer not enumerated), `--quiet`.

## Layout

| Path | What |
|---|---|
| `Sources/ShdongCore` | Pure logic: protocol frames/parser, messages, key map, modifier tracker, mouse mapping, scroll |
| `Sources/Shdong/Bridge` | Serial port (termios + DTR), IOKit hot-plug by VID/PID, `BridgeLink` heartbeat/RTT/status |
| `Sources/Shdong/Video` | Capture device pick, format selection, preview layer |
| `Sources/Shdong/Input` | Event tap, capture/release state machine, release hotkey, media keys |
| `Sources/Shdong/Viewer` | Video view + mouse forwarding, HUD |
| `Sources/Shdong/UI` | Status bar, settings, permissions onboarding |
| `Sources/ShdongMockBridge` | Pseudo-terminal stand-in for bridge + target |
| `Tests/ShdongCoreTests` | Frame vectors (shared with firmware), key map coverage, mouse math |

## Status

M1–M6 are written. Unit tests and the bridge heartbeat are verified (mock bridge); video and
real-board input await hardware. Per-milestone status: [PLAN.md §6](PLAN.md#6-milestones).

Known gaps:
- "No signal" is only shown when no capture device is present, not for a stick with no HDMI input.
- The window aspect lock includes the 26 pt status bar, so the video gets a thin letterbox.
- The click that starts capture is not forwarded to the Sharer (by design).
- With the ⌃⌥ hotkey, Ctrl reaches the Sharer briefly before `RELEASE_ALL` clears it.
