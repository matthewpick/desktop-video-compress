import Foundation
import ServiceManagement
import os

/// Start-at-login, via the modern `SMAppService` API rather than a hand-written
/// LaunchAgent plist like the Python version used.
enum LoginItem {
    private static let logger = Logger(subsystem: AppInfo.subsystem, category: "LoginItem")

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Returns the state actually achieved, which may differ from `enabled` if
    /// the user has blocked the login item in System Settings.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            logger.error("Could not \(enabled ? "register" : "unregister") login item: \(error.localizedDescription, privacy: .public)")
        }
        return isEnabled
    }
}
