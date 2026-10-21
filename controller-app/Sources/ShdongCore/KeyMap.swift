// macOS virtual keycodes (Carbon kVK_*) → USB HID usages.
//
// Physical mapping: the Sharer's own keyboard layout decides which character appears,
// exactly like a real keyboard plugged into it.

public enum KeyMap {
    /// Keyboard page (0x07) usage for a virtual keycode, or nil if it has none.
    public static func usage(for keyCode: UInt16) -> UInt8? { keyboard[keyCode] }

    /// Consumer page (0x0C) usage for keys that are media keys on the Controller.
    public static func consumerUsage(for keyCode: UInt16) -> UInt16? { consumer[keyCode] }

    /// Keycodes deliberately not forwarded (Fn/Globe has no HID usage; the Controller already
    /// turns Fn+arrows etc. into Home/End/...).
    public static let ignored: Set<UInt16> = [0x3F]

    public static let capsLockKeyCode: UInt16 = 0x39
    public static let capsLockUsage: UInt8 = 0x39

    static let keyboard: [UInt16: UInt8] = [
        // Letters
        0x00: 0x04, // A
        0x0B: 0x05, // B
        0x08: 0x06, // C
        0x02: 0x07, // D
        0x0E: 0x08, // E
        0x03: 0x09, // F
        0x05: 0x0A, // G
        0x04: 0x0B, // H
        0x22: 0x0C, // I
        0x26: 0x0D, // J
        0x28: 0x0E, // K
        0x25: 0x0F, // L
        0x2E: 0x10, // M
        0x2D: 0x11, // N
        0x1F: 0x12, // O
        0x23: 0x13, // P
        0x0C: 0x14, // Q
        0x0F: 0x15, // R
        0x01: 0x16, // S
        0x11: 0x17, // T
        0x20: 0x18, // U
        0x09: 0x19, // V
        0x0D: 0x1A, // W
        0x07: 0x1B, // X
        0x10: 0x1C, // Y
        0x06: 0x1D, // Z
        // Digits row
        0x12: 0x1E, // 1
        0x13: 0x1F, // 2
        0x14: 0x20, // 3
        0x15: 0x21, // 4
        0x17: 0x22, // 5
        0x16: 0x23, // 6
        0x1A: 0x24, // 7
        0x1C: 0x25, // 8
        0x19: 0x26, // 9
        0x1D: 0x27, // 0
        // Editing / whitespace
        0x24: 0x28, // Return
        0x35: 0x29, // Escape
        0x33: 0x2A, // Delete (backspace)
        0x30: 0x2B, // Tab
        0x31: 0x2C, // Space
        // Punctuation
        0x1B: 0x2D, // -
        0x18: 0x2E, // =
        0x21: 0x2F, // [
        0x1E: 0x30, // ]
        0x2A: 0x31, // \
        0x29: 0x33, // ;
        0x27: 0x34, // '
        0x32: 0x35, // `
        0x2B: 0x36, // ,
        0x2F: 0x37, // .
        0x2C: 0x38, // /
        0x0A: 0x64, // ISO § (non-US backslash)
        0x39: 0x39, // Caps Lock
        // Function keys
        0x7A: 0x3A, // F1
        0x78: 0x3B, // F2
        0x63: 0x3C, // F3
        0x76: 0x3D, // F4
        0x60: 0x3E, // F5
        0x61: 0x3F, // F6
        0x62: 0x40, // F7
        0x64: 0x41, // F8
        0x65: 0x42, // F9
        0x6D: 0x43, // F10
        0x67: 0x44, // F11
        0x6F: 0x45, // F12
        0x69: 0x68, // F13
        0x6B: 0x69, // F14
        0x71: 0x6A, // F15
        0x6A: 0x6B, // F16
        0x40: 0x6C, // F17
        0x4F: 0x6D, // F18
        0x50: 0x6E, // F19
        0x5A: 0x6F, // F20
        // Navigation
        0x72: 0x49, // Help → Insert (same physical position)
        0x73: 0x4A, // Home
        0x74: 0x4B, // Page Up
        0x75: 0x4C, // Forward Delete
        0x77: 0x4D, // End
        0x79: 0x4E, // Page Down
        0x7C: 0x4F, // Right
        0x7B: 0x50, // Left
        0x7D: 0x51, // Down
        0x7E: 0x52, // Up
        0x6E: 0x65, // Context menu → Application
        // Keypad
        0x47: 0x53, // Clear (Num Lock position)
        0x4B: 0x54, // /
        0x43: 0x55, // *
        0x4E: 0x56, // -
        0x45: 0x57, // +
        0x4C: 0x58, // Enter
        0x53: 0x59, // 1
        0x54: 0x5A, // 2
        0x55: 0x5B, // 3
        0x56: 0x5C, // 4
        0x57: 0x5D, // 5
        0x58: 0x5E, // 6
        0x59: 0x5F, // 7
        0x5B: 0x60, // 8
        0x5C: 0x61, // 9
        0x52: 0x62, // 0
        0x41: 0x63, // .
        0x51: 0x67, // =
        // JIS
        0x5F: 0x85, // Keypad ,
        0x5E: 0x87, // _ (International1, Ro)
        0x5D: 0x89, // ¥ (International3)
        0x68: 0x90, // Kana (LANG1)
        0x66: 0x91, // Eisu (LANG2)
        // Modifiers (normally handled via flagsChanged, listed for completeness)
        0x3B: 0xE0, // Left Control
        0x38: 0xE1, // Left Shift
        0x3A: 0xE2, // Left Option
        0x37: 0xE3, // Left Command
        0x3E: 0xE4, // Right Control
        0x3C: 0xE5, // Right Shift
        0x3D: 0xE6, // Right Option
        0x36: 0xE7, // Right Command
    ]

    static let consumer: [UInt16: UInt16] = [
        0x48: 0xE9, // Volume Up
        0x49: 0xEA, // Volume Down
        0x4A: 0xE2, // Mute
    ]
}

/// Turns modifier flag snapshots (from `flagsChanged`) into per-side down/up events.
///
/// Uses the device-dependent bits (NX_DEVICE*KEYMASK) in the low 16 bits of CGEventFlags,
/// which tell left and right apart.
public struct ModifierTracker {
    public static let sides: [(mask: UInt64, usage: UInt8)] = [
        (0x0000_0001, 0xE0), // left control
        (0x0000_0002, 0xE1), // left shift
        (0x0000_0020, 0xE2), // left option
        (0x0000_0008, 0xE3), // left command
        (0x0000_2000, 0xE4), // right control
        (0x0000_0004, 0xE5), // right shift
        (0x0000_0040, 0xE6), // right option
        (0x0000_0010, 0xE7), // right command
    ]
    static let allMask = sides.reduce(UInt64(0)) { $0 | $1.mask }

    public private(set) var held: UInt64 = 0

    public init() {}

    /// Returns the usages whose state changed, in a stable order.
    public mutating func update(flags: UInt64) -> [(usage: UInt8, down: Bool)] {
        let now = flags & Self.allMask
        let changed = now ^ held
        held = now
        return Self.sides.filter { changed & $0.mask != 0 }.map { ($0.usage, now & $0.mask != 0) }
    }

    public mutating func reset() { held = 0 }

    /// True when exactly the given device bits are held (used for the release hotkey).
    public func isExactly(_ mask: UInt64) -> Bool { held == mask }
}
