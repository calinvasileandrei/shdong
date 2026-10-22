import SwiftUI

struct StatusBarView: View {
    static let height: CGFloat = 26
    @EnvironmentObject var state: AppState

    var body: some View {
        let link = state.link
        let video = state.video
        HStack(spacing: 14) {
            Dot(label: "Bridge", on: link.isConnected, help: link.portPath ?? link.lastError ?? "Not plugged in")
            Dot(label: "Target", on: link.targetAlive,
                help: link.targetAlive ? (link.sharerMounted ? "Sharer sees the keyboard" : "Target not mounted by the Sharer")
                                       : "No reply from the target board")
            Dot(label: "Video", on: video.status == .running, help: video.current?.localizedName ?? "No capture device")
            if let rtt = link.rttMs {
                Text(String(format: "RTT %.1f ms", rtt)).monospacedDigit()
            }
            if link.targetAlive && !link.sharerMounted {
                Label("Sharer not mounted", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }
            if link.versionMismatch {
                Label("Firmware v\(link.firmwareVersion ?? 0): reflash", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
            Spacer()
            if link.capsLock {
                Text("⇪ Caps Lock").foregroundStyle(.yellow)
            }
            if video.status == .running {
                Text("\(Int(video.videoSize.width))×\(Int(video.videoSize.height))"
                     + (video.fps > 0 ? String(format: " @ %.0f", video.fps) : "")
                     + (video.codec.isEmpty ? "" : " \(video.codec)"))
                    .monospacedDigit()
            }
            Text(state.input.isCaptured ? "Captured · \(Settings.hotkey.short) to release" : "Click video to capture")
                .foregroundStyle(state.input.isCaptured ? .green : .secondary)
        }
        .font(.system(size: 11))
        .padding(.horizontal, 10)
        .frame(height: Self.height)
        .background(.bar)
    }
}

private struct Dot: View {
    let label: String
    let on: Bool
    let help: String

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(on ? Color.green : Color.red.opacity(0.8)).frame(width: 7, height: 7)
            Text(label)
        }
        .help(help)
    }
}
