import Foundation

private struct ExplicitBriefingCredential: GeminiCredentialStoring {
    let value: String
    func load() throws -> String? { value }
    func save(_ key: String) throws { throw GeminiError.invalidRequest }
    func delete() throws { throw GeminiError.invalidRequest }
}
private struct ExplicitBriefingContext: TodayBriefingContextProviding {
    let value: TodayBriefingContext
    func collect(force: Bool) async throws -> TodayBriefingContext { value }
    func isAuthorized(_ context: TodayBriefingContext) async -> Bool { context.revision == value.revision }
}
private struct ExplicitBriefingGemini: TodayBriefingGenerating {
    let client: GeminiClient
    let model: String
    func configuration() async -> TodayGeminiConfiguration { .init(model: model, credentialIdentity: "explicit-synthetic-integration-test", ready: true) }
    func generate(prompt: String, systemInstruction: String, model: String) async throws -> GeminiResponse {
        try await client.generate(prompt: prompt, model: model, schema: TodayReportSchema.data(), systemInstruction: systemInstruction, allowRetries: false)
    }
}

/// Opt-in only. Never reads the app's key or personal context, and makes at most one generation call.
@main struct TodayBriefingLiveTest {
    static func main() async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["NOTCHLOOM_TODAY_LIVE_CONSENT"] == "yes", let key = env["NOTCHLOOM_GEMINI_TEST_KEY"], !key.isEmpty,
              let model = env["NOTCHLOOM_GEMINI_TEST_MODEL"], GeminiClient.validModelID(model) else {
            print("SKIP live Today: explicit test credential, model and NOTCHLOOM_TODAY_LIVE_CONSENT=yes are required. No request made; the app Keychain is not read.")
            return
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("notchloom-today-live-" + UUID().uuidString)
        let keys = GeminiKeychainStore(service: "Notchloom.Today.LiveTest." + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder); try? keys.delete() }
        var settings = TodayPrivacySettings(); settings.collectionEnabled = true; settings.setupCompleted = true
        let engine = TodayContextService(sources: [TodayDateTimeSource()])
        await engine.configure(settings, revision: 1)
        let snapshot = try await engine.snapshot(zone: .gmt, locale: Locale(identifier: "en_US_POSIX"), revision: 1)
        let context = TodayBriefingContext(snapshot: snapshot, settings: settings, revision: 1, accessHash: "explicit-synthetic-context")
        let client = GeminiClient(credentials: ExplicitBriefingCredential(value: key))
        let service = TodayBriefingService(context: ExplicitBriefingContext(value: context), gemini: ExplicitBriefingGemini(client: client, model: model), cache: TodayBriefingCache(directory: folder, keys: keys))
        do {
            let report = try await service.generate(consent: .init(scopeHash: TodayPromptBuilder.scopeHash(settings), grantedAt: Date()))
            _ = try report.entry.validated()
            print("PASS live Today: one Gemini request produced a validated version 1 report from public UTC date/time only. No personal sources used. Scheduled proposals preserved only, never delivered.")
        } catch {
            print("FAIL live Today: " + ((error as? TodayBriefingError)?.localizedDescription ?? GeminiModelStore.safeMessage(error)))
            exit(1)
        }
    }
}
