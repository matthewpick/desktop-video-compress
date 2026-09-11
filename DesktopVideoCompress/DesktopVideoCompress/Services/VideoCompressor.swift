import AVFoundation
import VideoToolbox
import os

enum CompressionError: LocalizedError {
    case unreadable
    case noVideoTrack
    case readerFailed(String)
    case writerFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .unreadable: "The file could not be read as video."
        case .noVideoTrack: "The file has no video track."
        case .readerFailed(let message): "Could not read the source: \(message)"
        case .writerFailed(let message): "Could not write the output: \(message)"
        case .cancelled: "Cancelled."
        }
    }
}

/// What a single `compress` call decided to do.
enum CompressionResult: Sendable {
    /// An output file was written at the destination URL.
    case encoded
    /// Nothing was written — the source was already at or below our target.
    case alreadyEfficient
}

/// Re-encodes a video to HEVC in an MP4 container using an
/// `AVAssetReader` → `AVAssetWriter` pipeline.
///
/// `AVAssetExportSession` would be far less code, but its presets pin the
/// output to a fixed resolution and give no control over bitrate, which is the
/// entire point of this app.
///
/// One instance handles one file. `cancel()` is safe to call from any thread.
final class VideoCompressor: @unchecked Sendable {
    private let logger = Logger(subsystem: AppInfo.subsystem, category: "VideoCompressor")

    private let stateLock = NSLock()
    private var cancelled = false

    /// Requests cancellation. Safe to call from any thread, including while an
    /// encode is in flight.
    ///
    /// This only raises a flag. Tearing the reader and writer down here would
    /// deadlock: `cancelWriting()` makes AVFoundation stop invoking the
    /// `requestMediaDataWhenReady` block, so the pump would never reach
    /// `markAsFinished()` and `compress` would wait forever. Instead the pump
    /// notices the flag on its next turn and finishes normally, after which
    /// `compress` tears both sides down.
    func cancel() {
        stateLock.lock()
        cancelled = true
        stateLock.unlock()
    }

