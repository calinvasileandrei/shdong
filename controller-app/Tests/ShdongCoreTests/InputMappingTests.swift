import CoreGraphics
import Testing
@testable import ShdongCore

@Suite struct KeyMapTests {
    @Test func everyStandardKeycodeIsMappedOrIgnored() {
        // All kVK_* values from Carbon's Events.h.
        let all: [UInt16] = Array(0x00...0x32) + [0x33, 0x35, 0x36, 0x37, 0x38, 0x39, 0x3A, 0x3B, 0x3C,
            0x3D, 0x3E, 0x3F, 0x40, 0x41, 0x43, 0x45, 0x47, 0x48, 0x49, 0x4A, 0x4B, 0x4C, 0x4E, 0x4F,
            0x50, 0x51, 0x52, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5A, 0x5B, 0x5C, 0x5D, 0x5E,
            0x5F, 0x60, 0x61, 0x62, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69, 0x6A, 0x6B, 0x6D, 0x6E,
            0x6F, 0x71, 0x72, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7A, 0x7B, 0x7C, 0x7D, 0x7E]
        let missing = all.filter {
            KeyMap.usage(for: $0) == nil && KeyMap.consumerUsage(for: $0) == nil && !KeyMap.ignored.contains($0)
        }
        #expect(missing.isEmpty, "unmapped: \(missing.map { String($0, radix: 16) })")
    }

    @Test func noDuplicateUsages() {
        let usages = KeyMap.keyboard.values
        #expect(Set(usages).count == usages.count)
    }

    @Test func spotChecks() {
        #expect(KeyMap.usage(for: 0x00) == 0x04) // A
        #expect(KeyMap.usage(for: 0x31) == 0x2C) // Space
        #expect(KeyMap.usage(for: 0x37) == 0xE3) // Left Cmd
        #expect(KeyMap.usage(for: 0x7E) == 0x52) // Up
        #expect(KeyMap.consumerUsage(for: 0x4A) == 0xE2) // Mute
    }
}

@Suite struct ModifierTrackerTests {
    @Test func reportsSideSpecificChanges() {
        var t = ModifierTracker()
        // Left Cmd down (plus a device-independent bit that must be ignored).
        #expect(t.update(flags: 0x0010_0008).map(\.usage) == [0xE3])
        // Right Shift down too.
        let both = t.update(flags: 0x0010_0008 | 0x0000_0004)
        #expect(both.count == 1 && both[0].usage == 0xE5 && both[0].down)
        // Both released at once.
        let up = t.update(flags: 0)
        #expect(up.map(\.usage) == [0xE3, 0xE5] && up.allSatisfy { !$0.down })
    }

    @Test func releaseHotkeyDetection() {
        var t = ModifierTracker()
        _ = t.update(flags: 0x01 | 0x20)
        #expect(t.isExactly(0x01 | 0x20))
        _ = t.update(flags: 0x01 | 0x20 | 0x08)
        #expect(!t.isExactly(0x01 | 0x20))
    }
}

@Suite struct MouseMapperTests {
    @Test func pillarboxedVideo() {
        // 4:3 video in a 16:9 view → bars left and right.
        let r = MouseMapper.videoRect(viewSize: CGSize(width: 1600, height: 900),
                                      videoSize: CGSize(width: 1024, height: 768))
        #expect(r == CGRect(x: 200, y: 0, width: 1200, height: 900))
    }

    @Test func letterboxedVideo() {
        let r = MouseMapper.videoRect(viewSize: CGSize(width: 1000, height: 1000),
                                      videoSize: CGSize(width: 1920, height: 1080))
        #expect(abs(r.minX) < 0.001 && abs(r.width - 1000) < 0.001)
        #expect(abs(r.height - 562.5) < 0.001 && abs(r.minY - 218.75) < 0.001)
    }

    @Test func cornersAndFlip() {
        let view = CGSize(width: 1600, height: 900), video = CGSize(width: 1920, height: 1080)
        let topLeft = MouseMapper.map(CGPoint(x: 0, y: 900), viewSize: view, videoSize: video)
        #expect(topLeft.x == 0 && topLeft.y == 0 && topLeft.inside)
        let bottomRight = MouseMapper.map(CGPoint(x: 1600, y: 0), viewSize: view, videoSize: video)
        #expect(bottomRight.x == 32767 && bottomRight.y == 32767)
        let center = MouseMapper.map(CGPoint(x: 800, y: 450), viewSize: view, videoSize: video)
        #expect(center.x == 16384 && center.y == 16384)
    }

    @Test func clampsOutsideVideo() {
        let m = MouseMapper.map(CGPoint(x: 50, y: 450), viewSize: CGSize(width: 1600, height: 900),
                                videoSize: CGSize(width: 1024, height: 768))
        #expect(m.x == 0 && !m.inside)
    }
}

@Suite struct ScrollAccumulatorTests {
    @Test func carriesRemainder() {
        var s = ScrollAccumulator(pointsPerTick: 10)
        #expect(s.ticks(delta: 4, precise: true) == 0)
        #expect(s.ticks(delta: 4, precise: true) == 0)
        #expect(s.ticks(delta: 4, precise: true) == 1)
        #expect(s.ticks(delta: -25, precise: true) == -2)
    }

    @Test func wheelLinesPassThrough() {
        var s = ScrollAccumulator(pointsPerTick: 10)
        #expect(s.ticks(delta: 0.1, precise: false) == 1)
        #expect(s.ticks(delta: -3, precise: false) == -3)
        #expect(s.ticks(delta: 0, precise: false) == 0)
    }
}
