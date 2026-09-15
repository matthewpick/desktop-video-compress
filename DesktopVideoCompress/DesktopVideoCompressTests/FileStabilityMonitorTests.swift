import Foundation
import Testing

@testable import DesktopVideoCompress

@Suite("File stability")
struct FileStabilityMonitorTests {
    private func snapshot(_ size: Int64, at seconds: TimeInterval = 0) -> FileSnapshot {
        FileSnapshot(size: size, modified: Date(timeIntervalSince1970: seconds))
    }

    @Test("A growing file is never considered settled")
    func growingFileNeverSettles() {
        var tracker = StabilityTracker(requiredStableSamples: 3, maxSamples: 100)
        for step in 1...20 {
            let verdict = tracker.record(snapshot(Int64(step) * 1_000, at: TimeInterval(step)))
            #expect(verdict == .waiting, "settled early at sample \(step)")
        }
    }

    @Test("An unchanged file settles after the required number of samples")
    func settlesAfterQuietSamples() {
        var tracker = StabilityTracker(requiredStableSamples: 3, maxSamples: 100)
        let stable = snapshot(5_000, at: 10)

        #expect(tracker.record(stable) == .waiting)
        #expect(tracker.record(stable) == .waiting)
        #expect(tracker.record(stable) == .settled)
    }

    @Test("Growth resets the stable run")
    func growthResetsProgress() {
        var tracker = StabilityTracker(requiredStableSamples: 3, maxSamples: 100)
        let first = snapshot(5_000, at: 10)

        #expect(tracker.record(first) == .waiting)
        #expect(tracker.record(first) == .waiting)
        // One more byte arrives just before it would have settled.
        #expect(tracker.record(snapshot(5_001, at: 11)) == .waiting)
        #expect(tracker.record(snapshot(5_001, at: 11)) == .waiting)
        #expect(tracker.record(snapshot(5_001, at: 11)) == .settled)
    }

    @Test("A same-size but re-touched file is treated as still changing")
    func mtimeChangeCounts() {
        var tracker = StabilityTracker(requiredStableSamples: 2, maxSamples: 100)
        #expect(tracker.record(snapshot(5_000, at: 10)) == .waiting)
        #expect(tracker.record(snapshot(5_000, at: 11)) == .waiting)
        #expect(tracker.record(snapshot(5_000, at: 11)) == .settled)
    }

    @Test("A vanished file reports missing")
    func missingFile() {
        var tracker = StabilityTracker(requiredStableSamples: 3, maxSamples: 100)
        #expect(tracker.record(snapshot(5_000)) == .waiting)
        #expect(tracker.record(nil) == .missing)
    }

    @Test("A file that never stops changing eventually times out")
    func timesOut() {
        var tracker = StabilityTracker(requiredStableSamples: 3, maxSamples: 5)
        var verdicts: [StabilityTracker.Verdict] = []
        for step in 1...5 {
            verdicts.append(tracker.record(snapshot(Int64(step) * 1_000, at: TimeInterval(step))))
        }
        #expect(verdicts.last == .timedOut)
        #expect(!verdicts.dropLast().contains(.timedOut))
    }

    @Test("Settling wins over the sample ceiling on the same sample")
    func settledBeatsTimeout() {
        var tracker = StabilityTracker(requiredStableSamples: 2, maxSamples: 2)
        let stable = snapshot(1_000)
        #expect(tracker.record(stable) == .waiting)
        #expect(tracker.record(stable) == .settled)
    }

    @Test("Snapshots of a real file reflect its size")
    func realSnapshot() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let file = directory.appendingPathComponent("sample.bin")
        try Data(count: 1_234).write(to: file)

        let snapshot = FileStabilityMonitor.snapshot(of: file)
        #expect(snapshot?.size == 1_234)
        #expect(FileStabilityMonitor.snapshot(of: directory.appendingPathComponent("nope.bin")) == nil)
    }
}
