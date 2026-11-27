import Foundation
import Security

private final class MemoryCredential: GeminiCredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?
    var denied = false
    init(_ value: String? = "synthetic-not-a-real-api-key") { self.value = value }
    func load() throws -> String? { lock.lock(); defer { lock.unlock() }; if denied { throw GeminiCredentialError.keychain(errSecAuthFailed) }; return value }
    func save(_ key: String) throws { lock.lock(); defer { lock.unlock() }; if denied { throw GeminiCredentialError.keychain(errSecAuthFailed) }; value = key }
    func delete() throws { lock.lock(); defer { lock.unlock() }; if denied { throw GeminiCredentialError.keychain(errSecAuthFailed) }; value = nil }
}

private actor MockTransport: GeminiTransport {
    struct Reply: Sendable {
        var status = 200
        var body: Data
        var headers: [String: String] = [:]
        var error: URLError.Code?
        var delay: Double = 0
        init(_ text: String, status: Int = 200, headers: [String: String] = [:], error: URLError.Code? = nil, delay: Double = 0) {
            body = Data(text.utf8); self.status = status; self.headers = headers; self.error = error; self.delay = delay
        }
    }
    var replies: [Reply]
    private(set) var requests: [URLRequest] = []
    init(_ replies: [Reply]) { self.replies = replies }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !replies.isEmpty else { throw GeminiError.network }
        let reply = replies.removeFirst()
        if reply.delay > 0 { try await Task.sleep(for: .seconds(reply.delay)) }
        if let code = reply.error { throw URLError(code) }
        return (reply.body, HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: nil, headerFields: reply.headers)!)
    }
    var count: Int { requests.count }
}

private actor BackoffRecorder {
    var delays: [Double] = []
    func record(_ delay: Double) { delays.append(delay) }
}

