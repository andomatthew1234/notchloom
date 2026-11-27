import AppKit
import ApplicationServices
import Combine
import SwiftUI

enum IntelligenceProviderID: String, CaseIterable {
    case apple, chatGPT, gemini
}

struct IntelligenceSession {
    var prompt = ""
    var response: String?
    var followUp = ""
    private var history: [String] = []

    mutating func record(answer: String) {
        response = answer
        // Keep the most recent exchanges in memory for this conversation.
        history.append("User: " + String(prompt.prefix(3000)) + "\nAssistant: " + String(answer.prefix(6000)))
        if history.count > 6 { history.removeFirst() }
    }

    func modelInput(for question: String) -> String {
        guard !history.isEmpty else { return question }
        return "Continue the conversation below. Answer the latest user question using the previous replies.\n\n"
            + history.joined(separator: "\n\n") + "\n\nLatest user question: " + question
    }
}

@MainActor
final class IntelligenceCoordinator: ObservableObject {
    static let shared = IntelligenceCoordinator()

    enum State: Equatable {
        case idle, entering, composing, submitting, generating, completed, failed, dismissing
        case backgroundGenerating, backgroundCompleted, backgroundFailed, detaching
    }

    @Published private(set) var state: State = .idle
    @Published var session = IntelligenceSession()
    @Published private(set) var errorMessage: String?
    @Published private(set) var testing = false
    @Published private(set) var testMessage: String?
    @Published var shortcutName: String {
        didSet {
            UserDefaults.standard.set(shortcutName, forKey: Self.shortcutKey)
            testMessage = nil
            if shortcutName != oldValue { readyShortcutName = nil }
        }
    }
    @Published private(set) var selectedProvider: IntelligenceProviderID {
        didSet { UserDefaults.standard.set(selectedProvider.rawValue, forKey: Self.providerKey) }
    }
    @Published private(set) var readyShortcutName: String? {
        didSet { UserDefaults.standard.set(readyShortcutName, forKey: Self.readyKey) }
    }
    @Published private(set) var presentationScreenID: String?
    @Published private(set) var globalEscapeAvailable = false

    private static let shortcutKey = "intelligence.appleShortcutName"
    private static let providerKey = "intelligence.provider"
    private static let readyKey = "intelligence.testedShortcutName"
    private let provider: AIProvider = AppleIntelligenceProvider()
    private var generationTask: Task<Void, Never>?
    private var testTask: Task<Void, Never>?
    private weak var viewModel: BoringViewModel?
    private var localMonitor: Any?
    private var globalKeyMonitor: Any?
    private var escapeEventTap: CFMachPort?
    private var escapeTapSource: CFRunLoopSource?
    private var globalClickMonitor: Any?
    private var detachedWindow: NSWindow?
    private var detachedCloseObserver: Any?
    private var previousApplication: NSRunningApplication?
    private var presentationID = UUID()

