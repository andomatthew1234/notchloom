import AppKit
import KeyboardShortcuts
import SwiftUI

private enum IntelligencePalette {
    static let cyan = Color(red: 0.20, green: 0.87, blue: 0.94)
    static let blue = Color(red: 0.26, green: 0.55, blue: 0.97)
    static let purple = Color(red: 0.66, green: 0.47, blue: 0.94)
    static let pink = Color(red: 0.94, green: 0.48, blue: 0.72)
}

struct IntelligencePanelView: View {
    @EnvironmentObject private var vm: BoringViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var intelligence = IntelligenceCoordinator.shared
    @State private var promptHeight: CGFloat = 38
    @State private var focusEditor = false
    @State private var visibleParagraphs = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Color.clear.frame(height: 27)
            if intelligence.state != .dismissing && intelligence.state != .detaching {
                header
                    .transition(.opacity.combined(with: .offset(y: -5)))
                Group {
                    switch intelligence.state {
                    case .entering, .composing:
                        promptCard
                    case .submitting, .generating:
                        generatingCard
                    case .completed:
                        responseCard
                    case .failed:
                        errorCard
                    default:
                        EmptyView()
                    }
                }
                .transition(.opacity.combined(with: .offset(y: 6)))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            focusEditor = true
            if intelligence.state == .completed { revealResponse() }
        }
        .onChange(of: intelligence.state) { _, newState in
            if newState == .entering || newState == .composing {
                focusEditor = true
            }
            if newState == .completed {
                visibleParagraphs = 0
                revealResponse()
            }
        }
        .onExitCommand { intelligence.dismiss() }
    }

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: "sparkle")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(IntelligencePalette.cyan)
                .accessibilityHidden(true)
            Text("Ask Intelligence")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.91))
            Spacer(minLength: 10)
            Text(intelligence.providerDisplayName)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.54))
                .lineLimit(1)
            Button { intelligence.dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 24, height: 24)
                    .background(.white.opacity(0.09), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close Intelligence")
        }
    }

    private var promptCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            ZStack(alignment: .topLeading) {
                if intelligence.session.prompt.isEmpty {
                    Text("Ask anything...")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.43))
                        .padding(.leading, 5)
                        .padding(.top, 8)
                        .allowsHitTesting(false)
                }
                IntelligencePromptEditor(
                    text: $intelligence.session.prompt,
                    shouldFocus: focusEditor,
                    onSubmit: { intelligence.submit() },
                    onHeightChange: { height in
                        promptHeight = height
                        intelligence.updatePromptHeight(height)
                    }
                )
                .frame(height: min(112, max(34, promptHeight)))
            }
            HStack {
                Text("Return to ask  ·  Shift–Return for a new line")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.42))
                Spacer(minLength: 5)
                Button { intelligence.submit() } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 28, height: 28)
                        .background(IntelligencePalette.cyan, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(intelligence.session.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(intelligence.session.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.42 : 1)
                .accessibilityLabel("Submit prompt")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color(white: 0.085), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.07), lineWidth: 1))
    }

    private var generatingCard: some View {
        HStack(spacing: 11) {
            Image(systemName: "sparkles")
                .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion && intelligence.state == .generating)
                .foregroundStyle(IntelligencePalette.cyan)
            VStack(alignment: .leading, spacing: 3) {
                Text("Thinking")
                    .font(.system(size: 13, weight: .semibold))
                Text(intelligence.session.prompt)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.49))
                    .lineLimit(1)
            }
            Spacer()
            Button("Cancel") { intelligence.cancelRequest() }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
            Button("Hide") { intelligence.dismiss() }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.65))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 13)
        .background(Color(white: 0.075), in: RoundedRectangle(cornerRadius: 14))
    }

    private var responseCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(IntelligencePalette.cyan)
                    .accessibilityHidden(true)
                Text("Response")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Button("Copy") { intelligence.copyResponse() }
                Button("Expand") { intelligence.detachResponse() }
                    .accessibilityLabel("Open response in a window")
                Button("New chat") { intelligence.returnToInput() }
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white.opacity(0.75))
            Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(paragraphs.enumerated()), id: \.offset) { index, paragraph in
                        markdownText(paragraph)
                            .opacity(reduceMotion || index < visibleParagraphs ? 1 : 0)
                            .offset(y: reduceMotion || index < visibleParagraphs ? 0 : -6)
                            .animation(reduceMotion ? nil : .easeOut(duration: 0.26).delay(Double(index) * 0.055),
                                       value: visibleParagraphs)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: intelligence.responseContentHeight)
            .accessibilityLabel("Intelligence response")
            HStack(spacing: 8) {
                ZStack(alignment: .leading) {
                    if intelligence.session.followUp.isEmpty {
                        Text("Ask a follow-up…")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 7)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                    IntelligencePromptEditor(text: $intelligence.session.followUp,
                                             shouldFocus: true,
                                             onSubmit: { intelligence.submit() },
                                             onHeightChange: { _ in })
                        .frame(height: 34)
                        .accessibilityLabel("Ask a follow-up")
                }
                Button { intelligence.submit() } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 22))
                }
                .buttonStyle(.plain)
                .foregroundStyle(IntelligencePalette.cyan)
                .disabled(intelligence.session.followUp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Send follow-up")
            }
            .padding(.horizontal, 7)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        }
        .padding(12)
        .background(Color(white: 0.075), in: RoundedRectangle(cornerRadius: 15))
    }

    private var paragraphs: [String] {
        let value = intelligence.session.response ?? ""
        return value.components(separatedBy: "\n\n").filter { !$0.isEmpty }
    }

    private func revealResponse() {
        visibleParagraphs = paragraphs.count
    }

    private var errorCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                Text("Couldn't get a response").font(.system(size: 12, weight: .semibold))
                Spacer()
                Button("Retry") { intelligence.retry() }
                    .buttonStyle(.plain)
            }
            Text(intelligence.errorMessage ?? "The Shortcut failed.")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.67))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .padding(12)
        .background(Color(white: 0.075), in: RoundedRectangle(cornerRadius: 15))
    }
}

