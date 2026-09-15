import Foundation
import Observation

/// UserDefaults-backed settings. A single shared instance so the menu, the
/// settings window, and the watcher all read the same values.
@MainActor
@Observable
final class Preferences {
    static let shared = Preferences()

    private enum Key {
        static let watchedFolderPath = "watchedFolderPath"
        static let qualityTier = "qualityTier"
        static let maxDimension = "maxDimension"
        static let trashOriginal = "trashOriginal"
        static let compressExistingOnLaunch = "compressExistingOnLaunch"
        static let notificationsEnabled = "notificationsEnabled"
        static let hasCompletedFirstRun = "hasCompletedFirstRun"
    }

    private let defaults: UserDefaults

    var watchedFolder: URL {
        didSet { defaults.set(watchedFolder.path, forKey: Key.watchedFolderPath) }
    }

    var qualityTier: QualityTier {
        didSet { defaults.set(qualityTier.rawValue, forKey: Key.qualityTier) }
    }

    var maxDimension: MaxDimension {
        didSet { defaults.set(maxDimension.rawValue, forKey: Key.maxDimension) }
    }

    var trashOriginal: Bool {
        didSet { defaults.set(trashOriginal, forKey: Key.trashOriginal) }
    }

    var compressExistingOnLaunch: Bool {
        didSet { defaults.set(compressExistingOnLaunch, forKey: Key.compressExistingOnLaunch) }
    }

    var notificationsEnabled: Bool {
        didSet { defaults.set(notificationsEnabled, forKey: Key.notificationsEnabled) }
    }

    var hasCompletedFirstRun: Bool {
        didSet { defaults.set(hasCompletedFirstRun, forKey: Key.hasCompletedFirstRun) }
    }

    static var defaultWatchedFolder: URL {
        FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Desktop")
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let path = defaults.string(forKey: Key.watchedFolderPath), !path.isEmpty {
            watchedFolder = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            watchedFolder = Self.defaultWatchedFolder
        }

        qualityTier = defaults.string(forKey: Key.qualityTier)
            .flatMap(QualityTier.init(rawValue:)) ?? .balanced
        maxDimension = defaults.string(forKey: Key.maxDimension)
            .flatMap(MaxDimension.init(rawValue:)) ?? .original

        // `object(forKey:) == nil` distinguishes "never set" from "set to
        // false", so these default to true only on a fresh install.
        trashOriginal = defaults.object(forKey: Key.trashOriginal) as? Bool ?? true
        notificationsEnabled = defaults.object(forKey: Key.notificationsEnabled) as? Bool ?? true
        compressExistingOnLaunch = defaults.bool(forKey: Key.compressExistingOnLaunch)
        hasCompletedFirstRun = defaults.bool(forKey: Key.hasCompletedFirstRun)
    }
}
