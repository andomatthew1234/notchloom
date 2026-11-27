import Foundation
@preconcurrency import EventKit
import CoreLocation

struct TodaySourceRequest: Sendable {
    let policy: TodayPrivacySettings
    let now: Date
    let timeZoneIdentifier: String
    let localeIdentifier: String
    var forceRefresh = false
    var zone: TimeZone { TimeZone(identifier: timeZoneIdentifier) ?? .gmt }
}
struct TodaySourceResult: Sendable {
    let id: TodaySourceID
    let status: TodaySourceStatus
    var dateTime: TodayDateTimeContext?
    var weather: TodayWeatherContext?
    var events: [TodayCalendarItem] = []
    var notifications: [TodayNotificationItem] = []
    static func status(_ id: TodaySourceID, _ state: TodaySourceState, _ message: String, now: Date? = nil, count: Int = 0) -> Self {
        .init(id: id, status: .init(state: state, collectedAt: now, itemCount: count, message: message))
    }
}
protocol TodayDataSource: Sendable {
    var id: TodaySourceID { get }
    func collect(_ request: TodaySourceRequest) async -> TodaySourceResult
    func clear() async
    func configure(_ policy: TodayPrivacySettings, revision: Int) async
}
extension TodayDataSource {
    func configure(_ policy: TodayPrivacySettings, revision: Int) async { if !policy.enabled(id) { await clear() } }
}
struct TodayDateTimeSource: TodayDataSource {
    let id = TodaySourceID.dateTime
    func collect(_ request: TodaySourceRequest) async -> TodaySourceResult {
        var result = TodaySourceResult.status(id, .ready, "Local date and time. No network access.", now: request.now, count: 1)
        result.dateTime = .make(now: request.now, zone: request.zone, locale: Locale(identifier: request.localeIdentifier))
        return result
    }
    func clear() async {}
}

struct TodayCalendarOption: Identifiable, Sendable, Equatable { let id: String; let title: String }
protocol TodayCalendarProviding: Sendable {
    func permission() async -> TodayPermissionState
    func requestPermission() async -> TodayPermissionState
    func calendars() async -> [TodayCalendarOption]
    func events(_ request: TodaySourceRequest) async throws -> [TodayCalendarItem]
}

actor TodayEventKitProvider: TodayCalendarProviding {
    private let store = EKEventStore()
    func permission() -> TodayPermissionState {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: return .authorized
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        case .denied, .writeOnly: return .denied
        @unknown default: return .unavailable
        }
    }
    /// macOS 14 exposes no read-only EventKit grant. This adapter never writes events.
    func requestPermission() async -> TodayPermissionState {
        guard permission() == .notDetermined else { return permission() }
        _ = try? await store.requestFullAccessToEvents()
        return permission()
    }
    func calendars() -> [TodayCalendarOption] {
        guard permission() == .authorized else { return [] }
        return store.calendars(for: .event).prefix(100).map { .init(id: $0.calendarIdentifier, title: String($0.title.prefix(100))) }
    }
    func events(_ request: TodaySourceRequest) async throws -> [TodayCalendarItem] {
        try Task.checkCancellation()
        guard permission() == .authorized else { throw TodayContextError.permission }
        let calendars = store.calendars(for: .event).filter { request.policy.allCalendars || request.policy.selectedCalendarIDs.contains($0.calendarIdentifier) }
        guard !calendars.isEmpty else { return [] }
        let window = TodayContextValidator.eventWindow(now: request.now, zone: request.zone, lookahead: request.policy.lookaheadHours)
        let predicate = store.predicateForEvents(withStart: window.start, end: window.end, calendars: calendars)
        // EventKit expands recurring occurrences for this bounded interval.
        let events = store.events(matching: predicate)
        try Task.checkCancellation()
        guard permission() == .authorized else { throw TodayContextError.permission }
        var seen = Set<String>()
        return events.compactMap { event -> TodayCalendarItem? in
            guard event.status != .canceled, let start = event.startDate, let end = event.endDate,
                  end > request.now, start < window.end, end >= window.start else { return nil }
            let id = TodayContextValidator.stableID(prefix: "event", value: (event.eventIdentifier ?? event.calendarItemIdentifier) + "|" + String(start.timeIntervalSince1970))
            guard seen.insert(id).inserted else { return nil }
            let url = request.policy.includeMeetingURLs ? event.url.flatMap { ["https", "http"].contains($0.scheme?.lowercased() ?? "") && $0.absoluteString.count <= 2048 ? $0 : nil } : nil
            return .init(id: id, source: .calendar, collectedAt: request.now,
                         eventIdentifier: event.eventIdentifier.map { String($0.prefix(512)) },
                         title: String((event.title?.isEmpty == false ? event.title! : "Untitled event").prefix(200)), start: start, end: end,
                         isAllDay: event.isAllDay, calendarName: String(event.calendar.title.prefix(100)), calendarID: event.calendar.calendarIdentifier,
                         location: request.policy.includeEventLocations ? event.location.map { String($0.prefix(200)) } : nil,
                         meetingURL: url, timeZoneIdentifier: event.timeZone?.identifier, updatedAt: event.lastModifiedDate, recurring: event.hasRecurrenceRules || event.isDetached)
        }.sorted { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }.prefix(40).map { $0 }
    }
}

