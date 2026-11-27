import Foundation
import Combine
import CryptoKit

@MainActor
final class GeminiModelStore: ObservableObject {
    static let shared = GeminiModelStore()
    enum ConnectionState: String { case notConfigured = "Not Configured", configured = "Configured", connecting = "Connecting", connected = "Connected", failed = "Connection Failed", rateLimited = "Rate Limited" }
    enum StructuredCapability: String { case untested = "Not tested", verified = "Verified", failed = "Not verified" }

    @Published private(set) var state: ConnectionState = .notConfigured
    @Published private(set) var hasCredential = false
    @Published private(set) var models: [GeminiModel] = []
    @Published private(set) var message: String?
    @Published private(set) var busy = false
    @Published private(set) var latestResponse: GeminiResponse?
    @Published private(set) var structured: [String: StructuredCapability] = [:]
    @Published private(set) var debugOutput = ""
    @Published private(set) var todayConfigurationRevision = UUID()
    @Published var intelligenceModelID: String {
        didSet { defaults.set(intelligenceModelID, forKey: Self.intelligenceModelKey) }
    }
    @Published var todayModelID: String {
        didSet { defaults.set(todayModelID, forKey: Self.todayModelKey); if oldValue != todayModelID { todayConfigurationRevision = UUID() } }
    }

    static let intelligenceModelKey = "intelligence.gemini.model"
    static let todayModelKey = "today.gemini.model"
    private let credentials: any GeminiCredentialStoring
    private let defaults: UserDefaults
    private let client: GeminiClient
    private var testedModels = Set<String>()
    private var operation: Task<Void, Never>?
    private var revision = UUID()
    private struct Verification: Codable { let model: GeminiModel; let credentialHash: String; let verifiedAt: Date }
    private static let verificationKey = "today.gemini.verified.v1"
    private var credentialHash = ""
    var todayCredentialIdentity: String { credentialHash }

    init(credentials: any GeminiCredentialStoring = GeminiKeychainStore(), client: GeminiClient? = nil,
         defaults: UserDefaults = .standard) {
        self.credentials = credentials; self.defaults = defaults
        self.client = client ?? GeminiClient(credentials: credentials)
        intelligenceModelID = defaults.string(forKey: Self.intelligenceModelKey) ?? ""
        todayModelID = defaults.string(forKey: Self.todayModelKey) ?? ""
        // No credential reads, network access or automatic tests during app startup.
    }

    private func canUse(_ model: String) -> Bool { hasCredential && GeminiClient.validModelID(model) && (models.isEmpty || available(model)) }
    var isReady: Bool { canUse(intelligenceModelID) }
    var isTodayReady: Bool { canUse(todayModelID) }
    var statusLabel: String {
        if busy { return ConnectionState.connecting.rawValue }
        if state == .connected && !isReady { return "Choose a model" }
        return state.rawValue
    }
    func available(_ id: String) -> Bool { models.contains { $0.id == id } }

    func readCredentialStatus() {
        do {
            let key = try credentials.load()
            let previousIdentity = credentialHash
            hasCredential = key?.isEmpty == false
            credentialHash = key.map { SHA256.hash(data: Data($0.utf8)).map { String(format: "%02x", $0) }.joined() } ?? ""
            if !previousIdentity.isEmpty && previousIdentity != credentialHash { testedModels = []; structured = [:] }
            if !hasCredential {
                testedModels = []; structured = [:]; state = .notConfigured
            } else if state == .notConfigured { state = .configured }
            // Restore only a successful, bounded-age structured test bound to this credential.
            if let data = defaults.data(forKey: Self.verificationKey), let proof = try? JSONDecoder().decode(Verification.self, from: data),
               proof.model.id == todayModelID, proof.credentialHash == credentialHash,
               (0...604_800).contains(Date().timeIntervalSince(proof.verifiedAt)) {
                if !available(proof.model.id) { models.append(proof.model) }
                testedModels.insert(proof.model.id); structured[proof.model.id] = .verified
            }
        } catch { fail(error) }
    }

