import Foundation
import Combine

enum TodayGenerationState: Equatable {
    case idle, setupRequired, geminiRequired, consentRequired, empty, collecting, generating, ready, failed
    var busy: Bool { self == .collecting || self == .generating }
}

/// Presentation state and durable explicit consent. No network requests in SwiftUI.
@MainActor final class TodayBriefingCoordinator: ObservableObject {
    @Published private(set) var state: TodayGenerationState = .idle
    @Published private(set) var entry: TodayBriefingEntry?
    @Published private(set) var stale = false
    @Published private(set) var message: String?
    @Published private(set) var outgoing: Data?
    @Published private(set) var consent: TodayBriefingConsent
    private let service: TodayBriefingService
    private let context: TodayContextController
    private let defaults: UserDefaults
    private var operation: Task<Void, Never>?
    private var expiry: Task<Void, Never>?
    private var outgoingExpiry: Task<Void, Never>?
    private var purgeTask: Task<Void, Never>?
    private var revision = UUID()
    private var subscriptions = Set<AnyCancellable>()
    private var visible = false
    private var presentations = 0
    private var automaticRetryAfter: Date?
    static let consentKey = "today.gemini.consent.v1"

    init(service: TodayBriefingService, context: TodayContextController, defaults: UserDefaults = .standard) {
        self.service = service; self.context = context; self.defaults = defaults
        consent = defaults.data(forKey: Self.consentKey).flatMap { try? JSONDecoder().decode(TodayBriefingConsent.self, from: $0) } ?? .init()
        context.$authorizationRevision.dropFirst().sink { [weak self] _ in self?.privacyChanged() }.store(in: &subscriptions)
        context.$briefingRevision.dropFirst().sink { [weak self] _ in self?.sourceChanged() }.store(in: &subscriptions)
        context.$briefingStaleRevision.dropFirst().sink { [weak self] _ in
            if self?.entry != nil { self?.stale = true }
        }.store(in: &subscriptions)
    }
    deinit { operation?.cancel(); expiry?.cancel(); outgoingExpiry?.cancel() }
    var hasConsent: Bool { consent.permits(context.settings) }
    var document: TodayPageDocument? { try? entry?.document(stale: stale) }
    var busy: Bool { state.busy }
    func open() {
        presentations += 1
        guard presentations == 1 else { return }
        visible = true
        start(force: false)
    }
    func close() {
        presentations = max(0, presentations - 1)
        guard presentations == 0 else { return }
        visible = false; cancel(); outgoing = nil; outgoingExpiry?.cancel(); entry = nil
        // Reopening reloads only after checking current OS permissions, avoiding a stale private-content flash.
    }
    func resume() { if visible { start(force: false) } }
    func refresh() { start(force: true) }
    func allowGeneration() {
        guard context.configured else { state = .setupRequired; return }
        consent = .init(scopeHash: TodayPromptBuilder.scopeHash(context.settings), grantedAt: Date())
        persistConsent()
        automaticRetryAfter = nil
        start(force: false)
    }
    func revokeConsent() {
        consent = .init(); persistConsent(); privacyChanged()
        message = "Gemini briefing consent revoked. Cached reports were removed. Local source choices are unchanged."
    }
    func clearReports() {
        cancel(); entry = nil; outgoing = nil; outgoingExpiry?.cancel(); stale = false
        purgeTask = Task { await service.clear() }
        state = .idle; message = "Cached briefings cleared. Prepare Today again when you’re ready."
    }
    func configurationChanged() { privacyChanged() }
    func sourceChanged() {
        outgoing = nil; outgoingExpiry?.cancel()
        if entry != nil { stale = true }
        if busy { cancel(); message = "Your local sources changed. Refresh to use the latest information." }
    }
    func cancel() {
        if busy { automaticRetryAfter = Date().addingTimeInterval(10) }
        revision = UUID(); operation?.cancel(); operation = nil
        Task { await service.cancel() }
        if busy { state = entry == nil ? .idle : .ready; message = "Preparation canceled." }
    }
    func previewOutgoing() {
        guard !busy else { return }
        operation?.cancel(); outgoing = nil; state = .collecting
        let expected = UUID(); revision = expected
        operation = Task {
            await purgeTask?.value
            do {
                let preview = try await service.preview()
                guard expected == revision, !Task.isCancelled else { return }
                outgoing = preview.json; expireOutgoing(at: preview.privacyExpiresAt); state = entry == nil ? .consentRequired : .ready
            } catch { if expected == revision && !Task.isCancelled { fail(error) } }
        }
    }
    func pause() { cancel(); outgoing = nil; outgoingExpiry?.cancel() }
    private func start(force: Bool) {
        guard visible, !busy else { return }
        operation?.cancel()
        let expected = UUID(); revision = expected; message = nil
        state = .collecting
        if force { automaticRetryAfter = nil }
        operation = Task {
            await purgeTask?.value
            await context.refreshPermissions()
            guard expected == revision, !Task.isCancelled else { return }
            guard context.configured else { state = .setupRequired; return }
            let config = await service.configuration()
            guard expected == revision, !Task.isCancelled else { return }
            guard consent.permits(context.settings) else { state = config.ready ? .consentRequired : .geminiRequired; return }
            // Read a protected previous report before asking for a new one.
            if let cached = await service.cached(settings: context.settings, consent: consent, accessHash: context.briefingAccessHash) {
                guard expected == revision, !Task.isCancelled else { return }
                entry = cached; stale = cached.isStale(now: Date(), zone: .current, model: config.model)
                scheduleExpiry()
            }
            guard expected == revision, !Task.isCancelled else { return }
            guard config.ready else { state = .geminiRequired; message = "Save a key and choose your Gemini model in Intelligence → Models."; return }
            if !force, let automaticRetryAfter, Date() < automaticRetryAfter {
                state = entry == nil ? .idle : .ready
                message = "Preparation was canceled. Refresh when you’re ready to try again."
                return
            }
            do {
                let result = try await service.generate(consent: consent, force: force, onPreparing: { [weak coordinator = self] prepared in
                    await coordinator?.prepared(prepared, revision: expected)
                })
                guard expected == revision, !Task.isCancelled, visible, hasConsent else { return }
                entry = result.entry; stale = false; state = .ready; outgoing = nil; outgoingExpiry?.cancel()
                message = result.cacheWarning ? TodayBriefingError.cacheUnavailable.localizedDescription : nil
                scheduleExpiry()
            } catch is CancellationError {
                if expected == revision { state = entry == nil ? .idle : .ready; message = "Preparation canceled. You can try again." }
            } catch { if expected == revision && !Task.isCancelled { fail(error) } }
        }
    }
    private func prepared(_ value: TodayPreparedPrompt, revision: UUID) {
        guard revision == self.revision else { return }
        outgoing = value.json; expireOutgoing(at: value.privacyExpiresAt); state = .generating
    }
    private func fail(_ error: Error) {
        if let error = error as? TodayBriefingError {
            switch error {
            case .consentRequired: state = .consentRequired
            case .setupRequired: state = .setupRequired
            case .noContext: state = .empty
            default: state = .failed
            }
            message = error.localizedDescription
        } else { state = .failed; message = GeminiModelStore.safeMessage(error) }
        if entry != nil { stale = true }
    }
    private func privacyChanged() {
        cancel(); expiry?.cancel(); entry = nil; outgoing = nil; outgoingExpiry?.cancel(); stale = false
        purgeTask = Task { await service.clear() }
        state = context.configured ? (hasConsent ? .idle : .consentRequired) : .setupRequired
    }
    private func persistConsent() { defaults.set(try? JSONEncoder().encode(consent), forKey: Self.consentKey) }
    private func expireOutgoing(at expiration: Date) {
        outgoingExpiry?.cancel()
        outgoingExpiry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0.1, expiration.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            self?.outgoing = nil
        }
    }
    private func scheduleExpiry() {
        expiry?.cancel()
        guard let expiration = entry?.privacyExpiresAt else { return }
        // Privacy retention only. This does not schedule an insight, message or notification.
        expiry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0.1, expiration.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            self?.clearReports()
        }
    }
}
