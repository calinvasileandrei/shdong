import AVFoundation
import SwiftUI

@main
struct ShdongApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @StateObject private var state = AppState()

    var body: some Scene {
        Window("shdong", id: "viewer") {
            ContentView()
                .environmentObject(state)
                .onAppear { state.start() }
        }
        .defaultSize(width: 1280, height: 744)
        .commands { ShdongCommands(state: state) }

        SwiftUI.Settings {
            SettingsView().environmentObject(state)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Running the bare SwiftPM binary: make it a regular app with a Dock icon and menu bar.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct ContentView: View {
    @EnvironmentObject var state: AppState
    @State private var fullScreen = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                ViewerRepresentable(video: state.video, input: state.input, link: state.link)
                OverlayHUD()
            }
            if !fullScreen {
                StatusBarView()
            }
        }
        .background(Color.black)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in
            fullScreen = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
            fullScreen = false
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            state.input.release()
        }
        .sheet(isPresented: $state.showOnboarding) {
            OnboardingView().environmentObject(state)
        }
    }
}

struct ShdongCommands: Commands {
    @ObservedObject var state: AppState

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Button("Actual Size") { actualSize() }
                .keyboardShortcut("0", modifiers: .command)
            Button("Fit Window to Video") { fitWindow() }
            Divider()
        }
        CommandMenu("Input") {
            Button(state.input.isCaptured ? "Release" : "Capture Keyboard and Mouse") { state.input.toggle() }
                .keyboardShortcut("k", modifiers: [.command, .shift])
            Divider()
            Button("Send ⌘Tab") { state.input.sendCombo([0xE3, 0x2B]) }
            Button("Send ⌘Space") { state.input.sendCombo([0xE3, 0x2C]) }
            Button("Send ⌘⌥Esc (Force Quit)") { state.input.sendCombo([0xE3, 0xE2, 0x29]) }
            Button("Send ⌃⌘Q (Lock Screen)") { state.input.sendCombo([0xE0, 0xE3, 0x14]) }
            Divider()
            Button("Release All Keys on Sharer") { state.link.send(.releaseAll) }
        }
        CommandMenu("Devices") {
            Picker("Capture Device", selection: Binding(
                get: { state.video.current?.uniqueID ?? "" },
                set: { id in
                    if let d = state.video.devices.first(where: { $0.uniqueID == id }) { state.video.select(d) }
                }
            )) {
                ForEach(state.video.devices, id: \.uniqueID) { Text($0.localizedName).tag($0.uniqueID) }
            }
            .pickerStyle(.inline)
            Button("Rescan Capture Devices") { state.video.refresh() }
            Divider()
            Button("Permissions…") { state.showOnboarding = true }
        }
    }

    private var window: NSWindow? { NSApp.windows.first { $0.contentView != nil && $0.isVisible && $0.canBecomeMain } }

    /// One video pixel per screen pixel.
    private func actualSize() {
        guard let w = window else { return }
        let scale = w.backingScaleFactor
        let size = state.video.videoSize
        w.setContentSize(NSSize(width: size.width / scale, height: size.height / scale + StatusBarView.height))
    }

    /// Removes letterbox bars at the current width.
    private func fitWindow() {
        guard let w = window else { return }
        let size = state.video.videoSize
        let width = w.contentLayoutRect.width
        w.setContentSize(NSSize(width: width, height: width * size.height / size.width + StatusBarView.height))
    }
}
