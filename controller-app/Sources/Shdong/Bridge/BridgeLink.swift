import Combine
import Foundation
import ShdongCore

/// Connection to the bridge board: discovery, sending frames, heartbeat, target status.
/// Published state lives on the main actor; serial I/O happens in `BridgeIO` on its own queue.
@MainActor
final class BridgeLink: ObservableObject {
    static let vendorID = 0x1209
    static let productID = 0x0002
    static let pingInterval: TimeInterval = 0.25
    static let targetTimeout: TimeInterval = 1.0

    @Published private(set) var portPath: String?
    @Published private(set) var targetAlive = false
    @Published private(set) var rttMs: Double?
    @Published private(set) var sharerMounted = false
    @Published private(set) var leds: UInt8 = 0
    @Published private(set) var firmwareVersion: UInt8?
    @Published private(set) var lastError: String?

    var isConnected: Bool { portPath != nil }
    var capsLock: Bool { leds & LED.capsLock != 0 }
    var versionMismatch: Bool { firmwareVersion.map { $0 != Frame.protoVersion } ?? false }

    nonisolated let io = BridgeIO()
    private let watcher = DeviceWatcher(vendorID: vendorID, productID: productID)
    private var pingTimer: Timer?
    private var nextToken: UInt32 = 1
    private var pingSentAt: [UInt32: CFAbsoluteTime] = [:]
    private var lastPong: CFAbsoluteTime = 0
    /// Set SHDONG_BRIDGE_PORT to a path (e.g. from shdong-mock-bridge) to skip USB discovery.
    private let overridePath = ProcessInfo.processInfo.environment["SHDONG_BRIDGE_PORT"]

    func start() {
        io.onMessages = { [weak self] msgs in
            DispatchQueue.main.async { msgs.forEach { self?.handle($0) } }
        }
        io.onClose = { [weak self] in
            DispatchQueue.main.async { self?.disconnected() }
        }
        if overridePath == nil {
            watcher.onAppear = { [weak self] path in self?.connect(path) }
            watcher.onDisappear = { [weak self] path in
                guard let self, self.portPath == path else { return }
                self.io.close()
                self.disconnected()
            }
            watcher.start()
        }
        pingTimer = Timer.scheduledTimer(withTimeInterval: Self.pingInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        tick()
    }

    func stop() {
        io.send(.releaseAll)
        pingTimer?.invalidate()
        watcher.stop()
        io.close()
        disconnected()
    }

    /// Thread-safe; may be called from the event tap callback.
    nonisolated func send(_ message: OutMessage) { io.send(message) }

    private func connect(_ path: String) {
        guard portPath == nil else { return }
        do {
            try io.open(path)
        } catch {
            lastError = "\(error)"
            return
        }
        portPath = path
        lastError = nil
        tick() // first PING right away
    }

    private func disconnected() {
        guard portPath != nil else { return }
        portPath = nil
        targetAlive = false
        rttMs = nil
        firmwareVersion = nil
        pingSentAt.removeAll()
    }

    private func tick() {
        if portPath == nil, let overridePath { connect(overridePath) }
        guard portPath != nil else { return }
        let now = CFAbsoluteTimeGetCurrent()
        if targetAlive && now - lastPong > Self.targetTimeout {
            targetAlive = false
            rttMs = nil
        }
        let token = nextToken
        nextToken &+= 1
        pingSentAt = pingSentAt.filter { now - $0.value < Self.targetTimeout }
        pingSentAt[token] = now
        send(.ping(token: token))
    }

    private func handle(_ message: InMessage) {
        switch message {
        case let .pong(token, version, leds, mounted):
            let now = CFAbsoluteTimeGetCurrent()
            if let sent = pingSentAt.removeValue(forKey: token) { rttMs = (now - sent) * 1000 }
            lastPong = now
            targetAlive = true
            firmwareVersion = version
            self.leds = leds
            sharerMounted = mounted
        case let .status(leds, mounted):
            self.leds = leds
            sharerMounted = mounted
        }
    }
}

/// Serial port + frame parser, confined to one serial queue.
final class BridgeIO: @unchecked Sendable {
    private let queue = DispatchQueue(label: "shdong.bridge.io", qos: .userInteractive)
    private var port: SerialPort?
    private var parser = FrameParser()

    /// Called on the I/O queue.
    var onMessages: (([InMessage]) -> Void)?
    var onClose: (() -> Void)?

    func open(_ path: String) throws {
        try queue.sync {
            let p = SerialPort(path: path, queue: queue)
            p.onData = { [weak self] bytes in self?.received(bytes) }
            p.onClose = { [weak self] in
                self?.port = nil
                self?.onClose?()
            }
            try p.open()
            port = p
            parser = FrameParser()
        }
    }

    func close() {
        queue.sync {
            port?.close()
            port = nil
        }
    }

    func send(_ message: OutMessage) {
        let bytes = message.bytes
        queue.async { self.port?.write(bytes) }
    }

    private func received(_ bytes: [UInt8]) {
        let msgs = parser.feed(bytes).compactMap(InMessage.init)
        if !msgs.isEmpty { onMessages?(msgs) }
    }
}
