# shdong Controller — app plan

macOS app that runs on the **Controller Mac**. It shows the Sharer Mac's screen (from the HDMI
capture stick) and forwards keyboard and mouse to the **bridge board**, which passes them to the
**target board**, which types and clicks on the Sharer Mac.

```
┌──────────────────── Controller Mac ────────────────────┐
│                                                         │
│  Capture stick (UVC) ──▶ VideoPipeline ──▶ Viewer window│
│                                               │         │
│  Local keyboard/mouse ──▶ InputCapture ◀──────┘         │
│                               │                         │
│                          InputEncoder                   │
│                               │ frames (protocol.h)     │
│  Bridge board (CDC) ◀──── BridgeLink ──▶ heartbeat/PONG │
└─────────────────────────────────────────────────────────┘
```

---

## 1. Goals

**v1 (MVP)**
- Pick the capture device and bridge automatically, reconnect on hot-plug.
- Low-latency video in a window and fullscreen, keeping aspect ratio.
- Full keyboard forwarding, including Cmd‑Tab, Cmd‑Space, Cmd‑Q and Ctrl‑arrows, while "captured".
- Absolute mouse: clicking a spot in the viewer clicks the same spot on the Sharer Mac.
- Scroll (vertical and horizontal), left/right/middle buttons, drag.
- A clear capture/release hotkey so you never get locked out of your own Mac.
- Status: bridge connected, target alive, round-trip latency, Sharer Caps Lock.

**v2**
- HDMI audio passthrough.
- Paste-as-typing (send clipboard text as keystrokes).
- Media keys (volume, brightness, play/pause).
- Screenshot and recording.
- Keyboard layout handling for non-US Sharer layouts.
- Multiple kits (switch between several Sharer Macs).

**Later**
- Remote mode: stream video and input over the internet (the Controller Mac becomes a relay).
- Firmware update from inside the app.

