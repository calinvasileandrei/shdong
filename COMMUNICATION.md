# shdong — Communication details

Everything that moves between the parts of the system: wiring, USB identities, the frame protocol,
HID reports, message sequences and timings. High-level view: [ARCHITECTURE.md](ARCHITECTURE.md).

Source of truth for the protocol: `firmware/common/protocol.h`.

---

## 1. Full data path

```
CONTROLLER MAC                                  KIT                                    SHARER MAC
──────────────                                  ───                                    ──────────

 keyboard / mouse
       │ NSEvent / CGEventTap
       ▼
 ┌─────────────┐
 │ InputCapture│ keycode→HID usage, point→0..32767
 └──────┬──────┘
        │ OutMessage
        ▼
 ┌─────────────┐  frame bytes   ┌──────────────────────────────┐
 │ BridgeLink  │───────────────▶│ BOARD C (bridge)             │
 │  serial     │  USB CDC       │ CDC RX ──▶ uart_write ──┐    │
 │  /dev/cu.*  │◀───────────────│ CDC TX ◀── RX ring ◀─┐  │    │
 └─────────────┘                └──────────────────────┼──┼────┘
                                                       │  │  UART 1 Mbaud 8N1
                                                       │  │  GP0=TX GP1=RX
                                ┌──────────────────────┼──┼────┐
                                │ BOARD T (target)     │  ▼    │
                                │   UART IRQ ─▶ RX ring (1 KB) │
                                │        ▼                     │
                                │   frame parser (CRC check)   │
                                │        ▼                     │
                                │   state: modifiers, 6 keys,  │
                                │          buttons, consumer   │
                                │        ▼                     │      USB HID
                                │   report queue (64) ─────────┼──────────────▶ keyboard + mouse
                                │        ▲                     │◀────────────── LED output report
                                │   PONG / STATUS ─▶ uart_write│               (Caps Lock)
                                └──────────────────────────────┘

 ┌─────────────┐   UVC (USB 3)   ┌──────────────────┐   HDMI                   display output
 │VideoPipeline│◀────────────────│ capture stick    │◀─────────────────────────────────
 │ AVFoundation│  MJPEG/YUV      │ MS2130 (EDID)    │  TMDS + EDID/DDC
 └──────┬──────┘                 └──────────────────┘
        ▼
   viewer window
```

---

## 2. Physical links

| Link | Medium | Settings |
|---|---|---|
| Controller ↔ Board C | USB 2.0 Full Speed (12 Mbit/s) | CDC ACM, 64-byte bulk packets |
| Board C ↔ Board T | 3 wires (TX, RX, GND) | UART0, **1 000 000 baud, 8N1**, no flow control |
| Board T ↔ Sharer | USB 2.0 Full Speed | 2 HID interfaces, interrupt IN, 1 ms polling |
| Sharer → capture stick | HDMI | Stick's EDID decides offered modes |
| Capture stick → Controller | USB 3.0 (MS2130) | UVC, MJPEG or YUV |

### Wiring

```
 Board T (RP2040-Zero)              Board C (RP2040-Zero)
 ┌──────────────┐                   ┌──────────────┐
 │ GP0  UART TX ├───────────────────▶ GP1  UART RX │
 │ GP1  UART RX ◀───────────────────┤ GP0  UART TX │
 │ GND          ├───────────────────┤ GND          │
 │ 5V  (unused) │   not connected   │ 5V  (unused) │
 └──────┬───────┘                   └──────┬───────┘
        │ USB-C → Sharer                   │ USB-C → Controller
```

- RX pins have the internal pull-up enabled, so an unplugged cable reads as idle, not noise.
- Optional isolation: `TX ─▶ ADuM1201 ─▶ RX` in both directions, each side powered from its own board's 3V3.

---

## 3. USB identities

### Board T — what the Sharer sees

| Field | Value |
|---|---|
| VID / PID | `0x1209` / `0x0001` (pid.codes test IDs, replace before shipping) |
| Manufacturer / Product | "Generic" / "USB Keyboard and Mouse" (`target/config.h`) |
| Serial | RP2040 unique flash ID |
| Config attributes | Bus powered, **remote wakeup**, 100 mA |

| Interface | Class / Subclass / Protocol | Endpoint | Reports |
|---|---|---|---|
| 0 — keyboard | HID / Boot / Keyboard | `0x81` IN, 16 B, 1 ms | 8-byte boot report, no report ID; LED OUT report |
| 1 — mouse | HID / None / None | `0x82` IN, 16 B, 1 ms | ID 1 abs mouse, ID 2 rel mouse, ID 3 consumer |

The keyboard uses the **boot protocol**, so it also works in places with a minimal HID stack
(login window, FileVault unlock, firmware screens on Intel Macs).

### Board C — what the Controller sees

