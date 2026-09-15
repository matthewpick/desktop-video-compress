import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers
import os

/// Wires the watcher, the queue, and the system integrations together, and owns
/// the small amount of state the menu bar needs beyond the queue's.
@MainActor
@Observable
final class AppModel {
    let queue = CompressionQueue()

    private(set) var launchAtLogin = LoginItem.isEnabled
    private(set) var watchedFolderAccessible = true

    private let logger = Logger(subsystem: AppInfo.subsystem, category: "AppModel")
    private var watcher: FolderWatcher?

    var isPaused: Bool {
        get { queue.isPaused }
        set {
            queue.isPaused = newValue
            newValue ? watcher?.stop() : watcher?.start()
        }
    }

    var watchedFolder: URL { Preferences.shared.watchedFolder }

    func start() {
        NotificationService.shared.undoHandler = queue
        NotificationService.shared.start()

        LegacyAgentMigration.promptIfNeeded()
        startWatching()

        if Preferences.shared.compressExistingOnLaunch {
            for url in FolderWatcher.existingCandidates(in: watchedFolder) {
                queue.enqueue(url)
            }
        }

        if !Preferences.shared.hasCompletedFirstRun {
            Preferences.shared.hasCompletedFirstRun = true
            // Registering on first launch matches what the LaunchAgent used to
            // do, and it's the whole point of a background utility.
            launchAtLogin = LoginItem.setEnabled(true)
        }
    }

    /// Rebuilds the watcher against the current preference. Called at launch and
    /// whenever the watched folder changes.
    func startWatching() {
        watcher?.stop()

        let folder = watchedFolder
        // Reading the directory is also what triggers the TCC prompt on first
        // run, so a failure here usually means access was denied.
        watchedFolderAccessible = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) != nil
        if !watchedFolderAccessible {
            logger.error("Cannot read \(folder.path, privacy: .public)")
            NotificationService.shared.notifyError(
                title: AppInfo.displayName,
                body: "Can't read \(folder.lastPathComponent). Grant access in System Settings › Privacy & Security › Files and Folders."
            )
        }

        let watcher = FolderWatcher(folder: folder) { [weak self] url in
            Task { @MainActor [weak self] in self?.queue.enqueue(url) }
        }
        watcher.start()
        self.watcher = watcher
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLogin = LoginItem.setEnabled(enabled)
    }

    func chooseWatchedFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = watchedFolder
        panel.prompt = "Watch This Folder"

        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }

        Preferences.shared.watchedFolder = url
        startWatching()
    }

    /// Manual one-off compression, bypassing the stability wait's folder rules
    /// but not the queue.
    func chooseFileToCompress() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.mpeg4Movie, .quickTimeMovie]
        panel.prompt = "Compress"

        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }

        for url in panel.urls {
            queue.enqueue(url)
        }
    }

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
