import Foundation
import Combine

/// UI adapter; the underlying context service has no UI, AppKit or AI dependency.
@MainActor final class TodayContextController: ObservableObject {
    @Published private(set) var settings: TodayPrivacySettings
    @Published private(set) var snapshot: TodayContextSnapshot?
    @Published private(set) var busy = false
    @Published private(set) var calendarPermission: TodayPermissionState = .notDetermined
    @Published private(set) var locationPermission: TodayPermissionState = .notDetermined
    @Published private(set) var calendars: [TodayCalendarOption] = []
    @Published private(set) var message: String?
    @Published private(set) var cities: [TodayLocation] = []
    @Published private(set) var searching = false
    @Published private(set) var requestingPermission = false
    @Published private(set) var locationPermissionHandoff = false
    private var locationPresenters: [UUID: @MainActor () async -> Void] = [:]
    @Published private(set) var authorizationRevision = 0
    @Published private(set) var briefingRevision = 0
    @Published private(set) var briefingStaleRevision = 0
    @Published private(set) var notificationCapability: TodayNotificationSource.Capability = .unavailable
    @Published private(set) var localDate: TodayDateTimeContext?
    @Published var showingSetup = false
    private let service: TodayContextService
    private let calendar: any TodayCalendarProviding
    private let location: any TodayLocationProviding
    private let citySearch: @Sendable (String) async throws -> [TodayLocation]
    private let defaults: UserDefaults
    private var revision = 0
    private var presentations = 0
    private var active = true
    private var configuredRevision = -1
    private var refreshTask: Task<Void, Never>?
    private var applyTask: Task<Void, Never>?
    private var midnightTask: Task<Void, Never>?
    private var expiryTask: Task<Void, Never>?
    private var lastRefresh: Date?
    private var searchTask: Task<Void, Never>?
    private var searchID = UUID()
    private var pendingRefresh = false
    private var calendarListLoaded = false
    static let settingsKey = "today.privacy.v1"

    init(service: TodayContextService, calendar: any TodayCalendarProviding, location: any TodayLocationProviding,
         defaults: UserDefaults = .standard, citySearch: @escaping @Sendable (String) async throws -> [TodayLocation] = { _ in [] }) {
        self.service = service; self.calendar = calendar; self.location = location; self.defaults = defaults; self.citySearch = citySearch
        settings = defaults.data(forKey: Self.settingsKey).flatMap { try? JSONDecoder().decode(TodayPrivacySettings.self, from: $0) }?.bounded ?? .init()
        let initial = settings
        updateLocalDate()
        applyTask = Task {
            await service.configure(initial, revision: 0)
            if revision == 0 { configuredRevision = 0 }
        }
    }
    deinit { refreshTask?.cancel(); applyTask?.cancel(); midnightTask?.cancel(); searchTask?.cancel(); expiryTask?.cancel() }
    var configured: Bool { settings.setupCompleted && settings.collectionEnabled }
    var dataRevision: Int { revision }

    func beginPresentation() {
        presentations += 1
        updateLocalDate()
        refresh()
        scheduleMidnight()
    }
    func endPresentation() {
        presentations = max(0, presentations - 1)
        if presentations == 0 { midnightTask?.cancel(); expiryTask?.cancel(); refreshTask?.cancel(); refreshTask = nil; busy = false; snapshot = nil; lastRefresh = nil; calendars = []; calendarListLoaded = false }
    }
    func update(_ value: TodayPrivacySettings) {
        let value = value.bounded
        guard value != settings else { return }
        settings = value
        if !value.enabled(.calendar) { calendars = []; calendarListLoaded = false }
        updateLocalDate()
        invalidateCollection()
        defaults.set(try? JSONEncoder().encode(value), forKey: Self.settingsKey)
    }
    private func invalidateCollection() {
        revision += 1; lastRefresh = nil
        briefingRevision += 1; authorizationRevision += 1
        // Remove published data synchronously. Old in-flight results cannot republish it.
        snapshot = nil; cities = []; refreshTask?.cancel(); busy = false
        expiryTask?.cancel()
        cancelCitySearch()
        let value = settings
        let expected = revision
        applyTask?.cancel()
        applyTask = Task {
            await service.configure(value, revision: expected)
            guard revision == expected else { return }
            configuredRevision = expected
            if presentations > 0 && active { refresh() }
        }
    }
    func edit(_ body: (inout TodayPrivacySettings) -> Void) { var value = settings; body(&value); update(value) }

