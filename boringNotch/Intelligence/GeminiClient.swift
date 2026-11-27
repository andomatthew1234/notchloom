import Foundation
import CryptoKit

enum GeminiError: LocalizedError, Equatable {
    case missingKey, credentials, unavailableModel, invalidRequest, schemaTooComplex, unsupportedStructuredOutput, network, timeout
    case rateLimited(Double?), server(Int), malformed, empty, blocked, incomplete, tooLarge, notReady
    var errorDescription: String? {
        switch self {
        case .missingKey: return "Add your Gemini API key in Intelligence → Models."
        case .credentials: return "Google rejected this API key or its permissions. Replace the key or check its API access."
        case .unavailableModel: return "This model is unavailable. Refresh models and explicitly select a replacement."
        case .invalidRequest: return "Google rejected this request. Try again, or review the selected model in Intelligence → Models."
        case .schemaTooComplex: return "Google rejected Notchloom’s report format as too complex. No briefing was generated."
        case .unsupportedStructuredOutput: return "This model does not support the structured reports Today needs. Choose another Today model in Intelligence → Models."
        case .network: return "Could not reach Gemini. Check your internet connection and try again."
        case .timeout: return "Gemini took too long to respond. Try again."
        case .rateLimited(let seconds):
            if let seconds, seconds.isFinite, seconds <= 86_400 {
                return "Google rate limited this request. Try again in about \(Int(ceil(max(0, seconds)))) seconds."
            }
            return "Google rate limited this request. Check your quota and try again later."
        case .server(let code): return "Gemini is temporarily unavailable (HTTP \(code)). Try again later."
        case .malformed: return "Gemini returned an unreadable response."
        case .empty: return "Gemini returned no text. Try another prompt or model."
        case .blocked: return "Gemini declined this request under its content or safety rules."
        case .incomplete: return "Gemini stopped before completing the response. Shorten the request and try again."
        case .tooLarge: return "The request or response exceeded Notchloom's size limit."
        case .notReady: return "Save your Gemini API key and choose a model in Intelligence → Models."
        }
    }
}

struct GeminiModel: Codable, Identifiable, Sendable, Equatable {
    let name: String
    let displayName: String?
    let description: String?
    let inputTokenLimit: Int?
    let outputTokenLimit: Int?
    let supportedGenerationMethods: [String]?
    var id: String { name }
    var title: String { displayName ?? name }
    var supportsGeneration: Bool { supportedGenerationMethods?.contains("generateContent") == true }
}

struct GeminiUsage: Codable, Sendable, Equatable {
    let promptTokenCount: Int?
    let candidatesTokenCount: Int?
    let totalTokenCount: Int?
    let thoughtsTokenCount: Int?
    let cachedContentTokenCount: Int?
}

struct GeminiResponse: Sendable {
    let text: String
    let model: String
    let elapsed: TimeInterval
    let usage: GeminiUsage?
    /// Deliberately excludes keys, prompts, account identifiers and provider response bodies.
    var diagnostics: String {
        "Gemini · \(model) · \(String(format: "%.2f", elapsed))s · input \(usage?.promptTokenCount.map(String.init) ?? "unknown") · output \(usage?.candidatesTokenCount.map(String.init) ?? "unknown") · total \(usage?.totalTokenCount.map(String.init) ?? "unknown")"
    }
}

protocol GeminiTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// Reject redirects rather than forwarding an API credential to another origin.
private final class GeminiRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

struct GeminiURLTransport: GeminiTransport {
    private let session: URLSession
    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForResource = 90
        session = URLSession(configuration: configuration, delegate: GeminiRedirectPolicy(), delegateQueue: nil)
    }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (bytes, response) = try await session.bytes(for: request)
        defer { bytes.task.cancel() }
        guard let response = response as? HTTPURLResponse else { throw GeminiError.malformed }
        let limit = 2_000_000
        guard response.expectedContentLength <= limit else { throw GeminiError.tooLarge }
        var data = Data()
        for try await byte in bytes {
            if data.count % 4096 == 0 { try Task.checkCancellation() }
            guard data.count < limit else { throw GeminiError.tooLarge }
            data.append(byte)
        }
        return (data, response)
    }
}

