import Testing
@testable import ShdongCore

@Suite struct FrameTests {
    @Test func firmwareVector() {
        // Same bytes verified in protocol.c and shd.py (COMMUNICATION.md §4).
        #expect(OutMessage.key(usage: 0x04, down: true).bytes == [0xAA, 0x01, 0x02, 0x04, 0x01, 0x93])
    }

    @Test func crcMatchesReferenceAlgorithm() {
        // CRC-8/SMBUS check value for "123456789".
        #expect(Array("123456789".utf8).reduce(0, Frame.crc8) == 0xF4)
    }

    @Test func releaseAllIsEmptyFrame() {
        let b = OutMessage.releaseAll.bytes
        #expect(b.count == 4)
        #expect(Array(b[0...2]) == [0xAA, 0x05, 0x00])
        #expect(b[3] == [0x05, 0x00].reduce(0, Frame.crc8))
    }

    @Test func payloadLayouts() {
        #expect(OutMessage.mouseAbs(x: 0x1234, y: 0x7FFF, buttons: 0x03, wheel: -1, pan: 2).payload
            == [0x34, 0x12, 0xFF, 0x7F, 0x03, 0xFF, 0x02])
        #expect(OutMessage.mouseRel(dx: -2, dy: 300, buttons: 0, wheel: 0, pan: 0).payload
            == [0xFE, 0xFF, 0x2C, 0x01, 0, 0, 0])
        #expect(OutMessage.consumer(usage: 0xE9, down: true).payload == [0xE9, 0x00, 0x01])
        #expect(OutMessage.ping(token: 0xDEADBEEF).payload == [0xEF, 0xBE, 0xAD, 0xDE])
    }

    @Test func roundTripAllOutMessages() {
        let messages: [OutMessage] = [
            .key(usage: 0xE3, down: false),
            .mouseAbs(x: 1, y: 2, buttons: 1, wheel: 3, pan: -4),
            .mouseRel(dx: -100, dy: 100, buttons: 2, wheel: 0, pan: 0),
            .consumer(usage: 0xCD, down: true),
            .releaseAll,
            .ping(token: 42),
        ]
        var parser = FrameParser()
        let frames = parser.feed(messages.flatMap(\.bytes))
        #expect(frames.map(\.type) == messages.map(\.type.rawValue))
        #expect(frames.map(\.payload) == messages.map(\.payload))
    }

    @Test func parsesPongAndStatus() {
        var parser = FrameParser()
        let pong = Frame.encode(type: 0x11, payload: [0x2A, 0, 0, 0, 1, LED.capsLock, 1])
        let status = Frame.encode(type: 0x12, payload: [0, 0])
        let msgs = parser.feed(pong + status).compactMap(InMessage.init)
        #expect(msgs == [.pong(token: 42, version: 1, leds: LED.capsLock, mounted: true),
                         .status(leds: 0, mounted: false)])
    }

    @Test func resyncsAfterGarbageAndBadCrc() {
        var parser = FrameParser()
        var bad = OutMessage.key(usage: 4, down: true).bytes
        bad[5] ^= 0xFF
        let good = OutMessage.key(usage: 5, down: false).bytes
        let frames = parser.feed([0x00, 0x13, 0xAA, 0x01, 0xFF] + bad + good)
        #expect(frames == [RawFrame(type: 0x01, payload: [5, 0])])
    }

    @Test func rejectsOversizedLength() {
        var parser = FrameParser()
        let good = OutMessage.ping(token: 7).bytes
        #expect(parser.feed([0xAA, 0x10, 33] + good).count == 1)
    }

    @Test func unknownAndShortFramesAreIgnored() {
        #expect(InMessage(RawFrame(type: 0x30, payload: [])) == nil)
        #expect(InMessage(RawFrame(type: 0x11, payload: [1, 2, 3])) == nil)
    }
}
