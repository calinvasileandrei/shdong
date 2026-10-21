// Typed messages. Type codes and payload layouts match firmware/common/protocol.h.

public enum MessageType: UInt8 {
    // controller -> target
    case key = 0x01
    case mouseAbs = 0x02
    case mouseRel = 0x03
    case consumer = 0x04
    case releaseAll = 0x05
    case ping = 0x10
    // target -> controller
    case pong = 0x11
    case status = 0x12
}

public enum MouseButton: UInt8 {
    case left = 0x01, right = 0x02, middle = 0x04, back = 0x08, forward = 0x10
}

public enum LED {
    public static let numLock: UInt8 = 0x01
    public static let capsLock: UInt8 = 0x02
    public static let scrollLock: UInt8 = 0x04
}

public enum OutMessage: Equatable {
    case key(usage: UInt8, down: Bool)
    case mouseAbs(x: UInt16, y: UInt16, buttons: UInt8, wheel: Int8, pan: Int8)
    case mouseRel(dx: Int16, dy: Int16, buttons: UInt8, wheel: Int8, pan: Int8)
    case consumer(usage: UInt16, down: Bool)
    case releaseAll
    case ping(token: UInt32)

    public var type: MessageType {
        switch self {
        case .key: return .key
        case .mouseAbs: return .mouseAbs
        case .mouseRel: return .mouseRel
        case .consumer: return .consumer
        case .releaseAll: return .releaseAll
        case .ping: return .ping
        }
    }

    public var payload: [UInt8] {
        switch self {
        case let .key(usage, down):
            return [usage, down ? 1 : 0]
        case let .mouseAbs(x, y, buttons, wheel, pan):
            return le16(x) + le16(y) + [buttons, UInt8(bitPattern: wheel), UInt8(bitPattern: pan)]
        case let .mouseRel(dx, dy, buttons, wheel, pan):
            return le16(UInt16(bitPattern: dx)) + le16(UInt16(bitPattern: dy))
                + [buttons, UInt8(bitPattern: wheel), UInt8(bitPattern: pan)]
        case let .consumer(usage, down):
            return le16(usage) + [down ? 1 : 0]
        case .releaseAll:
            return []
        case let .ping(token):
            return le32(token)
        }
    }

    public var bytes: [UInt8] { Frame.encode(type: type.rawValue, payload: payload) }
}

public enum InMessage: Equatable {
    case pong(token: UInt32, version: UInt8, leds: UInt8, mounted: Bool)
    case status(leds: UInt8, mounted: Bool)

    /// Nil for unknown types or short payloads (newer firmware may add fields, so longer is fine).
    public init?(_ frame: RawFrame) {
        let p = frame.payload
        switch MessageType(rawValue: frame.type) {
        case .pong where p.count >= 7:
            self = .pong(token: rd32(p, 0), version: p[4], leds: p[5], mounted: p[6] != 0)
        case .status where p.count >= 2:
            self = .status(leds: p[0], mounted: p[1] != 0)
        default:
            return nil
        }
    }
}

func le16(_ v: UInt16) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8)] }
func le32(_ v: UInt32) -> [UInt8] { (0..<4).map { UInt8((v >> ($0 * 8)) & 0xFF) } }
func rd32(_ p: [UInt8], _ i: Int) -> UInt32 {
    UInt32(p[i]) | UInt32(p[i + 1]) << 8 | UInt32(p[i + 2]) << 16 | UInt32(p[i + 3]) << 24
}
