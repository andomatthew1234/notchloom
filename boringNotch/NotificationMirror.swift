import AppKit
import Defaults
import SwiftUI

/// Capture adapter. Presentation and animation live in NotificationPresentation.
@MainActor
final class NotificationMirror: NotificationPresentation {
    static let shared = NotificationMirror()
    private var pollingTask: Task<Void, Never>?
    private var seen: [String: Date] = [:]
    private var didTakeInitialSnapshot = false

    func start() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if Defaults[.showNotificationBanners] {
                    await self.readVisibleBanners()
                } else {
                    self.didTakeInitialSnapshot = false
                    self.seen.removeAll()
                    self.discardMirroredNotifications()
                }
                try? await Task.sleep(for: .milliseconds(350))
            }
        }
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
        seen.removeAll()
        didTakeInitialSnapshot = false
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
              let banners = try? JSONDecoder().decode([NotchNotification].self, from: data) else { return }
        let now = Date()
        seen = seen.filter { now.timeIntervalSince($0.value) < 25 }
        if !didTakeInitialSnapshot {
            banners.forEach { seen[$0.fingerprint] = now }
            didTakeInitialSnapshot = true
            return
        }
        for banner in banners {
            if seen[banner.fingerprint] == nil { enqueue(banner) }
            // Keep a persistent visible alert from being re-enqueued every 25 seconds.
            seen[banner.fingerprint] = now
        }
    }
}
