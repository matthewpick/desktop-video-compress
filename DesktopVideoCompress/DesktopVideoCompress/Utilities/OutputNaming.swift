import Foundation

/// Picks the filename for a compressed output. Kept separate from the
/// compressor so the collision rules are testable without touching disk.
enum OutputNaming {
    static let outputExtension = "mp4"
    static let compressedSuffix = "_compressed"

    /// Video containers we can actually demux with AVFoundation.
    ///
    /// The Python predecessor also listed mkv/webm/flv/wmv, but AVFoundation
    /// cannot read those, so they are deliberately absent rather than accepted
    /// and then failed.
    static let supportedExtensions: Set<String> = ["mp4", "m4v", "mov"]

    static func isSupportedVideo(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    /// Secondary guard against re-compressing our own output, backing up the
    /// extended attribute in `ProcessedMarker`. Catches files produced by an
    /// older install whose xattr was stripped (e.g. by a cloud sync client).
    static func looksLikeOurOutput(_ url: URL) -> Bool {
        url.deletingPathExtension().lastPathComponent.contains(compressedSuffix)
    }

    /// `<name>.mp4` next to the source, falling back to `_compressed`,
    /// `_compressed-2`, … when that name is taken or would overwrite the source.
    ///
    /// `exists` is injected so tests don't need a real filesystem.
    static func outputURL(for source: URL, exists: (URL) -> Bool) -> URL {
        let directory = source.deletingLastPathComponent()
        let base = source.deletingPathExtension().lastPathComponent

        let candidates = sequence(first: 0) { $0 + 1 }.lazy.map { (index: Int) -> URL in
            let name = switch index {
            case 0: base
            case 1: base + compressedSuffix
            default: "\(base)\(compressedSuffix)-\(index)"
            }
            return directory.appendingPathComponent(name).appendingPathExtension(outputExtension)
        }

        // `standardizedFileURL` so a `/Users/me/./clip.mp4` source still
        // compares equal to the candidate it would overwrite.
        let sourcePath = source.standardizedFileURL.path
        for candidate in candidates {
            if candidate.standardizedFileURL.path == sourcePath { continue }
            if exists(candidate) { continue }
            return candidate
        }

        // Unreachable: the sequence is infinite and names strictly increase.
        return directory
            .appendingPathComponent(base + compressedSuffix)
            .appendingPathExtension(outputExtension)
    }

    static func outputURL(for source: URL) -> URL {
        outputURL(for: source) { FileManager.default.fileExists(atPath: $0.path) }
    }
}
