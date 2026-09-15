import Foundation
import Testing

@testable import DesktopVideoCompress

@Suite("Output naming")
struct OutputNamingTests {
    private let desktop = URL(fileURLWithPath: "/Users/test/Desktop", isDirectory: true)

    private func source(_ name: String) -> URL {
        desktop.appendingPathComponent(name)
    }

    @Test("A .mov becomes a .mp4 with the same stem")
    func movBecomesMP4() {
        let output = OutputNaming.outputURL(for: source("clip.mov")) { _ in false }
        #expect(output.lastPathComponent == "clip.mp4")
        #expect(output.deletingLastPathComponent().path == desktop.path)
    }

    @Test("A .mp4 source never overwrites itself")
    func mp4SourceGetsSuffix() {
        // Nothing else exists, but `clip.mp4` IS the source.
        let output = OutputNaming.outputURL(for: source("clip.mp4")) { _ in false }
        #expect(output.lastPathComponent == "clip_compressed.mp4")
    }

    @Test("An existing file with the ideal name pushes to _compressed")
    func collisionGetsSuffix() {
        let taken = source("clip.mp4").path
        let output = OutputNaming.outputURL(for: source("clip.mov")) { $0.path == taken }
        #expect(output.lastPathComponent == "clip_compressed.mp4")
    }

    @Test("Repeated collisions get numbered")
    func repeatedCollisionsAreNumbered() {
        let taken: Set<String> = [
            source("clip.mp4").path,
            source("clip_compressed.mp4").path,
            source("clip_compressed-2.mp4").path,
        ]
        let output = OutputNaming.outputURL(for: source("clip.mov")) { taken.contains($0.path) }
        #expect(output.lastPathComponent == "clip_compressed-3.mp4")
    }

    @Test("A non-standardized source path still matches its own candidate")
    func standardizesBeforeComparing() {
        let messy = URL(fileURLWithPath: "/Users/test/Desktop/./clip.mp4")
        let output = OutputNaming.outputURL(for: messy) { _ in false }
        #expect(output.lastPathComponent == "clip_compressed.mp4")
    }

    @Test("Names with dots keep everything before the final extension")
    func dottedNamesAreHandled() {
        let output = OutputNaming.outputURL(for: source("Screen Recording 2026-09-11 at 10.03.27.mov")) { _ in false }
        #expect(output.lastPathComponent == "Screen Recording 2026-09-11 at 10.03.27.mp4")
    }

    // MARK: - Filters

    @Test("Supported extensions are recognized case-insensitively", arguments: [
        "a.mp4", "a.MP4", "a.mov", "a.MOV", "a.m4v", "a.M4V",
    ])
    func supportedExtensions(name: String) {
        #expect(OutputNaming.isSupportedVideo(URL(fileURLWithPath: name)))
    }

    @Test("Formats AVFoundation can't demux are rejected", arguments: [
        "a.mkv", "a.webm", "a.flv", "a.wmv", "a.avi", "a.txt", "a.jpg", "a",
    ])
    func unsupportedExtensions(name: String) {
        #expect(!OutputNaming.isSupportedVideo(URL(fileURLWithPath: name)))
    }

    @Test("Our own output is recognized by name as a backstop")
    func recognizesOwnOutput() {
        #expect(OutputNaming.looksLikeOurOutput(source("clip_compressed.mp4")))
        #expect(OutputNaming.looksLikeOurOutput(source("clip_compressed-2.mp4")))
        #expect(!OutputNaming.looksLikeOurOutput(source("clip.mp4")))
    }
}
