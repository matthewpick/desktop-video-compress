import Foundation

enum AppInfo {
    static let subsystem = Bundle.main.bundleIdentifier ?? "com.desktopvideocompress.DesktopVideoCompress"

    static let displayName = "Desktop Video Compress"

    static var version: String {
        let marketing = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(marketing) (\(build))"
    }

    /// LaunchAgent label used by the Python predecessor, kept here so the
    /// migration step and the uninstall script agree on the name.
    static let legacyLaunchAgentLabel = "com.desktop.video.compress"

    /// Unit tests run inside the app as their host. Startup side effects —
    /// the migration alert especially, which is modal and would hang CI —
    /// must not fire in that case.
    static let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        || NSClassFromString("XCTestCase") != nil
}
