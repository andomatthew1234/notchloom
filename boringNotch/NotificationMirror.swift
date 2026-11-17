import AppKit
import Defaults
import SwiftUI

struct NotchNotification: Decodable, Identifiable, Equatable {
    enum Kind: Equatable {
        case standard, clockAlarm, clockTimer, clock

        var isClock: Bool { self != .standard }
    }

    let id: String
    let source: String
    let title: String
    let body: String

    var fingerprint: String { "\(source)|\(title)|\(body)" }

    var kind: Kind {
        guard source.localizedCaseInsensitiveCompare("Clock") == .orderedSame else { return .standard }
        let content = "\(title) \(body)"
        if content.localizedCaseInsensitiveContains("alarm") { return .clockAlarm }
        if content.localizedCaseInsensitiveContains("timer") { return .clockTimer }
        return .clock
    }
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
                    self.clearMirroredBanners()
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
        showLocal(title: "Notifications from the notch", body: "A quiet preview of how new banners will appear.")
    }

    func previewClock(timer: Bool) {
        enqueue(NotchNotification(
            id: UUID().uuidString,
            source: "Clock",
            title: timer ? "Timer finished" : "Alarm",
            body: timer ? "Your timer has ended." : "It's time."
        ))
    }

    func showLocal(title: String, body: String) {
        if queued.count == 3 { queued.removeLast() }
        enqueue(NotchNotification(
            id: UUID().uuidString,
            source: "Notchloom",
            title: title,
            body: body
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
        if banner.kind.isClock {
            if current != nil && current?.kind.isClock == false {
                dismissTask?.cancel()
                dismissTask = nil
                current = nil
            }
            if queued.count == 3 { queued.removeLast() }
            queued.insert(banner, at: 0)
        } else {
            guard queued.count < 3 else { return }
            queued.append(banner)
        }
        presentNext()
    }

    private func presentNext() {
        guard current == nil, !queued.isEmpty else { return }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
            current = queued.removeFirst()
        }
        let displaySeconds = current?.kind.isClock == true ? 10 : 5
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(displaySeconds))
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

    private func clearMirroredBanners() {
        guard didTakeInitialSnapshot || !seen.isEmpty else { return }
        didTakeInitialSnapshot = false
        seen.removeAll()
        queued.removeAll { $0.source != "Notchloom" }
        if current?.source != "Notchloom" {
            dismissTask?.cancel()
            dismissTask = nil
            current = nil
            presentNext()
        }
    }
}

struct NotchNotificationCard: View {
    let notification: NotchNotification
    let stemHeight: CGFloat
    let stemWidth: CGFloat

    private var isClock: Bool { notification.kind.isClock }
    private var accent: Color {
        isClock ? Color(red: 1, green: 0.65, blue: 0.22) : Color(red: 0.20, green: 0.91, blue: 0.96)
    }
    private var eyebrow: String {
        switch notification.kind {
        case .clockAlarm: "CLOCK · ALARM"
        case .clockTimer: "CLOCK · TIMER"
        case .clock: "CLOCK"
        case .standard: notification.source.uppercased()
        }
    }

    private var clockSymbol: String {
        notification.kind == .clockAlarm ? "alarm.fill" : "timer"
    }

    private var appIcon: NSImage? {
        if let icon = NSWorkspace.shared.runningApplications.first(where: {
            $0.localizedName?.localizedCaseInsensitiveCompare(notification.source) == .orderedSame
        })?.icon { return icon }

        let knownApps = [
            "Messages": "com.apple.MobileSMS",
            "Mail": "com.apple.mail",
            "Calendar": "com.apple.iCal",
            "Reminders": "com.apple.reminders"
        ]
        guard let bundleID = knownApps[notification.source],
              let path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)?.path
        else { return nil }
        return NSWorkspace.shared.icon(forFile: path)
    }

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(.black)
                .frame(width: max(0, stemWidth - 12), height: stemHeight)

            HStack(alignment: .center, spacing: 13) {
                Group {
                    if isClock {
                        Image(systemName: clockSymbol)
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(accent)
                    } else if let appIcon {
                        Image(nsImage: appIcon)
                            .resizable()
                            .scaledToFit()
                    } else {
                        Image(systemName: "bell.badge.fill")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(accent)
                    }
                }
                .frame(width: 43, height: 43)
                .background(accent.opacity(isClock ? 0.14 : 0.10), in: RoundedRectangle(cornerRadius: 13))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(accent)
                            .frame(width: 5, height: 5)
                        Text(eyebrow)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .tracking(0.7)
                            .foregroundStyle(accent)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text("NOW")
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .tracking(0.5)
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    Text(notification.title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if !notification.body.isEmpty {
                        Text(notification.body)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.64))
                            .lineLimit(2)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .frame(width: 480, alignment: .leading)
            .background(LinearGradient(
                colors: [Color(white: 0.13), Color(white: 0.055)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ), in: UnevenRoundedRectangle(
                topLeadingRadius: 11,
                bottomLeadingRadius: 22,
                bottomTrailingRadius: 22,
                topTrailingRadius: 11
            ))
            .overlay {
                UnevenRoundedRectangle(
                    topLeadingRadius: 11,
                    bottomLeadingRadius: 22,
                    bottomTrailingRadius: 22,
                    topTrailingRadius: 11
                )
                .strokeBorder(.white.opacity(0.13), lineWidth: 1)
            }
            .shadow(color: accent.opacity(0.12), radius: 17, y: 8)
            .shadow(color: .black.opacity(0.45), radius: 15, y: 8)
        }
        .frame(width: 480)
        .accessibilityElement(children: .combine)
    }
}