    func refresh(force: Bool = false) {
        guard presentations > 0, active, !busy else { return }
        busy = true
        let applying = applyTask
        refreshTask = Task { [weak self] in
            guard let self else { return }
            let expected = revision
            await applying?.value
            guard !Task.isCancelled, expected == revision else { return }
            await refreshPermissions()
            guard !Task.isCancelled, expected == revision else { return }
            guard configured else { busy = false; snapshot = nil; return }
            if !force, let lastRefresh, snapshot != nil, (0..<60).contains(Date().timeIntervalSince(lastRefresh)) { busy = false; return }
            do {
                if configuredRevision != expected {
                    await service.configure(settings, revision: expected)
                    guard !Task.isCancelled, expected == revision else { return }
                    configuredRevision = expected
                }
                let result = try await service.snapshot(revision: expected, force: force, onUpdate: { [weak self] partial in
                    await self?.publishPartial(partial, revision: expected)
                })
                guard !Task.isCancelled, expected == revision else { return }
                // Check grants again after asynchronous weather/calendar work.
                await refreshPermissions()
                guard !Task.isCancelled, expected == revision else { return }
                if (!result.calendarEvents.isEmpty && calendarPermission != .authorized) ||
                   (result.weather != nil && settings.locationMode == .approximateDevice && locationPermission != .authorized) {
                    snapshot = nil; message = "A permission changed while refreshing. Refresh to collect the remaining available sources."
                } else { snapshot = result; lastRefresh = Date(); message = nil; scheduleNotificationExpiry() }
            } catch is CancellationError { /* A settings change or closed view canceled this request. */ }
            catch { if expected == revision { message = "The local context could not be validated. Try refreshing." } }
            if expected == revision { busy = false; if pendingRefresh { pendingRefresh = false; lastRefresh = nil; refresh() } }
        }
    }
    func refreshPermissions() async {
        let calendarState = await calendar.permission()
        let locationState = await location.permission()
        let revoked = calendarPermission == .authorized && calendarState != .authorized || locationPermission == .authorized && locationState != .authorized
        let changed = calendarPermission != calendarState || locationPermission != locationState
        calendarPermission = calendarState; locationPermission = locationState
        if revoked { invalidateCollection() }
        if changed { lastRefresh = nil }
        if calendarState != .authorized {
            calendars = []; calendarListLoaded = false
            if snapshot?.calendarEvents.isEmpty == false { snapshot = nil }
            await service.invalidate(.calendar)
        } else if presentations > 0 && active && settings.enabled(.calendar) && !calendarListLoaded { await loadCalendarOptions() }
        if locationState != .authorized && settings.locationMode == .approximateDevice {
            if snapshot?.weather != nil { snapshot = nil }
            await service.invalidate(.weather)
        }
    }
    func requestCalendar() async {
        guard !requestingPermission else { return }
        requestingPermission = true; defer { requestingPermission = false }
        calendarPermission = await calendar.requestPermission()
        await refreshPermissions()
        await loadCalendarOptions(allowSetup: true)
        lastRefresh = nil; if configured { refresh() }
    }
    func loadCalendarOptions(allowSetup: Bool = false) async {
        guard (presentations > 0 && active && settings.enabled(.calendar)) || allowSetup && showingSetup,
              await calendar.permission() == .authorized else { return }
        let expected = revision
        let options = await calendar.calendars()
        guard expected == revision, await calendar.permission() == .authorized,
              (presentations > 0 && active && settings.enabled(.calendar)) || allowSetup && showingSetup else { return }
        calendars = options; calendarListLoaded = true
    }
    func requestLocation() async {
        guard !requestingPermission else { return }
        let currentPermission = await location.permission()
        guard !requestingPermission else { return }
        guard currentPermission == .notDetermined else { await refreshPermissions(); return }
        requestingPermission = true
        defer { locationPermissionHandoff = false; requestingPermission = false }
        let presenters = locationPresenters
        if !presenters.isEmpty {
            locationPermissionHandoff = true
            // Await the real contraction before macOS displays its permission alert.
            await withTaskGroup(of: Void.self) { group in
                for prepare in presenters.values { group.addTask { await prepare() } }
            }
            guard !Task.isCancelled, presenters.keys.contains(where: { locationPresenters[$0] != nil }) else { return }
        }
        locationPermission = await location.requestPermission()
        await refreshPermissions()
        lastRefresh = nil; if configured { refresh() }
    }
    func registerLocationPresenter(_ id: UUID, prepare: @escaping @MainActor () async -> Void) { locationPresenters[id] = prepare }
    func unregisterLocationPresenter(_ id: UUID) { locationPresenters[id] = nil }
    func searchCity(_ query: String, consent: Bool) {
        guard consent, !searching else { return }
        searching = true; cities = []; message = nil
        let id = UUID(); searchID = id
        searchTask = Task {
            defer { if searchID == id { searching = false } }
            do {
                let results = try await citySearch(query)
                guard !Task.isCancelled, searchID == id else { return }
                cities = results; if cities.isEmpty { message = "No matching cities were found. Try a city and country." }
            } catch { if searchID == id { message = "City search is unavailable. You can enter approximate coordinates instead." } }
        }
    }
    func cancelCitySearch() { searchTask?.cancel(); searchTask = nil; searchID = UUID(); cities = []; searching = false }
    func clearCachedData() {
        revision += 1; refreshTask?.cancel(); busy = false; snapshot = nil; lastRefresh = nil; cities = []
        briefingRevision += 1; authorizationRevision += 1
        applyTask?.cancel(); cancelCitySearch(); expiryTask?.cancel()
        let expected = revision
        applyTask = Task {
            await service.clear()
            await service.configure(settings, revision: expected)
            if expected == revision { configuredRevision = expected; message = "Cached context cleared. Your source choices remain saved." }
        }
    }
    func lifecycleChanged(source: TodaySourceID? = nil) {
        lastRefresh = nil
        updateLocalDate()
        if source != nil { snapshot = nil; briefingRevision += 1 }
        if source == .calendar { calendarListLoaded = false }
        Task {
            await refreshPermissions()
            if let source { await service.invalidate(source) }
            if presentations > 0 && active { if busy { pendingRefresh = true } else { refresh() } }
        }
        scheduleMidnight()
    }
    func applicationActive(_ isActive: Bool) {
        active = isActive
        if isActive { lifecycleChanged() }
        else {
            // No retained calendar snapshot while the user is changing permissions in another app.
            refreshTask?.cancel(); busy = false; snapshot = nil; lastRefresh = nil
        }
    }
    func notificationCapabilityChanged(_ value: TodayNotificationSource.Capability) {
        guard value != notificationCapability else { return }
        notificationCapability = value
        if settings.enabled(.notifications) { invalidateCollection() }
    }
    func notificationArrived() {
        if settings.enabled(.notifications) { briefingStaleRevision += 1 }
        guard settings.enabled(.notifications), presentations > 0, active else { return }
        lastRefresh = nil; if busy { pendingRefresh = true } else { refresh() }
    }
    func updateLocalDate() {
        localDate = settings.enabled(.dateTime) ? .make(now: Date(), zone: .current, locale: .current) : nil
    }

