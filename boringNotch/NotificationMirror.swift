import AppKit
import Defaults
import SwiftUI

struct NotchNotification: Decodable, Identifiable, Equatable {
    let id: String
    let source: String
    let title: String
    let body: String

    var fingerprint: String { "\(source)|\(title)|\(body)" }
}

@MainActor
final class NotificationMirror: ObservableObject {
    static let shared = NotificationMirror()

    @Published private(set) var current: NotchNotification?
    private var pollingTask: Task<Void, Never>?
    private var dismissTask: Task<Void, Never>?
    private var queued: [NotchNotification] = []
    private var seen: [String: Date] = [:]
    private var didTakeInitialSnapshot = false

    private init() {}

    func start() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if Defaults[.showNotificationBanners] {
                    await self.readVisibleBanners()
                } else {
                    self.clear()
                }
                try? await Task.sleep(for: .milliseconds(350))
            }
        }
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
        clear()
    }

    func preview() {
        enqueue(NotchNotification(
            id: UUID().uuidString,
            source: "Notchloom",
            title: "Notifications from the notch",
            body: "A quiet preview of how new banners will appear."
        ))
    }

    private func readVisibleBanners() async {
        guard let data = await XPCHelperClient.shared.visibleNotificationBanners(),
              let banners = try? JSONDecoder().decode([NotchNotification].self, from: data)
        else { return }

        let now = Date()
        seen = seen.filter { now.timeIntervalSince($0.value) < 25 }
        if !didTakeInitialSnapshot {
            banners.forEach { seen[$0.fingerprint] = now }
            didTakeInitialSnapshot = true
            return
        }
        for banner in banners where seen[banner.fingerprint] == nil {
            seen[banner.fingerprint] = now
            enqueue(banner)
        }
    }

    private func enqueue(_ banner: NotchNotification) {
        guard queued.count < 3 else { return }
        queued.append(banner)
        presentNext()
    }

    private func presentNext() {
        guard current == nil, !queued.isEmpty else { return }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
            current = queued.removeFirst()
        }
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, let self else { return }
            withAnimation(.easeInOut(duration: 0.26)) { self.current = nil }
            try? await Task.sleep(for: .milliseconds(260))
            guard !Task.isCancelled else { return }
            self.presentNext()
        }
    }

    private func clear() {
        didTakeInitialSnapshot = false
        dismissTask?.cancel()
        dismissTask = nil
        queued.removeAll()
        seen.removeAll()
        current = nil
    }
}

struct NotchNotificationCard: View {
    let notification: NotchNotification
    let stemHeight: CGFloat
    let stemWidth: CGFloat

    private var appIcon: NSImage? {
        NSWorkspace.shared.runningApplications.first {
            $0.localizedName?.localizedCaseInsensitiveCompare(notification.source) == .orderedSame
        }?.icon
    }

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(.black)
                .frame(width: max(0, stemWidth - 12), height: stemHeight)

            HStack(alignment: .top, spacing: 13) {
                Group {
                    if let appIcon {
                        Image(nsImage: appIcon)
                            .resizable()
                            .scaledToFit()
                    } else {
                        Image(systemName: "bell.badge.fill")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(.cyan)
                    }
                }
                .frame(width: 39, height: 39)
                .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 11))

                VStack(alignment: .leading, spacing: 3) {
                    Text(notification.source)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.cyan)
                        .textCase(.uppercase)
                        .lineLimit(1)
                    Text(notification.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if !notification.body.isEmpty {
                        Text(notification.body)
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.68))
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 17)
            .padding(.vertical, 14)
            .frame(width: 480, alignment: .leading)
            .background(.black, in: UnevenRoundedRectangle(
                topLeadingRadius: 11,
                bottomLeadingRadius: 22,
                bottomTrailingRadius: 22,
                topTrailingRadius: 11
            ))
            .shadow(color: .black.opacity(0.4), radius: 14, y: 8)
        }
        .frame(width: 480)
        .accessibilityElement(children: .combine)
    }
}