    private var isCancelled: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return cancelled
    }

    /// Encodes `source` into `destination`, reporting 0…1 progress.
    ///
    /// `destination` should be a temp path on the same volume as the final
    /// location — the caller moves it into place only on success, so a
    /// half-written file never appears in the watched folder.
    func compress(
        source: URL,
        destination: URL,
        tier: QualityTier,
        maxDimension: MaxDimension,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> CompressionResult {
        let asset = AVURLAsset(url: source, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])

        guard try await asset.load(.isReadable) else { throw CompressionError.unreadable }
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw CompressionError.noVideoTrack
        }

        let info = try await SourceVideoInfo(asset: asset, track: videoTrack)
        let target = EncodeSettings.targetDimensions(for: info.dimensions, maxDimension: maxDimension)
        let bitrate = EncodeSettings.targetBitrate(for: target, frameRate: info.frameRate, tier: tier)

        // Re-encoding HEVC that's already at or below our target just loses a
        // generation of quality for no size win. Only skip when we also aren't
        // being asked to downscale.
        if target == info.dimensions,
           info.isHEVC,
           info.estimatedBitrate > 0,
           info.estimatedBitrate <= Double(bitrate) * 1.05 {
            logger.info("Skipping already-efficient HEVC source at \(Int(info.estimatedBitrate)) bps")
            return .alreadyEfficient
        }

        let reader = try AVAssetReader(asset: asset)
        let writer = try AVAssetWriter(outputURL: destination, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true  // faststart, like HandBrake's --optimize

        if isCancelled { throw CompressionError.cancelled }

        // MARK: Video

        let videoOutput = AVAssetReaderTrackOutput(
            track: videoTrack,
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: info.decodePixelFormat]
        )
        videoOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(videoOutput) else {
            throw CompressionError.readerFailed("cannot decode video track")
        }
        reader.add(videoOutput)

        let videoInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: videoOutputSettings(target: target, bitrate: bitrate, info: info)
        )
        videoInput.expectsMediaDataInRealTime = false
        // Rotation stays metadata, so the encoder works on the un-rotated
        // buffers and portrait clips don't come out sideways.
        videoInput.transform = info.transform
        guard writer.canAdd(videoInput) else {
            throw CompressionError.writerFailed("cannot add HEVC video input")
        }
        writer.add(videoInput)

        // MARK: Audio

        var audioPair: (input: AVAssetWriterInput, output: AVAssetReaderOutput)?
        if let audioTrack = try await asset.loadTracks(withMediaType: .audio).first {
            audioPair = try await makeAudioPair(track: audioTrack, reader: reader, writer: writer)
        }

        // MARK: Run

        guard reader.startReading() else {
            throw CompressionError.readerFailed(reader.error?.localizedDescription ?? "unknown")
        }
        guard writer.startWriting() else {
            throw CompressionError.writerFailed(writer.error?.localizedDescription ?? "unknown")
        }
        writer.startSession(atSourceTime: info.startTime)

        let durationSeconds = info.duration.seconds
        let startSeconds = info.startTime.seconds

        await runPumps(
            video: (videoInput, videoOutput),
            audio: audioPair,
            onVideoSample: { presentationTime in
                guard durationSeconds > 0 else { return }
                let elapsed = presentationTime.seconds - startSeconds
                progress(min(max(elapsed / durationSeconds, 0), 1))
            }
        )

        if isCancelled {
            reader.cancelReading()
            writer.cancelWriting()
            throw CompressionError.cancelled
        }

        if reader.status == .failed {
            writer.cancelWriting()
            throw CompressionError.readerFailed(reader.error?.localizedDescription ?? "unknown")
        }

        await writer.finishWriting()

        guard writer.status == .completed else {
            if isCancelled { throw CompressionError.cancelled }
            throw CompressionError.writerFailed(writer.error?.localizedDescription ?? "status \(writer.status.rawValue)")
        }

        progress(1)
        return .encoded
    }

    // MARK: - Settings

    private func videoOutputSettings(
        target: VideoDimensions,
        bitrate: Int,
        info: SourceVideoInfo
    ) -> [String: Any] {
        var compression: [String: Any] = [
            AVVideoAverageBitRateKey: bitrate,
            AVVideoExpectedSourceFrameRateKey: Int(info.frameRate.rounded()),
            AVVideoMaxKeyFrameIntervalDurationKey: 2.0,
            AVVideoAllowFrameReorderingKey: true,
            AVVideoProfileLevelKey: info.isHDR
                ? kVTProfileLevel_HEVC_Main10_AutoLevel as String
                : kVTProfileLevel_HEVC_Main_AutoLevel as String,
        ]
        if info.isHDR {
            compression[kVTCompressionPropertyKey_HDRMetadataInsertionMode as String] =
                kVTHDRMetadataInsertionMode_Auto as String
        }

        var settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: target.width,
            AVVideoHeightKey: target.height,
            AVVideoScalingModeKey: AVVideoScalingModeResizeAspect,
            AVVideoCompressionPropertiesKey: compression,
        ]
        // All three color tags must be present together or AVFoundation
        // rejects the dictionary, so this is all-or-nothing.
        if let colorProperties = info.colorProperties {
            settings[AVVideoColorPropertiesKey] = colorProperties
        }
        return settings
    }

    private func makeAudioPair(
        track: AVAssetTrack,
        reader: AVAssetReader,
        writer: AVAssetWriter
    ) async throws -> (input: AVAssetWriterInput, output: AVAssetReaderOutput)? {
        let formatDescriptions = try await track.load(.formatDescriptions)
        let sourceFormat = formatDescriptions.first
        let estimatedRate = Double(try await track.load(.estimatedDataRate))

        var channels = 2
        var sampleRate = 44_100.0
        var isAAC = false
        if let sourceFormat, let basic = CMAudioFormatDescriptionGetStreamBasicDescription(sourceFormat)?.pointee {
            channels = Int(basic.mChannelsPerFrame)
            sampleRate = basic.mSampleRate
            isAAC = basic.mFormatID == kAudioFormatMPEG4AAC
        }

        // Pass through when re-encoding would cost quality for no real win, and
        // for >2 channels, where an AAC encode would need an explicit channel
        // layout we have no good way to choose.
        let shouldPassThrough = channels > 2 || (isAAC && estimatedRate > 0 && estimatedRate <= 160_000)

        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: shouldPassThrough ? nil : [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ]
        )
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return nil }

        let input: AVAssetWriterInput
        if shouldPassThrough {
            input = AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: sourceFormat)
        } else {
            input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: max(channels, 1),
                AVSampleRateKey: sampleRate,
                AVEncoderBitRateKey: 128_000,
            ])
        }
        input.expectsMediaDataInRealTime = false
        guard writer.canAdd(input) else { return nil }

        reader.add(output)
        writer.add(input)
        return (input, output)
    }

    // MARK: - Sample pump

    /// Drives both writer inputs concurrently and returns once each has been
    /// marked finished.
    private func runPumps(
        video: (AVAssetWriterInput, AVAssetReaderOutput),
        audio: (input: AVAssetWriterInput, output: AVAssetReaderOutput)?,
        onVideoSample: @escaping @Sendable (CMTime) -> Void
    ) async {
        await withCheckedContinuation { continuation in
            let group = DispatchGroup()

            group.enter()
            startPump(
                input: video.0,
                output: video.1,
                queue: DispatchQueue(label: "\(AppInfo.subsystem).pump.video"),
                group: group,
                onSample: onVideoSample
            )

            if let audio {
                group.enter()
                startPump(
                    input: audio.input,
                    output: audio.output,
                    queue: DispatchQueue(label: "\(AppInfo.subsystem).pump.audio"),
                    group: group,
                    onSample: nil
                )
            }

            group.notify(queue: .global(qos: .utility)) {
                continuation.resume()
            }
        }
    }

    private func startPump(
        input: AVAssetWriterInput,
        output: AVAssetReaderOutput,
        queue: DispatchQueue,
        group: DispatchGroup,
        onSample: (@Sendable (CMTime) -> Void)?
    ) {
        // AVFoundation may invoke the ready-block again after we finish, so a
        // one-shot guard keeps `group.leave()` balanced.
        let finished = OSAllocatedUnfairLock(initialState: false)

        func finish() {
            let alreadyFinished = finished.withLock { state -> Bool in
                if state { return true }
                state = true
                return false
            }
            guard !alreadyFinished else { return }
            input.markAsFinished()
            group.leave()
        }

        input.requestMediaDataWhenReady(on: queue) { [weak self] in
            guard let self else { return finish() }

            while input.isReadyForMoreMediaData {
                if self.isCancelled { return finish() }
                guard let buffer = output.copyNextSampleBuffer() else { return finish() }

                onSample?(CMSampleBufferGetPresentationTimeStamp(buffer))

                if !input.append(buffer) { return finish() }
            }
        }
    }
}

