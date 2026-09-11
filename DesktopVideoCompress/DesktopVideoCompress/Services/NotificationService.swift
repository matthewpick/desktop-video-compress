import AppKit
import Foundation
import UserNotifications
import os

/// User notifications for job start/finish, plus the Finder-reveal and undo
/// actions attached to them.
@MainActor
final class NotificationService: NSObject {
    static let shared = NotificationService()

    private let logger = Logger(subsystem: AppInfo.subsystem, category: "Notifications")
    private let center = UNUserNotificationCenter.current()

    private enum Action {
        static let reveal = "reveal"
        static let undo = "undo"
        static let category = "job"
    }

    /// Set by `AppModel` so the undo action can reach the queue.
    weak var undoHandler: CompressionQueue?

    /// Completed jobs keyed by notification identifier, so an action tap can
    /// find the job it refers to.
    private var deliveredJobs: [String: CompletedJob] = [:]

    private var isAuthorized = false

    func start() {
        center.delegate = self
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: Action.category,
                actions: [
                    UNNotificationAction(identifier: Action.reveal, title: "Show in Finder"),
                    UNNotificationAction(identifier: Action.undo, title: "Undo"),
                ],
                intentIdentifiers: []
            )
        ])

        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            Task { @MainActor [weak self] in
                self?.isAuthorized = granted
                if let error {
                    self?.logger.error("Notification authorization failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    func notifyStarted(_ filename: String) {
        post(title: AppInfo.displayName, body: "Compressing \(filename)…")
    }

    func notifyFinished(_ job: CompletedJob) {
        switch job.outcome {
        case .compressed:
            post(
                title: "Compressed \(job.sourceName)",
                body: job.summary,
                job: job
            )
        case .skipped:
            post(title: job.sourceName, body: job.summary)
        case .failed(let message):
            post(title: "Could not compress \(job.sourceName)", body: message)
        case .cancelled:
            break  // The user cancelled it; they don't need to be told.
        }
    }

    func notifyError(title: String, body: String) {
        post(title: title, body: body)
    }

    private func post(title: String, body: String, job: CompletedJob? = nil) {
        guard Preferences.shared.notificationsEnabled, isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body

        let identifier = UUID().uuidString
        if let job {
            content.categoryIdentifier = Action.category
            deliveredJobs[identifier] = job
        }

        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil)) { error in
            guard let error else { return }
            Task { @MainActor [weak self] in
                self?.logger.error("Could not post notification: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

extension NotificationService: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let identifier = response.notification.request.identifier
        let actionIdentifier = response.actionIdentifier

        await MainActor.run {
            guard let job = deliveredJobs[identifier] else { return }

            switch actionIdentifier {
            case Action.undo:
                undoHandler?.undo(job)
            default:
                // Covers the explicit reveal action and a plain notification tap.
                if let url = job.revealURL {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
            deliveredJobs[identifier] = nil
        }
    }
}
