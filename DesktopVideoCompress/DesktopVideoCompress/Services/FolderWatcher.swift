import CoreServices
import Foundation
import os

/// Watches a single folder (non-recursively) and emits URLs of files that
/// appeared or changed.
///
/// Emission is intentionally noisy — a file being written produces many events.
/// `FileStabilityMonitor` downstream is what decides when a file is actually
/// done. This type only answers "something happened to this path".
final class FolderWatcher: @unchecked Sendable {
    private let logger = Logger(subsystem: AppInfo.subsystem, category: "FolderWatcher")
    private let queue = DispatchQueue(label: "\(AppInfo.subsystem).folderwatcher")

    private var stream: FSEventStreamRef?
    private let handler: @Sendable (URL) -> Void

    let folder: URL

    init(folder: URL, handler: @escaping @Sendable (URL) -> Void) {
        self.folder = folder
        self.handler = handler
    }

    deinit { stop() }

    func start() {
        stop()

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        // With kFSEventStreamCreateFlagUseCFTypes the `paths` argument is a
        // CFArray of CFStrings rather than a C string array.
        let callback: FSEventStreamCallback = { _, info, _, paths, _, _ in
            guard let info, let pathArray = unsafeBitCast(paths, to: NSArray.self) as? [String] else { return }
            let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()

            for path in pathArray {
                watcher.emit(path: path)
            }
        }

        // `FileEvents` gives per-file rather than per-directory granularity;
        // `NoDefer` delivers the first event immediately instead of waiting out
        // the latency window, so a dropped file is noticed right away.
        let flags = UInt32(
            kFSEventStreamCreateFlagUseCFTypes
                | kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagNoDefer
        )

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            [folder.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5,
            flags
        ) else {
            logger.error("Could not create FSEventStream for \(self.folder.path, privacy: .public)")
            return
        }

        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            logger.error("Could not start FSEventStream for \(self.folder.path, privacy: .public)")
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            return
        }

        self.stream = stream
        logger.info("Watching \(self.folder.path, privacy: .public)")
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    private func emit(path: String) {
        let url = URL(fileURLWithPath: path)

        // FSEvents reports the whole subtree; we only care about direct
        // children of the watched folder.
        guard url.deletingLastPathComponent().standardizedFileURL.path == folder.standardizedFileURL.path else {
            return
        }
        guard FolderWatcher.isCandidate(url) else { return }

        handler(url)
    }

    /// Cheap, side-effect-free filters. Anything surviving these gets handed to
    /// the stability monitor.
    static func isCandidate(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        guard !name.hasPrefix(".") else { return false }

        // Browsers and download managers write these while the real file is
        // still incomplete.
        let partialSuffixes = ["download", "crdownload", "part", "partial"]
        guard !partialSuffixes.contains(url.pathExtension.lowercased()) else { return false }

        guard OutputNaming.isSupportedVideo(url) else { return false }
        guard !OutputNaming.looksLikeOurOutput(url) else { return false }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else { return false }

        guard !ProcessedMarker.isMarked(url) else { return false }

        return true
    }

    /// Direct children of the watched folder that are already eligible. Used
    /// for the optional "compress what's already here" pass at launch.
    static func existingCandidates(in folder: URL) -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        )) ?? []
        return contents.filter(isCandidate)
    }
}
