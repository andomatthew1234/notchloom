import Foundation
import CryptoKit

enum TodaySourceID: String, Codable, CaseIterable, Sendable, CodingKeyRepresentable { case dateTime, weather, calendar, notifications }
enum TodaySourceState: String, Codable, Sendable { case disabled, permissionRequired, loading, ready, stale, unavailable, failed }
enum TodayPermissionState: String, Codable, Sendable { case notDetermined, authorized, denied, restricted, unavailable, notRequired }
struct TodaySourceStatus: Codable, Sendable, Equatable {
    let state: TodaySourceState
    let collectedAt: Date?
    let itemCount: Int
    let message: String
}

struct TodayPrivacySettings: Codable, Sendable, Equatable {
    enum LocationMode: String, Codable, Sendable { case manual, approximateDevice }
    enum TemperatureUnit: String, Codable, CaseIterable, Sendable { case system, celsius, fahrenheit }
    var collectionEnabled = false
    var setupCompleted = false
    var dateTimeEnabled = true
    var weatherEnabled = false
    var calendarEnabled = false
    var notificationsEnabled = false
    var weatherProviderConsent = false
    var locationMode: LocationMode = .manual
    var manualLocation: TodayLocation?
    var selectedCalendarIDs: Set<String> = []
    var allCalendars = true
    var includeEventLocations = false
    var includeMeetingURLs = false
    var lookaheadHours = 6
    var weatherRefreshMinutes = 30
    var temperatureUnit: TemperatureUnit = .system
    func enabled(_ source: TodaySourceID) -> Bool {
        guard collectionEnabled && setupCompleted else { return false }
        switch source {
        case .dateTime: return dateTimeEnabled
        case .weather: return weatherEnabled
        case .calendar: return calendarEnabled
        case .notifications: return notificationsEnabled
        }
    }
    var authorizedSources: Set<TodaySourceID> { Set(TodaySourceID.allCases.filter(enabled)) }
    var bounded: Self {
        var copy = self
        copy.lookaheadHours = min(12, max(0, lookaheadHours))
        copy.weatherRefreshMinutes = min(120, max(15, weatherRefreshMinutes))
        copy.selectedCalendarIDs = Set(copy.selectedCalendarIDs.sorted().prefix(100).map { String($0.prefix(512)) })
        if let location = copy.manualLocation {
            copy.manualLocation = location.isValid ? TodayLocation(name: location.name, latitude: location.latitude, longitude: location.longitude) : nil
        }
        return copy
    }
}

struct TodayLocation: Codable, Sendable, Equatable, Identifiable {
    let name: String
    let latitude: Double
    let longitude: Double
    var id: String { String(format: "%.2f,%.2f", latitude, longitude) }
    var isValid: Bool { latitude.isFinite && longitude.isFinite && (-90...90).contains(latitude) && (-180...180).contains(longitude) && (1...100).contains(name.count) }
    init(name: String, latitude: Double, longitude: Double) {
        self.name = String(name.prefix(100))
        self.latitude = (latitude * 100).rounded() / 100
        self.longitude = (longitude * 100).rounded() / 100
    }
}

struct TodayDateTimeContext: Codable, Sendable, Equatable {
    enum Period: String, Codable, Sendable { case morning, afternoon, evening, night }
    let source: TodaySourceID
    let timestamp: Date
    let localISO8601: String
    let localDate: String
    let localTime: String
    let weekday: String
    let timeZoneIdentifier: String
    let utcOffsetSeconds: Int
    let localeIdentifier: String
    let period: Period
    static func make(now: Date, zone: TimeZone, locale: Locale) -> Self {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        let iso = ISO8601DateFormatter(); iso.timeZone = zone
        let date = DateFormatter(); date.calendar = calendar; date.timeZone = zone
        date.locale = Locale(identifier: "en_US_POSIX"); date.dateFormat = "yyyy-MM-dd"
        let time = DateFormatter(); time.locale = Locale(identifier: "en_US_POSIX"); time.timeZone = zone; time.dateFormat = "HH:mm:ss"
        let weekday = DateFormatter(); weekday.timeZone = zone; weekday.locale = locale; weekday.dateFormat = "EEEE"
        let hour = calendar.component(.hour, from: now)
        let period: Period = (5..<12).contains(hour) ? .morning : (12..<17).contains(hour) ? .afternoon : (17..<22).contains(hour) ? .evening : .night
        return .init(source: .dateTime, timestamp: now, localISO8601: iso.string(from: now), localDate: date.string(from: now),
                     localTime: time.string(from: now), weekday: weekday.string(from: now), timeZoneIdentifier: zone.identifier,
                     utcOffsetSeconds: zone.secondsFromGMT(for: now), localeIdentifier: locale.identifier, period: period)
    }
}