// MARK: - Source inspection

/// The handful of source properties the encoder needs, loaded once up front.
private struct SourceVideoInfo {
    var dimensions: VideoDimensions
    var frameRate: Double
    var estimatedBitrate: Double
    var isHEVC: Bool
    var isHDR: Bool
    var transform: CGAffineTransform
    var colorProperties: [String: Any]?
    var startTime: CMTime
    var duration: CMTime

    var decodePixelFormat: OSType {
        isHDR ? kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
              : kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
    }

    init(asset: AVAsset, track: AVAssetTrack) async throws {
        let (naturalSize, transform, nominalFrameRate, estimatedDataRate, formatDescriptions, timeRange) =
            try await track.load(
                .naturalSize, .preferredTransform, .nominalFrameRate,
                .estimatedDataRate, .formatDescriptions, .timeRange
            )

        dimensions = VideoDimensions(
            width: Int(abs(naturalSize.width).rounded()),
            height: Int(abs(naturalSize.height).rounded())
        )
        self.transform = transform
        frameRate = nominalFrameRate > 0 ? Double(nominalFrameRate) : 30
        estimatedBitrate = Double(estimatedDataRate)
        startTime = timeRange.start
        duration = try await asset.load(.duration)

        let formatDescription = formatDescriptions.first
        let subType = formatDescription.map { CMFormatDescriptionGetMediaSubType($0) }
        isHEVC = subType == kCMVideoCodecType_HEVC || subType == kCMVideoCodecType_HEVCWithAlpha

        let extensions = formatDescription
            .flatMap { CMFormatDescriptionGetExtensions($0) as? [String: Any] }
        let primaries = extensions?[kCVImageBufferColorPrimariesKey as String]
        let transfer = extensions?[kCVImageBufferTransferFunctionKey as String]
        let matrix = extensions?[kCVImageBufferYCbCrMatrixKey as String]

        if let primaries, let transfer, let matrix {
            colorProperties = [
                AVVideoColorPrimariesKey: primaries,
                AVVideoTransferFunctionKey: transfer,
                AVVideoYCbCrMatrixKey: matrix,
            ]
        }

        let transferString = transfer as? String
        isHDR = transferString == (kCVImageBufferTransferFunction_ITU_R_2100_HLG as String)
            || transferString == (kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ as String)
    }
}