actor GeminiClient {
    private let credentials: any GeminiCredentialStoring
    private let transport: any GeminiTransport
    private let sleep: @Sendable (Double) async throws -> Void
    private let timeout: TimeInterval
    private let retries: Int
    private struct Flight { let id: UUID; let task: Task<GeminiResponse, Error> }
    private var flights: [String: Flight] = [:]

    init(credentials: any GeminiCredentialStoring = GeminiKeychainStore(),
         transport: any GeminiTransport = GeminiURLTransport(), timeout: TimeInterval = 45, retries: Int = 2,
         sleep: @escaping @Sendable (Double) async throws -> Void = { seconds in
             try await Task.sleep(for: .seconds(seconds))
         }) {
        self.credentials = credentials; self.transport = transport
        self.timeout = max(1, min(timeout, 120)); self.retries = max(0, min(retries, 3)); self.sleep = sleep
    }

    func cancelAll() {
        flights.values.forEach { $0.task.cancel() }
        flights.removeAll()
    }

    func models() async throws -> [GeminiModel] {
        let key = try credential()
        struct Page: Decodable { let models: [GeminiModel]?; let nextPageToken: String? }
        var result: [GeminiModel] = []
        var token: String?
        var seen = Set<String>()
        for _ in 0..<20 {
            var items = [URLQueryItem(name: "pageSize", value: "100")]
            if let token { items.append(URLQueryItem(name: "pageToken", value: token)) }
            let data = try await request(path: "models", query: items, key: key)
            guard let page = try? JSONDecoder().decode(Page.self, from: data) else { throw GeminiError.malformed }
            result += (page.models ?? []).filter { $0.supportsGeneration && Self.validModelID($0.id) }
            guard let next = page.nextPageToken, !next.isEmpty else {
                var ids = Set<String>()
                return result.filter { ids.insert($0.id).inserted }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            }
            guard next.count < 4096, seen.insert(next).inserted else { throw GeminiError.malformed }
            token = next
        }
        throw GeminiError.tooLarge
    }

    static func validModelID(_ value: String) -> Bool {
        value.range(of: "^models/[A-Za-z0-9._-]{1,160}$", options: .regularExpression) != nil
    }

    func generate(prompt: String, model: String, schema: Data? = nil, systemInstruction: String? = nil,
                  maxOutputTokens: Int = 4096, allowRetries: Bool = true) async throws -> GeminiResponse {
        try Task.checkCancellation()
        guard Self.validModelID(model) else { throw GeminiError.unavailableModel }
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw GeminiError.invalidRequest }
        guard prompt.utf8.count <= 128_000 else { throw GeminiError.tooLarge }
        guard systemInstruction?.utf8.count ?? 0 <= 16_000, (128...8192).contains(maxOutputTokens) else { throw GeminiError.tooLarge }
        let key = try credential()
        // Hashes remain in memory only and are removed immediately on completion.
        var hasher = SHA256()
        for component in [Data(key.utf8), Data(model.utf8), Data(prompt.utf8), schema ?? Data(), Data((systemInstruction ?? "").utf8), Data("\(maxOutputTokens):\(allowRetries)".utf8)] {
            hasher.update(data: Data("\(component.count):".utf8))
            hasher.update(data: component)
        }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        let flight: Flight
        if let existing = flights[digest] { flight = existing }
        else {
            let id = UUID()
            let task = Task { try await self.performGeneration(prompt: prompt, model: model, schema: schema, key: key,
                                                              systemInstruction: systemInstruction, maxOutputTokens: maxOutputTokens, allowRetries: allowRetries) }
            flight = Flight(id: id, task: task)
            flights[digest] = flight
        }
        defer { if flights[digest]?.id == flight.id { flights[digest] = nil } }
        // Identical concurrent callers share one request; canceling either cancels that shared request.
        return try await withTaskCancellationHandler {
            let result = try await flight.task.value
            try Task.checkCancellation()
            return result
        } onCancel: { flight.task.cancel() }
    }

    private func performGeneration(prompt: String, model: String, schema: Data?, key: String,
                                   systemInstruction: String?, maxOutputTokens: Int, allowRetries: Bool) async throws -> GeminiResponse {
        let start = ContinuousClock.now
        var config: [String: Any] = ["maxOutputTokens": maxOutputTokens]
        if let schema {
            guard schema.count <= 64_000, let object = try? JSONSerialization.jsonObject(with: schema) as? [String: Any] else {
                throw GeminiError.invalidRequest
            }
            config["responseMimeType"] = "application/json"
            config["responseJsonSchema"] = object
        }
        var payload: [String: Any] = [
            "contents": [["role": "user", "parts": [["text": prompt]]]], "generationConfig": config
        ]
        if let systemInstruction { payload["systemInstruction"] = ["parts": [["text": systemInstruction]]] }
        let body = try JSONSerialization.data(withJSONObject: payload)
        let data = try await request(path: model + ":generateContent", key: key, body: body, retryLimit: allowRetries ? nil : 0)
        struct Envelope: Decodable {
            struct Feedback: Decodable { let blockReason: String? }
            struct Candidate: Decodable {
                struct Content: Decodable {
                    struct Part: Decodable { let text: String?; let thought: Bool? }
                    let parts: [Part]?
                }
                let content: Content?; let finishReason: String?
            }
            let candidates: [Candidate]?; let promptFeedback: Feedback?; let usageMetadata: GeminiUsage?
        }
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else { throw GeminiError.malformed }
        if let reason = envelope.promptFeedback?.blockReason, reason != "BLOCK_REASON_UNSPECIFIED" { throw GeminiError.blocked }
        guard let candidate = envelope.candidates?.first else { throw GeminiError.empty }
        if let reason = candidate.finishReason, reason != "STOP" {
            if reason == "MAX_TOKENS" { throw GeminiError.incomplete }
            throw GeminiError.blocked
        }
        let text = (candidate.content?.parts ?? []).filter { $0.thought != true }.compactMap(\.text).joined()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw GeminiError.empty }
        let elapsed = start.duration(to: .now).components
        return GeminiResponse(text: text, model: model,
                              elapsed: Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18, usage: envelope.usageMetadata)
    }

    private func credential() throws -> String {
        guard let key = try credentials.load(), !key.isEmpty else { throw GeminiError.missingKey }
        return try GeminiCredentialValue.normalized(key)
    }

    private func request(path: String, query: [URLQueryItem] = [], key: String, body: Data? = nil, retryLimit: Int? = nil) async throws -> Data {
        var components = URLComponents(string: "https://generativelanguage.googleapis.com/v1beta/" + path)!
        components.queryItems = query.isEmpty ? nil : query
        var request = URLRequest(url: components.url!, timeoutInterval: timeout)
        request.httpMethod = body == nil ? "GET" : "POST"
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let attempts = retryLimit ?? retries
        for attempt in 0...attempts {
            try Task.checkCancellation()
            do {
                let (data, response) = try await transport.send(request)
                try Task.checkCancellation()
                guard data.count <= 2_000_000 else { throw GeminiError.tooLarge }
                let status = response.statusCode
                if (200..<300).contains(status) { return data }
                // Provider error bodies are intentionally never surfaced, logged or copied.
                if status == 401 || status == 403 { throw GeminiError.credentials }
                if status == 400,
                   let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let error = object["error"] as? [String: Any],
                   let details = error["details"] as? [[String: Any]],
                   details.contains(where: { $0["reason"] as? String == "API_KEY_INVALID" }) {
                    throw GeminiError.credentials
                }
                if status == 400 { throw Self.requestRejection(data) }
                if status == 404 { throw GeminiError.unavailableModel }
                if status == 429 || status == 408 || (500...599).contains(status) {
                    let retry = Self.retryDelay(response.value(forHTTPHeaderField: "Retry-After"))
                    guard attempt < attempts, (retry ?? 0) <= 60 else {
                        if status == 429 { throw GeminiError.rateLimited(retry) }
                        if status == 408 { throw GeminiError.timeout }
                        throw GeminiError.server(status)
                    }
                    try await sleep(max(retry ?? 0, 0.5 * pow(2, Double(attempt))))
                    continue
                }
                throw GeminiError.invalidRequest
            } catch is CancellationError { throw CancellationError() }
            catch let error as URLError {
                if Task.isCancelled || error.code == .cancelled { throw CancellationError() }
                if attempt < attempts && [.timedOut, .networkConnectionLost, .cannotConnectToHost].contains(error.code) {
                    try await sleep(0.5 * pow(2, Double(attempt)))
                    continue
                }
                throw error.code == .timedOut ? GeminiError.timeout : GeminiError.network
            } catch let error as GeminiError { throw error }
            catch let error as GeminiCredentialError { throw error }
            catch { throw GeminiError.network }
        }
        throw GeminiError.network
    }

    static func retryDelay(_ value: String?, now: Date = Date()) -> Double? {
        guard let value else { return nil }
        if let seconds = Double(value), seconds.isFinite { return max(0, seconds) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        return formatter.date(from: value).map { max(0, $0.timeIntervalSince(now)) }
    }
    /// Classify provider explanations into fixed local messages; never expose or log raw bodies.
    static func requestRejection(_ data: Data) -> GeminiError {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = object["error"] as? [String: Any], let raw = error["message"] as? String else { return .invalidRequest }
        let message = raw.lowercased()
        if (message.contains("schema") || message.contains("constraint")),
           message.contains("complex") || message.contains("too many states") || message.contains("too many state") { return .schemaTooComplex }
        if (message.contains("json") || message.contains("response_schema") || message.contains("response schema") || message.contains("structured")),
           message.contains("not supported") || message.contains("unsupported") { return .unsupportedStructuredOutput }
        return .invalidRequest
    }
}