| Field | Value |
|---|---|
| VID / PID | `0x1209` / `0x0002` |
| Manufacturer / Product | "shdong" / "shdong bridge" |
| Class | Misc / IAD → CDC ACM (notification EP `0x81`, data OUT `0x02`, IN `0x82`) |
| macOS device | `/dev/cu.usbmodem<serial>` |

The app finds the bridge by **VID/PID**, never by guessing port names.

---

## 4. Frame format

```
 byte:   0        1        2        3 … 3+len-1      3+len
       ┌──────┬────────┬────────┬────────────────┬────────┐
       │ 0xAA │  type  │  len   │    payload     │  crc8  │
       └──────┴────────┴────────┴────────────────┴────────┘
          SOF            0..32     len bytes        CRC over type, len, payload
```

| Property | Value |
|---|---|
| Start of frame | `0xAA` |
| Max payload | 32 bytes (max frame 36) |
| CRC | CRC-8, polynomial `0x07`, init `0x00`, no reflection, no final XOR |
| Byte order | Little-endian for multi-byte fields |
| Resync | Parser drops back to waiting for `0xAA` on bad length or CRC |

### Parser state machine (same in C, Python and Swift)

```
            0xAA                any               len ≤ 32, len > 0
 ┌─────┐ ─────────▶ ┌──────┐ ─────────▶ ┌─────┐ ─────────────────▶ ┌─────────┐
 │ SOF │            │ TYPE │            │ LEN │                    │ PAYLOAD │
 └─────┘ ◀───────── └──────┘            └─────┘                    └────┬────┘
    ▲    other byte                       │ │ len == 0                  │ idx == len
    │                                     │ └────────────┐              ▼
    │       len > 32 (drop)               │              └─────▶ ┌───────┐
    ├─────────────────────────────────────┘                      │  CRC  │
    │                                                            └───┬───┘
    └───────────── always return to SOF; frame valid if crc matches ─┘
```

### Test vector

`KEY(usage=0x04 'A', pressed=1)` → `AA 01 02 04 01 93`

Verified identical in C (`protocol.c`), Python (`shd.py`) and Swift (`FrameTests.firmwareVector`).

---

## 5. Message catalog

### Controller → Target

| Type | Name | Payload (offset: field) | Size |
|---|---|---|---|
| `0x01` | `KEY` | 0: u8 HID usage (page 0x07) · 1: u8 pressed (0/1) | 2 |
| `0x02` | `MOUSE_ABS` | 0: u16 x · 2: u16 y (0..32767) · 4: u8 buttons · 5: i8 wheel · 6: i8 pan | 7 |
| `0x03` | `MOUSE_REL` | 0: i16 dx · 2: i16 dy · 4: u8 buttons · 5: i8 wheel · 6: i8 pan | 7 |
| `0x04` | `CONSUMER` | 0: u16 usage (page 0x0C) · 2: u8 pressed | 3 |
| `0x05` | `RELEASE_ALL` | — | 0 |
| `0x10` | `PING` | 0: u32 token | 4 |

**Buttons bitmask:** bit0 left, bit1 right, bit2 middle, bit3 back, bit4 forward.

**Modifiers** are sent as ordinary `KEY` frames with usages `0xE0`–`0xE7`:

| Usage | Key | Usage | Key |
|---|---|---|---|
| `0xE0` | Left Ctrl | `0xE4` | Right Ctrl |
| `0xE1` | Left Shift | `0xE5` | Right Shift |
| `0xE2` | Left Option | `0xE6` | Right Option |
| `0xE3` | Left Cmd | `0xE7` | Right Cmd |

### Target → Controller

| Type | Name | Payload | Size | Sent when |
|---|---|---|---|---|
| `0x11` | `PONG` | 0: u32 token (echo) · 4: u8 proto version · 5: u8 kbd LEDs · 6: u8 USB mounted | 7 | Reply to every `PING` |
| `0x12` | `STATUS` | 0: u8 kbd LEDs · 1: u8 USB mounted | 2 | Sharer mounts/unmounts Board T, or LEDs change |

**LED bits:** bit0 Num Lock, bit1 Caps Lock, bit2 Scroll Lock.

---

## 6. HID reports (Board T → Sharer)

### Keyboard — interface 0, no report ID (8 bytes)

```
 ┌───────────┬──────────┬──────┬──────┬──────┬──────┬──────┬──────┐
 │ modifiers │ reserved │ key1 │ key2 │ key3 │ key4 │ key5 │ key6 │
 └───────────┴──────────┴──────┴──────┴──────┴──────┴──────┴──────┘
   bit0..7 = E0..E7       up to 6 keys held at once (6-key rollover)
```

### Absolute mouse — interface 1, report ID 1 (7 bytes after ID)

