import AVFoundation
import Foundation
import Testing
import os

@testable import DesktopVideoCompress

/// Builds real, throwaway video files so the compressor can be exercised
/// against actual bitstreams rather than mocks.
enum TestClipFactory {
    /// Writes a clip of moving noise-over-gradient. Noise matters: a flat color
    /// encodes to almost nothing and wouldn't exercise the bitrate logic.
    static func makeClip(
        at url: URL,
        width: Int = 1280,
        height: Int = 720,
        frameCount: Int = 60,
        frameRate: Int32 = 30,
        codec: AVVideoCodecType = .h264,
        bitrate: Int = 8_000_000,
        noisy: Bool = true
    ) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: codec,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: bitrate],
        ])
        input.expectsMediaDataInRealTime = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
            ]
        )

        writer.add(input)
        guard writer.startWriting() else {
            throw TestClipError.setupFailed(writer.error?.localizedDescription ?? "startWriting")
        }
        writer.startSession(atSourceTime: .zero)

        for frame in 0..<frameCount {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(5))
            }
            guard let pool = adaptor.pixelBufferPool else {
                throw TestClipError.setupFailed("no pixel buffer pool")
            }

            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer)
            guard let buffer else { throw TestClipError.setupFailed("no pixel buffer") }

            fill(buffer, frame: frame, width: width, height: height, noisy: noisy)
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: frameRate))
        }

        input.markAsFinished()
        await writer.finishWriting()

        guard writer.status == .completed else {
            throw TestClipError.setupFailed(writer.error?.localizedDescription ?? "status \(writer.status.rawValue)")
        }
    }

    private static func fill(_ buffer: CVPixelBuffer, frame: Int, width: Int, height: Int, noisy: Bool) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let pixels = base.assumingMemoryBound(to: UInt8.self)

        // Deterministic pseudo-noise so the encode is reproducible run to run.
        var seed = UInt32(truncatingIfNeeded: frame &* 2_654_435_761)
        func next() -> UInt8 {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            return UInt8(truncatingIfNeeded: seed >> 16)
        }

        guard noisy else { return fillScreenRecording(pixels, bytesPerRow: bytesPerRow, frame: frame, width: width, height: height) }

        for y in 0..<height {
            let row = pixels + y * bytesPerRow
            for x in 0..<width {
                let offset = x * 4
                let noise = next() / 4
                row[offset + 0] = UInt8((x &+ frame &* 3) % 256) / 2 &+ noise      // B
                row[offset + 1] = UInt8((y &+ frame &* 5) % 256) / 2 &+ noise      // G
                row[offset + 2] = UInt8((x &+ y &+ frame) % 256) / 2 &+ noise      // R
                row[offset + 3] = 255
            }
        }
    }

    /// Stands in for a screen recording: a static background with one small
    /// moving element. Whole-frame motion, as in the noisy generator, is not
    /// what this app mostly sees, and it hides the benefit of constant quality.
    private static func fillScreenRecording(
        _ pixels: UnsafeMutablePointer<UInt8>,
        bytesPerRow: Int,
        frame: Int,
        width: Int,
        height: Int
    ) {
        let cursorSize = 48
        let cursorX = (frame &* 7) % max(width - cursorSize, 1)
        let cursorY = (frame &* 3) % max(height - cursorSize, 1)

        for y in 0..<height {
            let row = pixels + y * bytesPerRow
            // Static "window chrome" bands plus a flat background.
            let band: UInt8 = y < height / 10 ? 60 : (y < height / 9 ? 90 : 34)
            for x in 0..<width {
                let offset = x * 4
                let inCursor = x >= cursorX && x < cursorX + cursorSize
                    && y >= cursorY && y < cursorY + cursorSize
                let value: UInt8 = inCursor ? 240 : (x % 320 < 2 ? 70 : band)
                row[offset + 0] = value
                row[offset + 1] = value
                row[offset + 2] = value
                row[offset + 3] = 255
            }
        }
    }

    enum TestClipError: Error {
        case setupFailed(String)
    }
}

@Suite("End-to-end compression", .serialized)
struct CompressionEndToEndTests {
    /// Each test gets its own scratch directory, removed afterwards.
    private func withScratchDirectory<T>(_ body: (URL) async throws -> T) async throws -> T {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("dvc-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        return try await body(directory)
    }

    private func size(of url: URL) -> Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.int64Value ?? 0
    }

