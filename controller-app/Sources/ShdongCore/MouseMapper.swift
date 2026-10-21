import CoreGraphics

public enum MouseMapper {
    public static let absMax: Double = 32767

    /// Rect the video occupies inside a view when aspect-fit (letterbox/pillarbox).
    public static func videoRect(viewSize: CGSize, videoSize: CGSize) -> CGRect {
        guard viewSize.width > 0, viewSize.height > 0, videoSize.width > 0, videoSize.height > 0 else {
            return CGRect(origin: .zero, size: viewSize)
        }
        let scale = min(viewSize.width / videoSize.width, viewSize.height / videoSize.height)
        let w = videoSize.width * scale
        let h = videoSize.height * scale
        return CGRect(x: (viewSize.width - w) / 2, y: (viewSize.height - h) / 2, width: w, height: h)
    }

    /// Maps a point in view coordinates (bottom-left origin, as in AppKit) to 0..32767 on both axes.
    /// Points outside the video are clamped to its edge; `inside` says whether it was in the video.
    public static func map(_ p: CGPoint, viewSize: CGSize, videoSize: CGSize)
        -> (x: UInt16, y: UInt16, inside: Bool)
    {
        let r = videoRect(viewSize: viewSize, videoSize: videoSize)
        guard r.width > 0, r.height > 0 else { return (0, 0, false) }
        let fx = (p.x - r.minX) / r.width
        let fy = 1 - (p.y - r.minY) / r.height // flip: HID y grows downwards
        let inside = (0...1).contains(fx) && (0...1).contains(fy)
        return (scale(fx), scale(fy), inside)
    }

    static func scale(_ f: Double) -> UInt16 {
        UInt16((min(max(f, 0), 1) * absMax).rounded())
    }
}

/// Converts fine-grained scroll deltas (trackpads give pixels) into whole wheel ticks,
/// carrying the remainder so slow scrolls still add up.
public struct ScrollAccumulator {
    public var pointsPerTick: Double
    private var remainder: Double = 0

    public init(pointsPerTick: Double) { self.pointsPerTick = pointsPerTick }

    /// `precise` deltas are in points; non-precise ones (classic wheels) are already in lines.
    public mutating func ticks(delta: Double, precise: Bool) -> Int8 {
        if !precise {
            remainder = 0
            let lines = delta.rounded(.awayFromZero)
            return Int8(max(-127, min(127, delta == 0 ? 0 : lines)))
        }
        remainder += delta / pointsPerTick
        let whole = remainder.rounded(.towardZero)
        remainder -= whole
        return Int8(max(-127, min(127, whole)))
    }

    public mutating func reset() { remainder = 0 }
}