    var isActive: Bool {
        switch state {
        case .idle, .backgroundGenerating, .backgroundCompleted, .backgroundFailed: false
        default: true
        }
    }
    var isBackgroundGenerating: Bool { state == .backgroundGenerating }
    var hasBackgroundResult: Bool { state == .backgroundCompleted || state == .backgroundFailed }
    var responseContentHeight: CGFloat {
        let text = (session.response ?? "") as NSString
        let height = text.boundingRect(
            with: CGSize(width: 420, height: 4_000),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: NSFont.systemFont(ofSize: 12)]
        ).height
        return min(132, max(30, ceil(height) + 12))
    }
    private var responsePanelHeight: CGFloat { max(234, 198 + responseContentHeight) }
    var isReady: Bool {
        let name = shortcutName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty && readyShortcutName == name
    }

    private init() {
        let defaults = UserDefaults.standard
        shortcutName = defaults.string(forKey: Self.shortcutKey) ?? ""
        selectedProvider = IntelligenceProviderID(rawValue: defaults.string(forKey: Self.providerKey) ?? "apple") ?? .apple
        readyShortcutName = defaults.string(forKey: Self.readyKey)
        refreshGlobalEscapePermission()
    }

    func refreshGlobalEscapePermission() {
        globalEscapeAvailable = AXIsProcessTrusted() || CGPreflightListenEventAccess()
    }

    func requestGlobalEscapePermission() {
        _ = CGRequestListenEventAccess()
        refreshGlobalEscapePermission()
    }

    func select(_ provider: IntelligenceProviderID) {
        guard provider != .chatGPT, provider != selectedProvider,
              generationTask == nil else { return }
        // A provider change starts a fresh conversation; no existing chat is silently forwarded.
        session = IntelligenceSession()
        errorMessage = nil
        if state == .completed || state == .failed { returnToInput() }
        if state == .backgroundCompleted || state == .backgroundFailed { state = .idle }
        selectedProvider = provider
    }

    var providerDisplayName: String { selectedProvider == .gemini ? "Gemini" : "Apple Intelligence" }

    func activate(on viewModel: BoringViewModel) {
        guard !isActive else { return }
        let priorState = state
        presentationID = UUID()
        if priorState == .idle {
            session = IntelligenceSession()
            errorMessage = nil
        }
        previousApplication = NSWorkspace.shared.frontmostApplication
        self.viewModel = viewModel
        presentationScreenID = viewModel.screenUUID
        SharingStateManager.shared.beginInteraction()
        installMonitors()
        let size: CGSize
        switch priorState {
        case .backgroundGenerating:
            state = .generating
            size = CGSize(width: 466, height: 174)
        case .backgroundCompleted:
            state = .completed
            size = CGSize(width: 510, height: responsePanelHeight)
        case .backgroundFailed:
            state = .failed
            size = CGSize(width: 482, height: 205)
        default:
            state = .entering
            size = CGSize(width: 480, height: 192)
        }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
            viewModel.showIntelligence(size: size)
        }
        if state == .entering {
            let id = presentationID
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(270))
                guard self?.presentationID == id else { return }
                self?.entranceCompleted()
            }
        }
    }

    func entranceCompleted() {
        guard state == .entering else { return }
        state = .composing
    }

    func updatePromptHeight(_ height: CGFloat) {
        guard state == .entering || state == .composing else { return }
        let target = min(278, max(192, 156 + height))
        guard abs((viewModel?.notchSize.height ?? 0) - target) > 2 else { return }
        withAnimation(.easeOut(duration: 0.18)) {
            viewModel?.showIntelligence(size: CGSize(width: 480, height: target))
        }
    }

    func submit() {
        let isFollowUp = state == .completed
        guard isFollowUp || state == .entering || state == .composing else { return }
        let draft = isFollowUp ? session.followUp : session.prompt
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        let modelInput = session.modelInput(for: prompt)
        session.followUp = ""
        session.prompt = prompt
        session.response = nil
        errorMessage = nil
        state = .submitting
        withAnimation(.spring(response: 0.31, dampingFraction: 0.9)) {
            viewModel?.showIntelligence(size: CGSize(width: 466, height: 174))
        }
        let name = shortcutName.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = presentationID
        let requestProvider: AIProvider = selectedProvider == .gemini ? GeminiIntelligenceProvider() : provider
        let usesApple = selectedProvider == .apple
        generationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await requestProvider.generate(prompt: modelInput, shortcutName: name)
                guard !Task.isCancelled else { return }
                self.session.record(answer: result)
                if usesApple { self.readyShortcutName = name }
                if self.state == .backgroundGenerating {
                    self.state = .backgroundCompleted
                } else if self.state == .dismissing {
                    // The contraction completes before deciding which collapsed indicator to show.
                } else if self.state == .submitting || self.state == .generating {
                    self.state = .completed
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.88)) {
                        self.viewModel?.showIntelligence(size: CGSize(width: 510, height: self.responsePanelHeight))
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self.errorMessage = error.localizedDescription
                if self.state == .backgroundGenerating {
                    self.state = .backgroundFailed
                } else if self.state == .dismissing {
                    // Preserve the error for the collapsed state.
                } else if self.state == .submitting || self.state == .generating {
                    self.state = .failed
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.88)) {
                        self.viewModel?.showIntelligence(size: CGSize(width: 482, height: 205))
                    }
                }
            }
            self.generationTask = nil
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(160))
            guard self?.presentationID == id, self?.state == .submitting else { return }
            self?.state = .generating
        }
    }

    func retry() {
        guard state == .failed else { return }
        state = .composing
        submit()
    }

    func cancelRequest() {
        guard state == .submitting || state == .generating || state == .backgroundGenerating else { return }
        generationTask?.cancel()
        generationTask = nil
        if state == .backgroundGenerating {
            state = .idle
        } else {
            state = .failed
            dismiss()
        }
    }

    func returnToInput() {
        guard state == .completed || state == .failed else { return }
        session = IntelligenceSession()
        errorMessage = nil
        state = .entering
        withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
            viewModel?.showIntelligence(size: CGSize(width: 480, height: 192))
        }
        let id = presentationID
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(270))
            guard self?.presentationID == id else { return }
            self?.entranceCompleted()
        }
    }

    func copyResponse() {
        guard let response = session.response else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(response, forType: .string)
    }

    func dismiss() {
        dismiss(outsideClick: false)
    }

    func dismiss(outsideClick: Bool) {
        guard isActive, state != .dismissing, state != .detaching else { return }
        let wasGenerating = state == .submitting || state == .generating
        state = .dismissing
        removeMonitors()
        viewModel?.hostWindow?.makeFirstResponder(nil)
        (viewModel?.hostWindow as? BoringNotchSkyLightWindow)?.allowsIntelligenceKeyboardFocus = false
        withAnimation(.spring(response: 0.32, dampingFraction: 0.95)) {
            viewModel?.restoreFromIntelligence(wasOpen: false)
        }
        if !outsideClick,
           NSWorkspace.shared.frontmostApplication?.processIdentifier == NSRunningApplication.current.processIdentifier {
            previousApplication?.activate(options: [])
        }
        let id = presentationID
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(330))
            guard self?.presentationID == id else { return }
            self?.finishDismissal(background: wasGenerating)
        }
    }

    private func finishDismissal(background: Bool) {
        guard state == .dismissing || state == .detaching else { return }
        removeMonitors()
        viewModel?.finishIntelligenceContraction()
        presentationScreenID = nil
        viewModel = nil
        previousApplication = nil
        state = background ? (session.response != nil ? .backgroundCompleted :
            errorMessage != nil ? .backgroundFailed : .backgroundGenerating) : .idle
        SharingStateManager.shared.endInteraction()
    }

    func detachResponse() {
        guard state == .completed, let response = session.response,
              let host = viewModel?.hostWindow,
              let screen = host.screen ?? NSScreen.main else { return }
        let start = CGRect(x: host.frame.midX - 250, y: host.frame.maxY - 240,
                           width: 500, height: 210)
        let visible = screen.visibleFrame
        let width = min(680, max(400, visible.width - 40))
        let height = min(420, max(270, min(visible.height - 60, 180 + responseContentHeight)))
        let target = CGRect(x: visible.midX - width / 2, y: visible.maxY - height - 40,
                            width: width, height: height)
        closeDetachedResponse()
        let detached = NSWindow(contentRect: start,
                                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                backing: .buffered, defer: false)
        detached.title = "Intelligence Response"
        detached.titlebarAppearsTransparent = true
        detached.isReleasedWhenClosed = false
        detached.backgroundColor = .black
        detached.minSize = NSSize(width: 400, height: 270)
        detached.contentView = NSHostingView(rootView: IntelligenceDetachedResponseView(response: response))
        detached.alphaValue = 0
        detachedWindow = detached
        detachedCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: detached, queue: .main
        ) { [weak self, weak detached] _ in
            Task { @MainActor [weak self] in
                guard self?.detachedWindow === detached else { return }
                self?.detachedWindow = nil
                if let token = self?.detachedCloseObserver {
                    NotificationCenter.default.removeObserver(token)
                    self?.detachedCloseObserver = nil
                }
            }
        }
        state = .detaching
        detached.orderFrontRegardless()
        removeMonitors()
        viewModel?.hostWindow?.makeFirstResponder(nil)
        (viewModel?.hostWindow as? BoringNotchSkyLightWindow)?.allowsIntelligenceKeyboardFocus = false
        withAnimation(.spring(response: 0.32, dampingFraction: 0.95)) {
            viewModel?.restoreFromIntelligence(wasOpen: false)
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.36
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            detached.animator().setFrame(target, display: true)
            detached.animator().alphaValue = 1
        } completionHandler: { [weak self] in
            Task { @MainActor in self?.detachedWindow?.makeKeyAndOrderFront(nil) }
        }
        let id = presentationID
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(330))
            guard self?.presentationID == id else { return }
            self?.finishDismissal(background: false)
        }
    }

    func closeDetachedResponse() {
        detachedWindow?.close()
        detachedWindow = nil
        if let detachedCloseObserver { NotificationCenter.default.removeObserver(detachedCloseObserver) }
        detachedCloseObserver = nil
    }

    private func installMonitors() {
        removeMonitors()
        refreshGlobalEscapePermission()
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, self.isActive else { return event }
            if event.type == .keyDown, event.keyCode == 53 {
                self.dismiss()
                return nil
            }
            if event.type == .leftMouseDown || event.type == .rightMouseDown,
               !self.pointerIsInPanel() {
                self.dismiss(outsideClick: true)
            }
            return event
        }
        if globalEscapeAvailable {
            globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard event.keyCode == 53, !event.isARepeat else { return }
                Task { @MainActor [weak self] in self?.dismiss(outsideClick: true) }
            }
        }
        // Input Monitoring can observe keys even when Accessibility is not
        // granted. This passive tap sees only key-down events, exists only while
        // Intelligence is visible, and never consumes the focused app's key.
        if CGPreflightListenEventAccess() {
            let mask = CGEventMask(1) << CGEventType.keyDown.rawValue
            if let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                           place: .headInsertEventTap,
                                           options: .listenOnly,
                                           eventsOfInterest: mask,
                                           callback: { _, type, event, userInfo in
                guard type == .keyDown,
                      event.getIntegerValueField(.keyboardEventKeycode) == 53,
                      let userInfo else { return Unmanaged.passUnretained(event) }
                let coordinator = Unmanaged<IntelligenceCoordinator>
                    .fromOpaque(userInfo).takeUnretainedValue()
                Task { @MainActor in coordinator.dismiss(outsideClick: true) }
                return Unmanaged.passUnretained(event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()) {
                escapeEventTap = tap
                let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
                escapeTapSource = source
                CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        }
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isActive, !self.pointerIsInPanel() else { return }
                self.dismiss(outsideClick: true)
            }
        }
    }

    private func pointerIsInPanel() -> Bool {
        guard let model = viewModel, let host = model.hostWindow else { return false }
        let rect = CGRect(x: host.frame.midX - model.notchSize.width / 2,
                          y: host.frame.maxY - model.notchSize.height,
                          width: model.notchSize.width, height: model.notchSize.height)
        return rect.insetBy(dx: -4, dy: -4).contains(NSEvent.mouseLocation)
    }

    private func removeMonitors() {
        for monitor in [localMonitor, globalKeyMonitor, globalClickMonitor] {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
        localMonitor = nil
        globalKeyMonitor = nil
        globalClickMonitor = nil
        if let escapeTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), escapeTapSource, .commonModes)
        }
        if let escapeEventTap { CFMachPortInvalidate(escapeEventTap) }
        escapeTapSource = nil
        escapeEventTap = nil
    }

    func testConnection() {
        guard !testing else { return }
        let name = shortcutName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            testMessage = "Enter the exact name of your Shortcut first."
            return
        }
        testing = true
        testMessage = nil
        testTask = Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await self.provider.generate(prompt: "Reply briefly to confirm Notchloom can reach this model.", shortcutName: name)
                guard !Task.isCancelled else { return }
                if self.shortcutName.trimmingCharacters(in: .whitespacesAndNewlines) == name {
                    self.readyShortcutName = name
                    self.testMessage = "Connected. The Shortcut returned a real response."
                }
            } catch {
                guard !Task.isCancelled else { return }
                self.readyShortcutName = nil
                self.testMessage = error.localizedDescription
            }
            self.testing = false
        }
    }
}