private func markdownText(_ source: String) -> some View {
    let attributed = (try? AttributedString(markdown: source)) ?? AttributedString(source)
    return Text(attributed)
        .font(.system(size: 12))
        .lineSpacing(3)
        .foregroundStyle(.white.opacity(0.9))
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
}

private struct IntelligencePromptEditor: NSViewRepresentable {
    @Binding var text: String
    let shouldFocus: Bool
    let onSubmit: () -> Void
    let onHeightChange: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.verticalScrollElasticity = .allowed
        let editor = PromptTextView()
        editor.delegate = context.coordinator
        editor.isRichText = false
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.font = .systemFont(ofSize: 14)
        editor.textColor = .white
        editor.insertionPointColor = NSColor(red: 0.2, green: 0.87, blue: 0.94, alpha: 1)
        editor.backgroundColor = .clear
        editor.drawsBackground = false
        editor.textContainerInset = NSSize(width: 2, height: 5)
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        editor.frame = NSRect(x: 0, y: 0, width: 420, height: 34)
        editor.autoresizingMask = [.width]
        editor.onSubmit = { context.coordinator.parent.onSubmit() }
        scroll.documentView = editor
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? PromptTextView else { return }
        if editor.string != text { editor.string = text }
        if shouldFocus, !context.coordinator.didFocus {
            context.coordinator.didFocus = true
            DispatchQueue.main.async {
                if scroll.window != nil {
                    (scroll.window as? BoringNotchSkyLightWindow)?.allowsIntelligenceKeyboardFocus = true
                    scroll.window?.makeKeyAndOrderFront(nil)
                    NSApp.activate(ignoringOtherApps: true)
                    scroll.window?.makeFirstResponder(editor)
                }
            }
        }
        context.coordinator.updateHeight(editor)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: IntelligencePromptEditor
        var didFocus = false
        init(_ parent: IntelligencePromptEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            parent.text = editor.string
            updateHeight(editor)
        }