    /// Reuses Phase 3 collectors and permission checks; no HTTP or AI request is constructed here.
    func collectBriefingContext(force: Bool) async throws -> TodayBriefingContext {
        guard configured, presentations > 0, active else { throw TodayBriefingError.setupRequired }
        await applyTask?.value
        await refreshTask?.value
        try Task.checkCancellation()
        await refreshPermissions()
        let expected = revision, contentVersion = briefingRevision
        guard configured, presentations > 0, active else { throw CancellationError() }
        await applyTask?.value
        let result = try await service.snapshot(revision: expected, force: force)
        try Task.checkCancellation()
        await refreshPermissions()
        guard expected == revision, contentVersion == briefingRevision, configured, presentations > 0, active else { throw TodayBriefingError.authorizationChanged }
        snapshot = result
        scheduleNotificationExpiry()
        return .init(snapshot: result, settings: settings, revision: contentVersion, accessHash: briefingAccessHash)
    }
    var briefingAccessHash: String {
        let values = [settings.enabled(.calendar) ? calendarPermission.rawValue : "off",
                      settings.enabled(.weather) && settings.locationMode == .approximateDevice ? locationPermission.rawValue : "notRequired",
                      settings.enabled(.notifications) ? String(describing: notificationCapability) : "off"]
        return todayDigest(Data(values.joined(separator: "|").utf8))
    }
    func briefingStillAuthorized(_ context: TodayBriefingContext) async -> Bool {
        await refreshPermissions()
        return configured && presentations > 0 && active && briefingRevision == context.revision &&
            settings == context.settings && briefingAccessHash == context.accessHash
    }
    private func publishPartial(_ result: TodayContextSnapshot, revision: Int) async {
        guard !Task.isCancelled, revision == self.revision else { return }
        await refreshPermissions()
        guard !Task.isCancelled, revision == self.revision else { return }
        snapshot = result
        scheduleNotificationExpiry()
    }
    private func scheduleNotificationExpiry() {
        expiryTask?.cancel()
        guard let first = snapshot?.notifications.map(\.observedAt).min() else { return }
        expiryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0.1, first.addingTimeInterval(1800.1).timeIntervalSinceNow)))
            guard !Task.isCancelled, let self else { return }
            briefingRevision += 1
            snapshot = nil; lastRefresh = nil
            if presentations > 0 && active { refresh() }
        }
    }
    private func scheduleMidnight() {
        midnightTask?.cancel()
        guard presentations > 0 else { return }
        let now = Date(); let calendar = Calendar.current
        guard let next = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else { return }
        midnightTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(1, next.timeIntervalSince(now))))
            guard !Task.isCancelled else { return }
            self?.lifecycleChanged(source: .calendar)
        }
    }
}
