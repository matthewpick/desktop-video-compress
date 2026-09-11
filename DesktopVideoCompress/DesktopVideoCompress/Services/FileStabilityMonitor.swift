import AVFoundation
import Foundation
import os

struct FileSnapshot: Equatable, Sendable {
    var size: Int64
    var modified: Date
}

/// Decides when a file has stopped being written to.
///
/// This is the correctness detail the Python predecessor got wrong: it slept a
/// flat two seconds after the create event, which is nowhere near enough for a
/// screen recording that keeps growing for minutes.
struct StabilityTracker {
    enum Verdict: Equatable {
        /// Still changing (or not yet sampled enough times).
        case waiting
        /// Unchanged for `requiredStableSamples` consecutive samples.
        case settled
        /// The file disappeared — moved, renamed, or deleted.
        case missing
        /// Exceeded `maxSamples` without ever settling.
        case timedOut
    }

    let requiredStableSamples: Int
    let maxSamples: Int

    private var lastSnapshot: FileSnapshot?
    private var consecutiveStable = 0
    private var samplesTaken = 0

    init(requiredStableSamples: Int = 3, maxSamples: Int = 7200) {
        self.requiredStableSamples = requiredStableSamples
        self.maxSamples = maxSamples
    }

    /// Feed one observation. `nil` means the file is no longer there.
    mutating func record(_ snapshot: FileSnapshot?) -> Verdict {
        samplesTaken += 1

        guard let snapshot else { return .missing }

        if let lastSnapshot, lastSnapshot == snapshot {
            consecutiveStable += 1
        } else {
            // Size or mtime moved: the writer is still going, start over.
            consecutiveStable = 1
        }
        lastSnapshot = snapshot

        if consecutiveStable >= requiredStableSamples { return .settled }
        if samplesTaken >= maxSamples { return .timedOut }
        return .waiting
    }
}

/// Polls a file until it stops changing and AVFoundation can actually open it.
final class FileStabilityMonitor: Sendable {
    private let logger = Logger(subsystem: AppInfo.subsystem, category: "FileStabilityMonitor")

    let pollInterval: Duration
    let requiredStableSamples: Int
    let maxSamples: Int

    /// Defaults: a sample every second, settled after 3 quiet seconds, give up
    /// after two hours — long enough for a feature-length screen recording.
    init(
        pollInterval: Duration = .seconds(1),
        requiredStableSamples: Int = 3,
        maxSamples: Int = 7200
    ) {
        self.pollInterval = pollInterval
        self.requiredStableSamples = requiredStableSamples
        self.maxSamples = maxSamples
    }

    static func snapshot(of url: URL) -> FileSnapshot? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber,
              let modified = attributes[.modificationDate] as? Date else { return nil }
        return FileSnapshot(size: size.int64Value, modified: modified)
    }

    /// Returns true once the file is stable and readable as video.
    /// Returns false if it vanished, timed out, or never became readable.
    func waitUntilReady(_ url: URL) async -> Bool {
        var tracker = StabilityTracker(
            requiredStableSamples: requiredStableSamples,
            maxSamples: maxSamples
        )

        while true {
            if Task.isCancelled { return false }

            switch tracker.record(Self.snapshot(of: url)) {
            case .waiting:
                break
            case .missing:
                logger.info("\(url.lastPathComponent, privacy: .public) disappeared while settling")
                return false
            case .timedOut:
                logger.error("\(url.lastPathComponent, privacy: .public) never stopped changing; giving up")
                return false
            case .settled:
                // Size can go quiet before the moov atom is written, so a
                // stable file is not automatically a playable one.
                if await isReadableVideo(url) { return true }
                logger.info("\(url.lastPathComponent, privacy: .public) is stable but not yet readable; still waiting")
                tracker = StabilityTracker(
                    requiredStableSamples: requiredStableSamples,
                    maxSamples: maxSamples
                )
            }

            do {
                try await Task.sleep(for: pollInterval)
            } catch {
                return false
            }
        }
    }

    private func isReadableVideo(_ url: URL) async -> Bool {
        let asset = AVURLAsset(url: url)
        do {
            guard try await asset.load(.isReadable) else { return false }
            let duration = try await asset.load(.duration)
            guard duration.isValid, duration.seconds > 0 else { return false }
            return try await !asset.loadTracks(withMediaType: .video).isEmpty
        } catch {
            return false
        }
    }
}
