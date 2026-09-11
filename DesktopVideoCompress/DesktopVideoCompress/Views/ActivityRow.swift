import SwiftUI

/// One finished job in the menu's recent-activity list.
struct ActivityRow: View {
    let job: CompletedJob
    let onReveal: (URL) -> Void
    let onUndo: (CompletedJob) -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(job.sourceName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(job.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if isHovering, job.undoTrashURL != nil {
                Button("Undo") { onUndo(job) }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(isHovering ? Color.primary.opacity(0.08) : .clear, in: .rect(cornerRadius: 5))
        .contentShape(.rect)
        .onHover { isHovering = $0 }
        .onTapGesture {
            if let url = job.revealURL { onReveal(url) }
        }
        .help(job.revealURL != nil ? "Show in Finder" : job.summary)
    }

    private var iconName: String {
        switch job.outcome {
        case .compressed: "checkmark.circle.fill"
        case .skipped: "minus.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .cancelled: "xmark.circle.fill"
        }
    }

    private var iconColor: Color {
        switch job.outcome {
        case .compressed: .green
        case .skipped: .secondary
        case .failed: .orange
        case .cancelled: .secondary
        }
    }
}
