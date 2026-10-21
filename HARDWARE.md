# shdong — Hardware kit and assembly

What to buy and how to connect it. Background: [ARCHITECTURE.md](ARCHITECTURE.md).
Pin-level and protocol details: [COMMUNICATION.md](COMMUNICATION.md) §2–3.

```
 SHARER MAC                                                          CONTROLLER MAC
 HDMI out ──HDMI cable──▶ [capture stick] ──USB 3──────────────────▶ USB 3 port
 USB port ◀──USB-C cable── [Board T] ═3 wires═ [Board C] ──USB-C───▶ USB port
```

---

## 1. Bill of materials

### Required

| # | Part | Qty | Notes |
|---|---|---|---|
| 1 | **RP2040-Zero** (Waveshare or clone) | 2 | One becomes Board T (target), one Board C (bridge). Any RP2040 board works if GP0/GP1 are exposed; pin numbers below assume the Zero |
| 2 | **HDMI capture stick, MS2130 chip** | 1 | USB 3, 1080p60. Listings often say "USB 3.0 HDMI video capture, 4K input 1080p60". Check "MS2130" in the description |
| 3 | HDMI cable | 1 | Sharer → capture stick. Short is fine |
| 4 | USB-C ↔ USB cable (data, not charge-only) | 2 | Board T → Sharer, Board C → Controller. Pick the other end to match each Mac's ports |
| 5 | Jumper wires, female–female (Dupont) | 3 | TX, RX, GND between the boards. ~10–20 cm |
| 6 | 2.54 mm pin headers | 1 strip | The Zero ships without headers soldered; you need at least GP0, GP1 and GND on each board |

### Depending on your Macs

| Part | When you need it |
|---|---|
| USB-C → HDMI adapter (or USB-C hub with HDMI) | Sharer Mac has no HDMI port (most MacBook Air/Pro without HDMI) |
| USB-C → USB-A adapter/hub **with USB 3 (5 Gbps)** | Controller Mac has only USB-C; the capture stick usually has a USB-A plug. A USB 2 adapter caps video at ~1080p30 MJPEG |
| USB-C → USB-A adapter | Either Mac has only USB-C and your board cables are USB-A |

### Optional

| Part | Why |
|---|---|
| **ADuM1201BRZ** or **ADuM1201CRZ** digital isolator + 2× 100 nF capacitors | Separates the two Macs' grounds (avoids ground-loop hum/noise when both are charging from different outlets). **Not** the `AR` grade: it's limited to 1 Mbps, too close to the link's 1 Mbaud |
| Small perfboard / breadboard | To mount the isolator |
| MS2109 capture stick | Cheaper fallback: USB 2, 1080p30, more latency |
| Small enclosure / heat-shrink | Keep the two boards and wires together as one "kit" |

### Tools

Soldering iron + solder (for the headers), a Mac with `cmake` + ARM toolchain to build firmware
(see [firmware/README.md](firmware/README.md)).

---

## 2. Prepare the boards

1. **Solder headers** on both RP2040-Zero boards — at minimum the pins **GP0, GP1 and GND**.
2. **Build the firmware:**
   ```sh
   cd firmware
   cmake -B build && cmake --build build -j
   ```
   Outputs: `build/target/shdong_target.uf2` and `build/bridge/shdong_bridge.uf2`.
3. **Flash Board T:** hold **BOOT**, plug it into any Mac, release. A drive `RPI-RP2` appears;
   drag `shdong_target.uf2` onto it. It reboots by itself.
4. **Flash Board C** the same way with `shdong_bridge.uf2`.
5. **Label them** (tape, marker). They look identical and swapping them is the most common mistake.

---

## 3. Wire the two boards

Crossed TX/RX plus a shared ground. **Do not connect 5V or 3V3** — each board is powered by its own Mac.

