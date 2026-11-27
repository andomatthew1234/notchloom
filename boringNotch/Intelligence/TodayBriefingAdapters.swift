import Foundation

@MainActor final class TodayLiveContextAccess: TodayBriefingContextProviding {
    private let controller: TodayContextController
    init(_ controller: TodayContextController) { self.controller = controller }
    func collect(force: Bool) async throws -> TodayBriefingContext { try await controller.collectBriefingContext(force: force) }
    func isAuthorized(_ context: TodayBriefingContext) async -> Bool { await controller.briefingStillAuthorized(context) }
}
@MainActor final class TodayLiveGeminiAccess: TodayBriefingGenerating {
    private let store: GeminiModelStore
    init(_ store: GeminiModelStore) { self.store = store }
    func configuration() -> TodayGeminiConfiguration {
        store.readCredentialStatus()
        return .init(model: store.todayModelID, credentialIdentity: store.todayCredentialIdentity, ready: store.isTodayReady)
    }
    func generate(prompt: String, systemInstruction: String, model: String) async throws -> GeminiResponse {
        try await store.generateBriefing(prompt: prompt, systemInstruction: systemInstruction, model: model)
    }
}
