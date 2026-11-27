import Foundation

struct TodayBriefingResult: Sendable {
    let entry: TodayBriefingEntry
    let reused: Bool
    let cacheWarning: Bool
}

/// Owns collection → privacy checks → one Gemini request → validation → protected persistence.
actor TodayBriefingService {
    private let context: any TodayBriefingContextProviding
    private let gemini: any TodayBriefingGenerating
    private let cache: any TodayBriefingCaching
    private var generation = 0
    private var flight: (id: UUID, task: Task<TodayBriefingResult, Error>)?
    init(context: any TodayBriefingContextProviding, gemini: any TodayBriefingGenerating, cache: any TodayBriefingCaching) {
        self.context = context; self.gemini = gemini; self.cache = cache
    }
    func configuration() async -> TodayGeminiConfiguration { await gemini.configuration() }
    func cached(settings: TodayPrivacySettings, consent: TodayBriefingConsent, accessHash: String, now: Date = Date()) async -> TodayBriefingEntry? {
        guard consent.permits(settings) else { await clear(); return nil }
        let epoch = generation
        guard let entry = try? await cache.load() else { return nil }
        guard epoch == generation else { return nil }
        let config = await gemini.configuration()
        guard epoch == generation else { return nil }
        guard entry.scopeHash == TodayPromptBuilder.scopeHash(settings), entry.accessHash == accessHash,
              entry.credentialIdentity == config.credentialIdentity, !config.credentialIdentity.isEmpty,
              entry.model == config.model, now >= entry.generatedAt, now < entry.privacyExpiresAt else {
            await clear(); return nil
        }
        return entry
    }
    func preview() async throws -> TodayPreparedPrompt {
        let collected = try await context.collect(force: false)
        try Task.checkCancellation()
        guard await context.isAuthorized(collected) else { throw TodayBriefingError.authorizationChanged }
        return try TodayPromptBuilder.prepare(collected)
    }
    func generate(consent: TodayBriefingConsent, force: Bool = false,
                  onPreparing: (@Sendable (TodayPreparedPrompt) async -> Void)? = nil) async throws -> TodayBriefingResult {
        if let flight { return try await flight.task.value }
        let id = UUID(), epoch = generation
        let context = self.context, gemini = self.gemini, cache = self.cache
        let task = Task { () throws -> TodayBriefingResult in
            let config = await gemini.configuration()
            guard config.ready, GeminiClient.validModelID(config.model) else { throw GeminiError.notReady }
            let collected = try await context.collect(force: force)
            try Task.checkCancellation()
            guard consent.permits(collected.settings) else { throw TodayBriefingError.consentRequired }
            let prepared = try TodayPromptBuilder.prepare(collected)
            guard await context.isAuthorized(collected) else { throw TodayBriefingError.authorizationChanged }
            if !force, let existing = try? await cache.load(), existing.scopeHash == prepared.scopeHash,
               existing.accessHash == prepared.accessHash, existing.credentialIdentity == config.credentialIdentity,
               Date() < existing.privacyExpiresAt,
               !existing.isStale(now: Date(), zone: TimeZone(identifier: prepared.timezone)!, model: config.model, contextHash: prepared.contextHash) {
                return .init(entry: existing, reused: true, cacheWarning: false)
            }
            if let onPreparing { await onPreparing(prepared) }
            try Task.checkCancellation()
            guard await context.isAuthorized(collected), await gemini.configuration() == config else { throw TodayBriefingError.authorizationChanged }
            // No second request for malformed JSON, retry/fallback model, or token streaming simulation.
            let response = try await gemini.generate(prompt: String(decoding: prepared.json, as: UTF8.self), systemInstruction: TodayPromptBuilder.systemInstruction, model: config.model)
            try Task.checkCancellation()
            guard Date() < prepared.privacyExpiresAt else { throw TodayBriefingError.staleContext }
            guard await context.isAuthorized(collected), await gemini.configuration() == config else { throw TodayBriefingError.authorizationChanged }
            let report: ValidatedTodayReport
            do {
                report = try TodayReportValidator.validate(Data(response.text.utf8), context: prepared.registry.validationContext)
                try TodayPromptBuilder.validateGrounding(report, registry: prepared.registry, now: Date())
            } catch { throw TodayBriefingError.invalidReport }
            let selected = prepared.registry.widgets(for: report)
            guard selected.count == report.report.widgets.count, response.model == config.model else { throw TodayBriefingError.invalidReport }
            let entry = TodayBriefingEntry(version: 1, generatedAt: Date(), model: config.model, credentialIdentity: config.credentialIdentity,
                contextHash: prepared.contextHash, scopeHash: prepared.scopeHash, accessHash: prepared.accessHash,
                timezone: prepared.timezone, localDay: prepared.localDay, validUntil: prepared.validUntil,
                privacyExpiresAt: prepared.privacyExpiresAt, sourceFreshness: prepared.sourceFreshness,
                report: report.report, widgets: selected, referencedSources: Set(report.report.scheduledInsights.map(\.sourceReference)),
                usage: response.usage, elapsed: response.elapsed, hasWeather: prepared.hasWeather)
            _ = try entry.validated()
            try Task.checkCancellation()
            var warning = false
            do { try await cache.save(entry, generation: epoch) }
            catch is CancellationError { throw CancellationError() }
            catch { warning = true }
            try Task.checkCancellation()
            guard await context.isAuthorized(collected) else {
                await cache.clear(generation: epoch)
                throw TodayBriefingError.authorizationChanged
            }
            return .init(entry: entry, reused: false, cacheWarning: warning)
        }
        flight = (id, task)
        defer { if flight?.id == id { flight = nil } }
        let result = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
        guard generation == epoch else { throw CancellationError() }
        return result
    }
    func cancel() { flight?.task.cancel(); flight = nil }
    func clear() async {
        generation += 1; cancel()
        await cache.clear(generation: generation)
    }
}
