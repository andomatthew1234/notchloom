import Foundation

/// UI- and AI-independent context assembly. Only explicitly enabled collectors run.
actor TodayContextService {
    private let sources: [TodaySourceID: any TodayDataSource]
    private var policy = TodayPrivacySettings()
    private var revision = -1
    private var configuring = false
    private var flight: (id: UUID, task: Task<TodayContextSnapshot, Error>)?
    init(sources: [any TodayDataSource]) {
        var entries: [TodaySourceID: any TodayDataSource] = [:]
        for source in sources { entries[source.id] = source }
        self.sources = entries
    }
    func configure(_ settings: TodayPrivacySettings, revision: Int) async {
        guard revision >= self.revision else { return }
        self.revision = revision; policy = settings.bounded; configuring = true
        flight?.task.cancel(); flight = nil
        for source in sources.values {
            guard self.revision == revision else { return }
            await source.configure(policy, revision: revision)
        }
        if self.revision == revision { configuring = false }
    }
    func clear() async {
        flight?.task.cancel(); flight = nil
        for source in sources.values { await source.clear() }
    }
    func invalidate(_ id: TodaySourceID) async { await sources[id]?.clear() }
    func snapshot(now: Date = Date(), zone: TimeZone = .current, locale: Locale = .current, revision: Int, force: Bool = false,
                  onUpdate: (@Sendable (TodayContextSnapshot) async -> Void)? = nil) async throws -> TodayContextSnapshot {
        guard !configuring, revision == self.revision else { throw CancellationError() }
        if let flight { return try await flight.task.value }
        let id = UUID()
        let policy = self.policy
        let sources = self.sources
        let task = Task { () throws -> TodayContextSnapshot in
            let request = TodaySourceRequest(policy: policy, now: now, timeZoneIdentifier: zone.identifier, localeIdentifier: locale.identifier, forceRefresh: force)
            var results: [TodaySourceID: TodaySourceResult] = [:]
            await withTaskGroup(of: (TodaySourceID, TodaySourceResult).self) { group in
                for id in TodaySourceID.allCases {
                    guard policy.enabled(id) else { results[id] = .status(id, .disabled, "This source is off."); continue }
                    guard let source = sources[id] else { results[id] = .status(id, .unavailable, "No supported collector is configured for this source."); continue }
                    group.addTask { (id, await source.collect(request)) }
                }
                for await (id, result) in group {
                    guard !Task.isCancelled else { group.cancelAll(); continue }
                    var component = Self.assemble(results: [id: result], request: request)
                    if result.id != id || (try? TodayContextValidator.validate(component, policy: policy)) == nil {
                        component = Self.assemble(results: [id: .status(id, .failed, "This source returned invalid data. Other sources remain available.")], request: request)
                        results[id] = Self.result(id: id, snapshot: component)
                    } else { results[id] = result }
                    if let onUpdate { await onUpdate(Self.assemble(results: results, request: request)) }
                }
            }
            try Task.checkCancellation()
            let snapshot = Self.assemble(results: results, request: request)
            try TodayContextValidator.validate(snapshot, policy: policy)
            return snapshot
        }
        flight = (id, task)
        defer { if flight?.id == id { flight = nil } }
        let snapshot = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
        guard self.revision == revision else { throw CancellationError() }
        return snapshot
    }
    private static func assemble(results: [TodaySourceID: TodaySourceResult], request: TodaySourceRequest) -> TodayContextSnapshot {
        let status = Dictionary(uniqueKeysWithValues: TodaySourceID.allCases.map { id in (id, results[id]?.status ?? .init(state: request.policy.enabled(id) ? .loading : .disabled, collectedAt: nil, itemCount: 0, message: request.policy.enabled(id) ? "Collecting this source…" : "This source is off.")) })
        return .init(version: 1, generatedAt: request.now, timezone: request.timeZoneIdentifier,
                     authorizedSources: request.policy.authorizedSources, externalTransmissionAllowed: false,
                     dateTime: results[.dateTime]?.dateTime, weather: results[.weather]?.weather,
                     calendarEvents: results[.calendar]?.events ?? [], notifications: results[.notifications]?.notifications ?? [], sourceStatus: status)
    }
    private static func result(id: TodaySourceID, snapshot: TodayContextSnapshot) -> TodaySourceResult {
        .init(id: id, status: snapshot.sourceStatus[id]!, dateTime: nil, weather: nil)
    }
}
