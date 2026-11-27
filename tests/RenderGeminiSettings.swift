import AppKit
import SwiftUI

private struct NoCredential: GeminiCredentialStoring {
    func load() throws -> String? { nil }
    func save(_ key: String) throws {}
    func delete() throws {}
}

private struct SyntheticModelTransport: GeminiTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let payload = #"{"models":[{"name":"models/synthetic-model","displayName":"Synthetic model · UI fixture","description":"A synthetic description for layout review. This is not a discovered Google model and no network request was made.","inputTokenLimit":32000,"outputTokenLimit":4096,"supportedGenerationMethods":["generateContent"]}]}"#
        return (Data(payload.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
private struct FixtureCredential: GeminiCredentialStoring {
    func load() throws -> String? { "synthetic-ui-fixture-only" }
    func save(_ key: String) throws {}
    func delete() throws {}
}

@main struct RenderGeminiSettings {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        let folder = URL(fileURLWithPath: "/tmp/notchloom-gemini-review", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let suite = "Notchloom.RenderTests." + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let empty = GeminiModelStore(credentials: NoCredential(), defaults: preferences)
        try await render(empty, name: "not-configured", folder: folder)
        let fixture = FixtureCredential()
        let configured = GeminiModelStore(credentials: fixture, client: GeminiClient(credentials: fixture, transport: SyntheticModelTransport()), defaults: preferences)
        configured.intelligenceModelID = "models/synthetic-model"
        configured.refreshModels()
        for _ in 0..<100 where configured.busy { try await Task.sleep(for: .milliseconds(10)) }
        try await render(configured, name: "model-selected", folder: folder)
        print("PASS native Gemini Settings rendered at 610pt and 2x scale with empty and synthetic-model states. No real key or network used.")
    }
    @MainActor private static func render(_ store: GeminiModelStore, name: String, folder: URL) async throws {
        let host = NSHostingView(rootView: GeminiSettingsView(store: store).frame(width: 610).fixedSize(horizontal: false, vertical: true).padding(24).background(Color(white: 0.12)).preferredColorScheme(.dark))
        let window = NSWindow(contentRect: CGRect(x: -3000, y: -3000, width: 658, height: 1200), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        host.setFrameSize(host.fittingSize)
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { fatalError("No settings image") }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("No PNG") }
        try png.write(to: folder.appendingPathComponent(name + ".png"))
        window.close()
    }
}