```
 ┌────┬─────────┬─────────┬─────────┬───────┬─────┐
 │ ID │ buttons │ x (u16) │ y (u16) │ wheel │ pan │
 │ 01 │ 5 bits  │ 0..32767│ 0..32767│  i8   │ i8  │
 └────┴─────────┴─────────┴─────────┴───────┴─────┘
```
The Sharer maps 0..32767 onto its full screen area. If it has several displays, it covers
the whole combined desktop.

### Relative mouse — interface 1, report ID 2 (5 bytes after ID)

```
 ┌────┬─────────┬──────┬──────┬───────┬─────┐
 │ ID │ buttons │ dx i8│ dy i8│ wheel │ pan │
 │ 02 │         │      │      │  i8   │ i8  │
 └────┴─────────┴──────┴──────┴───────┴─────┘
```
`MOUSE_REL` frames with |dx| or |dy| > 127 are split into several reports.

### Consumer — interface 1, report ID 3 (2 bytes after ID)

```
 ┌────┬──────────────┐
 │ ID │ usage (u16)  │   0 = released
 │ 03 │              │
 └────┴──────────────┘
```
Common usages: `0xE9` volume up, `0xEA` volume down, `0xE2` mute, `0xCD` play/pause,
`0xB5` next, `0xB6` previous, `0x6F` brightness up, `0x70` brightness down.

### Keyboard LED output report (Sharer → Board T)

1 byte, same bits as the LED field above. Board T forwards it as a `STATUS` frame.

---

## 7. Sequences

### 7.1 Startup and connect

```
 Controller app          Board C              Board T              Sharer
      │                     │                    │                    │
      │                     │                    │◀── USB enumerate ──│ plug in
      │                     │                    │─── STATUS(mounted=1) ─▶ (UART, goes nowhere
      │                     │                    │                    │      until app connects)
      │◀─ IOKit: bridge appeared (VID/PID)        │                    │
      │── open /dev/cu.*, set DTR ─▶│             │                    │
      │── PING(t) ─────────▶│── bytes ──────────▶│                    │
      │                     │◀── PONG(t,v1,leds,mounted) ─────────────│
      │◀── PONG ────────────│                    │                    │
      │  status: bridge ● target ● RTT 2 ms      │                    │
```

### 7.2 Key press (e.g. Cmd+Space)

```
 App (event tap)          Board C          Board T                         Sharer
      │ flagsChanged Cmd↓    │                │                                 │
      │── KEY(E3,1) ────────▶│───────────────▶│ mods=08 → queue [08 00 00…]      │
      │ keyDown Space        │                │                                 │
      │── KEY(2C,1) ────────▶│───────────────▶│ keys=[2C] → queue [08 00 2C…]    │
      │                      │                │── report ──────────────────────▶│ Spotlight opens
      │ keyUp Space          │                │── report ──────────────────────▶│
      │── KEY(2C,0) ────────▶│───────────────▶│ keys=[] → queue [08 00 00…]      │
      │ flagsChanged Cmd↑    │                │                                 │
      │── KEY(E3,0) ────────▶│───────────────▶│ mods=00 → queue [00 00 00…]      │
      │                      │                │── reports ─────────────────────▶│
```
Each change produces its own queued report, so a fast tap is never lost.

### 7.3 Mouse move and click

```
 App (viewer)                   Board T                                   Sharer
   │ mouseMoved (120 Hz)           │                                         │
   │── MOUSE_ABS(x1,y1,0) ────────▶│ queue: [abs x1,y1]                      │
   │── MOUSE_ABS(x2,y2,0) ────────▶│ same buttons → overwrite: [abs x2,y2]   │  coalesced
   │                               │── report abs x2,y2 ────────────────────▶│ cursor jumps there
   │ mouseDown                     │                                         │
   │── MOUSE_ABS(x2,y2,1) ────────▶│ buttons changed → new entry             │
   │ mouseUp                       │                                         │
   │── MOUSE_ABS(x2,y2,0) ────────▶│ buttons changed → new entry             │
   │                               │── report (down) ── report (up) ────────▶│ click
```
Rule: a move merges into the last queued abs report only if buttons are equal and neither has
wheel/pan. Button changes and scrolls always get their own report.

### 7.4 Heartbeat and liveness

```
 App                                Board T
  │── PING(t1) ───────────────────────▶│
  │◀────────────────── PONG(t1,…) ─────│   RTT = now - send time of t1
  │        … every 250 ms …            │
  │── PING(t2) ─────────────────────X  │   cable pulled
  │   no PONG for 1 s → "target offline"│
  │                                    │   no frame for 1 s + something held → release_all()
```

### 7.5 Caps Lock LED