**Out of scope:** clipboard *from* the Sharer and file transfer (there's no software on the Sharer).

---

## 2. Tech choices

| Area | Choice | Why |
|---|---|---|
| Language/UI | Swift 5.10+, **SwiftUI** shell + **AppKit** `NSView` for the viewer | SwiftUI for settings/status; AppKit for precise event handling |
| Min macOS | 13 Ventura | Modern SwiftUI and AVFoundation APIs; covers nearly all Apple Silicon Macs |
| Video | **AVFoundation** `AVCaptureSession` → `AVSampleBufferDisplayLayer` | Lowest latency path, no copies through CPU |
| Serial | POSIX `open/termios/read/write` on `/dev/cu.usbmodem*` | No dependencies, full control |
| Device discovery | **IOKit** matching notifications (VID 0x1209 / PID 0x0002) | Hot-plug events, finds the right port without guessing |
| Keyboard capture | **`CGEventTap`** (session level) | Only way to intercept Cmd‑Tab, Cmd‑Space and other system shortcuts |
| Distribution | Xcode project, **not sandboxed**, Developer ID signed + notarized | Event taps and raw serial access don't fit the App Sandbox |
| Dependencies | **None** | Everything above is in the OS |

---

## 3. Modules

> **As built:** a Swift package instead of an `.xcodeproj` (builds with only the Command Line
> Tools; Xcode opens `Package.swift` directly). Pure logic is split into `ShdongCore` so it can be
> unit tested; `scripts/bundle.sh` produces the signed `.app`. See [README.md](README.md).

```
controller-app/
├── Shdong.xcodeproj
├── Shdong/
│   ├── App/
│   │   ├── ShdongApp.swift          # @main, windows, menu commands
│   │   ├── AppState.swift           # ObservableObject: connection state, settings
│   │   └── Settings.swift           # UserDefaults-backed preferences
│   ├── Protocol/
│   │   ├── Frame.swift              # encode/decode, CRC-8 (mirror of protocol.h)
│   │   └── Messages.swift           # typed messages: key, mouseAbs, ping, pong, status...
│   ├── Bridge/
│   │   ├── SerialPort.swift         # termios wrapper, non-blocking read via DispatchSource
│   │   ├── DeviceWatcher.swift      # IOKit hot-plug for the bridge
│   │   └── BridgeLink.swift         # connect, send queue, heartbeat, PONG/RTT, STATUS
│   ├── Video/
│   │   ├── CaptureDeviceManager.swift  # list/auto-pick capture stick, hot-plug
│   │   ├── VideoPipeline.swift      # AVCaptureSession, format selection (1080p60 MJPEG)
│   │   └── AudioPipeline.swift      # (v2) HDMI audio → output device
│   ├── Input/
│   │   ├── KeyMap.swift             # macOS virtual keycode → HID usage table
│   │   ├── EventTap.swift           # CGEventTap install/enable/disable
│   │   ├── InputCapture.swift       # captured/released state machine, hotkey
│   │   ├── MouseMapper.swift        # view point → 0..32767 with letterbox handling
│   │   └── TypeOut.swift            # (v2) paste-as-typing
│   ├── Viewer/
│   │   ├── ViewerView.swift         # NSView hosting the display layer + tracking area
│   │   ├── ViewerWindow.swift       # fullscreen, aspect-locked resize
│   │   └── OverlayHUD.swift         # "Captured — press ⌃⌥ to release", status chip
│   ├── UI/
│   │   ├── StatusBarView.swift      # connection dots, RTT, Caps Lock
│   │   ├── SettingsView.swift
│   │   └── OnboardingView.swift     # permissions walkthrough
│   └── Resources/
│       ├── Info.plist               # NSCameraUsageDescription, NSMicrophoneUsageDescription
│       └── Shdong.entitlements
└── ShdongTests/
    ├── FrameTests.swift             # CRC + encode vectors shared with firmware
    ├── KeyMapTests.swift
    └── MouseMapperTests.swift
```

---

## 4. Component details

### 4.1 Protocol (`Frame.swift`, `Messages.swift`)
- Mirror `firmware/common/protocol.h` exactly: `[0xAA][type][len][payload][crc8]`, CRC‑8 poly 0x07.
- Typed enum:
  ```swift
  enum OutMessage { case key(usage: UInt8, down: Bool)
                    case mouseAbs(x: UInt16, y: UInt16, buttons: UInt8, wheel: Int8, pan: Int8)
                    case mouseRel(dx: Int16, dy: Int16, buttons: UInt8, wheel: Int8, pan: Int8)
                    case consumer(usage: UInt16, down: Bool)
                    case releaseAll, ping(token: UInt32) }
  enum InMessage  { case pong(token: UInt32, version: UInt8, leds: UInt8, mounted: Bool)
                    case status(leds: UInt8, mounted: Bool) }
  ```
- Streaming parser, same state machine as the firmware.
- Unit test against a known vector: key(0x04, down) → `aa0102040193` (already verified in C and Python).

### 4.2 Bridge link (`SerialPort`, `DeviceWatcher`, `BridgeLink`)
- `DeviceWatcher` uses `IOServiceAddMatchingNotification` for USB devices with the bridge VID/PID,
  then reads the `IOCalloutDevice` property to get `/dev/cu.usbmodemXXXX`.
- `SerialPort`: `open(O_RDWR | O_NOCTTY | O_NONBLOCK)`, raw mode via `cfmakeraw`, set DTR
  (this tells the bridge the app is connected; dropping it releases all keys on the Sharer).
- Reads via `DispatchSource.makeReadSource` → parser → `InMessage` published on the main actor.
- Writes on a serial `DispatchQueue`. Messages are tiny, so writes go out immediately.
- **Heartbeat:** `ping` every 250 ms (the firmware times out after 1 s). RTT = time to matching PONG.
- **Target state:** alive if a PONG arrived in the last 1 s. `mounted` and `leds` come from PONG/STATUS.
- Unplug: close port, set state, retry when `DeviceWatcher` sees it again.

### 4.3 Video (`CaptureDeviceManager`, `VideoPipeline`)
- Discover with `AVCaptureDevice.DiscoverySession(deviceTypes: [.external], mediaType: .video)`
  (`.externalUnknown` on macOS 13).
- Auto-pick: remember the last unique ID; otherwise prefer names containing "MS2130", "USB3 Video",
  "Capture"; otherwise ask.
- Pick the format: highest resolution at 60 fps (fall back to 30), prefer MJPEG/NV12 as offered.
  Set `activeFormat`, `activeVideoMin/MaxFrameDuration`.
- Lowest latency path: `AVCaptureVideoDataOutput` with `alwaysDiscardsLateVideoFrames = true`
  → enqueue each `CMSampleBuffer` into an `AVSampleBufferDisplayLayer` (set the
  `DisplayImmediately` attachment). This skips the extra buffering of `AVCaptureVideoPreviewLayer`.
  Start with the preview layer for the MVP, then switch and measure.
- Report the video's pixel size to `MouseMapper`.
- Watch for `AVCaptureDeviceWasConnected` / `WasDisconnected` and show "No signal" states.

### 4.4 Input capture (`EventTap`, `InputCapture`, `KeyMap`, `MouseMapper`)

**States**
```
Released ──(click in viewer / hotkey)──▶ Captured
Captured ──(release hotkey / window loses focus / app deactivates)──▶ Released
```
- **Released:** the local Mac behaves normally, nothing is forwarded.
- **Captured:** the event tap swallows keyboard events (returns `nil`) and forwards them; mouse events
  inside the viewer are forwarded; the local cursor is hidden over the video.
- On entering Released: send `releaseAll`.

**Release hotkey:** **⌃ + ⌥ (left Control + left Option) pressed together**, detected in the tap and
never forwarded. It's configurable. Also show it in the HUD whenever capture starts.

**Event tap**
- `CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
  eventsOfInterest: keyDown | keyUp | flagsChanged | systemDefined, ...)`.
- Requires **Accessibility** permission (`AXIsProcessTrustedWithOptions` prompt).
- Only active while Captured; disabled otherwise so the app never interferes when idle.
- Handle `tapDisabledByTimeout`: re-enable immediately. Keep the callback fast (just enqueue).

**Keyboard mapping (`KeyMap.swift`)**
- Table from macOS virtual keycodes (`kVK_*`, Carbon) to HID usage (Keyboard page 0x07).
  ~110 entries: letters, digits, punctuation, F1–F20, arrows, nav cluster, keypad, modifiers.
- Physical mapping, not characters: the Sharer's own layout decides what character appears,
  exactly like a real keyboard. This is correct for any layout as long as both Macs use the same one.
- Modifiers come through `flagsChanged`. Compare with the previous flags to decide down/up for each
  side (left/right Cmd, Opt, Ctrl, Shift are separate bits in the device-dependent flags).
- **Caps Lock:** macOS reports it as a state toggle. Send press + release on each change, and show
  the Sharer's real Caps Lock LED (from STATUS) in the status bar.
- **Fn / Globe:** not available in standard HID. Translate Fn+arrows etc. on the Controller side
  (the Controller's keycodes are already the result, e.g. Fn+← arrives as Home).
- Key repeat: ignore autorepeat keyDowns (`kCGKeyboardEventAutorepeat`); the Sharer Mac repeats by
  itself while the key is held.

**Media keys (v2):** `systemDefined` events subtype 8 → consumer usages (volume 0xE9/0xEA,
mute 0xE2, play/pause 0xCD, next 0xB5, prev 0xB6, brightness 0x6F/0x70).

**Mouse (`MouseMapper.swift`)**
- `ViewerView` uses an `NSTrackingArea` for moves and overrides `mouseDown/Up`, `rightMouseDown/Up`,
  `otherMouseDown/Up`, `*Dragged`, `scrollWheel`.
- Video is aspect-fit, so compute the video rect inside the view (letterbox/pillarbox).
  Map point → `x = (p.x - rect.minX) / rect.width * 32767`, flip Y (AppKit is bottom-left), clamp.
- Points outside the video rect are clamped (or ignored when Released).
- Rate: send at most one move per display refresh (~120 Hz) — coalesce in the app too.
- Scroll: accumulate `scrollingDeltaY/X`; trackpads give fine pixel deltas, so convert to
  wheel ticks with a configurable divisor and carry the remainder. Respect "natural scrolling":
  the Sharer applies its own setting, so send raw direction (invert using
  `isDirectionInvertedFromDevice`).
- Hide the local cursor while it's over the video in Captured mode (`NSCursor.hide/unhide`), since
  the Sharer draws its own cursor in the video.

### 4.5 Viewer UI
- One main window: video fills it, aspect-locked (`contentAspectRatio`), toolbar hidden in fullscreen.
- Status bar (bottom, hides in fullscreen): bridge ●, target ●, video ●, RTT, Caps Lock, video resolution/fps.
- HUD overlay: "Captured — ⌃⌥ to release", fades after 2 s; "No signal"; "Bridge not connected".
- Menu: View ▸ Fullscreen / Actual Size / Fit; Input ▸ Capture, Send Ctrl‑Alt‑Del-style combos
  (Cmd‑Opt‑Esc, Cmd‑Tab, Cmd‑Space), Release All; Devices ▸ pick capture device / bridge.
- Settings: release hotkey, scroll speed, preferred video format, show local cursor, auto-capture on click.

### 4.6 Permissions & onboarding
| Permission | Why | When asked |
|---|---|---|
| Camera | Reading the capture stick (it's a UVC "camera") | First launch, video start |
| Accessibility | Event tap to forward system shortcuts | First time you capture |
| Microphone (v2) | HDMI audio arrives as an audio input | When audio is enabled |

The onboarding screen shows each one with a ✓/✗ and an "Open System Settings" button,
re-checking when the app becomes active.

---

## 5. Latency budget and how to measure

| Stage | Target |
|---|---|
| Key/mouse → serial write | < 1 ms |
| USB CDC + UART + target → Sharer USB | ~2–3 ms |
| Sharer renders change | 8–16 ms |
| HDMI → MS2130 capture + MJPEG | 16–35 ms |
| USB 3 → decode → display layer | 8–16 ms |
| **Total glass‑to‑glass** | **~40–70 ms** |

Measure: a debug mode that sends a key while showing a timestamp, then detects the change in the
video frame (pixel diff in a small region) → log real end-to-end latency. Use this to compare
preview layer vs sample buffer layer and different capture formats.

---

## 6. Milestones

| # | Milestone | Done when | Est. | Status |
|---|---|---|---|---|
| M1 | Project skeleton + `Frame.swift` + tests | Tests pass against the firmware vector | 0.5 d | ✅ done |
| M2 | Bridge link: discovery, serial, heartbeat | Status shows "target alive, RTT x ms" with real boards | 1 d | 🟡 code done, verified with mock bridge; real boards pending |
| M3 | Video: device pick + preview in window | Sharer screen visible, aspect correct | 1 d | 🟡 code done; needs capture stick |
| M4 | Mouse: absolute move, click, drag, scroll | Can use the Sharer's Finder with the mouse | 1 d | 🟡 code done, frames checked with mock; needs target |
| M5 | Keyboard: event tap, KeyMap, modifiers, capture/release | Can type, Cmd‑Tab, Cmd‑Space on the Sharer; hotkey always releases | 1.5 d | 🟡 code done, frames checked with mock; needs target |
| M6 | Polish: fullscreen, HUD, status bar, onboarding, reconnect | Unplug/replug anything and it recovers by itself | 1.5 d | 🟡 code done; hot-plug untested on hardware |
| **MVP** | | | **~6–7 days** | |
| M7 | Low-latency video path + latency meter | Measured numbers, best path chosen | 1 d | ⬜ |
| M8 | Audio, paste-as-typing, media keys | | 1.5 d | ⬜ (media keys already done) |
| M9 | Signing, notarization, DMG | Installs on another Mac without warnings | 0.5 d | ⬜ (`scripts/bundle.sh` signs; notarization todo) |

M1 and M3 can be built and tested before the boards arrive (the capture stick alone is enough for M3).

---

## 7. Testing

- **Unit:** frame encode/decode vectors, CRC, KeyMap coverage (every `kVK_*` has a usage or is
  explicitly ignored), MouseMapper letterbox math (4:3 video in 16:9 view etc.).
- **Without hardware:** `shdong-mock-bridge` (pseudo-terminal via `openpty`) answers PINGs, toggles
  Caps Lock like a Sharer and logs every frame; run the app with `SHDONG_BRIDGE_PORT=<path>`.
  Unit tests: `scripts/test.sh` (needed with only the Command Line Tools; `swift test` with Xcode).
- **With hardware:** manual checklist — type all printable keys in TextEdit on the Sharer; every
  modifier combo; Cmd‑Tab cycling; login screen; Caps Lock LED; drag a window; trackpad and wheel
  scroll; unplug bridge mid-keypress (nothing stuck); unplug capture stick (No signal, recovers).

---

## 8. Risks

| Risk | Mitigation |
|---|---|
| Getting locked out while Captured | Hotkey handled first in the tap; auto-release on focus loss; tap disabled when not captured |
| Event tap disabled by the system under load | Handle `tapDisabledByTimeout`, keep callback minimal |
| Capture stick quirks (wrong formats, odd names) | Format picker in settings, remember choice per device ID |
| Video latency higher than expected | Sample buffer display path; try NV12 vs MJPEG; measure (M7) |
| Different keyboard layouts on the two Macs | Physical mapping by default; v2 "type by character" mode for paste |
| Secure input (password fields) on the Controller blocks the tap | Detect `IsSecureEventInputEnabled()` and warn in the HUD |
