import SwiftUI

struct MenuContentView: View {
    @Bindable var model: AppModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if let current = model.queue.current {
                Divider()
                currentJob(current)
            }

            if !model.queue.pending.isEmpty {
                Text("\(model.queue.pending.count) waiting")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !model.queue.completed.isEmpty {
                Divider()
                recentActivity
            }

            Divider()
            actions
        }
        .padding(12)
        .frame(width: 320)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "film.stack")
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(AppInfo.displayName)
                    .font(.headline)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(model.watchedFolderAccessible ? Color.secondary : Color.red)
            }
        }
    }

    private var statusText: String {
        guard model.watchedFolderAccessible else {
            return "No access to \(model.watchedFolder.lastPathComponent)"
        }
        if model.isPaused { return "Paused" }
        return "Watching \(model.watchedFolder.lastPathComponent)"
    }

    private func currentJob(_ job: CompressionJob) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(job.displayName)
                .lineLimit(1)
                .truncationMode(.middle)

            HStack(spacing: 8) {
                ProgressView(value: model.queue.currentProgress)
                    .progressViewStyle(.linear)
                Text(model.queue.currentProgress.formatted(.percent.precision(.fractionLength(0))))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button("Cancel") { model.queue.cancelCurrent() }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
        }
    }

    private var recentActivity: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Recent")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(model.queue.completed) { job in
                        ActivityRow(
                            job: job,
                            onReveal: model.reveal,
                            onUndo: model.queue.undo
                        )
                    }
                }
            }
            .frame(maxHeight: 200)
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 2) {
            MenuButton(
                title: model.isPaused ? "Resume Watching" : "Pause Watching",
                systemImage: model.isPaused ? "play.fill" : "pause.fill"
            ) {
                model.isPaused.toggle()
            }

            MenuButton(title: "Compress File…", systemImage: "plus.circle") {
                model.chooseFileToCompress()
            }

            MenuButton(title: "Settings…", systemImage: "gearshape") {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            }

            MenuButton(title: "Quit", systemImage: "power") {
                NSApp.terminate(nil)
            }
        }
    }
}

/// Menu-style row button. `MenuBarExtra` in `.window` style renders plain
/// `Button`s as chunky push buttons, which looks wrong in a menu.
private struct MenuButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
                .background(isHovering ? Color.accentColor.opacity(0.15) : .clear, in: .rect(cornerRadius: 5))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