```
 App              Board T                      Sharer
  │── KEY(39,1) ──▶│── report ────────────────▶│ toggles Caps Lock
  │── KEY(39,0) ──▶│── report ────────────────▶│
  │                │◀── LED OUT report (0x02) ─│
  │◀─ STATUS(leds=0x02, mounted=1) ────────────│
  │  status bar shows ⇪ on                     │
```

### 7.6 Sleep and wake

```
 App                 Board T                               Sharer
  │                     │◀──────── USB suspend ────────────│ goes to sleep
  │── KEY(…) ──────────▶│ queued; bus suspended            │
  │                     │── remote wakeup (max 1 / 500 ms) ▶│ wakes up
  │                     │◀──────── USB resume ─────────────│
  │                     │── queued reports ───────────────▶│
```
If Board T is not mounted at all (Sharer off or unplugged), the queue is cleared instead.

### 7.7 Three stuck-key safety nets

```
 ┌──────────────────────────┬───────────────────────────┬───────────────────────────────┐
 │ Event                    │ Who acts                  │ Action                        │
 ├──────────────────────────┼───────────────────────────┼───────────────────────────────┤
 │ User releases capture    │ App                       │ sends RELEASE_ALL             │
 │ (⌃⌥, focus lost)         │                           │                               │
 │ App quits / crashes,     │ Board C                   │ DTR drop → sends RELEASE_ALL  │
 │ port closed              │ (tud_cdc_line_state_cb)   │ over UART                     │
 │ Bridge unplugged,        │ Board T                   │ no valid frame for 1 s while  │
 │ wires cut, anything else │                           │ held → release_all()          │
 └──────────────────────────┴───────────────────────────┴───────────────────────────────┘
```

---

## 8. Timing and capacity

### Constants

| Constant | Value | Where |
|---|---|---|
| UART baud | 1 000 000 | `SHD_LINK_BAUD` |
| App PING interval | 250 ms | app |
| Target link timeout | 1000 ms | `SHD_LINK_TIMEOUT_MS` |
| App "target offline" | 1000 ms without PONG | app |
| Remote wakeup retry | 500 ms | `target/main.c` |
| UART RX ring | 1024 bytes per board | `common/link.c` |
| HID report queue | 64 entries | `target/main.c` |
| HID polling interval | 1 ms | descriptors |

### Capacity

| | Value |
|---|---|
| UART throughput | ~100 KB/s (10 bits per byte) |
| `MOUSE_ABS` frame | 11 bytes → ~110 µs on the wire |
| Max frames/s on UART | ~9 000 |
| HID reports/s to Sharer | up to 1 000 per interface |
| App mouse rate | ~120/s (one per display refresh) |

The link runs at about **1–2 %** load during normal use, with plenty of room for audio-control,
gamepad or storage messages later.

### Input latency (Controller key → Sharer receives HID report)

| Step | Typical |
|---|---|
| Event tap → serial write | < 0.5 ms |
| USB CDC to Board C (1 ms frames) | ≤ 1 ms |
| UART, 6-byte KEY frame | 0.06 ms |
| Board T parse + queue | < 0.05 ms |
| USB HID poll by Sharer | ≤ 1 ms |
| **Total** | **~1–3 ms** |

Video is the slow part (~40–70 ms glass-to-glass, see `controller-app/PLAN.md` §5).

---

## 9. Video path details

```
 Sharer GPU ──HDMI──▶ MS2130 ──USB 3 UVC──▶ AVCaptureSession ──▶ display layer ──▶ viewer
               │         │                       │
               │         └─ EDID: advertises the modes the stick can capture
               │            (Sharer picks e.g. 1920×1080@60 and treats it as a monitor)
               └─ HDCP content (DRM video) shows black: expected
```

| Step | Detail |
|---|---|
| Mode | The Sharer drives the stick like a monitor. Mirror or extend in Sharer's Display settings |
| Format | App picks the highest resolution at 60 fps; MJPEG preferred at 1080p60 over USB 3 |
| Mouse mapping | App knows the video size and the letterboxed rect in the window → 0..32767 |
| Audio (v2) | Stick exposes HDMI audio as a USB audio input → app plays it to an output device |

When the Sharer **extends** its desktop onto the stick, the absolute mouse covers the whole
combined desktop, but the video only shows the extended display. Use **mirror** mode, or make the
stick the only display, so clicks line up with the picture.

---

## 10. Versioning and extension

- `PONG` carries `proto_version` (currently **1**). The app warns on a mismatch and suggests reflashing.
- New messages: pick an unused type, add it to `protocol.h`, handle it in Board T and the app.
  Board C needs no change.
- Unknown types are ignored by Board T, so a newer app can talk to an older target.
- Reserved ranges: `0x01–0x0F` input, `0x10–0x1F` link/status, `0x20–0x2F` future
  (storage, gamepad), `0x30+` vendor/experimental.