@main
struct GeminiPhaseOneTests {
    static var checks = 0
    static let modelID = "models/mock-text-model"
    static let list = #"{"models":[{"name":"models/mock-text-model","displayName":"Synthetic Text Model","description":"Test only","supportedGenerationMethods":["generateContent"],"inputTokenLimit":32000,"outputTokenLimit":4096},{"name":"models/embed-only","supportedGenerationMethods":["embedContent"]}]}"#
    static let report = #"{"version":1,"title":"Hello","blocks":[{"id":"intro","type":"paragraph","parts":[{"type":"text","value":"Synthetic test."}]}],"widgets":[],"scheduledInsights":[]}"#
    static func envelope(_ text: String = "Hello") -> String {
        let object: [String: Any] = ["candidates": [["content": ["parts": [["text": text]]], "finishReason": "STOP"]],
                                    "usageMetadata": ["promptTokenCount": 7, "candidatesTokenCount": 4, "totalTokenCount": 12, "thoughtsTokenCount": 1]]
        return String(data: try! JSONSerialization.data(withJSONObject: object), encoding: .utf8)!
    }
    static func expect(_ value: Bool, _ name: String) throws {
        guard value else { throw TestFailure(name) }
        checks += 1
    }
    struct TestFailure: Error { let name: String; init(_ name: String) { self.name = name } }
    static func rejects(_ name: String, _ body: () async throws -> Void, matching: ((Error) -> Bool)? = nil) async throws {
        do { try await body() } catch {
            try expect(matching?(error) ?? true, name + " error classification")
            return
        }
        throw TestFailure(name + " unexpectedly succeeded")
    }
    private static func client(_ transport: MockTransport, key: MemoryCredential = .init(), retries: Int = 0) -> GeminiClient {
        GeminiClient(credentials: key, transport: transport, timeout: 1, retries: retries, sleep: { _ in try Task.checkCancellation() })
    }
    @MainActor
    static func main() async throws {
        // Isolated real Keychain item: never reads or modifies the app's credential.
        let keychain = GeminiKeychainStore(service: "Notchloom.Tests." + UUID().uuidString)
        defer { try? keychain.delete() }
        try expect(try keychain.load() == nil, "Keychain initial missing")
        try keychain.save("synthetic_keychain_value_123456")
        try expect(try keychain.load() == "synthetic_keychain_value_123456", "Keychain save/load")
        try keychain.save("synthetic_keychain_replacement_123")
        try expect(try keychain.load() == "synthetic_keychain_replacement_123", "Keychain replace")
        try keychain.delete()
        try expect(try keychain.load() == nil, "Keychain delete")
        try await rejects("Keychain rejects embedded newline") { try keychain.save("synthetic\nheader-injection") }
        try keychain.save("  synthetic.opaque/+key=with:punctuation  \n")
        try expect(try keychain.load() == "synthetic.opaque/+key=with:punctuation", "Opaque key punctuation preserved and surrounding whitespace trimmed")
        try keychain.save(String(repeating: "x", count: 1024))
        try expect(try keychain.load()?.count == 1024, "Key length is not guessed from legacy formats")
        try await rejects("Empty credential") { _ = try GeminiCredentialValue.normalized(" \n ") }
        let missing = MockTransport([])
        try await rejects("Missing credential", { _ = try await client(missing, key: .init(nil)).models() }, matching: { ($0 as? GeminiError) == .missingKey })
        try expect(await missing.count == 0, "Missing key makes no request")
        let denied = MemoryCredential(); denied.denied = true
        try await rejects("Keychain access failure") { _ = try await client(MockTransport([]), key: denied).models() }

        let paged = MockTransport([.init(#"{"models":[{"name":"models/mock-text-model","supportedGenerationMethods":["generateContent"]}],"nextPageToken":"page 2"}"#), .init(list)])
        let discovered = try await client(paged).models()
        try expect(discovered.count == 1 && discovered[0].id == modelID, "Models filtered and deduplicated across pages")
        let pageRequests = await paged.requests
        try expect(pageRequests.count == 2 && pageRequests[1].url!.query!.contains("pageToken="), "Discovery pagination")
        let textTransport = MockTransport([.init(envelope())])
        let text = try await client(textTransport).generate(prompt: "Synthetic test", model: modelID)
        try expect(text.text == "Hello" && text.model == modelID && text.elapsed >= 0, "Text response")
        try expect(text.usage?.totalTokenCount == 12 && text.usage?.thoughtsTokenCount == 1, "Usage metadata")
        let request = await textTransport.requests[0]
        try expect(request.url!.query == nil && request.value(forHTTPHeaderField: "x-goog-api-key") != nil, "Authentication uses header")
        try expect(!text.diagnostics.contains("synthetic-not-a-real-api-key") && !text.diagnostics.contains("Synthetic test"), "Sanitized diagnostics")
        let jsonTransport = MockTransport([.init(envelope(report))])
        let json = try await client(jsonTransport).generate(prompt: TodayReportSchema.syntheticPrompt, model: modelID, schema: TodayReportSchema.data())
        let valid = try TodayReportValidator.validate(Data(json.text.utf8))
        try expect(valid.report.title == "Hello", "Structured decode and validation")
        let jsonRequest = await jsonTransport.requests[0]
        let body = try JSONSerialization.jsonObject(with: jsonRequest.httpBody!) as! [String: Any]
        let config = body["generationConfig"] as! [String: Any]
        try expect(config["responseMimeType"] as? String == "application/json" && config["responseJsonSchema"] != nil, "Schema-constrained request")

        let wireSchema = try JSONSerialization.jsonObject(with: TodayReportSchema.data())
        func hasCostlyConstraints(_ value: Any) -> Bool {
            if let object = value as? [String: Any] {
                if !Set(object.keys).isDisjoint(with: ["maxItems", "minItems", "pattern", "minLength", "maxLength"]) { return true }
                return object.values.contains(where: hasCostlyConstraints)
            }
            if let values = value as? [Any] { return values.contains(where: hasCostlyConstraints) }
            return false
        }
        try expect(!hasCostlyConstraints(wireSchema), "Wire schema avoids grammar-state multiplication; local limits remain enforced")
        let complexError = #"{"error":{"message":"The response schema is too complex for serving. Private provider text must not appear in UI."}}"#
        try await rejects("Complex schema classified accurately", { _ = try await client(MockTransport([.init(complexError, status: 400)])).generate(prompt: "Synthetic", model: modelID) }, matching: { ($0 as? GeminiError) == .schemaTooComplex })
        try expect(!GeminiError.schemaTooComplex.localizedDescription.contains("Private provider"), "Provider body never reaches error UI")
        let unsupportedError = #"{"error":{"message":"JSON response schema is not supported for this model."}}"#
        try await rejects("Actual unsupported format distinguished", { _ = try await client(MockTransport([.init(unsupportedError, status: 400)])).generate(prompt: "Synthetic", model: modelID) }, matching: { ($0 as? GeminiError) == .unsupportedStructuredOutput })
        try expect(!GeminiError.invalidRequest.localizedDescription.contains("may not support"), "Generic request failure does not guess model incompatibility")
        for (name, input) in [
            ("Malformed JSON", "{"), ("Version", report.replacingOccurrences(of: "\"version\":1", with: "\"version\":2")),
            ("Unknown block", report.replacingOccurrences(of: "paragraph", with: "executeCommand")),
            ("Missing fields", "{}"),
            ("Unknown fields", report.replacingOccurrences(of: "\"version\":1", with: "\"command\":\"launch\",\"version\":1")),
            ("Oversized title", report.replacingOccurrences(of: "Hello", with: String(repeating: "x", count: 121))),
            ("Unknown widget", report.replacingOccurrences(of: #"{"type":"text","value":"Synthetic test."}"#, with: #"{"type":"widgetReference","widgetID":"invented"}"#)),
            ("Duplicate ID", report.replacingOccurrences(of: "\"widgets\":[]", with: #""widgets":[{"id":"intro","type":"information"}]"#))
        ] {
            try await rejects(name) { _ = try TodayReportValidator.validate(Data(input.utf8)) }
        }
        let source = TodayReport.Source(type: .calendarEvent, id: "event1")
        var withWidget = try JSONSerialization.jsonObject(with: Data(report.utf8)) as! [String: Any]
        withWidget["widgets"] = [["id": "event-widget", "type": "calendarEvent", "sourceReference": ["type": "calendarEvent", "id": "event1"]]]
        let widgetData = try JSONSerialization.data(withJSONObject: withWidget)
        try await rejects("Unverified source") { _ = try TodayReportValidator.validate(widgetData) }
        _ = try TodayReportValidator.validate(widgetData, context: .init(widgets: ["event-widget": .calendarEvent], sources: [source]))
        checks += 1
        withWidget["scheduledInsights"] = [["id": "reminder1", "triggerAt": "bad-date", "title": "Synthetic", "body": "Test", "sourceReference": ["type": "calendarEvent", "id": "event1"], "delivery": "quiet"]]
        try await rejects("Invalid timestamp") { _ = try TodayReportValidator.validate(JSONSerialization.data(withJSONObject: withWidget), context: .init(widgets: ["event-widget": .calendarEvent], sources: [source])) }
        var scheduled = (withWidget["scheduledInsights"] as! [[String: Any]])[0]
        scheduled["triggerAt"] = "2026-02-30T10:00:00Z"
        withWidget["scheduledInsights"] = [scheduled]
        try await rejects("Nonexistent calendar date") { _ = try TodayReportValidator.validate(JSONSerialization.data(withJSONObject: withWidget), context: .init(widgets: ["event-widget": .calendarEvent], sources: [source])) }
        scheduled["triggerAt"] = "2026-11-21T10:00:00+11:00"
        withWidget["scheduledInsights"] = [scheduled]
        _ = try TodayReportValidator.validate(JSONSerialization.data(withJSONObject: withWidget), context: .init(widgets: ["event-widget": .calendarEvent], sources: [source]))
        checks += 1
        var tooMany = try JSONSerialization.jsonObject(with: Data(report.utf8)) as! [String: Any]
        tooMany["blocks"] = Array(repeating: (tooMany["blocks"] as! [[String: Any]])[0], count: 25)
        try await rejects("Block count limit") { _ = try TodayReportValidator.validate(JSONSerialization.data(withJSONObject: tooMany)) }
        try await rejects("Structured byte limit") { _ = try TodayReportValidator.validate(Data(repeating: 32, count: 128_001)) }
        try await rejects("Malformed local schema") { _ = try await client(MockTransport([])).generate(prompt: "Synthetic", model: modelID, schema: Data("not-json".utf8)) }
        try await rejects("Google invalid key reason", { _ = try await client(MockTransport([.init(#"{"error":{"details":[{"reason":"API_KEY_INVALID"}]}}"#, status: 400)])).models() }, matching: { ($0 as? GeminiError) == .credentials })
        try expect(!GeminiError.rateLimited(1e300).localizedDescription.isEmpty, "Untrusted huge Retry-After cannot overflow error UI")

        for (status, expected) in [(401, GeminiError.credentials), (403, .credentials), (404, .unavailableModel), (400, .invalidRequest), (503, .server(503)), (429, .rateLimited(nil))] {
            try await rejects("HTTP \(status)", { _ = try await client(MockTransport([.init("secret provider error body", status: status)])).models() }, matching: { ($0 as? GeminiError) == expected })
        }
        let retry = MockTransport([.init("", status: 429, headers: ["Retry-After": "2"]), .init(list)])
        _ = try await client(retry, retries: 2).models()
        try expect(await retry.count == 2, "429 retried once then succeeds")
        let backoff = BackoffRecorder()
        let headerTransport = MockTransport([.init("", status: 429, headers: ["Retry-After": "3"]), .init(list)])
        _ = try await GeminiClient(credentials: MemoryCredential(), transport: headerTransport, retries: 1, sleep: { delay in await backoff.record(delay) }).models()
        try expect(await backoff.delays == [3], "Retry waits for provider's Retry-After")
        let limited = MockTransport([.init("", status: 429, headers: ["Retry-After": "120"]), .init(list)])
        try await rejects("Long Retry-After", { _ = try await client(limited, retries: 2).models() }, matching: { ($0 as? GeminiError) == .rateLimited(120) })
        try expect(await limited.count == 1, "Long Retry-After not ignored")
        let bounded = MockTransport(Array(repeating: .init("", status: 503), count: 5))
        try await rejects("Bounded retries") { _ = try await client(bounded, retries: 2).models() }
        try expect(await bounded.count == 3, "Retry bound")
        try expect(GeminiClient.retryDelay("2") == 2, "Numeric Retry-After")
        try expect(GeminiClient.retryDelay("Wed, 21 Oct 2015 07:28:00 GMT", now: Date(timeIntervalSince1970: 1445412470)) == 10, "HTTP date Retry-After")
        try await rejects("Timeout", { _ = try await client(MockTransport([.init("", error: .timedOut)])).models() }, matching: { ($0 as? GeminiError) == .timeout })
        let timeoutRecovery = MockTransport([.init("", error: .timedOut), .init(list)])
        _ = try await client(timeoutRecovery, retries: 1).models()
        try expect(await timeoutRecovery.count == 2, "Timeout retry")
        for (name, payload, expected) in [
            ("Empty", "{}", GeminiError.empty), ("Malformed envelope", "bad", .malformed),
            ("Safety blocked", #"{"promptFeedback":{"blockReason":"SAFETY"}}"#, .blocked),
            ("Candidate blocked", #"{"candidates":[{"finishReason":"SAFETY"}]}"#, .blocked),
            ("Truncated", #"{"candidates":[{"finishReason":"MAX_TOKENS"}]}"#, .incomplete),
            ("Thoughts only", #"{"candidates":[{"content":{"parts":[{"text":"private thinking","thought":true}]},"finishReason":"STOP"}]}"#, .empty)
        ] {
            try await rejects(name, { _ = try await client(MockTransport([.init(payload)])).generate(prompt: "Synthetic", model: modelID) }, matching: { ($0 as? GeminiError) == expected })
        }
        try await rejects("Bad model ID") { _ = try await client(MockTransport([])).generate(prompt: "Synthetic", model: "../other-host") }
        try await rejects("Large input") { _ = try await client(MockTransport([])).generate(prompt: String(repeating: "x", count: 128_001), model: modelID) }

        let slow = MockTransport([.init(envelope(), delay: 5)])
        let slowClient = client(slow)
        let task = Task { try await slowClient.generate(prompt: "Synthetic cancel", model: modelID) }
        try await Task.sleep(for: .milliseconds(30)); task.cancel()
        try await rejects("Cancellation", { _ = try await task.value }, matching: { $0 is CancellationError })
        let duplicate = MockTransport([.init(envelope(), delay: 0.1)])
        let duplicateClient = client(duplicate)
        async let first = duplicateClient.generate(prompt: "Same synthetic", model: modelID)
        async let second = duplicateClient.generate(prompt: "Same synthetic", model: modelID)
        _ = try await (first, second)
        try expect(await duplicate.count == 1, "Concurrent generation deduplication")
        let noUsage = try await client(MockTransport([.init(#"{"candidates":[{"content":{"parts":[{"text":"Hi"}]},"finishReason":"STOP"}]}"#)])).generate(prompt: "Synthetic", model: modelID)
        try expect(noUsage.usage == nil && noUsage.diagnostics.contains("unknown"), "Missing usage stays unknown")
        try await rejects("Response size limit") { _ = try await client(MockTransport([.init(String(repeating: "x", count: 2_000_001))])).models() }
        let cyclePage = #"{"models":[],"nextPageToken":"same"}"#
        try await rejects("Model pagination cycle") { _ = try await client(MockTransport([.init(cyclePage), .init(cyclePage)])).models() }

        let suiteName = "Notchloom.Tests." + UUID().uuidString
        let preferences = UserDefaults(suiteName: suiteName)!
        defer { preferences.removePersistentDomain(forName: suiteName) }
        preferences.set("apple", forKey: "intelligence.provider")
        let mockKey = MemoryCredential()
        let flow = MockTransport([.init(list), .init(envelope()), .init(envelope(report))])
        let store = GeminiModelStore(credentials: mockKey, client: client(flow, key: mockKey), defaults: preferences)
        try expect(!store.isReady && !store.isTodayReady, "Startup is unverified")
        store.intelligenceModelID = modelID
        store.readCredentialStatus()
        store.testConnection()
        await wait(store)
        try expect(store.state == .connected && store.isReady && store.isTodayReady, "Optional connection test records two successful responses")
        try expect(store.todayModelID == modelID && store.structured[modelID] == .verified, "Today defaults to tested structured model")
        let verifiedRestart = GeminiModelStore(credentials: mockKey, client: client(MockTransport([])), defaults: preferences)
        verifiedRestart.readCredentialStatus()
        try expect(verifiedRestart.isTodayReady, "Successful structured verification restores for the same key after restart")
        let otherCredential = MemoryCredential("different-synthetic-key")
        let wrongKeyRestart = GeminiModelStore(credentials: otherCredential, client: client(MockTransport([]), key: otherCredential), defaults: preferences)
        wrongKeyRestart.readCredentialStatus()
        try expect(wrongKeyRestart.isTodayReady && wrongKeyRestart.structured[modelID] != .verified, "A new credential can be used without inheriting old test results")
        let metadataTransport = MockTransport([.init(list), .init(envelope()), .init(envelope(report)), .init(envelope(report))])
        let metadataStore = GeminiModelStore(credentials: mockKey, client: client(metadataTransport, key: mockKey), defaults: preferences)
        metadataStore.intelligenceModelID = modelID
        metadataStore.readCredentialStatus(); metadataStore.testConnection(); await wait(metadataStore)
        let personalResult = try await metadataStore.generateBriefing(prompt: "Synthetic private briefing", systemInstruction: "Synthetic test policy", model: modelID)
        try expect(!personalResult.text.isEmpty && metadataStore.latestResponse?.text.isEmpty == true, "Global status retains usage without private briefing text")
        store.todayModelID = "models/another-choice"
        try expect(store.intelligenceModelID == modelID && !store.isTodayReady && preferences.string(forKey: "intelligence.provider") == "apple", "Today choice independent from general provider")
        let restored = GeminiModelStore(credentials: mockKey, client: client(MockTransport([])), defaults: preferences)
        try expect(restored.intelligenceModelID == modelID && restored.todayModelID == "models/another-choice" && !restored.isReady, "Model persistence never persists Connected")
        store.disconnect()
        try expect(try mockKey.load() == nil && store.state == .notConfigured && store.intelligenceModelID == modelID, "Disconnect removes credential, keeps model preference")
        let unavailableTransport = MockTransport([.init(list)])
        let unavailable = GeminiModelStore(credentials: MemoryCredential(), client: client(unavailableTransport), defaults: preferences)
        unavailable.intelligenceModelID = "models/no-longer-available"
        unavailable.testConnection()
        await wait(unavailable)
        let unavailableRequestCount = await unavailableTransport.count
        try expect(unavailable.state == .failed && unavailable.intelligenceModelID == "models/no-longer-available" && unavailableRequestCount == 1, "Unavailable model never silently replaced")
        let invalidStructured = GeminiModelStore(credentials: MemoryCredential(), client: client(MockTransport([.init(list), .init(envelope()), .init(envelope("not JSON"))])), defaults: preferences)
        invalidStructured.intelligenceModelID = modelID
        invalidStructured.todayModelID = modelID
        invalidStructured.testConnection(); await wait(invalidStructured)
        try expect(invalidStructured.isReady && invalidStructured.isTodayReady && invalidStructured.structured[modelID] == .failed, "Optional structured test failure does not gate a normal request")
        let failedFlow = GeminiModelStore(credentials: MemoryCredential(), client: client(MockTransport([.init(list), .init("", status: 401)])), defaults: preferences)
        failedFlow.intelligenceModelID = modelID
        failedFlow.testConnection(); await wait(failedFlow)
        try expect(failedFlow.state == .failed && failedFlow.message != nil, "Failed test reports the error without claiming Connected")
        let busyTransport = MockTransport([.init(list, delay: 5)])
        let busyFlow = GeminiModelStore(credentials: MemoryCredential(), client: client(busyTransport), defaults: preferences)
        busyFlow.testConnection(); busyFlow.testConnection()
        try await Task.sleep(for: .milliseconds(30))
        busyFlow.cancel()
        try await Task.sleep(for: .milliseconds(30))
        try expect(await busyTransport.count == 1, "Repeated test clicks do not duplicate requests")
        try expect(!busyFlow.busy && !busyFlow.isReady, "Canceled workflow stays unverified")
        busyFlow.todayModelID = ""
        try await rejects("Missing Today selection never falls back") { _ = try await busyFlow.generateToday(prompt: "Synthetic", context: .init()) }
        let setupKey = MemoryCredential(nil)
        let setupTransport = MockTransport([])
        let setupStore = GeminiModelStore(credentials: setupKey, client: client(setupTransport, key: setupKey), defaults: preferences)
        try expect(await setupTransport.count == 0, "No idle/startup network requests")
        try expect(setupStore.saveCredential("synthetic_keychain_setup_only_123") && setupStore.hasCredential && setupStore.state == .configured, "Saving a key configures without claiming a tested connection")
        let directTransport = MockTransport([.init(envelope(report))])
        let directKey = MemoryCredential()
        let directStore = GeminiModelStore(credentials: directKey, client: client(directTransport, key: directKey), defaults: preferences)
        directStore.todayModelID = modelID
        let directReport = try await directStore.generateToday(prompt: "Normal request without a connection test", context: .init())
        try expect(directReport.report.version == 1 && directStore.isTodayReady, "Today works directly with a saved key and selected model")
        try expect(await directTransport.count == 1, "Normal generation makes no preliminary connection-test requests")
        let directChatTransport = MockTransport([.init(envelope("Hello"))])
        let directChat = GeminiModelStore(credentials: directKey, client: client(directChatTransport, key: directKey), defaults: preferences)
        directChat.intelligenceModelID = modelID
        try expect(try await directChat.generateIntelligence(prompt: "Hello without setup tests") == "Hello", "Notch chat also works without connection tests")
        setupKey.denied = true
        try expect(!setupStore.saveCredential("synthetic_replacement_123456") && setupStore.state == .failed, "Keychain save failure shown")
        try expect(GeminiModelStore.safeMessage(NSError(domain: "sensitive credential text", code: 1)) == "Gemini could not complete the request. Try again.", "Unknown diagnostics never expose raw error details")
        let disconnectKey = MemoryCredential()
        let disconnectTransport = MockTransport([.init(list), .init(envelope()), .init(envelope(report)), .init(envelope(), delay: 5)])
        let disconnectStore = GeminiModelStore(credentials: disconnectKey, client: client(disconnectTransport, key: disconnectKey), defaults: preferences)
        disconnectStore.intelligenceModelID = modelID
        disconnectStore.testConnection(); await wait(disconnectStore)
        let inProgress = Task { try await disconnectStore.generateIntelligence(prompt: "Synthetic disconnection") }
        try await Task.sleep(for: .milliseconds(30))
        disconnectStore.disconnect()
        try await rejects("Disconnect during chat is recoverable", { _ = try await inProgress.value }, matching: { ($0 as? GeminiError) == .notReady })
        print("PASS: \(checks) Gemini Phase 1 checks. All network calls mocked; isolated Keychain roundtrip passed. No live credential used.")
    }
    @MainActor static func wait(_ store: GeminiModelStore) async {
        for _ in 0..<500 {
            if !store.busy { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}
