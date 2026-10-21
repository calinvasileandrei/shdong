import Darwin
import Foundation

/// Raw POSIX serial port. Reads arrive on `queue` via a DispatchSource; writes are synchronous
/// on the same queue (frames are a few bytes, so they go out immediately).
final class SerialPort {
    enum Error: Swift.Error, CustomStringConvertible {
        case open(String, Int32), configure(Int32)
        var description: String {
            switch self {
            case let .open(path, e): return "open \(path): \(String(cString: strerror(e)))"
            case let .configure(e): return "configure: \(String(cString: strerror(e)))"
            }
        }
    }

    // _IO('t', 121) / _IO('t', 120): function-like macros, not imported into Swift.
    private static let TIOCSDTR: UInt = 0x2000_7479
    private static let TIOCCDTR: UInt = 0x2000_7478

    let path: String
    private let queue: DispatchQueue
    private var fd: Int32 = -1
    private var source: DispatchSourceRead?

    var onData: (([UInt8]) -> Void)?
    var onClose: (() -> Void)?

    init(path: String, queue: DispatchQueue) {
        self.path = path
        self.queue = queue
    }

    func open() throws {
        let fd = Darwin.open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard fd >= 0 else { throw Error.open(path, errno) }

        var t = termios()
        guard tcgetattr(fd, &t) == 0 else { let e = errno; Darwin.close(fd); throw Error.configure(e) }
        cfmakeraw(&t)
        t.c_cflag |= tcflag_t(CLOCAL | CREAD | HUPCL)
        // Baud is irrelevant for USB CDC, but set something sane for real UARTs.
        cfsetspeed(&t, speed_t(B115200))
        guard tcsetattr(fd, TCSANOW, &t) == 0 else { let e = errno; Darwin.close(fd); throw Error.configure(e) }
        tcflush(fd, TCIOFLUSH)
        // DTR tells the bridge the app is connected; dropping it makes it send RELEASE_ALL.
        // Fails harmlessly on a pseudo-terminal (mock bridge).
        _ = ioctl(fd, Self.TIOCSDTR)

        self.fd = fd
        let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        src.setEventHandler { [weak self] in self?.readAvailable() }
        src.setCancelHandler { _ = ioctl(fd, Self.TIOCCDTR); Darwin.close(fd) }
        source = src
        src.resume()
    }

    /// Must be called on `queue`.
    func write(_ bytes: [UInt8]) {
        guard fd >= 0 else { return }
        var off = 0
        while off < bytes.count {
            let n = bytes[off...].withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
            if n > 0 {
                off += n
            } else if n < 0 && (errno == EAGAIN || errno == EINTR) {
                usleep(200) // CDC buffer momentarily full
            } else {
                fail()
                return
            }
        }
    }

    /// Must be called on `queue`.
    func close() {
        guard fd >= 0 else { return }
        fd = -1
        source?.cancel()
        source = nil
    }

    private func readAvailable() {
        var buf = [UInt8](repeating: 0, count: 512)
        let n = buf.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
        if n > 0 {
            onData?(Array(buf[0..<n]))
        } else if n == 0 || (errno != EAGAIN && errno != EINTR) {
            fail() // device unplugged
        }
    }

    private func fail() {
        close()
        onClose?()
    }
}