actor TodayCalendarSource: TodayDataSource {
    nonisolated let id = TodaySourceID.calendar
    private let provider: any TodayCalendarProviding
    init(provider: any TodayCalendarProviding) { self.provider = provider }
    func collect(_ request: TodaySourceRequest) async -> TodaySourceResult {
        guard await provider.permission() == .authorized else { return .status(id, .permissionRequired, "Calendar access is not granted. Today never writes events.") }
        do {
            let events = TodayCalendarSelection.apply(try await provider.events(request), request: request)
            guard await provider.permission() == .authorized else { return .status(id, .permissionRequired, "Calendar access was changed. Cached events have been removed.") }
            var result = TodaySourceResult.status(id, .ready, events.isEmpty ? "No upcoming events in the selected calendars and time window." : "Upcoming events only. Event notes are never read.", now: request.now, count: events.count)
            result.events = events; return result
        } catch { return .status(id, await provider.permission() == .authorized ? .failed : .permissionRequired, "Calendar could not be read. Other sources are unaffected.") }
    }
    func clear() async {}
}

/// The same bounded occurrence rules apply to native EventKit and injected providers.
enum TodayCalendarSelection {
    static func apply(_ events: [TodayCalendarItem], request: TodaySourceRequest) -> [TodayCalendarItem] {
        let window = TodayContextValidator.eventWindow(now: request.now, zone: request.zone, lookahead: request.policy.lookaheadHours)
        var seen = Set<String>()
        return events.filter { item in
            item.end > request.now && item.start < window.end && item.end >= window.start &&
            (request.policy.allCalendars || request.policy.selectedCalendarIDs.contains(item.calendarID)) && seen.insert(item.id).inserted
        }.sorted { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }.prefix(40).map { $0 }
    }
}

protocol TodayLocationProviding: Sendable {
    func permission() async -> TodayPermissionState
    func requestPermission() async -> TodayPermissionState
    func locationIfAuthorized() async throws -> TodayLocation
}

@MainActor final class TodayLocationManager: NSObject, TodayLocationProviding, @preconcurrency CLLocationManagerDelegate {
    private lazy var manager: CLLocationManager = {
        let value = CLLocationManager(); value.delegate = self; value.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        return value
    }()
    private var locationWaiter: CheckedContinuation<TodayLocation, Error>?
    private var permissionWaiter: CheckedContinuation<TodayPermissionState, Never>?
    private var timeout: Task<Void, Never>?
    private var requestID: UUID?
    func permission() -> TodayPermissionState {
        switch manager.authorizationStatus {
        case .authorized, .authorizedAlways: return .authorized
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        case .denied: return .denied
        @unknown default: return .unavailable
        }
    }
    func requestPermission() async -> TodayPermissionState {
        guard permission() == .notDetermined else { return permission() }
        guard permissionWaiter == nil else { return .notDetermined }
        return await withCheckedContinuation { continuation in
            permissionWaiter = continuation
            manager.requestWhenInUseAuthorization()
        }
    }
    func locationIfAuthorized() async throws -> TodayLocation {
        guard permission() == .authorized else { throw TodayContextError.permission }
        guard locationWaiter == nil else { throw TodayContextError.unavailable }
        let id = UUID()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                locationWaiter = continuation
                requestID = id
                manager.requestLocation()
                timeout = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(15))
                    guard !Task.isCancelled else { return }
                    if self?.requestID == id { self?.finish(.failure(TodayContextError.timeout)) }
                }
            }
        } onCancel: { Task { @MainActor [weak self] in if self?.requestID == id { self?.finish(.failure(CancellationError())) } } }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let state = permission()
        if state != .notDetermined { permissionWaiter?.resume(returning: state); permissionWaiter = nil }
        if state != .authorized { finish(.failure(TodayContextError.permission)) }
        NotificationCenter.default.post(name: .todayLocationPermissionChanged, object: nil)
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard permission() == .authorized, let location = locations.last,
              location.horizontalAccuracy >= 0, abs(location.timestamp.timeIntervalSinceNow) < 300 else {
            finish(.failure(TodayContextError.locationRequired)); return
        }
        // Never retain or transmit the full-precision CLLocation.
        finish(.success(.init(name: "Approximate location", latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)))
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { finish(.failure(TodayContextError.locationRequired)) }
    private func finish(_ result: Result<TodayLocation, Error>) {
        timeout?.cancel(); timeout = nil; manager.stopUpdatingLocation()
        let waiter = locationWaiter; locationWaiter = nil
        requestID = nil
        waiter?.resume(with: result)
    }
}
extension Notification.Name { static let todayLocationPermissionChanged = Notification.Name("Notchloom.Today.LocationPermissionChanged") }
