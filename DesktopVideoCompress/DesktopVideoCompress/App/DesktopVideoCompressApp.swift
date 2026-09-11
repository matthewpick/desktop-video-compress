import SwiftUI

@main
struct DesktopVideoCompressApp: App {
    @State private var model = AppModel()
    @State private var hasStarted = false

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(model: model)
        } label: {
            Image(systemName: menuBarSymbol)
                .task {
                    // `.task` on the label runs once the menu bar item exists,
                    // which is the earliest point NSAlert and NSOpenPanel behave
                    // correctly for an LSUIElement app.
                    guard !hasStarted, !AppInfo.isRunningTests else { return }
                    hasStarted = true
                    model.start()
                }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model)
        }
    }

    private var menuBarSymbol: String {
        if model.isPaused { return "pause.circle" }
        if model.queue.isBusy { return "arrow.down.circle" }
        return "film.stack"
    }
}
