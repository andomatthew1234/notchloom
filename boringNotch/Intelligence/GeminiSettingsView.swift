import AppKit
import SwiftUI

@MainActor
struct GeminiSettingsView: View {
    @ObservedObject var store: GeminiModelStore
    @State private var key = ""
    @State private var search = ""
    @State private var confirmDisconnect = false
    init(store: GeminiModelStore? = nil) { self.store = store ?? .shared }
    #if DEBUG
    @State private var testPrompt = TodayReportSchema.syntheticPrompt
    @State private var structuredTest = true
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                // Original native symbol treatment; no third-party trademark artwork is bundled.
                Image(systemName: "sparkle")
                    .font(.system(size: 25, weight: .medium))
                    .foregroundStyle(LinearGradient(colors: [.cyan, .blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 43, height: 43)
                    .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Gemini API").font(.system(size: 16, weight: .semibold))
                    Text("Connect directly to Google with your own API key.").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 5)
                Label(store.statusLabel, systemImage: store.state == .connected ? "checkmark.circle.fill" : "circle.dotted")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(store.state == .connected ? Color.cyan : Color.secondary)
            }
            Divider()
            VStack(alignment: .leading, spacing: 9) {
                Text(store.hasCredential ? "Replace API key" : "API key").font(.system(size: 12, weight: .semibold))
                HStack {
                    SecureField(store.hasCredential ? "A key is securely saved · enter a replacement" : "Enter your Gemini API key", text: $key)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Gemini API key")
                    Button("Save key") { if store.saveCredential(key) { key = "" } }
                        .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.busy)
                }
                HStack {
                    Text("Saved only in this Mac's Keychain.").foregroundStyle(.secondary)
                    Spacer()
                    Link("Get an API key ↗", destination: URL(string: "https://ai.google.dev/gemini-api/docs/api-key")!)
                }.font(.system(size: 11))
            }
            HStack {
                Text("Available models").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("Refresh models") { store.refreshModels() }.disabled(!store.hasCredential || store.busy)
            }
            if !store.models.isEmpty {
                TextField("Search model name or identifier", text: $search).textFieldStyle(.roundedBorder)
                Picker("Notch chat", selection: $store.intelligenceModelID) {
                    Text("Choose a model…").tag("")
                    if !store.intelligenceModelID.isEmpty && !store.available(store.intelligenceModelID) {
                        Text("Unavailable: " + store.intelligenceModelID).tag(store.intelligenceModelID)
                    }
                    ForEach(filteredModels) { model in Text(model.title).tag(model.id) }
                }
                .disabled(store.busy)
                if let model = store.models.first(where: { $0.id == store.intelligenceModelID }) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(model.id).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                        if let description = model.description { Text(description).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                        Text("Context: \(model.inputTokenLimit.map { String($0) } ?? "not supplied") input · \(model.outputTokenLimit.map { String($0) } ?? "not supplied") output tokens")
                        Text("Operations: \((model.supportedGenerationMethods ?? []).joined(separator: ", "))")
                        Text("Last optional Today test: \((store.structured[model.id] ?? .untested).rawValue)")
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                }
            } else {
                Text("Save a key and refresh to discover the models Google makes available to it. No model is chosen automatically.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if !store.intelligenceModelID.isEmpty { Text("Saved choice: \(store.intelligenceModelID)").font(.system(size: 11)).foregroundStyle(.secondary) }
            }
            HStack {
                Button(store.busy ? "Connecting…" : "Test connection (optional)") { store.testConnection() }
                    .disabled(store.busy || !store.hasCredential || !store.available(store.intelligenceModelID))
                if store.busy { ProgressView().controlSize(.small); Button("Cancel") { store.cancel() } }
                Spacer()
                if store.hasCredential { Button("Disconnect…", role: .destructive) { confirmDisconnect = true }.disabled(store.busy) }
            }
            Text("Testing sends two small synthetic requests: one text response and one validated Today report. Google API usage may incur charges.")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let message = store.message {
                Text(message).font(.system(size: 12)).foregroundStyle(store.state == .failed || store.state == .rateLimited ? Color.orange : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Label("Model for Today", systemImage: "sun.max").font(.system(size: 13, weight: .semibold))
                Text("Independent of notch chat. Today uses your selected Gemini model. Connection tests are optional; every briefing is validated when generated. Configuring a model sends no personal data.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Picker("Today", selection: $store.todayModelID) {
                    Text("Choose a model…").tag("")
                    if !store.todayModelID.isEmpty && !store.available(store.todayModelID) {
                        Text("Unavailable: " + store.todayModelID).tag(store.todayModelID)
                    }
                    ForEach(store.models) { model in
                        Text(model.title + (store.structured[model.id] == .verified ? " · verified" : "")).tag(model.id)
                    }
                }
                .disabled(store.busy || store.models.isEmpty)
                HStack {
                    Label(store.isTodayReady ? "Configured for Today" : "Save a key and choose a Today model", systemImage: store.isTodayReady ? "checkmark.circle" : "info.circle")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    Button("Test Today model (optional)") { store.testConnection(modelID: store.todayModelID) }
                        .disabled(store.busy || !store.hasCredential || !store.available(store.todayModelID))
                }
            }
            if let response = store.latestResponse {
                Divider()
                Text("Last request").font(.system(size: 12, weight: .semibold))
                Text(response.diagnostics).font(.system(size: 10)).foregroundStyle(.secondary).textSelection(.enabled)
                Text("Token counts describe this request, not your bill or remaining quota. Thinking tokens may be included in the total.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            #if DEBUG
            DisclosureGroup("Developer playground · synthetic prompts only") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Uses the Notch chat model selected above. Nothing is sent until Run is pressed.").font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $testPrompt).font(.system(size: 12)).frame(height: 90)
                    Toggle("Validate a version 1 Today report", isOn: $structuredTest)
                    HStack {
                        Button("Run") { store.runPlayground(prompt: testPrompt, model: store.intelligenceModelID, useStructured: structuredTest) }
                            .disabled(store.busy || !store.available(store.intelligenceModelID))
                        Button("Copy sanitized diagnostics") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(store.latestResponse?.diagnostics ?? "No completed Gemini request.", forType: .string)
                        }
                    }
                    if !store.debugOutput.isEmpty {
                        Text(store.debugOutput).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                    }
                }.padding(.top, 10)
            }
            #endif
        }
        .padding(16)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 15))
        .onAppear { store.readCredentialStatus() }
        .onDisappear { key = "" }
        .confirmationDialog("Disconnect Gemini?", isPresented: $confirmDisconnect, titleVisibility: .visible) {
            Button("Remove API key", role: .destructive) { key = ""; store.disconnect() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This removes the API key from this Mac's Keychain. Your model choices remain saved. Today will be unavailable until you reconnect.") }
    }

    private var filteredModels: [GeminiModel] {
        store.models.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.id.localizedCaseInsensitiveContains(search) || $0.id == store.intelligenceModelID }
    }
}