struct TodayWeatherContext: Codable, Sendable, Equatable {
    struct Hour: Codable, Sendable, Equatable {
        let timestamp: Date
        let temperatureCelsius: Double?
        let precipitationProbability: Double?
        let conditionCode: Int?
    }
    let source: TodaySourceID
    let provider: String
    let locationName: String
    let timeZoneIdentifier: String
    let collectedAt: Date
    let validAt: Date
    let temperatureCelsius: Double?
    let apparentTemperatureCelsius: Double?
    let highCelsius: Double?
    let lowCelsius: Double?
    let precipitationProbability: Double?
    let todayPrecipitationProbability: Double?
    let conditionCode: Int?
    let nearTerm: [Hour]
    /// nil means the provider does not supply alerts; it never means "no alerts".
    let alerts: [String]?
    let attribution: String
}

struct TodayCalendarItem: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let source: TodaySourceID
    let collectedAt: Date
    let eventIdentifier: String?
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let calendarName: String
    let calendarID: String
    let location: String?
    let meetingURL: URL?
    let timeZoneIdentifier: String?
    let updatedAt: Date?
    let recurring: Bool
}

struct TodayNotificationItem: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let source: TodaySourceID
    let applicationIdentifier: String?
    let applicationName: String
    let title: String
    let body: String
    /// Time Notchloom observed the visible banner, not its original delivery time.
    let observedAt: Date
}

struct TodayContextSnapshot: Codable, Sendable, Equatable {
    let version: Int
    let generatedAt: Date
    let timezone: String
    let authorizedSources: Set<TodaySourceID>
    let externalTransmissionAllowed: Bool
    let dateTime: TodayDateTimeContext?
    let weather: TodayWeatherContext?
    let calendarEvents: [TodayCalendarItem]
    let notifications: [TodayNotificationItem]
    let sourceStatus: [TodaySourceID: TodaySourceStatus]
    func encoded() throws -> Data {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
    static func decode(_ data: Data) throws -> Self {
        guard data.count <= 256_000 else { throw TodayContextError.invalidData }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Self.self, from: data)
    }
}

enum TodayContextError: LocalizedError, Equatable {
    case invalidData, permission, unavailable, network, timeout, rateLimited, locationRequired
    var errorDescription: String? {
        switch self {
        case .invalidData: "This source returned incomplete or invalid data. Try refreshing."
        case .permission: "Access is not granted. You can change it in macOS System Settings."
        case .unavailable: "This source is not available right now. Other sources can still work."
        case .network: "Weather could not be reached. Check your connection and try again."
        case .timeout: "The source took too long to respond. Try again."
        case .rateLimited: "The weather provider asked us to wait. Try again later."
        case .locationRequired: "Choose a city or request an approximate location for weather."
        }
    }
}

