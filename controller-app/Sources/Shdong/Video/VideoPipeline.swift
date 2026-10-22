@preconcurrency import AVFoundation
import Combine
import CoreMedia

/// Finds the capture stick, picks its best format and shows it on `layer`.
///
/// Two display paths, chosen by `Settings.lowLatencyVideo` at launch:
/// - low latency: `AVCaptureVideoDataOutput` → `AVSampleBufferDisplayLayer`, late frames dropped,
///   each frame shown as soon as it is decoded;
/// - standard: `AVCaptureVideoPreviewLayer`.
@MainActor
final class VideoPipeline: ObservableObject {
    enum Status: Equatable {
        case idle, noPermission, noDevice, running, failed(String)
    }

    @Published private(set) var status = Status.idle
    @Published private(set) var devices: [AVCaptureDevice] = []
    @Published private(set) var current: AVCaptureDevice?
    /// Pixel size of the active format, used for aspect locking and mouse mapping.
    @Published private(set) var videoSize = CGSize(width: 1920, height: 1080)
    @Published private(set) var fps: Double = 0
    /// "YUV" or "MJPEG": what the stick is sending.
    @Published private(set) var codec = ""

    let session = AVCaptureSession()
    private(set) lazy var previewLayer: AVCaptureVideoPreviewLayer = {
        let l = AVCaptureVideoPreviewLayer(session: session)
        l.videoGravity = .resizeAspect
        l.backgroundColor = CGColor.black
        return l
    }()
    private(set) lazy var displayLayer: AVSampleBufferDisplayLayer = {
        let l = AVSampleBufferDisplayLayer()
        l.videoGravity = .resizeAspect
        l.backgroundColor = CGColor.black
        return l
    }()
    private lazy var lowLatency = UserDefaults.standard.bool(forKey: Settings.lowLatencyVideo)
    /// The layer the viewer shows, for the display path chosen at launch.
    var layer: CALayer { lowLatency ? displayLayer : previewLayer }
    private lazy var frameSink = FrameSink(layer: displayLayer)
    private var output: AVCaptureVideoDataOutput?

    private let sessionQueue = DispatchQueue(label: "shdong.video.session")
    private var observers: [NSObjectProtocol] = []
    private var input: AVCaptureDeviceInput?

    private static let lastDeviceKey = "lastCaptureDeviceID"
    private static let preferredNames = ["MS2130", "USB3 Video", "USB Video", "Capture", "HDMI"]

