# shdong — Architecture

shdong lets one Mac (the **Controller**) see and control another Mac (the **Sharer**) through
plug-in hardware. The Sharer runs **no software**: it only sees a monitor, a keyboard and a mouse.

Byte-level details, sequences and timings: [COMMUNICATION.md](COMMUNICATION.md).
Parts list and assembly: [HARDWARE.md](HARDWARE.md).

---

## System overview

```
        SHARER MAC                         THE KIT                           CONTROLLER MAC
 ┌──────────────────────┐                                              ┌──────────────────────┐
 │                      │  HDMI   ┌────────────────────┐   USB 3       │                      │
 │  display output ─────┼────────▶│ HDMI capture stick │──────────────▶│  Controller app      │
 │                      │         │ (MS2130)           │   (UVC video) │  ├─ video viewer     │
 │                      │         └────────────────────┘               │  ├─ input capture    │
 │                      │                                              │  └─ bridge link      │
 │                      │  USB    ┌─────────┐  UART   ┌─────────┐ USB  │                      │
 │  keyboard + mouse ◀──┼─────────│ Board T │◀───────▶│ Board C │◀─────┼──────────────────────│
 │                      │  (HID)  │ target  │ 3 wires │ bridge  │(CDC) │                      │
 └──────────────────────┘         └─────────┘         └─────────┘      └──────────────────────┘
   sees: monitor,                  RP2040              RP2040            sees: camera,
   keyboard, mouse                                                       serial port
```

There are two independent paths:

| Path | Direction | Carries | Hardware |
|---|---|---|---|
| **Video** | Sharer → Controller | Screen image (and later audio) | HDMI capture stick, no firmware of ours |
| **Input** | Controller → Sharer | Keys, mouse, media keys | Board C → Board T, our firmware |

A small **status** channel runs back along the input path (Target → Controller): heartbeat replies,
USB connection state, Caps Lock LED.

---

## Components

### 1. HDMI capture stick (off the shelf)
- Toward the Sharer it acts as a **monitor**: it has its own EDID listing supported resolutions.
- Toward the Controller it acts as a **UVC camera**: standard video class, no driver needed.
- MS2130: USB 3, 1080p60, MJPEG/YUV. An MS2109 (USB 2, 1080p30) works as a cheaper fallback.

### 2. Board T — target (`firmware/target`)
- RP2040-Zero plugged into the Sharer.
- USB device with two HID interfaces: a **boot keyboard** and a **mouse/consumer** interface
  (absolute mouse, relative mouse, media keys).
- Receives frames over UART, keeps the keyboard/mouse state, queues HID reports, sends them to the Sharer.
- Safety: releases everything if the link goes quiet for 1 s while something is held.
- Wakes the Sharer from sleep when input arrives (USB remote wakeup).

### 3. Board C — bridge (`firmware/bridge`)
- RP2040-Zero plugged into the Controller.
- USB serial device (CDC) named "shdong bridge".
- A transparent byte pipe between USB and UART. It doesn't parse frames.
- When the app closes the port (DTR drops), it sends `RELEASE_ALL` to Board T.

### 4. Board-to-board link
- 3 wires: TX, RX, GND (crossed). UART 1 Mbaud, 8N1.
- Optional ADuM1201 isolator to separate the two Macs' grounds.

### 5. Controller app (`controller-app`)
- macOS app (Swift, SwiftUI + AppKit), built as a Swift package. Plan: [controller-app/PLAN.md](controller-app/PLAN.md),
  build/run: [controller-app/README.md](controller-app/README.md).
- **Video pipeline:** AVFoundation reads the capture stick and shows it in the viewer.
- **Input capture:** an event tap and viewer mouse events become protocol frames.
- **Bridge link:** finds the bridge by USB VID/PID, sends frames, pings every 250 ms, reads replies.

### 6. Shared protocol (`firmware/common/protocol.h`)
- One frame format used end to end: `[0xAA][type][len][payload][crc8]`.
- Implemented in C (firmware), Python (`firmware/tools/shd.py`) and Swift (`controller-app/Sources/ShdongCore`).

---

## Layers

```
 ┌───────────────────────────────────────────────────────────────┐
 │ App layer        viewer · capture/release · key & mouse mapping│  Controller app
 ├───────────────────────────────────────────────────────────────┤
 │ Protocol layer   frames: KEY, MOUSE_ABS, PING/PONG, STATUS...  │  app + Board T
 ├───────────────────────────────────────────────────────────────┤
 │ Transport layer  USB CDC (Mac↔C) · UART (C↔T)                  │  Board C is a pipe
 ├───────────────────────────────────────────────────────────────┤
 │ Device layer     USB HID reports to the Sharer                 │  Board T
 └───────────────────────────────────────────────────────────────┘
```

The protocol travels unchanged from the app to Board T. Board C only moves bytes, so new message
types only need changes in the app and in Board T.

---

## Design principles

1. **Nothing installed on the Sharer.** It only sees standard USB HID and a standard display.
2. **Dumb hardware, smart app.** The Controller Mac does the heavy work (video decoding, UI).
   The boards stay tiny, cheap and easy to reason about.
3. **Never leave a key stuck.** There are three independent release mechanisms: the app sends
   `RELEASE_ALL` when capture ends, the bridge sends it when the port closes, and the target releases
   everything itself after 1 s of silence.
4. **No lost events.** Each key or button change becomes its own HID report. Only pure mouse moves
   are merged.
5. **One protocol, written down once.** `protocol.h` is the source of truth; other languages mirror it
   and are tested against the same byte vectors.
6. **No dependencies.** Pico SDK + TinyUSB on the boards; only Apple frameworks in the app.

---

## Repository layout

```
shdong/
├── ARCHITECTURE.md          # this file
├── COMMUNICATION.md         # detailed diagrams, byte formats, sequences, timings
├── HARDWARE.md              # parts list, wiring, assembly, first checks
├── firmware/
│   ├── common/              # protocol + UART link (shared by both boards)
│   ├── target/              # Board T: USB HID
│   ├── bridge/              # Board C: USB CDC ↔ UART
│   └── tools/shd.py         # terminal test tool
└── controller-app/
    ├── PLAN.md              # app plan and milestones
    ├── README.md            # build, run, test, mock bridge
    ├── Package.swift        # Swift package (open in Xcode, or build with the CLT)
    ├── Sources/ShdongCore/  # protocol, key map, mouse math (pure, unit tested)
    ├── Sources/Shdong/      # the app: bridge, video, input, viewer, UI
    ├── Sources/ShdongMockBridge/  # fake bridge + target on a pseudo-terminal
    ├── Tests/               # swift-testing unit tests
    └── scripts/             # bundle.sh (.app), test.sh
```

---

## Evolution

| Stage | Change |
|---|---|
| **Now** | Off-the-shelf capture stick + two RP2040-Zero boards + 3 wires. App MVP (M1–M6) written; hardware testing pending |
| **Next** | Audio passthrough, media keys, paste-as-typing (app + firmware only) |
| **Product** | One custom PCB: MS2130 + RP2040 (or RP2350) in a single dongle. Same protocol |
| **Remote** | Controller app relays video and input over the internet; the kit is unchanged |
