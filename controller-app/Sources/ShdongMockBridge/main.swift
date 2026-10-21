// Pretends to be bridge + target on a pseudo-terminal: answers PING with PONG and logs
// every frame the app sends. Run it, then start the app with SHDONG_BRIDGE_PORT=<printed path>.
//
//   swift run shdong-mock-bridge [--caps] [--unmounted] [--quiet]

import Darwin
import Foundation
import ShdongCore

let args = Set(CommandLine.arguments.dropFirst())
var leds: UInt8 = args.contains("--caps") ? LED.capsLock : 0
let mounted: UInt8 = args.contains("--unmounted") ? 0 : 1
let quiet = args.contains("--quiet")

var master: Int32 = 0, slave: Int32 = 0
var name = [CChar](repeating: 0, count: 128)
guard openpty(&master, &slave, &name, nil, nil) == 0 else {
    perror("openpty")
    exit(1)
}
var t = termios()
tcgetattr(slave, &t)
cfmakeraw(&t)
tcsetattr(slave, TCSANOW, &t)

let path = String(cString: name)
print("mock bridge on \(path)")
print("run the app with:  SHDONG_BRIDGE_PORT=\(path) swift run Shdong")
setvbuf(stdout, nil, _IOLBF, 0)

func describe(_ f: RawFrame) -> String {
    let p = f.payload
    func u16(_ i: Int) -> Int { Int(p[i]) | Int(p[i + 1]) << 8 }
    switch MessageType(rawValue: f.type) {
    case .key: return String(format: "KEY        usage=0x%02X %@", p[0], p[1] != 0 ? "down" : "up")
    case .mouseAbs: return "MOUSE_ABS  x=\(u16(0)) y=\(u16(2)) buttons=\(p[4]) wheel=\(Int8(bitPattern: p[5])) pan=\(Int8(bitPattern: p[6]))"
    case .mouseRel: return "MOUSE_REL  dx=\(Int16(bitPattern: UInt16(u16(0)))) dy=\(Int16(bitPattern: UInt16(u16(2)))) buttons=\(p[4])"
    case .consumer: return String(format: "CONSUMER   usage=0x%02X %@", u16(0), p[2] != 0 ? "down" : "up")
    case .releaseAll: return "RELEASE_ALL"
    default: return String(format: "type=0x%02X len=%d", f.type, p.count)
    }
}

var parser = FrameParser()
var pings = 0
var buf = [UInt8](repeating: 0, count: 512)
while true {
    let n = read(master, &buf, buf.count)
    if n <= 0 {
        // No reader attached yet (EIO) or interrupted.
        usleep(10_000)
        continue
    }
    for f in parser.feed(buf[0..<n]) {
        if f.type == MessageType.ping.rawValue, f.payload.count == 4 {
            pings += 1
            if pings == 1 || pings % 40 == 0 { print("PING #\(pings) answered") }
            let reply = Frame.encode(type: MessageType.pong.rawValue,
                                     payload: f.payload + [Frame.protoVersion, leds, mounted])
            _ = reply.withUnsafeBytes { write(master, $0.baseAddress, $0.count) }
            continue
        }
        if f.type == MessageType.key.rawValue, f.payload == [KeyMap.capsLockUsage, 1] {
            // Behave like the Sharer: toggle Caps Lock and report the LED.
            leds ^= LED.capsLock
            let status = Frame.encode(type: MessageType.status.rawValue, payload: [leds, mounted])
            _ = status.withUnsafeBytes { write(master, $0.baseAddress, $0.count) }
        }
        if !quiet { print(describe(f)) }
    }
}