    @discardableResult
    func saveCredential(_ key: String) -> Bool {
        guard !busy else { return false }
        do {
            try credentials.save(GeminiCredentialValue.normalized(key))
            revision = UUID()
            defaults.removeObject(forKey: Self.verificationKey); credentialHash = ""; todayConfigurationRevision = UUID()
            models = []; testedModels = []; structured = [:]; latestResponse = nil; debugOutput = ""
            hasCredential = true; state = .configured
            message = "Key saved in macOS Keychain. Choose a model to start. Connection tests are optional."
            return true
        } catch { fail(error); return false }
    }

    func disconnect() {
        cancel()
        do {
            try credentials.delete()
            revision = UUID()
            defaults.removeObject(forKey: Self.verificationKey); credentialHash = ""; todayConfigurationRevision = UUID()
            hasCredential = false; models = []; testedModels = []; structured = [:]
            latestResponse = nil; debugOutput = ""; message = nil; state = .notConfigured
            // Model preferences intentionally survive disconnection; the key and verification do not.
            Task { await client.cancelAll() }
        } catch { fail(error) }
    }

    func refreshModels() { start { try await self.discover() } }
    private func discover() async throws {
        let discovered = try await client.models()
        try Task.checkCancellation()
        hasCredential = true
        models = discovered
        testedModels.formIntersection(Set(discovered.map(\.id)))
        if discovered.isEmpty { message = "Google returned no models supporting text generation for this key." }
        else if !intelligenceModelID.isEmpty && !available(intelligenceModelID) {
            message = "Your saved model is no longer available. Select a replacement; Notchloom will not substitute one."
        } else { message = "Models refreshed. Choose a model to start. Connection tests are optional." }
        state = testedModels.contains(intelligenceModelID) && isReady ? .connected : .configured
    }

    func testConnection(modelID: String? = nil) {
        let selected = modelID ?? intelligenceModelID
        start {
            try await self.discover()
            guard self.available(selected) else { throw GeminiError.unavailableModel }
            let response = try await self.client.generate(prompt: "Reply with one short greeting. This is a synthetic Notchloom connection test.", model: selected)
            try Task.checkCancellation()
            self.latestResponse = response
            self.testedModels.insert(selected)
            self.state = .connected
            // A successful text call is not evidence of structured-output compatibility.
            do {
                let json = try await self.client.generate(prompt: TodayReportSchema.syntheticPrompt, model: selected, schema: TodayReportSchema.data())
                _ = try TodayReportValidator.validate(Data(json.text.utf8))
                try Task.checkCancellation()
                self.latestResponse = json
                self.structured[selected] = .verified
                if self.todayModelID.isEmpty { self.todayModelID = selected }
                self.readCredentialStatus()
                if let model = self.models.first(where: { $0.id == selected }) {
                    let proof = Verification(model: model, credentialHash: self.credentialHash, verifiedAt: Date())
                    self.defaults.set(try JSONEncoder().encode(proof), forKey: Self.verificationKey)
                }
                self.todayConfigurationRevision = UUID()
                self.message = "Connected. Text generation and the version 1 Today report both passed real requests."
            } catch is CancellationError { throw CancellationError() }
            catch {
                self.structured[selected] = .failed
                self.message = "Text connection succeeded. Today structured output is not verified: " + Self.safeMessage(error)
                if case GeminiError.rateLimited = error { self.state = .rateLimited }
            }
        }
    }

    /// Explicit prompt only. No calendar, notifications, weather or other personal data is collected here.
    func generateIntelligence(prompt: String) async throws -> String {
        readCredentialStatus()
        guard isReady else { throw GeminiError.notReady }
        let currentRevision = revision
        do {
            let result = try await client.generate(prompt: prompt, model: intelligenceModelID)
            guard currentRevision == revision else { throw GeminiError.notReady }
            latestResponse = result
            return result.text
        } catch is CancellationError {
            // Disconnect can cancel the shared client without canceling the chat's caller Task.
            // Return a recoverable configuration error so the chat never stays on Thinking.
            if currentRevision != revision && !Task.isCancelled { throw GeminiError.notReady }
            throw CancellationError()
        }
    }

