import AppKit
import Carbon.HIToolbox
import Combine
import ShdongCore

/// Captured/Released state machine and keyboard forwarding.
///
///   Released ──(click in viewer / menu)──▶ Captured
///   Captured ──(release hotkey / focus lost / app deactivates)──▶ Released
@MainActor
final class InputCapture: ObservableObject {
    @Published private(set) var isCaptured = false
    /// Secure input (a password field somewhere on the Controller) may block key events.
    @Published private(set) var secureInputActive = false

    private let link: BridgeLink
    private let tap = EventTap()
    private var modifiers = ModifierTracker()
    private var observers: [NSObjectProtocol] = []

    init(link: BridgeLink) {
        self.link = link
        tap.handler = { [weak self] type, event in
            MainActor.assumeIsolated { self?.handle(type, event) ?? false }
        }
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.release() }
        })
    }

    func capture() {
        guard !isCaptured else { return }
        tap.install()
        secureInputActive = IsSecureEventInputEnabled()
        modifiers.reset()
        tap.setEnabled(true)
        isCaptured = true
    }

    func release() {
        guard isCaptured else { return }
        tap.setEnabled(false)
        isCaptured = false
        modifiers.reset()
        link.send(.releaseAll)
    }

    func toggle() { isCaptured ? release() : capture() }

    /// Taps a key combination on the Sharer (menu shortcuts like Cmd-Tab).
    func sendCombo(_ usages: [UInt8]) {
        usages.forEach { link.send(.key(usage: $0, down: true)) }
        usages.reversed().forEach { link.send(.key(usage: $0, down: false)) }
    }

    // MARK: - Key events

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        guard isCaptured else { return false }
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        switch type {
        case .keyDown, .keyUp:
            let down = type == .keyDown
            // The Sharer repeats by itself while the key is held.
            if down && event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return true }
            if let usage = KeyMap.usage(for: keyCode) {
                link.send(.key(usage: usage, down: down))
            } else if let usage = KeyMap.consumerUsage(for: keyCode) {
                link.send(.consumer(usage: usage, down: down))
            }
            return true

        case .flagsChanged:
            if keyCode == KeyMap.capsLockKeyCode {
                // macOS reports Caps Lock as a toggle; the Sharer toggles on press.
                link.send(.key(usage: KeyMap.capsLockUsage, down: true))
                link.send(.key(usage: KeyMap.capsLockUsage, down: false))
                return true
            }
            for change in modifiers.update(flags: event.flags.rawValue) {
                link.send(.key(usage: change.usage, down: change.down))
            }
            if modifiers.isExactly(Settings.hotkey.mask) {
                // The hotkey modifiers already went out as KEY frames; release() sends RELEASE_ALL.
                DispatchQueue.main.async { self.release() }
            }
            return true

        case EventTap.systemDefined:
            if let (usage, down) = Self.mediaKey(event) {
                link.send(.consumer(usage: usage, down: down))
                return true
            }
            return false

        default:
            return false
        }
    }

    /// NX_SYSDEFINED subtype 8 → consumer page usage.
    private static func mediaKey(_ event: CGEvent) -> (UInt16, Bool)? {
        guard let ns = NSEvent(cgEvent: event), ns.subtype.rawValue == 8 else { return nil }
        let key = (ns.data1 & 0xFFFF_0000) >> 16
        let state = (ns.data1 & 0xFF00) >> 8
        let usages: [Int: UInt16] = [
            0: 0xE9, // NX_KEYTYPE_SOUND_UP
            1: 0xEA, // NX_KEYTYPE_SOUND_DOWN
            2: 0x6F, // NX_KEYTYPE_BRIGHTNESS_UP
            3: 0x70, // NX_KEYTYPE_BRIGHTNESS_DOWN
            7: 0xE2, // NX_KEYTYPE_MUTE
            16: 0xCD, // NX_KEYTYPE_PLAY
            17: 0xB5, // NX_KEYTYPE_NEXT
            18: 0xB6, // NX_KEYTYPE_PREVIOUS
            19: 0xB3, // NX_KEYTYPE_FAST
            20: 0xB4, // NX_KEYTYPE_REWIND
        ]
        guard let usage = usages[key], state == 0x0A || state == 0x0B else { return nil }
        return (usage, state == 0x0A)
    }
}