enum TodayContextValidator {
    static func validate(_ snapshot: TodayContextSnapshot, policy: TodayPrivacySettings) throws {
        guard snapshot.version == 1, snapshot.generatedAt.timeIntervalSince1970.isFinite,
              TimeZone(identifier: snapshot.timezone) != nil, !snapshot.externalTransmissionAllowed,
              snapshot.authorizedSources == policy.authorizedSources,
              Set(snapshot.sourceStatus.keys) == Set(TodaySourceID.allCases),
              snapshot.calendarEvents.count <= 40, snapshot.notifications.count <= 20 else { throw TodayContextError.invalidData }
        guard policy.enabled(.dateTime) || snapshot.dateTime == nil,
              policy.enabled(.weather) || snapshot.weather == nil,
              policy.enabled(.calendar) || snapshot.calendarEvents.isEmpty,
              policy.enabled(.notifications) || snapshot.notifications.isEmpty else { throw TodayContextError.invalidData }
        for id in TodaySourceID.allCases {
            let count: Int
            switch id {
            case .dateTime: count = snapshot.dateTime == nil ? 0 : 1
            case .weather: count = snapshot.weather == nil ? 0 : 1
            case .calendar: count = snapshot.calendarEvents.count
            case .notifications: count = snapshot.notifications.count
            }
            let status = snapshot.sourceStatus[id]!
            guard status.itemCount == count, policy.enabled(id) || status.state == .disabled,
                  status.message.count <= 1000, status.collectedAt?.timeIntervalSince1970.isFinite != false,
                  count == 0 || status.state == .ready || status.state == .stale else { throw TodayContextError.invalidData }
        }
        if let date = snapshot.dateTime {
            guard date.source == .dateTime, TimeZone(identifier: date.timeZoneIdentifier) != nil,
                  ISO8601DateFormatter().date(from: date.localISO8601) != nil,
                  (-50_400...50_400).contains(date.utcOffsetSeconds), date.timeZoneIdentifier == snapshot.timezone,
                  date == TodayDateTimeContext.make(now: date.timestamp, zone: TimeZone(identifier: date.timeZoneIdentifier)!, locale: Locale(identifier: date.localeIdentifier)) else { throw TodayContextError.invalidData }
        }
        if let weather = snapshot.weather {
            let temperatures = [weather.temperatureCelsius, weather.apparentTemperatureCelsius, weather.highCelsius, weather.lowCelsius] + weather.nearTerm.map(\.temperatureCelsius)
            guard policy.weatherProviderConsent, weather.source == .weather, weather.nearTerm.count <= 12, weather.provider == "Open-Meteo",
                  TimeZone(identifier: weather.timeZoneIdentifier) != nil, weather.locationName.count <= 100,
                  weather.collectedAt.timeIntervalSince1970.isFinite, weather.attribution.count <= 1000,
                  weather.nearTerm.allSatisfy({ $0.timestamp.timeIntervalSince1970.isFinite }),
                  temperatures.compactMap({ $0 }).allSatisfy({ $0.isFinite && (-150...100).contains($0) }),
                  ([weather.precipitationProbability, weather.todayPrecipitationProbability] + weather.nearTerm.map(\.precipitationProbability)).compactMap({ $0 }).allSatisfy({ (0...1).contains($0) }),
                  weather.validAt.timeIntervalSince1970.isFinite else { throw TodayContextError.invalidData }
        }
        var ids = Set<String>()
        let window = eventWindow(now: snapshot.generatedAt, zone: TimeZone(identifier: snapshot.timezone)!, lookahead: policy.lookaheadHours)
        for item in snapshot.calendarEvents {
            guard item.source == .calendar, ids.insert(item.id).inserted, (1...200).contains(item.title.count), item.calendarName.count <= 100,
                  item.start.timeIntervalSince1970.isFinite, item.end.timeIntervalSince1970.isFinite, item.end >= item.start,
                  item.collectedAt.timeIntervalSince1970.isFinite, item.updatedAt?.timeIntervalSince1970.isFinite != false,
                  item.end > snapshot.generatedAt, item.start < window.end,
                  item.id.count <= 128, item.calendarID.count <= 512, item.eventIdentifier?.count ?? 0 <= 512,
                  item.location?.count ?? 0 <= 200, item.meetingURL?.absoluteString.count ?? 0 <= 2048,
                  policy.allCalendars || policy.selectedCalendarIDs.contains(item.calendarID),
                  policy.includeEventLocations || item.location == nil,
                  policy.includeMeetingURLs || item.meetingURL == nil,
                  item.meetingURL == nil || ["https", "http"].contains(item.meetingURL!.scheme?.lowercased() ?? "") else { throw TodayContextError.invalidData }
        }
        for item in snapshot.notifications {
            let age = snapshot.generatedAt.timeIntervalSince(item.observedAt)
            guard item.source == .notifications, ids.insert(item.id).inserted, item.title.count <= 120, item.body.count <= 240,
                  item.id.count <= 128, item.applicationIdentifier?.count ?? 0 <= 150,
                  item.applicationName.count <= 64, age >= -2 && age <= 1800 else { throw TodayContextError.invalidData }
        }
        guard (try snapshot.encoded()).count <= 256_000 else { throw TodayContextError.invalidData }
    }
    static func stableID(prefix: String, value: String) -> String {
        prefix + "-" + SHA256.hash(data: Data(value.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
    }
    static func eventWindow(now: Date, zone: TimeZone, lookahead: Int) -> DateInterval {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        let start = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: start)!
        return DateInterval(start: start, end: calendar.date(byAdding: .hour, value: min(12, max(0, lookahead)), to: tomorrow)!)
    }
}
