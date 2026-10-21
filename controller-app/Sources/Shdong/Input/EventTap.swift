import AppKit
import CoreGraphics

/// In-app keyboard monitor. While enabled it swallows every keyboard event delivered to shdong
/// and hands it to `handler`. Needs no permission (unlike a session event tap, which requires
/// Accessibility), so shortcuts the system grabs first (Cmd-Tab, Cmd-Space) never reach it.
final class EventTap {
    /// NX_SYSDEFINED: media keys arrive as system-defined events.
    static let systemDefined = CGEventType(rawValue: 14)!

    private var monitor: Any?
    private var enabled = false
    /// Return true to swallow the event. Runs on the main thread; keep it fast.
    var handler: ((CGEventType, CGEvent) -> Bool)?

    func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .keyUp, .flagsChanged, .systemDefined]
        ) { [weak self] event in
            guard let self, self.enabled, let cg = event.cgEvent,
                  let type = CGEventType(rawValue: cg.type.rawValue) else { return event }
            return self.handler?(type, cg) == true ? nil : event
        }
    }

    func setEnabled(_ on: Bool) { enabled = on }
}
