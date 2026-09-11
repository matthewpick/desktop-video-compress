import Foundation

/// How aggressively to compress. Scales the computed target bitrate.
enum QualityTier: String, CaseIterable, Identifiable, Sendable {
    case smaller
    case balanced
    case higher

    var id: String { rawValue }

    var multiplier: Double {
        switch self {
        case .smaller: 0.7
        case .balanced: 1.0
        case .higher: 1.5
        }
    }

    var displayName: String {
        switch self {
        case .smaller: "Smaller file"
        case .balanced: "Balanced"
        case .higher: "Higher quality"
        }
    }
}

/// Optional cap on the output's longest edge. Anything at or below the cap is
/// left at its native size — we never upscale.
enum MaxDimension: String, CaseIterable, Identifiable, Sendable {
    case original
    case uhd4K
    case hd1080
    case hd720

    var id: String { rawValue }

    /// Longest-edge limit in pixels, or nil for "keep native resolution".
    var longestEdge: Int? {
        switch self {
        case .original: nil
        case .uhd4K: 3840
        case .hd1080: 1920
        case .hd720: 1280
        }
    }

    var displayName: String {
        switch self {
        case .original: "Original"
        case .uhd4K: "4K (3840px)"
        case .hd1080: "1080p (1920px)"
        case .hd720: "720p (1280px)"
        }
    }
}

struct VideoDimensions: Equatable, Sendable {
    var width: Int
    var height: Int

    var pixelCount: Int { width * height }
}

/// Pure bitrate/resolution math, kept free of AVFoundation so it can be tested
/// directly. `VideoCompressor` is the only caller.
enum EncodeSettings {
    /// Absolute bounds, so a pathological input can't ask for a 2 Kbps or
    /// 500 Mbps encode.
    static let minimumBitrate = 300_000
    static let maximumBitrate = 60_000_000

    /// Bits per pixel per frame at 30fps. Higher resolutions need fewer bits
    /// per pixel to look equivalent, hence the ladder rather than a constant.
    static func bitsPerPixel(forPixelCount pixels: Int) -> Double {
        switch pixels {
        case ..<921_601: 0.100      // up to 720p
        case ..<2_073_601: 0.080    // up to 1080p
        case ..<3_686_401: 0.065    // up to 1440p
        default: 0.050              // 4K and beyond
        }
    }

    /// Scale the source down to fit `maxDimension`, preserving aspect ratio.
    /// Dimensions are rounded to even numbers because H.265 chroma subsampling
    /// requires it.
    static func targetDimensions(for source: VideoDimensions, maxDimension: MaxDimension) -> VideoDimensions {
        guard source.width > 0, source.height > 0 else { return source }
        guard let limit = maxDimension.longestEdge else { return evenized(source) }

        let longest = max(source.width, source.height)
        guard longest > limit else { return evenized(source) }

        let scale = Double(limit) / Double(longest)
        return evenized(VideoDimensions(
            width: Int((Double(source.width) * scale).rounded()),
            height: Int((Double(source.height) * scale).rounded())
        ))
    }

    /// Target average bitrate in bits/second for the given output geometry.
    ///
    /// Frame rate scales sub-linearly (`^0.7`): 60fps content needs more bits
    /// than 30fps, but nowhere near double, because consecutive frames are more
    /// similar the faster you sample.
    static func targetBitrate(
        for dimensions: VideoDimensions,
        frameRate: Double,
        tier: QualityTier
    ) -> Int {
        let pixels = max(dimensions.pixelCount, 1)
        let fps = frameRate.isFinite && frameRate > 0 ? frameRate : 30
        let fpsFactor = pow(fps / 30.0, 0.7)

        let bits = Double(pixels) * 30.0 * bitsPerPixel(forPixelCount: pixels) * fpsFactor * tier.multiplier
        return min(max(Int(bits), minimumBitrate), maximumBitrate)
    }

    /// Rounds both edges down to even values, never below 2.
    private static func evenized(_ dimensions: VideoDimensions) -> VideoDimensions {
        VideoDimensions(
            width: max(2, dimensions.width - (dimensions.width % 2)),
            height: max(2, dimensions.height - (dimensions.height % 2))
        )
    }
}