    @Test("A generated H.264 clip is re-encoded to a readable, smaller HEVC MP4")
    func compressesRealClip() async throws {
        try await withScratchDirectory { directory in
            let source = directory.appendingPathComponent("clip.mov")
            let destination = directory.appendingPathComponent("out.mp4")
            try await TestClipFactory.makeClip(at: source)

            // Progress arrives on the encoder's queue, so it needs a lock.
            let highestProgress = OSAllocatedUnfairLock(initialState: 0.0)
            let result = try await VideoCompressor().compress(
                source: source,
                destination: destination,
                tier: .balanced,
                maxDimension: .original,
                progress: { value in
                    highestProgress.withLock { $0 = max($0, value) }
                }
            )

            #expect(result == .encoded)
            #expect(FileManager.default.fileExists(atPath: destination.path))
            let lastProgress = highestProgress.withLock { $0 }
            #expect(lastProgress > 0.5, "progress only reached \(lastProgress)")

            let output = AVURLAsset(url: destination)
            #expect(try await output.load(.isReadable))

            let sourceDuration = try await AVURLAsset(url: source).load(.duration).seconds
            let outputDuration = try await output.load(.duration).seconds
            #expect(abs(outputDuration - sourceDuration) < 0.1,
                    "duration drifted: \(sourceDuration) → \(outputDuration)")

            let track = try #require(try await output.loadTracks(withMediaType: .video).first)
            let naturalSize = try await track.load(.naturalSize)
            #expect(Int(naturalSize.width) == 1280)
            #expect(Int(naturalSize.height) == 720)

            let formatDescription = try #require(try await track.load(.formatDescriptions).first)
            #expect(CMFormatDescriptionGetMediaSubType(formatDescription) == kCMVideoCodecType_HEVC)

            // The source is a deliberately over-bitrated H.264 encode, so HEVC
            // at our target should be comfortably smaller.
            #expect(size(of: destination) < size(of: source))
        }
    }

    @Test("Compressible content lands far below the bitrate ceiling")
    func constantQualitySpendsFewerBitsOnEasyContent() async throws {
        try await withScratchDirectory { directory in
            let source = directory.appendingPathComponent("easy.mov")
            let destination = directory.appendingPathComponent("out.mp4")
            let seconds = 2.0
            try await TestClipFactory.makeClip(
                at: source, width: 1280, height: 720, frameCount: 60, noisy: false
            )

            #expect(try await VideoCompressor().compress(
                source: source,
                destination: destination,
                tier: .balanced,
                maxDimension: .original,
                progress: { _ in }
            ) == .encoded)

            let dimensions = VideoDimensions(width: 1280, height: 720)
            let target = EncodeSettings.targetBitrate(for: dimensions, frameRate: 30, tier: .balanced)
            let actualBitrate = Double(size(of: destination)) * 8 / seconds

            // Under average-bitrate control this would sit near the target
            // regardless of how little detail the content has. Constant quality
            // should come in far under it.
            #expect(actualBitrate < Double(target) * 0.25,
                    "expected well under \(target) bps, got \(Int(actualBitrate)) bps")
        }
    }

    @Test("Hard-to-encode content still respects the ceiling")
    func ceilingHoldsOnHardContent() async throws {
        try await withScratchDirectory { directory in
            let source = directory.appendingPathComponent("hard.mov")
            let destination = directory.appendingPathComponent("out.mp4")
            let seconds = 2.0
            // Full-frame noise: the worst case for any encoder, and what would
            // balloon without a data rate limit.
            try await TestClipFactory.makeClip(
                at: source, width: 1280, height: 720, frameCount: 60,
                bitrate: 40_000_000, noisy: true
            )

            _ = try await VideoCompressor().compress(
                source: source,
                destination: destination,
                tier: .balanced,
                maxDimension: .original,
                progress: { _ in }
            )

            let dimensions = VideoDimensions(width: 1280, height: 720)
            let target = EncodeSettings.targetBitrate(for: dimensions, frameRate: 30, tier: .balanced)
            let ceiling = Double(target) * EncodeSettings.ceilingMultiplier
            let actualBitrate = Double(size(of: destination)) * 8 / seconds

            // Container overhead on a 2s clip is a few percent, hence the slack.
            #expect(actualBitrate < ceiling * 1.25,
                    "expected under ~\(Int(ceiling)) bps, got \(Int(actualBitrate)) bps")
        }
    }

    @Test("Downscaling honours the maximum dimension setting")
    func downscales() async throws {
        try await withScratchDirectory { directory in
            let source = directory.appendingPathComponent("clip.mov")
            let destination = directory.appendingPathComponent("out.mp4")
            try await TestClipFactory.makeClip(at: source, width: 1920, height: 1080, frameCount: 30)

            let result = try await VideoCompressor().compress(
                source: source,
                destination: destination,
                tier: .balanced,
                maxDimension: .hd720,
                progress: { _ in }
            )

            #expect(result == .encoded)
            let track = try #require(
                try await AVURLAsset(url: destination).loadTracks(withMediaType: .video).first
            )
            let naturalSize = try await track.load(.naturalSize)
            #expect(Int(naturalSize.width) == 1280)
            #expect(Int(naturalSize.height) == 720)
        }
    }

    @Test("An already-efficient HEVC source is left alone")
    func skipsEfficientSource() async throws {
        try await withScratchDirectory { directory in
            let source = directory.appendingPathComponent("clip.mov")
            let destination = directory.appendingPathComponent("out.mp4")
            // Well below the ~1.2 Mbps a 640x360 target would ask for.
            try await TestClipFactory.makeClip(
                at: source,
                width: 640, height: 360, frameCount: 30,
                codec: .hevc, bitrate: 150_000
            )

            let result = try await VideoCompressor().compress(
                source: source,
                destination: destination,
                tier: .balanced,
                maxDimension: .original,
                progress: { _ in }
            )

            #expect(result == .alreadyEfficient)
            #expect(!FileManager.default.fileExists(atPath: destination.path),
                    "nothing should be written when we skip")
        }
    }

    @Test("A non-video file fails cleanly instead of producing garbage")
    func rejectsNonVideo() async throws {
        try await withScratchDirectory { directory in
            let source = directory.appendingPathComponent("not-a-video.mp4")
            try Data("this is definitely not an MP4".utf8).write(to: source)

            await #expect(throws: (any Error).self) {
                try await VideoCompressor().compress(
                    source: source,
                    destination: directory.appendingPathComponent("out.mp4"),
                    tier: .balanced,
                    maxDimension: .original,
                    progress: { _ in }
                )
            }
        }
    }

    @Test("Cancelling mid-encode throws rather than leaving a usable file")
    func cancellationStops() async throws {
        try await withScratchDirectory { directory in
            let source = directory.appendingPathComponent("clip.mov")
            let destination = directory.appendingPathComponent("out.mp4")
            try await TestClipFactory.makeClip(at: source, width: 1920, height: 1080, frameCount: 120)

            let compressor = VideoCompressor()
            let work = Task {
                try await compressor.compress(
                    source: source,
                    destination: destination,
                    tier: .higher,
                    maxDimension: .original,
                    progress: { _ in }
                )
            }

            try await Task.sleep(for: .milliseconds(150))
            compressor.cancel()

            await #expect(throws: (any Error).self) { try await work.value }
        }
    }

    @Test("The processed marker round-trips and is absent on untouched files")
    func processedMarker() async throws {
        try await withScratchDirectory { directory in
            let file = directory.appendingPathComponent("marked.mp4")
            try Data(count: 16).write(to: file)

            #expect(!ProcessedMarker.isMarked(file))
            #expect(ProcessedMarker.mark(file))
            #expect(ProcessedMarker.isMarked(file))

            // A marked file must not be picked up by the watcher again.
            #expect(!FolderWatcher.isCandidate(file))
        }
    }

    @Test("The watcher accepts a plain video and rejects the cases it should")
    func watcherCandidateRules() async throws {
        try await withScratchDirectory { directory in
            let video = directory.appendingPathComponent("clip.mp4")
            try Data(count: 16).write(to: video)
            #expect(FolderWatcher.isCandidate(video))

            let hidden = directory.appendingPathComponent(".clip.mp4")
            try Data(count: 16).write(to: hidden)
            #expect(!FolderWatcher.isCandidate(hidden))

            let partial = directory.appendingPathComponent("clip.mp4.download")
            try Data(count: 16).write(to: partial)
            #expect(!FolderWatcher.isCandidate(partial))

            let ourOutput = directory.appendingPathComponent("clip_compressed.mp4")
            try Data(count: 16).write(to: ourOutput)
            #expect(!FolderWatcher.isCandidate(ourOutput))

            let unsupported = directory.appendingPathComponent("clip.mkv")
            try Data(count: 16).write(to: unsupported)
            #expect(!FolderWatcher.isCandidate(unsupported))

            #expect(!FolderWatcher.isCandidate(directory.appendingPathComponent("ghost.mp4")))

            // Only the plain video should come back from a directory scan.
            let candidates = FolderWatcher.existingCandidates(in: directory).map(\.lastPathComponent)
            #expect(candidates == ["clip.mp4"])
        }
    }
}