        func updateHeight(_ editor: NSTextView) {
            guard let container = editor.textContainer,
                  let layout = editor.layoutManager else { return }
            layout.ensureLayout(for: container)
            let height = min(112, max(34, layout.usedRect(for: container).height + 12))
            DispatchQueue.main.async { [weak self] in
                self?.parent.onHeightChange(height)
            }
        }
    }

    final class PromptTextView: NSTextView {
        var onSubmit: (() -> Void)?
        override func keyDown(with event: NSEvent) {
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            if (event.keyCode == 36 || event.keyCode == 76), modifiers.isEmpty {
                onSubmit?()
                return
            }
            super.keyDown(with: event)
        }
    }
}

struct IntelligenceDetachedResponseView: View {
    let response: String
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Image(systemName: "sparkle").foregroundStyle(IntelligencePalette.cyan)
                Text("Intelligence Response")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(response, forType: .string)
                }
                .buttonStyle(.bordered)
                Button("Close") { IntelligenceCoordinator.shared.closeDetachedResponse() }
                    .buttonStyle(.bordered)
            }
            ScrollView {
                markdownText(response)
                    .font(.system(size: 14))
                    .padding(.vertical, 5)
            }
        }
        .padding(25)
        .frame(minWidth: 400, minHeight: 270)
        .background(Color.black)
        .preferredColorScheme(.dark)
    }
}

