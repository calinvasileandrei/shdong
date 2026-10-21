import AVFoundation
import AppKit
import Combine

/// Owns the long-lived pieces and forwards their changes to SwiftUI.
@MainActor
final class AppState: ObservableObject {
    let link = BridgeLink()
    let video = VideoPipeline()
    let input: InputCapture

    @Published var showOnboarding = false
    @Published private(set) var cameraAllowed = false

    private var cancellables: Set<AnyCancellable> = []
    private var started = false

    init() {
        Settings.registerDefaults()
        input = InputCapture(link: link)
        // Re-publish child changes so views observing AppState redraw.
        [link.objectWillChange, video.objectWillChange, input.objectWillChange].forEach {
            $0.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        }
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.refreshPermissions() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in self?.shutdown() }
            .store(in: &cancellables)
    }

    func start() {
        guard !started else { return }
        started = true
        refreshPermissions()
        showOnboarding = AVCaptureDevice.authorizationStatus(for: .video) == .denied
        link.start()
        video.start()
    }

    func shutdown() {
        input.release()
        link.stop()
        video.stop()
    }

    func refreshPermissions() {
        cameraAllowed = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        if cameraAllowed, video.status == .noPermission { video.refresh() }
    }

    static func openPrivacySettings(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}
