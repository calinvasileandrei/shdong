# shdong firmware

Two RP2040-Zero boards linked by 3 wires:

- **target** (`shdong_target.uf2`) plugs into the **Sharer Mac** and shows up as a USB keyboard + mouse.
- **bridge** (`shdong_bridge.uf2`) plugs into the **Controller Mac** and shows up as a USB serial port.

```
Controller app ──USB serial──▶ bridge ──UART 1 Mbaud──▶ target ──USB HID──▶ Sharer Mac
```

## Wiring

```
target          bridge
GP0 (TX) ─────▶ GP1 (RX)
GP1 (RX) ◀───── GP0 (TX)
GND ─────────── GND
```

Do not connect 5V/3V3 between boards: each one is powered by its own Mac.
Optional: an ADuM1201 isolator on TX/RX if both Macs are charging from different outlets.

## Build

```sh
brew install cmake
brew install --cask gcc-arm-embedded

cd firmware
cmake -B build            # downloads the Pico SDK if PICO_SDK_PATH is not set
cmake --build build -j
```

Outputs: `build/target/shdong_target.uf2` and `build/bridge/shdong_bridge.uf2`.

## Flash

Hold **BOOT** on the board, plug it in, release. It mounts as `RPI-RP2`; drag the `.uf2` onto it.

## Test without the app

```sh
pip3 install pyserial
python3 tools/shd.py ping              # checks bridge + wires + target
python3 tools/shd.py type "hello"      # types on the Sharer Mac
python3 tools/shd.py key cmd+space
python3 tools/shd.py move 0.5 0.5
python3 tools/shd.py click
```

The first time the target is plugged in, macOS may open **Keyboard Setup Assistant**
(it does this for any keyboard it doesn't recognise). Quit it, or press the key it asks for once.

## Protocol

See `common/protocol.h`. Frames are `[0xAA][type][len][payload][crc8]`.
The controller app should send `PING` every ~250 ms; the target releases all keys and
buttons if it hears nothing for 1 s while something is held.
