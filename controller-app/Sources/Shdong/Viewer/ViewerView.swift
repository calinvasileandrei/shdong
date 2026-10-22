import AppKit
import ShdongCore
import SwiftUI

/// NSView that shows the video layer and turns mouse events over it into absolute mouse frames.
final class ViewerView: NSView {
    var link: BridgeLink?
    var input: InputCapture?
    var videoLayer: CALayer? {
        didSet {
            oldValue?.removeFromSuperlayer()
            if let videoLayer { layer?.addSublayer(videoLayer) }
            needsLayout = true
        }
    }
    var videoSize = CGSize(width: 1920, height: 1080) {
        didSet { if videoSize != oldValue { applyAspectRatio() } }
    }

    private var buttons: UInt8 = 0
    private var lastPos: (x: UInt16, y: UInt16) = (16384, 16384)
    private var pendingMove = false
    private var lastMoveSent: CFTimeInterval = 0
    private var scrollY = ScrollAccumulator(pointsPerTick: 12)
    private var scrollX = ScrollAccumulator(pointsPerTick: 12)
    private var cursorHidden = false
    private var tracking: NSTrackingArea?

    /// At most one move per display refresh at 120 Hz.
    private static let moveInterval: CFTimeInterval = 1.0 / 120

    private var captured: Bool { MainActor.assumeIsolated { input?.isCaptured ?? false } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        videoLayer?.frame = bounds
        CATransaction.commit()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyAspectRatio()
    }

    private func applyAspectRatio() {
        guard let window, videoSize.width > 0, videoSize.height > 0 else { return }
        window.contentAspectRatio = videoSize
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let t = NSTrackingArea(rect: .zero,
                               options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                               owner: self)
        addTrackingArea(t)
        tracking = t
    }

    // MARK: - Cursor

    func updateCursorVisibility() {
        let inside = window.map { bounds.contains(convert($0.mouseLocationOutsideOfEventStream, from: nil)) } ?? false
        let showLocal = UserDefaults.standard.bool(forKey: Settings.showLocalCursor)
        let hide = captured && inside && !showLocal
        if hide != cursorHidden {
            hide ? NSCursor.hide() : NSCursor.unhide()
            cursorHidden = hide
        }
    }

    override func mouseEntered(with event: NSEvent) { updateCursorVisibility() }
    override func mouseExited(with event: NSEvent) { updateCursorVisibility() }

    // MARK: - Mouse

    override func mouseMoved(with event: NSEvent) { move(event) }
    override func mouseDragged(with event: NSEvent) { move(event) }
    override func rightMouseDragged(with event: NSEvent) { move(event) }
    override func otherMouseDragged(with event: NSEvent) { move(event) }

    override func mouseDown(with event: NSEvent) {
        if !captured {
            // First click only captures; it isn't forwarded, so it never lands somewhere surprising.
            if UserDefaults.standard.bool(forKey: Settings.autoCaptureOnClick) {
                MainActor.assumeIsolated { input?.capture() }
                updateCursorVisibility()
            }
            return
        }
        button(MouseButton.left.rawValue, down: true, event)
    }

    override func mouseUp(with event: NSEvent) { button(MouseButton.left.rawValue, down: false, event) }
    override func rightMouseDown(with event: NSEvent) { button(MouseButton.right.rawValue, down: true, event) }
    override func rightMouseUp(with event: NSEvent) { button(MouseButton.right.rawValue, down: false, event) }
    override func otherMouseDown(with event: NSEvent) { button(Self.otherMask(event), down: true, event) }
    override func otherMouseUp(with event: NSEvent) { button(Self.otherMask(event), down: false, event) }

    override func scrollWheel(with event: NSEvent) {
        guard captured else { return }
        let ppt = UserDefaults.standard.double(forKey: Settings.scrollPointsPerTick)
        scrollY.pointsPerTick = ppt
        scrollX.pointsPerTick = ppt
        if event.phase == .began { scrollY.reset(); scrollX.reset() }
        // Send the raw device direction; the Sharer applies its own natural-scrolling setting.
        let sign: Double = event.isDirectionInvertedFromDevice ? -1 : 1
        let wheel = scrollY.ticks(delta: sign * event.scrollingDeltaY, precise: event.hasPreciseScrollingDeltas)
        let pan = scrollX.ticks(delta: -sign * event.scrollingDeltaX, precise: event.hasPreciseScrollingDeltas)
        guard wheel != 0 || pan != 0 else { return }
        updatePosition(event)
        send(wheel: wheel, pan: pan)
    }

    private static func otherMask(_ event: NSEvent) -> UInt8 {
        switch event.buttonNumber {
        case 2: return MouseButton.middle.rawValue
        case 3: return MouseButton.back.rawValue
        case 4: return MouseButton.forward.rawValue
        default: return 0
        }
    }

    private func button(_ mask: UInt8, down: Bool, _ event: NSEvent) {
        guard captured, mask != 0 else { return }
        // Releases always go out so nothing stays held; presses only when inside the video.
        let inside = updatePosition(event)
        if down && !inside { return }
        if down { buttons |= mask } else { buttons &= ~mask }
        send()
    }

    private func move(_ event: NSEvent) {
        updateCursorVisibility()
        guard captured else { return }
        updatePosition(event)
        let now = CACurrentMediaTime()
        if now - lastMoveSent >= Self.moveInterval {
            send()
        } else if !pendingMove {
            pendingMove = true
            DispatchQueue.main.asyncAfter(deadline: .now() + (Self.moveInterval - (now - lastMoveSent))) { [weak self] in
                guard let self, self.pendingMove else { return }
                self.send()
            }
        }
    }

    @discardableResult
    private func updatePosition(_ event: NSEvent) -> Bool {
        let p = convert(event.locationInWindow, from: nil)
        let m = MouseMapper.map(p, viewSize: bounds.size, videoSize: videoSize)
        lastPos = (m.x, m.y)
        return m.inside
    }

    private func send(wheel: Int8 = 0, pan: Int8 = 0) {
        pendingMove = false
        lastMoveSent = CACurrentMediaTime()
        link?.send(.mouseAbs(x: lastPos.x, y: lastPos.y, buttons: buttons, wheel: wheel, pan: pan))
    }

    /// Called when capture ends: the Sharer already got RELEASE_ALL.
    func resetInputState() {
        buttons = 0
        pendingMove = false
        updateCursorVisibility()
    }
}

/// SwiftUI wrapper.
struct ViewerRepresentable: NSViewRepresentable {
    @ObservedObject var video: VideoPipeline
    @ObservedObject var input: InputCapture
    let link: BridgeLink

    func makeNSView(context: Context) -> ViewerView {
        let v = ViewerView(frame: .zero)
        v.link = link
        v.input = input
        v.videoLayer = video.layer
        v.videoSize = video.videoSize
        return v
    }

    func updateNSView(_ v: ViewerView, context: Context) {
        v.videoSize = video.videoSize
        if !input.isCaptured { v.resetInputState() } else { v.updateCursorVisibility() }
    }
}
