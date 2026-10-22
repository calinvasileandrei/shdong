import SwiftUI

struct SettingsView: View {
    @AppStorage(Settings.releaseHotkey) private var hotkey = ReleaseHotkey.leftControlOption.rawValue
    @AppStorage(Settings.scrollPointsPerTick) private var scrollPointsPerTick = 12.0
    @AppStorage(Settings.autoCaptureOnClick) private var autoCapture = true
    @AppStorage(Settings.showLocalCursor) private var showLocalCursor = false
    @AppStorage(Settings.lowLatencyVideo) private var lowLatencyVideo = true
    @AppStorage(Settings.minimalFrame) private var minimalFrame = true
    @AppStorage(Settings.showStatusBar) private var showStatusBar = false

    var body: some View {
        Form {
            Picker("Release hotkey", selection: $hotkey) {
                ForEach(ReleaseHotkey.allCases) { Text($0.label).tag($0.rawValue) }
            }
            Toggle("Capture when clicking the video", isOn: $autoCapture)
            Toggle("Show local cursor over the video", isOn: $showLocalCursor)
            Toggle("Low-latency video (restart to apply)", isOn: $lowLatencyVideo)
            Toggle("Minimal window frame", isOn: $minimalFrame)
            Toggle("Show status bar", isOn: $showStatusBar)
            LabeledContent("Trackpad scroll speed") {
                // Fewer points per wheel tick = faster scrolling.
                Slider(value: $scrollPointsPerTick, in: 2...40) { EmptyView() }
                    minimumValueLabel: { Text("Fast") } maximumValueLabel: { Text("Slow") }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
    }
}

struct OnboardingView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Permissions").font(.title2.bold())
            Text("shdong needs this to show the other Mac.").foregroundStyle(.secondary)
            row("Camera", "Reads the HDMI capture stick (macOS treats it as a camera).",
                ok: state.cameraAllowed, anchor: "Privacy_Camera")
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 480)
        .onAppear { state.refreshPermissions() }
    }

    private func row(_ title: String, _ detail: String, ok: Bool, anchor: String,
                     request: (() -> Void)? = nil) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(ok ? .green : .red).font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if !ok {
                Button("Open System Settings") {
                    request?()
                    AppState.openPrivacySettings(anchor)
                }
            }
        }
    }
}
