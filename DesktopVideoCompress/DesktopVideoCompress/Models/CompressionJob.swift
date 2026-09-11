import Foundation

/// Why a file was left alone instead of compressed.
enum SkipReason: Sendable {
    /// Source is already HEVC at or below the bitrate we'd target.
    case alreadyEfficient
    /// We encoded it, and the result wasn't meaningfully smaller.
    case noMeaningfulSavings

    var displayText: String {
        switch self {
        case .alreadyEfficient: "Already efficient — left alone"
        case .noMeaningfulSavings: "No worthwhile savings — left alone"
        }
    }
}

enum JobOutcome: Sendable {
    case compressed(outputURL: URL, originalBytes: Int64, compressedBytes: Int64, trashURL: URL?)
    case skipped(SkipReason)
    case failed(String)
    case cancelled
}

/// A single unit of work: one source file, start to finish.
struct CompressionJob: Identifiable, Sendable {
    let id = UUID()
    let source: URL
    let queuedAt: Date

    init(source: URL, queuedAt: Date = Date()) {
        self.source = source
        self.queuedAt = queuedAt
    }

    var displayName: String { source.lastPathComponent }
}

/// A finished job, retained for the menu's recent-activity list.
struct CompletedJob: Identifiable, Sendable {
    let id: UUID
    let sourceName: String
    let outcome: JobOutcome
    let finishedAt: Date

    /// The file the user should be shown in Finder, if there is one.
    var revealURL: URL? {
        if case .compressed(let outputURL, _, _, _) = outcome { return outputURL }
        return nil
    }

    /// Present only while the original is still recoverable from the Trash.
    var undoTrashURL: URL? {
        if case .compressed(_, _, _, let trashURL) = outcome { return trashURL }
        return nil
    }

    var summary: String {
        switch outcome {
        case .compressed(_, let originalBytes, let compressedBytes, _):
            let savings = ByteFormatting.savingsPercent(original: originalBytes, compressed: compressedBytes)
            return "\(ByteFormatting.string(originalBytes)) → \(ByteFormatting.string(compressedBytes)) (\(savings) saved)"
        case .skipped(let reason):
            return reason.displayText
        case .failed(let message):
            return "Failed: \(message)"
        case .cancelled:
            return "Cancelled"
        }
    }
}

enum ByteFormatting {
    static func string(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    static func savingsPercent(original: Int64, compressed: Int64) -> String {
        guard original > 0 else { return "0%" }
        let fraction = Double(original - compressed) / Double(original)
        return String(format: "%.0f%%", fraction * 100)
    }
}
