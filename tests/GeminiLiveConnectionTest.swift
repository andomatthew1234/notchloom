import Foundation

private struct ExplicitTestCredential: GeminiCredentialStoring {
    let value: String
    func load() throws -> String? { value }
    func save(_ key: String) throws { throw GeminiError.invalidRequest }
    func delete() throws { throw GeminiError.invalidRequest }
}

/// Only invoked with run-gemini-checks.sh --live and explicitly configured test variables.
@main struct GeminiLiveConnectionTest {
    static func main() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let key = environment["NOTCHLOOM_GEMINI_TEST_KEY"], !key.isEmpty,
              let model = environment["NOTCHLOOM_GEMINI_TEST_MODEL"], GeminiClient.validModelID(model) else {
            print("SKIP live Gemini test: explicitly configure NOTCHLOOM_GEMINI_TEST_KEY and NOTCHLOOM_GEMINI_TEST_MODEL first. No request made.")
            return
        }
        do {
            let client = GeminiClient(credentials: ExplicitTestCredential(value: key))
            let models = try await client.models()
            guard models.contains(where: { $0.id == model }) else { throw GeminiError.unavailableModel }
            let text = try await client.generate(prompt: "Reply briefly: Hello. Synthetic integration test.", model: model)
            let structured = try await client.generate(prompt: TodayReportSchema.syntheticPrompt, model: model, schema: TodayReportSchema.data())
            _ = try TodayReportValidator.validate(Data(structured.text.utf8))
            print("PASS live Gemini: \(models.count) generation models discovered; text and validated report returned.")
            print(text.diagnostics)
            print(structured.diagnostics)
        } catch {
            // No raw provider body, key, prompt or response is ever printed.
            print("FAIL live Gemini: " + GeminiModelStore.safeMessage(error))
            exit(1)
        }
    }
}