    /// Gemini only, using the independently selected Today model; output validation is mandatory.
    func generateToday(prompt: String, context: TodayValidationContext) async throws -> ValidatedTodayReport {
        readCredentialStatus()
        guard isTodayReady else { throw GeminiError.notReady }
        let currentRevision = revision
        let result = try await client.generate(prompt: prompt, model: todayModelID, schema: TodayReportSchema.data())
        guard currentRevision == revision else { throw CancellationError() }
        latestResponse = result
        return try TodayReportValidator.validate(Data(result.text.utf8), context: context)
    }

    /// One structured request per briefing action. No silent paid retries or model substitution.
    func generateBriefing(prompt: String, systemInstruction: String, model: String) async throws -> GeminiResponse {
        guard isTodayReady, model == todayModelID else { throw GeminiError.notReady }
        let expected = revision
        let result: GeminiResponse
        do {
            result = try await client.generate(prompt: prompt, model: model, schema: TodayReportSchema.data(),
                                                systemInstruction: systemInstruction, maxOutputTokens: 4096, allowRetries: false)
        } catch {
            if let providerError = error as? GeminiError,
               [.credentials, .unavailableModel, .invalidRequest, .unsupportedStructuredOutput].contains(providerError) {
                testedModels.remove(model); structured[model] = .failed
                defaults.removeObject(forKey: Self.verificationKey)
            }
            throw error
        }
        try Task.checkCancellation()
        guard expected == revision, model == todayModelID else { throw CancellationError() }
        // The global status panel needs usage only; personal briefing prose belongs to its consent-aware owner.
        latestResponse = .init(text: "", model: result.model, elapsed: result.elapsed, usage: result.usage)
        return result
    }

    #if DEBUG
    func runPlayground(prompt: String, model: String, useStructured: Bool) {
        start {
            guard self.available(model) else { throw GeminiError.unavailableModel }
            let result = try await self.client.generate(prompt: prompt, model: model, schema: useStructured ? TodayReportSchema.data() : nil)
            if useStructured { _ = try TodayReportValidator.validate(Data(result.text.utf8)) }
            try Task.checkCancellation()
            self.latestResponse = result
            self.debugOutput = result.text
            self.message = useStructured ? "Structured test decoded and validated." : "Text test completed."
        }
    }
    #endif

    func cancel() {
        operation?.cancel(); operation = nil
        revision = UUID(); busy = false
        state = testedModels.contains(intelligenceModelID) && isReady ? .connected : (hasCredential ? .configured : .notConfigured)
        message = "Request canceled."
    }
    private func start(_ body: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true; state = .connecting; message = nil
        let currentRevision = revision
        operation = Task {
            do { try await body() }
            catch is CancellationError { if self.revision == currentRevision { self.message = "Request canceled." } }
            catch { if self.revision == currentRevision { self.fail(error) } }
            guard self.revision == currentRevision else { return }
            self.busy = false
            if self.state == .connecting { self.state = self.isReady ? .connected : .configured }
            self.operation = nil
        }
    }
    private func fail(_ error: Error) {
        if case GeminiError.rateLimited = error { state = .rateLimited } else { state = .failed }
        message = Self.safeMessage(error)
    }
    nonisolated static func safeMessage(_ error: Error) -> String {
        // Never pass an arbitrary network/Keychain/provider error description into UI or diagnostics.
        if let error = error as? GeminiError { return error.localizedDescription }
        if let error = error as? GeminiCredentialError { return error.localizedDescription }
        if let error = error as? TodayValidationError { return error.localizedDescription }
        return "Gemini could not complete the request. Try again."
    }
}
