import SwiftUI

/// Center messages over the video: capture banner (fades after 2 s) and problem states.
struct OverlayHUD: View {
    @EnvironmentObject var state: AppState
    @State private var showCaptureBanner = false

    var body: some View {
        VStack(spacing: 10) {
            if let problem {
                Banner(text: problem, symbol: "exclamationmark.triangle")
            }
            if state.input.isCaptured && state.input.secureInputActive {
                Banner(text: "Secure input is on in another app: keys may not be captured",
                       symbol: "lock.shield")
            }
            if showCaptureBanner {
                Banner(text: "Captured — press \(Settings.hotkey.short) to release", symbol: "keyboard")
                    .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
        .onChange(of: state.input.isCaptured) { captured in
            withAnimation { showCaptureBanner = captured }
            guard captured else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation(.easeOut(duration: 0.4)) { showCaptureBanner = false }
            }
        }
    }

    private var problem: String? {
        switch state.video.status {
        case .noPermission: return "Camera access is needed to show the capture stick"
        case .noDevice: return "No signal — plug in the HDMI capture stick"
        case let .failed(msg): return "Video error: \(msg)"
        case .idle, .running: break
        }
        if !state.link.isConnected { return "Bridge not connected" }
        if !state.link.targetAlive { return "Bridge connected, target board not responding" }
        return nil
    }
}

private struct Banner: View {
    let text: String
    let symbol: String

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
    }
}
