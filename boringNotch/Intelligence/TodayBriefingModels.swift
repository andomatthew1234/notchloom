import Foundation
import CryptoKit

struct TodayBriefingConsent: Codable, Sendable, Equatable {
    var version = 1
    var scopeHash: String?
    var grantedAt: Date?
    func permits(_ settings: TodayPrivacySettings) -> Bool {
        version == 1 && settings.collectionEnabled && settings.setupCompleted && scopeHash == TodayPromptBuilder.scopeHash(settings) && grantedAt != nil
    }
}
struct TodayGeminiConfiguration: Sendable, Equatable {
    let model: String
    let credentialIdentity: String
    let ready: Bool
}
struct TodayBriefingContext: Sendable {
    let snapshot: TodayContextSnapshot
    let settings: TodayPrivacySettings
    let revision: Int
    let accessHash: String
}
protocol TodayBriefingContextProviding: Sendable {
    func collect(force: Bool) async throws -> TodayBriefingContext
    func isAuthorized(_ context: TodayBriefingContext) async -> Bool
}
protocol TodayBriefingGenerating: Sendable {
    func configuration() async -> TodayGeminiConfiguration
    func generate(prompt: String, systemInstruction: String, model: String) async throws -> GeminiResponse
}
enum TodayBriefingError: LocalizedError, Equatable {
    case consentRequired, setupRequired, noContext, staleContext, authorizationChanged, cacheUnavailable, invalidReport
    var errorDescription: String? {
        switch self {
        case .consentRequired: "Choose whether to send your selected Today information to Google’s Gemini API."
        case .setupRequired: "Set up Today’s local data sources first."
        case .noContext: "There’s no usable information yet. Enable date and time or connect another source."
        case .staleContext: "Today’s local information needs refreshing. Try again."
        case .authorizationChanged: "Your source choices or permissions changed. Review them before preparing Today again."
        case .cacheUnavailable: "The briefing is ready for this session, but could not be saved securely on this Mac."
        case .invalidReport: "Gemini returned a report with unsupported content or unverified references. Your previous briefing is still available if authorized."
        }
    }
}
struct TodayPreparedPrompt: Sendable {
    let json: Data
    let contextHash: String
    let registry: TodayWidgetRegistry
    let widgets: [TodayLinkedWidget]
    let sourceFreshness: [TodaySourceID: TodaySourceStatus]
    let generatedAt: Date
    let timezone: String
    let localDay: String
    let scopeHash: String
    let accessHash: String
    let validUntil: Date
    let privacyExpiresAt: Date
    let hasWeather: Bool
}

struct TodayBriefingEntry: Codable, Sendable {
    let version: Int
    let generatedAt: Date
    let model: String
    let credentialIdentity: String
    let contextHash: String
    let scopeHash: String
    let accessHash: String
    let timezone: String
    let localDay: String
    let validUntil: Date
    let privacyExpiresAt: Date
    let sourceFreshness: [TodaySourceID: TodaySourceStatus]
    let report: TodayReport
    /// Native display data for selected cards only. No raw context snapshot or prompt is stored.
    let widgets: [TodayLinkedWidget]
    let referencedSources: Set<TodayReport.Source>
    let usage: GeminiUsage?
    let elapsed: TimeInterval
    let hasWeather: Bool
    func validated() throws -> ValidatedTodayReport {
        guard version == 1, widgets.count <= 12, TimeZone(identifier: timezone) != nil,
              generatedAt.timeIntervalSince1970.isFinite, validUntil.timeIntervalSince1970.isFinite,
              privacyExpiresAt > generatedAt, privacyExpiresAt <= generatedAt.addingTimeInterval(86_401),
              GeminiClient.validModelID(model) else { throw TodayBriefingError.invalidReport }
        let registry = try TodayWidgetRegistry(widgets)
        guard referencedSources.count <= 12 else { throw TodayBriefingError.invalidReport }
        var validation = registry.validationContext; validation.sources.formUnion(referencedSources)
        let result = try TodayReportValidator.validate(JSONEncoder().encode(report), context: validation)
        try TodayPromptBuilder.validateGrounding(result, registry: registry, now: generatedAt)
        guard widgets.count == result.report.widgets.count else { throw TodayBriefingError.invalidReport }
        return result
    }
    func document(stale: Bool) throws -> TodayPageDocument {
        .init(report: try validated(), registry: try TodayWidgetRegistry(widgets), eyebrow: "TODAY",
              subtitle: stale ? "Your earlier briefing. Refresh when you’re ready." : generatedAt.formatted(.dateTime.weekday(.wide).month(.wide).day()), isPreview: false,
              statusLabel: stale ? "Earlier briefing" : "Updated " + generatedAt.formatted(date: .omitted, time: .shortened),
              footerText: "Prepared by Gemini " + generatedAt.formatted(date: .abbreviated, time: .shortened) + ". AI can make mistakes; check the linked source details. " + (hasWeather ? "Weather data: Open-Meteo · CC BY 4.0. Model forecasts, not weather alerts." : ""),
              footerURL: hasWeather ? URL(string: "https://open-meteo.com/") : nil, sectionLabel: "YOUR BRIEFING")
    }
    func isStale(now: Date, zone: TimeZone, model: String, contextHash: String? = nil) -> Bool {
        now < generatedAt || now >= validUntil || self.model != model || timezone != zone.identifier ||
        localDay != TodayPromptBuilder.localDay(now, zone: zone) || contextHash.map { $0 != self.contextHash } == true
    }
}

func todayDigest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
