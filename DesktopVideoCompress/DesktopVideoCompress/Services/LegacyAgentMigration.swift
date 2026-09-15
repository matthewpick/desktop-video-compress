import AppKit
import Foundation
import os

/// Removes the LaunchAgent installed by the Python version of this tool.
///
/// Left in place it would keep running `desktop_video_compress.py` against the
/// same Desktop, and two services racing over the same files produces duplicate
/// compressions and lost originals.
enum LegacyAgentMigration {
    private static let logger = Logger(subsystem: AppInfo.subsystem, category: "LegacyMigration")

    static var plistURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/LaunchAgents")
            .appendingPathComponent("\(AppInfo.legacyLaunchAgentLabel).plist")
    }

    static var isPresent: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    /// Offers to unload and delete the old agent. No-op when it isn't installed.
    @MainActor
    static func promptIfNeeded() {
        guard isPresent else { return }

        let alert = NSAlert()
        alert.messageText = "Remove the old Desktop Video Compress service?"
        alert.informativeText = """
            The previous Python version is still installed as a background service. \
            If both keep running they will compete over the same files.

            This removes \(plistURL.lastPathComponent) and stops the old service. \
            Your files are not touched.
            """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Remove Old Service")
        alert.addButton(withTitle: "Leave It")

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        remove()
    }

    static func remove() {
        bootout()

        do {
            try FileManager.default.removeItem(at: plistURL)
            logger.info("Removed legacy LaunchAgent")
        } catch {
            logger.error("Could not remove legacy LaunchAgent: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func bootout() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["bootout", "gui/\(getuid())/\(AppInfo.legacyLaunchAgentLabel)"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            // Not fatal: the agent may simply not be loaded, in which case
            // deleting the plist is all that's needed.
            logger.info("launchctl bootout did not run: \(error.localizedDescription, privacy: .public)")
        }
    }
}
