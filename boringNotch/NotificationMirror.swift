import AppKit
import Combine
import Defaults
import SwiftUI

/// Capture adapter. Presentation and animation live in NotificationPresentation.
@MainActor
final class NotificationMirror: NotificationPresentation {
    /// New, legitimately observed visible banners only; preview/local animations never publish here.
    let observedBanners = PassthroughSubject<NotchNotification, Never>()
    static let shared = NotificationMirror()
    private var pollingTask: Task<Void, Never>?
    enum CaptureStatus: String {
        case checking = "Checking notification access…"
        case ready = "Ready to read visible macOS banners"
        case needsAccess = "Accessibility access is required"
        case disconnected = "Notification reader is unavailable"
        case off = "Notification mirroring is off"
    }
    private struct Snapshot: Decodable {
        let accessibilityAuthorized: Bool
        let banners: [NotchNotification]
    }
    @Published private(set) var captureStatus: CaptureStatus = .checking
    private var arrivals = NotificationArrivalTracker()

    func start() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if Defaults[.showNotificationBanners] {
                    await self.readVisibleBanners()
                } else {
                    self.arrivals = NotificationArrivalTracker()
                    self.captureStatus = .off
                    self.discardMirroredNotifications()
                }
                try? await Task.sleep(for: .milliseconds(350))
            }
        }
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
        arrivals = NotificationArrivalTracker()
        reset()
    }

    func preview() {
        showLocal(title: "A little closer", body: "Your notifications, right here in the notch.")
    }

    func previewClock(timer: Bool) {
        enqueue(NotchNotification(id: UUID().uuidString, source: "Clock",
            title: timer ? "Timer finished" : "Alarm", body: timer ? "Your timer has ended." : "It's time."))
    }

    func showLocal(title: String, body: String) {
        enqueue(NotchNotification(id: UUID().uuidString, source: "Notchloom", title: title, body: body))
    }

    func previewSequence() {
        showLocal(title: "Ready", body: "")
        showLocal(title: "A longer notification", body: "This longer message checks wrapping and truncation. It should remain readable inside the notch, with a maximum of two lines and no change to the surrounding surface.")
        previewClock(timer: true)
    }

    private func readVisibleBanners() async {
        guard let data = await XPCHelperClient.shared.visibleNotificationBanners(),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else {
            captureStatus = .disconnected
            return
        }
        guard snapshot.accessibilityAuthorized else {
            captureStatus = .needsAccess
            return
        }
        captureStatus = .ready
        for banner in arrivals.arrivals(in: snapshot.banners) { observedBanners.send(banner); enqueue(banner) }
    }
}
