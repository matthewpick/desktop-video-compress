import Foundation
import Observation
import os

/// Runs compression jobs one at a time and keeps the state the menu renders.
///
/// Serial on purpose: two concurrent 4K HEVC encodes just contend for the same
/// media engine and finish later than if they'd queued.
@MainActor
@Observable
final class CompressionQueue {
    /// Below this, the re-encode isn't worth swapping the file for.
    static let minimumSavingsFraction = 0.05
    static let recentJobLimit = 20

    private(set) var pending: [CompressionJob] = []
    private(set) var current: CompressionJob?
    private(set) var currentProgress: Double = 0
    private(set) var completed: [CompletedJob] = []

    var isPaused = false {
        didSet { if !isPaused { drain() } }
    }

    private let logger = Logger(subsystem: AppInfo.subsystem, category: "CompressionQueue")
    private let stabilityMonitor: FileStabilityMonitor
    private let notifications: NotificationService

    /// Paths queued or in flight, so repeated FSEvents for one file collapse
    /// into a single job.
    private var trackedPaths: Set<String> = []
    private var activeCompressor: VideoCompressor?
    private var drainTask: Task<Void, Never>?

    /// `notifications` defaults to the shared service; it's an explicit `nil`
    /// rather than a default argument because default arguments are evaluated
    /// outside the main actor.
    init(
        stabilityMonitor: FileStabilityMonitor = FileStabilityMonitor(),
        notifications: NotificationService? = nil
    ) {
        self.stabilityMonitor = stabilityMonitor
        self.notifications = notifications ?? .shared
    }

    var isBusy: Bool { current != nil }

    // MARK: - Intake

    func enqueue(_ url: URL) {
        let path = url.standardizedFileURL.path
        guard !trackedPaths.contains(path) else { return }

        trackedPaths.insert(path)
        pending.append(CompressionJob(source: url))
        logger.info("Queued \(url.lastPathComponent, privacy: .public)")
        drain()
    }

    func cancelCurrent() {
        activeCompressor?.cancel()
    }

    /// Puts a trashed original back and removes the compressed replacement.
    func undo(_ job: CompletedJob) {
        guard case .compressed(let outputURL, _, _, let trashURL) = job.outcome,
              let trashURL else { return }

        let restoreURL = outputURL.deletingLastPathComponent().appendingPathComponent(job.sourceName)
        do {
            try FileManager.default.moveItem(at: trashURL, to: restoreURL)
            try? FileManager.default.removeItem(at: outputURL)
            completed.removeAll { $0.id == job.id }
            logger.info("Undid \(job.sourceName, privacy: .public)")
        } catch {
            logger.error("Undo failed for \(job.sourceName, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Draining

    private func drain() {
        guard drainTask == nil else { return }

        drainTask = Task { [weak self] in
            while let self, !self.isPaused, !self.pending.isEmpty {
                let job = self.pending.removeFirst()
                self.current = job
                self.currentProgress = 0

                let outcome = await self.process(job)

                self.trackedPaths.remove(job.source.standardizedFileURL.path)
                self.current = nil
                self.currentProgress = 0

                if let outcome {
                    self.record(CompletedJob(
                        id: job.id,
                        sourceName: job.displayName,
                        outcome: outcome,
                        finishedAt: Date()
                    ))
                }
            }
            self?.drainTask = nil
        }
    }

    private func record(_ job: CompletedJob) {
        completed.insert(job, at: 0)
        if completed.count > Self.recentJobLimit {
            completed.removeLast(completed.count - Self.recentJobLimit)
        }
        notifications.notifyFinished(job)
    }

    // MARK: - Processing

    /// Returns nil when the job should vanish without a trace — the file was
    /// moved away or never finished being written.
    private func process(_ job: CompressionJob) async -> JobOutcome? {
        let source = job.source

        guard await stabilityMonitor.waitUntilReady(source) else { return nil }
        // The file may have been renamed, trashed, or already handled during
        // the wait, so re-check rather than trusting the intake filter.
        guard FolderWatcher.isCandidate(source) else { return nil }

        let tier = Preferences.shared.qualityTier
        let maxDimension = Preferences.shared.maxDimension
        let shouldTrash = Preferences.shared.trashOriginal

        let originalBytes = Self.fileSize(source)
        notifications.notifyStarted(source.lastPathComponent)

        let temporaryDirectory: URL
        do {
            temporaryDirectory = try FileManager.default.url(
                for: .itemReplacementDirectory,
                in: .userDomainMask,
                appropriateFor: source,
                create: true
            )
        } catch {
            return .failed("Could not create a temporary directory: \(error.localizedDescription)")
        }
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let temporaryURL = temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(OutputNaming.outputExtension)

        let compressor = VideoCompressor()
        activeCompressor = compressor
        defer { activeCompressor = nil }

        let result: CompressionResult
        do {
            result = try await compressor.compress(
                source: source,
                destination: temporaryURL,
                tier: tier,
                maxDimension: maxDimension,
                progress: { [weak self] value in
                    Task { @MainActor [weak self] in self?.currentProgress = value }
                }
            )
        } catch is CancellationError {
            return .cancelled
        } catch CompressionError.cancelled {
            return .cancelled
        } catch {
            logger.error("Compression failed for \(source.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return .failed(error.localizedDescription)
        }

        if result == .alreadyEfficient {
            // Tag it so relaunching with "compress existing files" on doesn't
            // re-examine the same file forever.
            ProcessedMarker.mark(source)
            return .skipped(.alreadyEfficient)
        }

        let compressedBytes = Self.fileSize(temporaryURL)
        let savings = originalBytes > 0 ? Double(originalBytes - compressedBytes) / Double(originalBytes) : 0
        guard savings >= Self.minimumSavingsFraction else {
            logger.info("Discarding output for \(source.lastPathComponent, privacy: .public): only \(Int(savings * 100))% saved")
            ProcessedMarker.mark(source)
            return .skipped(.noMeaningfulSavings)
        }

        // Resolve the final name now rather than earlier, so a file that
        // appeared during the encode doesn't get clobbered.
        let outputURL = OutputNaming.outputURL(for: source)
        do {
            try FileManager.default.moveItem(at: temporaryURL, to: outputURL)
        } catch {
            return .failed("Could not save the compressed file: \(error.localizedDescription)")
        }
        ProcessedMarker.mark(outputURL)

        var trashURL: URL?
        if shouldTrash {
            var resulting: NSURL?
            do {
                try FileManager.default.trashItem(at: source, resultingItemURL: &resulting)
                trashURL = resulting as URL?
            } catch {
                logger.error("Could not trash \(source.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        logger.info("Compressed \(source.lastPathComponent, privacy: .public): \(originalBytes) → \(compressedBytes) bytes")
        return .compressed(
            outputURL: outputURL,
            originalBytes: originalBytes,
            compressedBytes: compressedBytes,
            trashURL: trashURL
        )
    }

    private static func fileSize(_ url: URL) -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)??.int64Value ?? 0
    }
}