```
 Board T (target)                  Board C (bridge)
 ┌──────────────┐                  ┌──────────────┐
 │ GP0  (TX) ●──┼──── wire 1 ─────▶┼──● GP1  (RX) │
 │ GP1  (RX) ●◀─┼──── wire 2 ──────┼──● GP0  (TX) │
 │ GND       ●──┼──── wire 3 ──────┼──● GND       │
 │ 5V / 3V3     │  NOT connected   │ 5V / 3V3     │
 └──────┬───────┘                  └──────┬───────┘
        USB-C → Sharer Mac                USB-C → Controller Mac
```

| Wire | From | To |
|---|---|---|
| 1 | Board T **GP0** | Board C **GP1** |
| 2 | Board C **GP0** | Board T **GP1** |
| 3 | Board T **GND** | Board C **GND** |

Keep wires short (under ~30 cm); 1 Mbaud is happy over jumper wires at that length.

### Optional: with the ADuM1201 isolator

Each side of the chip is powered by the board on that side (3V3 of that board), and each side gets
its own 100 nF capacitor between VDD and GND, close to the chip.

```
              ADuM1201 (top view)
 Board T side            ┌──────┐            Board C side
 3V3  ───────── 1 VDD1   │●     │  VDD2 8 ─────── 3V3
 GP1 (RX) ◀──── 2 VOA    │      │  VOB  7 ──────▶ GP1 (RX)
 GP0 (TX) ────▶ 3 VIB    │      │  VIA  6 ◀────── GP0 (TX)
 GND  ───────── 4 GND1   │      │  GND2 5 ─────── GND
                         └──────┘
```

- Channel B carries T → C (`VIB` → `VOB`), channel A carries C → T (`VIA` → `VOA`).
- With the isolator, **do not** connect the two GNDs directly — isolation is the point.
- Here, connecting 3V3 is correct: each board powers only its own side.

---

## 4. Connect to the Macs

1. **Board T → Sharer Mac** USB port. The Sharer sees "USB Keyboard and Mouse".
   The first time, macOS may open **Keyboard Setup Assistant**: quit it, or press the key it asks for.
2. **Board C → Controller Mac** USB port. It appears as `/dev/cu.usbmodem…` ("shdong bridge").
3. **Sharer HDMI out → capture stick** (through a USB-C→HDMI adapter if needed).
4. **Capture stick → Controller Mac**, on a **USB 3** port (blue tab on USB-A, or any USB-C port
   through a USB 3 adapter).
5. On the **Sharer**, open System Settings ▸ Displays and set the stick's display to **mirror**
   the main display (or make it the only display). Otherwise the mouse covers the whole desktop
   while the video shows only one screen, and clicks won't line up.

---

## 5. Check it works (in order)

| Step | Command / action | Expected |
|---|---|---|
| 1 | `python3 firmware/tools/shd.py ping` on the Controller | PONG with `mounted=1`. Tests bridge, wires and target together |
| 2 | `python3 firmware/tools/shd.py type "hello"` (TextEdit focused on the Sharer) | "hello" appears on the Sharer |
| 3 | `python3 firmware/tools/shd.py move 0.5 0.5` | Sharer cursor jumps to screen center |
| 4 | Open the capture stick in QuickTime (File ▸ New Movie Recording, pick the stick) | Sharer's screen visible |
| 5 | Start the controller app (`controller-app/README.md`) | Status bar: Bridge ●, Target ●, Video ● and an RTT in ms |

### Troubleshooting

| Symptom | Likely cause |
|---|---|
| `shdong bridge not found` | Board C not flashed with the bridge firmware, boards swapped, or a charge-only cable |
| Bridge found, no PONG | TX/RX not crossed, GND missing, or Board T not flashed / not powered (plug it into the Sharer) |
| PONG with `mounted=0` | Board T has power but the Sharer hasn't enumerated it: try another port/cable, or wake the Sharer |
| Video black | Sharer's display output is off or asleep; HDCP content (DRM video) is always black |
| Video choppy / 30 fps max | Stick on a USB 2 port or adapter, or an MS2109 stick |
| Clicks land in the wrong place | Sharer is extending, not mirroring, onto the stick (step 4.5) |
| Keyboard Setup Assistant keeps appearing | Normal on first plug-in; complete or dismiss it once |
