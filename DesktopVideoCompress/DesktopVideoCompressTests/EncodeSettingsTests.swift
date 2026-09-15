import Testing

@testable import DesktopVideoCompress

@Suite("Encode settings")
struct EncodeSettingsTests {
    // MARK: - Dimensions

    @Test("Original keeps the source size")
    func originalKeepsSize() {
        let source = VideoDimensions(width: 3840, height: 2160)
        #expect(EncodeSettings.targetDimensions(for: source, maxDimension: .original) == source)
    }

    @Test("A cap larger than the source never upscales")
    func neverUpscales() {
        let source = VideoDimensions(width: 640, height: 480)
        #expect(EncodeSettings.targetDimensions(for: source, maxDimension: .uhd4K) == source)
    }

    @Test("Downscaling preserves aspect ratio", arguments: [
        (MaxDimension.hd1080, VideoDimensions(width: 1920, height: 1080)),
        (MaxDimension.hd720, VideoDimensions(width: 1280, height: 720)),
        (MaxDimension.uhd4K, VideoDimensions(width: 3840, height: 2160)),
    ])
    func downscalePreservesAspect(limit: MaxDimension, expected: VideoDimensions) {
        let source = VideoDimensions(width: 7680, height: 4320)
        #expect(EncodeSettings.targetDimensions(for: source, maxDimension: limit) == expected)
    }

    @Test("Portrait video is capped on its longest edge")
    func portraitUsesLongestEdge() {
        let source = VideoDimensions(width: 1080, height: 3840)
        let target = EncodeSettings.targetDimensions(for: source, maxDimension: .hd1080)
        #expect(target.height == 1920)
        #expect(target.width == 540)
    }

    @Test("Output dimensions are always even")
    func dimensionsAreEven() {
        // 4:3 at an awkward size: a naive scale gives odd numbers.
        let source = VideoDimensions(width: 1999, height: 1501)
        for limit in MaxDimension.allCases {
            let target = EncodeSettings.targetDimensions(for: source, maxDimension: limit)
            #expect(target.width % 2 == 0, "width \(target.width) for \(limit)")
            #expect(target.height % 2 == 0, "height \(target.height) for \(limit)")
        }
    }

    @Test("Zero-sized input is passed through rather than crashing")
    func zeroSizeIsSafe() {
        let source = VideoDimensions(width: 0, height: 0)
        #expect(EncodeSettings.targetDimensions(for: source, maxDimension: .hd1080) == source)
    }

    // MARK: - Bitrate

    @Test("Higher tiers produce higher bitrates")
    func tiersAreOrdered() {
        let dimensions = VideoDimensions(width: 1920, height: 1080)
        let smaller = EncodeSettings.targetBitrate(for: dimensions, frameRate: 30, tier: .smaller)
        let balanced = EncodeSettings.targetBitrate(for: dimensions, frameRate: 30, tier: .balanced)
        let higher = EncodeSettings.targetBitrate(for: dimensions, frameRate: 30, tier: .higher)

        #expect(smaller < balanced)
        #expect(balanced < higher)
    }

    @Test("1080p30 balanced lands in a sane range")
    func plausibleFor1080p() {
        let bitrate = EncodeSettings.targetBitrate(
            for: VideoDimensions(width: 1920, height: 1080),
            frameRate: 30,
            tier: .balanced
        )
        #expect(bitrate > 3_000_000)
        #expect(bitrate < 8_000_000)
    }

    @Test("4K60 balanced lands in a sane range")
    func plausibleFor4K60() {
        let bitrate = EncodeSettings.targetBitrate(
            for: VideoDimensions(width: 3840, height: 2160),
            frameRate: 60,
            tier: .balanced
        )
        #expect(bitrate > 12_000_000)
        #expect(bitrate < 35_000_000)
    }

    @Test("Frame rate scales the bitrate sub-linearly")
    func frameRateIsSubLinear() {
        let dimensions = VideoDimensions(width: 1920, height: 1080)
        let at30 = EncodeSettings.targetBitrate(for: dimensions, frameRate: 30, tier: .balanced)
        let at60 = EncodeSettings.targetBitrate(for: dimensions, frameRate: 60, tier: .balanced)

        #expect(at60 > at30)
        #expect(at60 < at30 * 2)
    }

    @Test("Higher resolutions get fewer bits per pixel")
    func bitsPerPixelDecreases() {
        let ladder = [640 * 480, 1920 * 1080, 2560 * 1440, 3840 * 2160]
            .map(EncodeSettings.bitsPerPixel(forPixelCount:))
        #expect(ladder == ladder.sorted(by: >))
    }

    @Test("Degenerate inputs clamp to the floor instead of producing nonsense", arguments: [
        Double.nan, 0, -30,
    ])
    func invalidFrameRatesAreHandled(frameRate: Double) {
        let bitrate = EncodeSettings.targetBitrate(
            for: VideoDimensions(width: 1920, height: 1080),
            frameRate: frameRate,
            tier: .balanced
        )
        #expect(bitrate >= EncodeSettings.minimumBitrate)
        #expect(bitrate <= EncodeSettings.maximumBitrate)
    }

    @Test("An absurd resolution is capped at the ceiling")
    func ceilingApplies() {
        let bitrate = EncodeSettings.targetBitrate(
            for: VideoDimensions(width: 15360, height: 8640),
            frameRate: 120,
            tier: .higher
        )
        #expect(bitrate == EncodeSettings.maximumBitrate)
    }

    // MARK: - Constant quality

    @Test("Quality levels are ordered and stay inside VideoToolbox's 0…1 range")
    func qualityLevelsAreOrdered() {
        let levels = [QualityTier.smaller, .balanced, .higher].map(\.qualityLevel)
        #expect(levels == levels.sorted())
        #expect(levels.allSatisfy { $0 > 0 && $0 < 1 })
    }

    @Test("The data rate ceiling sits above the target, not on it")
    func ceilingExceedsTarget() {
        let dimensions = VideoDimensions(width: 1920, height: 1080)
        let target = EncodeSettings.targetBitrate(for: dimensions, frameRate: 30, tier: .balanced)

        let limits = EncodeSettings.dataRateLimits(for: dimensions, frameRate: 30, tier: .balanced)
        let bytesPerWindow = try! #require(limits.first as? Int)
        let seconds = try! #require(limits.last as? Int)

        // A ceiling equal to the target would just be ABR by another name.
        #expect(seconds == 1)
        #expect(bytesPerWindow * 8 > target)
        #expect(Double(bytesPerWindow * 8) <= Double(target) * EncodeSettings.ceilingMultiplier * 1.01)
    }

    @Test("The ceiling is expressed as [bytes, seconds] for VideoToolbox")
    func ceilingShape() {
        let limits = EncodeSettings.dataRateLimits(
            for: VideoDimensions(width: 1280, height: 720),
            frameRate: 30,
            tier: .balanced
        )
        #expect(limits.count == 2)
        #expect(limits.allSatisfy { $0 is Int })
    }

    @Test("A tiny thumbnail-sized clip is raised to the floor")
    func floorApplies() {
        let bitrate = EncodeSettings.targetBitrate(
            for: VideoDimensions(width: 16, height: 16),
            frameRate: 1,
            tier: .smaller
        )
        #expect(bitrate == EncodeSettings.minimumBitrate)
    }
}
