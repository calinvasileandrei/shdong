import Foundation

/// UserDefaults keys and defaults. Views bind with `@AppStorage(Settings.x)`.
enum Settings {
    static let releaseHotkey = "releaseHotkey"
    static let scrollPointsPerTick = "scrollPointsPerTick"
    static let autoCaptureOnClick = "autoCaptureOnClick"
    static let showLocalCursor = "showLocalCursor"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            releaseHotkey: ReleaseHotkey.leftControlOption.rawValue,
            scrollPointsPerTick: 12.0,
            autoCaptureOnClick: true,
            showLocalCursor: false,
        ])
    }

    static var hotkey: ReleaseHotkey {
        ReleaseHotkey(rawValue: UserDefaults.standard.string(forKey: releaseHotkey) ?? "") ?? .leftControlOption
    }
}

/// Modifier-only chords: they can't collide with a normal shortcut on the Sharer.
enum ReleaseHotkey: String, CaseIterable, Identifiable {
    case leftControlOption, rightCommandRightOption, leftControlLeftCommand

    var id: String { rawValue }

    /// Device-dependent flag bits (see ModifierTracker.sides).
    var mask: UInt64 {
        switch self {
        case .leftControlOption: return 0x01 | 0x20
        case .rightCommandRightOption: return 0x10 | 0x40
        case .leftControlLeftCommand: return 0x01 | 0x08
        }
    }

    var label: String {
        switch self {
        case .leftControlOption: return "⌃⌥ (left Control + left Option)"
        case .rightCommandRightOption: return "right ⌘⌥ (right Command + right Option)"
        case .leftControlLeftCommand: return "⌃⌘ (left Control + left Command)"
        }
    }

    var short: String {
        switch self {
        case .leftControlOption: return "⌃⌥"
        case .rightCommandRightOption: return "right ⌘⌥"
        case .leftControlLeftCommand: return "⌃⌘"
        }
    }
}
