import Foundation

/// A bounded, opt-in in-memory buffer of newly observed banners. No system history is queried.
actor TodayNotificationSource: TodayDataSource {
    enum Capability: Sendable, Equatable { case visibleBanners, permissionRequired, mirroringOff, unavailable }
    nonisolated let id = TodaySourceID.notifications
    private var items: [TodayNotificationItem] = []
    private var enabled = false
    private var revision = -1
    private var capability: Capability = .unavailable
    private var capabilityRevision = -1
    private var expiryTask: Task<Void, Never>?
    func configure(_ policy: TodayPrivacySettings, revision: Int) async {
        guard revision >= self.revision else { return }
        self.revision = revision
        enabled = policy.enabled(id)
        if !enabled { await clear() }
    }
    func updateCapability(_ value: Capability, revision: Int = 0) {
        guard revision >= capabilityRevision else { return }
        capabilityRevision = revision
        capability = value
        if value != .visibleBanners { items = []; expiryTask?.cancel(); expiryTask = nil }
    }
    func record(identifier: String, applicationIdentifier: String?, applicationName: String, title: String, body: String, observedAt: Date, capabilityRevision: Int? = nil, policyRevision: Int? = nil) {
        guard enabled, capability == .visibleBanners else { return }
        if let policyRevision, policyRevision != revision { return }
        if let capabilityRevision, capabilityRevision != self.capabilityRevision { return }
        let id = TodayContextValidator.stableID(prefix: "banner", value: identifier)
        guard !items.contains(where: { $0.id == id }) else { return }
        let item = TodayNotificationItem(id: id, source: .notifications, applicationIdentifier: applicationIdentifier.map { String($0.prefix(150)) },
                                         applicationName: String(applicationName.prefix(64)), title: String(title.prefix(120)), body: String(body.prefix(240)), observedAt: observedAt)
        items.append(item)
        prune(now: observedAt)
        scheduleExpiry()
    }
    func collect(_ request: TodaySourceRequest) async -> TodaySourceResult {
        guard enabled else { return .status(id, .disabled, "Notification context is off.") }
        switch capability {
        case .permissionRequired: items = []; return .status(id, .permissionRequired, "Existing banner capture needs Accessibility permission. This is not complete notification history.")
        case .mirroringOff: items = []; return .status(id, .unavailable, "Turn on Notchloom's existing banner mirroring to observe new visible banners. Today never enables it for you.")
        case .unavailable: items = []; return .status(id, .unavailable, "The existing visible-banner reader is unavailable. No notification history can be retrieved.")
        case .visibleBanners: break
        }
        prune(now: request.now)
        var result = TodaySourceResult.status(id, .ready, "Only banners observed after opt-in while Notchloom is running; capture times, not original delivery times. Incomplete coverage. Held in memory for at most 30 minutes.", now: request.now, count: items.count)
        result.notifications = items.sorted { $0.observedAt > $1.observedAt }
        return result
    }
    func clear() async { items = []; expiryTask?.cancel(); expiryTask = nil }
    private func scheduleExpiry() {
        expiryTask?.cancel()
        guard let first = items.map(\.observedAt).min() else { return }
        let delay = max(0.1, first.addingTimeInterval(1800.1).timeIntervalSinceNow)
        expiryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await self?.expire()
        }
    }
    private func expire() { prune(now: Date()); scheduleExpiry() }
    deinit { expiryTask?.cancel() }
    private func prune(now: Date) {
        items.removeAll { now.timeIntervalSince($0.observedAt) > 1800 || now.timeIntervalSince($0.observedAt) < -2 }
        if items.count > 20 { items.removeFirst(items.count - 20) }
    }
}
