#!/usr/bin/env python3
"""Test tool: drive the target board from the Controller Mac's terminal.

  pip3 install pyserial
  python3 tools/shd.py ping
  python3 tools/shd.py type "hello world"
  python3 tools/shd.py key cmd+space
  python3 tools/shd.py move 0.5 0.5        # fraction of the Sharer screen
  python3 tools/shd.py click [left|right|middle]
  python3 tools/shd.py scroll -3
  python3 tools/shd.py release
"""
import struct
import sys
import time

import serial
from serial.tools import list_ports

SOF = 0xAA
KEY, MOUSE_ABS, MOUSE_REL, CONSUMER, RELEASE_ALL, PING = 0x01, 0x02, 0x03, 0x04, 0x05, 0x10
PONG, STATUS = 0x11, 0x12
BRIDGE_VID, BRIDGE_PID = 0x1209, 0x0002

# HID usages (US layout positions; the Sharer Mac's layout decides the final character)
MODIFIERS = {"ctrl": 0xE0, "shift": 0xE1, "alt": 0xE2, "opt": 0xE2, "cmd": 0xE3,
             "rctrl": 0xE4, "rshift": 0xE5, "ralt": 0xE6, "rcmd": 0xE7}
NAMED = {"enter": 0x28, "esc": 0x29, "backspace": 0x2A, "tab": 0x2B, "space": 0x2C,
         "right": 0x4F, "left": 0x50, "down": 0x51, "up": 0x52, "delete": 0x4C,
         "home": 0x4A, "end": 0x4D, "pageup": 0x4B, "pagedown": 0x4E, "capslock": 0x39}
NAMED.update({f"f{i}": 0x3A + i - 1 for i in range(1, 13)})

PLAIN = {c: 0x04 + i for i, c in enumerate("abcdefghijklmnopqrstuvwxyz")}
PLAIN.update({c: 0x1E + i for i, c in enumerate("1234567890")})
PLAIN.update({" ": 0x2C, "\n": 0x28, "\t": 0x2B, "-": 0x2D, "=": 0x2E, "[": 0x2F, "]": 0x30,
              "\\": 0x31, ";": 0x33, "'": 0x34, "`": 0x35, ",": 0x36, ".": 0x37, "/": 0x38})
SHIFTED = {u: PLAIN[l] for u, l in zip('!@#$%^&*()_+{}|:"~<>?', "1234567890-=[]\;'`,./")}
SHIFTED.update({c.upper(): PLAIN[c] for c in "abcdefghijklmnopqrstuvwxyz"})

BUTTONS = {"left": 1, "right": 2, "middle": 4}


def crc8(data):
    crc = 0
    for b in data:
        crc ^= b
        for _ in range(8):
            crc = ((crc << 1) ^ 0x07) & 0xFF if crc & 0x80 else (crc << 1) & 0xFF
    return crc


def frame(ftype, payload=b""):
    body = bytes([ftype, len(payload)]) + payload
    return bytes([SOF]) + body + bytes([crc8(body)])


def open_bridge():
    for p in list_ports.comports():
        if p.vid == BRIDGE_VID and p.pid == BRIDGE_PID:
            return serial.Serial(p.device, timeout=0.5)
    sys.exit("shdong bridge not found (is Board C plugged in?)")


def key(s, usage, pressed):
    s.write(frame(KEY, bytes([usage, int(pressed)])))


def tap(s, usage, mods=()):
    for m in mods:
        key(s, m, True)
    key(s, usage, True)
    key(s, usage, False)
    for m in reversed(mods):
        key(s, m, False)
    time.sleep(0.005)


def cmd_type(s, text):
    for ch in text:
        if ch in PLAIN:
            tap(s, PLAIN[ch])
        elif ch in SHIFTED:
            tap(s, SHIFTED[ch], [MODIFIERS["shift"]])
        else:
            print(f"skipping unsupported char {ch!r}")


def cmd_key(s, combo):
    *mods, last = combo.lower().split("+")
    usage = NAMED.get(last) or PLAIN.get(last)
    if usage is None:
        sys.exit(f"unknown key: {last}")
    tap(s, usage, [MODIFIERS[m] for m in mods])


def mouse_abs(s, x, y, buttons=0, wheel=0):
    s.write(frame(MOUSE_ABS, struct.pack("<HHBbb", x, y, buttons, wheel, 0)))


# The board does not report the cursor position, so remember the last move here
_pos = [16384, 16384]


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    cmd, args = sys.argv[1], sys.argv[2:]
    s = open_bridge()

    if cmd == "ping":
        token = int(time.time()) & 0xFFFFFFFF
        t0 = time.monotonic()
        s.write(frame(PING, struct.pack("<I", token)))
        data = s.read(64)
        idx = data.find(bytes([SOF, PONG]))
        if idx < 0:
            sys.exit("no PONG from target (check the 3 wires and that Board T is flashed)")
        tok, ver, leds, mounted = struct.unpack("<IBBB", data[idx + 3: idx + 10])
        rtt = (time.monotonic() - t0) * 1000
        print(f"target ok: proto v{ver}, usb_mounted={mounted}, leds=0x{leds:02x}, rtt={rtt:.1f} ms")
    elif cmd == "type":
        cmd_type(s, " ".join(args))
    elif cmd == "key":
        cmd_key(s, args[0])
    elif cmd == "move":
        _pos[0], _pos[1] = int(float(args[0]) * 32767), int(float(args[1]) * 32767)
        mouse_abs(s, *_pos)
    elif cmd == "click":
        b = BUTTONS[args[0] if args else "left"]
        s.write(frame(MOUSE_REL, struct.pack("<hhBbb", 0, 0, b, 0, 0)))
        s.write(frame(MOUSE_REL, struct.pack("<hhBbb", 0, 0, 0, 0, 0)))
    elif cmd == "scroll":
        s.write(frame(MOUSE_REL, struct.pack("<hhBbb", 0, 0, 0, int(args[0]), 0)))
    elif cmd == "release":
        s.write(frame(RELEASE_ALL))
    else:
        sys.exit(__doc__)
    s.flush()


if __name__ == "__main__":
    main()