/// Draws only during generation and traces the same NotchShape as the black surface.
struct IntelligencePerimeterGlow: View {
    let shape: NotchShape
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: reduceMotion)) { timeline in
            Canvas { context, size in
                let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                let path = shape.path(in: CGRect(origin: .zero, size: size).insetBy(dx: 2, dy: 2))
                let shift = sin(time * 0.47) * size.width * 0.13
                let tint = 0.5 + 0.5 * sin(time * 0.81)
                let colors: [Color] = [
                    IntelligencePalette.cyan,
                    IntelligencePalette.blue.opacity(0.75 + tint * 0.2),
                    IntelligencePalette.purple,
                    IntelligencePalette.pink.opacity(0.72 + tint * 0.18),
                    Color(red: 1, green: 0.70, blue: 0.51),
                    IntelligencePalette.cyan
                ]
                let shade = GraphicsContext.Shading.linearGradient(
                    Gradient(colors: colors),
                    startPoint: CGPoint(x: shift, y: 0),
                    endPoint: CGPoint(x: size.width + shift, y: size.height)
                )
                var glow = context
                glow.addFilter(.blur(radius: 8))
                glow.stroke(path, with: shade, lineWidth: 10)
                context.stroke(path, with: shade, lineWidth: 2)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct IntelligenceSettingsView: View {
    var body: some View { IntelligenceModelsView() }
}

struct IntelligenceModelsView: View {
    @ObservedObject private var intelligence = IntelligenceCoordinator.shared
    @ObservedObject private var gemini = GeminiModelStore.shared
    @State private var shortcutConflict: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Provider for notch chat")
                        .font(.system(size: 15, weight: .semibold))
                    Button { intelligence.select(.apple) } label: {
                        providerCard("Apple Intelligence", description: "Use a Shortcut with Apple's Use Model action.", symbol: "apple.logo", status: intelligence.isReady ? "Ready" : "Setup needed", enabled: intelligence.selectedProvider == .apple)
                    }.buttonStyle(.plain)
                    Button { intelligence.select(.gemini) } label: {
                        providerCard("Gemini API", description: "Direct Google API connection · configured below", symbol: "sparkle", status: gemini.statusLabel, enabled: intelligence.selectedProvider == .gemini)
                    }.buttonStyle(.plain)
                    providerCard("ChatGPT API", description: "Direct API connection", symbol: "bubble.left.and.bubble.right", status: "Coming Soon", enabled: false)
                }
                GeminiSettingsView()
                VStack(alignment: .leading, spacing: 12) {
                    Text("Connect Apple Intelligence")
                        .font(.system(size: 15, weight: .semibold))
                    Text("In Shortcuts, create a shortcut with a Use Model action. Pass Shortcut Input as its prompt and make the model response the shortcut's final output. Enter its exact name below, then run a connection test. Your Mac must support and have Apple Intelligence enabled for the chosen model.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        TextField("Shortcut name", text: $intelligence.shortcutName)
                            .textFieldStyle(.roundedBorder)
                        Button("Open Shortcuts") {
                            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Shortcuts.app"))
                        }
                        Button(intelligence.testing ? "Testing…" : "Test connection") { intelligence.testConnection() }
                            .disabled(intelligence.testing)
                    }
                    if let message = intelligence.testMessage {
                        Text(message)
                            .font(.system(size: 11))
                            .foregroundStyle(intelligence.isReady ? IntelligencePalette.cyan : .orange)
                            .textSelection(.enabled)
                    }
                }
                .padding(16)
                .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 15))

                VStack(alignment: .leading, spacing: 10) {
                    Text("Open from anywhere")
                        .font(.system(size: 15, weight: .semibold))
                    HStack {
                        Text("Keyboard shortcut")
                        Spacer()
                        KeyboardShortcuts.Recorder(for: .openIntelligence) { shortcut in
                            let otherNames: [KeyboardShortcuts.Name] = [.toggleNotchOpen, .toggleSneakPeek, .toggleMicrophone, .clipboardHistoryPanel]
                            if let shortcut, otherNames.contains(where: { KeyboardShortcuts.getShortcut(for: $0) == shortcut }) {
                                shortcutConflict = "This shortcut is already used by another Notchloom action. Choose a different combination."
                                KeyboardShortcuts.reset(.openIntelligence)
                            } else {
                                shortcutConflict = nil
                            }
                        }
                    }
                    if let shortcutConflict {
                        Text(shortcutConflict).foregroundStyle(.orange).font(.system(size: 11))
                    }
                    HStack(spacing: 8) {
                        Image(systemName: intelligence.globalEscapeAvailable ? "checkmark.circle.fill" : "exclamationmark.circle")
                            .foregroundStyle(intelligence.globalEscapeAvailable ? IntelligencePalette.cyan : .orange)
                        Text(intelligence.globalEscapeAvailable ?
                             "Escape can close Intelligence when another app is focused." :
                             "Global Escape needs macOS Input Monitoring or Accessibility permission.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Spacer()
                        if !intelligence.globalEscapeAvailable {
                            Button("Enable") { intelligence.requestGlobalEscapePermission() }
                        }
                    }
                    Text("Default: Control–F5. On MacBook keyboards, you may need Control–Fn–F5 unless F1–F12 are set as standard function keys. macOS may reserve some combinations; choose another if recording reports a conflict.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 15))
            }
            .frame(maxWidth: 690, alignment: .leading)
            .padding(24)
        }
        .background(Color(red: 0.12, green: 0.12, blue: 0.13))
        .onAppear { intelligence.refreshGlobalEscapePermission() }
    }

    private func providerCard(_ title: String, description: String, symbol: String, status: String, enabled: Bool) -> some View {
        HStack(spacing: 13) {
            Image(systemName: symbol)
                .font(.system(size: 20))
                .frame(width: 37, height: 37)
                .foregroundStyle(enabled ? IntelligencePalette.cyan : .white.opacity(0.45))
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(description).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Text(status)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(enabled ? IntelligencePalette.cyan : .secondary)
            if enabled {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(IntelligencePalette.cyan)
            }
        }
        .padding(13)
        .background(enabled ? IntelligencePalette.cyan.opacity(0.09) : .white.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(enabled ? IntelligencePalette.cyan.opacity(0.24) : .clear, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}
