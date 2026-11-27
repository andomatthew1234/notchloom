import Foundation

protocol AIProvider {
    func generate(prompt: String, shortcutName: String) async throws -> String
}

enum AIProviderError: LocalizedError {
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .notConfigured: "Choose a Shortcut in Intelligence settings first."
        }
    }
}

/// Uses the app's signed XPC helper to invoke the public macOS Shortcuts CLI.
/// The main app is sandboxed, so running the CLI directly from it can silently
/// produce no output even when the same Shortcut works in Terminal.
struct AppleIntelligenceProvider: AIProvider {
    func generate(prompt: String, shortcutName: String) async throws -> String {
        let name = shortcutName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw AIProviderError.notConfigured }
        return try await XPCHelperClient.shared.runIntelligenceShortcut(name: name, prompt: prompt)
    }
}

struct GeminiIntelligenceProvider: AIProvider {
    func generate(prompt: String, shortcutName: String) async throws -> String {
        try await GeminiModelStore.shared.generateIntelligence(prompt: prompt)
    }
}