    func start() {
        let nc = NotificationCenter.default
        for name in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification] {
            observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            refresh()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { _ in
                DispatchQueue.main.async { self.refresh() }
            }
        default:
            status = .noPermission
        }
    }

    func stop() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        sessionQueue.async { [session] in session.stopRunning() }
    }

    /// Re-scans devices and (re)starts on the best one if the current one went away.
    func refresh() {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            status = .noPermission
            return
        }
        devices = Self.discover()
        if let current, devices.contains(where: { $0.uniqueID == current.uniqueID }), status == .running {
            return
        }
        guard let pick = Self.autoPick(devices) else {
            detach()
            status = .noDevice
            return
        }
        use(pick)
    }

    func select(_ device: AVCaptureDevice) {
        UserDefaults.standard.set(device.uniqueID, forKey: Self.lastDeviceKey)
        use(device)
    }

    private func use(_ device: AVCaptureDevice) {
        let (format, rate) = Self.bestFormat(device)
        do {
            let newInput = try AVCaptureDeviceInput(device: device)
            let old = input
            input = newInput
            if lowLatency, output == nil { output = makeOutput() }
            if let output, let format {
                let native = CMFormatDescriptionGetMediaSubType(format.formatDescription)
                output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String:
                    Self.isUncompressed(format) ? native : kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
            }
            let output = output
            sessionQueue.async { [session] in
                session.beginConfiguration()
                if let old { session.removeInput(old) }
                if session.canAddInput(newInput) { session.addInput(newInput) }
                if let output, !session.outputs.contains(output), session.canAddOutput(output) {
                    session.addOutput(output)
                }
                if let format, (try? device.lockForConfiguration()) != nil {
                    device.activeFormat = format
                    if let rate {
                        device.activeVideoMinFrameDuration = rate.minFrameDuration
                        device.activeVideoMaxFrameDuration = rate.minFrameDuration
                    }
                    device.unlockForConfiguration()
                }
                session.commitConfiguration()
                if !session.isRunning { session.startRunning() }
            }
            let dims = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
            let shown = format.map { CMVideoFormatDescriptionGetDimensions($0.formatDescription) } ?? dims
            videoSize = CGSize(width: Int(shown.width), height: Int(shown.height))
            fps = rate?.maxFrameRate ?? 0
            codec = format.map(Self.codecName) ?? ""
            current = device
            UserDefaults.standard.set(device.uniqueID, forKey: Self.lastDeviceKey)
            status = .running
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    private func makeOutput() -> AVCaptureVideoDataOutput {
        let o = AVCaptureVideoDataOutput()
        o.alwaysDiscardsLateVideoFrames = true
        // The stick sends MJPEG; ask for a format the display layer shows without converting.
        o.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
        o.setSampleBufferDelegate(frameSink, queue: frameSink.queue)
        return o
    }

    private func detach() {
        guard let old = input else { return }
        input = nil
        current = nil
        sessionQueue.async { [session] in
            session.beginConfiguration()
            session.removeInput(old)
            session.commitConfiguration()
        }
    }

    static func discover() -> [AVCaptureDevice] {
        let types: [AVCaptureDevice.DeviceType]
        if #available(macOS 14.0, *) {
            types = [.external]
        } else {
            types = [.externalUnknown]
        }
        return AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .video, position: .unspecified)
            .devices
    }

    static func autoPick(_ devices: [AVCaptureDevice]) -> AVCaptureDevice? {
        if let last = UserDefaults.standard.string(forKey: lastDeviceKey),
           let d = devices.first(where: { $0.uniqueID == last }) {
            return d
        }
        for name in preferredNames {
            if let d = devices.first(where: { $0.localizedName.localizedCaseInsensitiveContains(name) }) {
                return d
            }
        }
        return devices.first
    }

    static func isUncompressed(_ f: AVCaptureDevice.Format) -> Bool {
        let t = CMFormatDescriptionGetMediaSubType(f.formatDescription)
        return t == kCVPixelFormatType_422YpCbCr8_yuvs || t == kCVPixelFormatType_422YpCbCr8
            || t == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
    }

    /// Short name of a format's encoding, for the status bar.
    static func codecName(_ f: AVCaptureDevice.Format) -> String {
        isUncompressed(f) ? "YUV" : "MJPEG"
    }

    /// Highest resolution at 60 fps, falling back to 30, then anything.
    static func bestFormat(_ device: AVCaptureDevice) -> (AVCaptureDevice.Format?, AVFrameRateRange?) {
        func pixels(_ f: AVCaptureDevice.Format) -> Int32 {
            let d = CMVideoFormatDescriptionGetDimensions(f.formatDescription)
            return d.width * d.height
        }
        for minRate in [59.0, 29.0, 0.0] {
            let candidates = device.formats.compactMap { f -> (AVCaptureDevice.Format, AVFrameRateRange)? in
                guard let r = f.videoSupportedFrameRateRanges.filter({ $0.maxFrameRate >= minRate })
                    .max(by: { $0.maxFrameRate < $1.maxFrameRate }) else { return nil }
                return (f, r)
            }
            // On a tie, prefer uncompressed YUV: the stick skips MJPEG encoding and we skip decoding.
            func raw(_ f: AVCaptureDevice.Format) -> Int { isUncompressed(f) ? 1 : 0 }
            if let best = candidates.max(by: {
                (pixels($0.0), $0.1.maxFrameRate, raw($0.0)) < (pixels($1.0), $1.1.maxFrameRate, raw($1.0))
            }) {
                return best
            }
        }
        return (nil, nil)
    }
}

/// Receives decoded frames and shows each one immediately on the display layer.
private final class FrameSink: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let queue = DispatchQueue(label: "shdong.video.frames", qos: .userInteractive)
    private let layer: AVSampleBufferDisplayLayer

    init(layer: AVSampleBufferDisplayLayer) { self.layer = layer }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        // Skip the layer's timing: show the frame now instead of at its presentation time.
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true),
           CFArrayGetCount(attachments) > 0 {
            let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(dict, Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                                 Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        if layer.status == .failed { layer.flush() }
        layer.enqueue(sampleBuffer)
    }
}
