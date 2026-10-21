// Mirror of firmware/common/protocol.{h,c}.
//
// Frame: [SOF 0xAA][type][len][payload: len bytes][crc8]
// CRC-8 (poly 0x07, init 0x00) covers type, len and payload.
// Multi-byte fields are little-endian.

public enum Frame {
    public static let sof: UInt8 = 0xAA
    public static let maxPayload = 32
    public static let maxFrame = maxPayload + 4
    public static let protoVersion: UInt8 = 1

    public static func crc8(_ crc: UInt8, _ byte: UInt8) -> UInt8 {
        var crc = crc ^ byte
        for _ in 0..<8 {
            crc = (crc & 0x80) != 0 ? (crc << 1) ^ 0x07 : crc << 1
        }
        return crc
    }

    public static func encode(type: UInt8, payload: [UInt8] = []) -> [UInt8] {
        let body = payload.prefix(maxPayload)
        var out: [UInt8] = [sof, type, UInt8(body.count)]
        out.append(contentsOf: body)
        out.append(out.dropFirst().reduce(0, crc8))
        return out
    }
}

public struct RawFrame: Equatable {
    public var type: UInt8
    public var payload: [UInt8]

    public init(type: UInt8, payload: [UInt8]) {
        self.type = type
        self.payload = payload
    }
}

/// Streaming parser, same state machine as `shd_parser_feed`.
public struct FrameParser {
    private enum State { case sof, type, len, payload, crc }

    private var state = State.sof
    private var crc: UInt8 = 0
    private var type: UInt8 = 0
    private var len = 0
    private var payload: [UInt8] = []

    public init() {}

    /// Feeds one byte. Returns a frame when one is complete and its CRC matches.
    public mutating func feed(_ b: UInt8) -> RawFrame? {
        switch state {
        case .sof:
            if b == Frame.sof { state = .type }
        case .type:
            type = b
            crc = Frame.crc8(0, b)
            state = .len
        case .len:
            if Int(b) > Frame.maxPayload {
                state = .sof
                return nil
            }
            len = Int(b)
            crc = Frame.crc8(crc, b)
            payload.removeAll(keepingCapacity: true)
            state = len > 0 ? .payload : .crc
        case .payload:
            payload.append(b)
            crc = Frame.crc8(crc, b)
            if payload.count == len { state = .crc }
        case .crc:
            state = .sof
            if b == crc { return RawFrame(type: type, payload: payload) }
        }
        return nil
    }

    public mutating func feed<S: Sequence>(_ bytes: S) -> [RawFrame] where S.Element == UInt8 {
        bytes.compactMap { feed($0) }
    }
}
