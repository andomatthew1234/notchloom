import Foundation

protocol TodayHTTPTransport: Sendable { func data(_ url: URL) async throws -> Data }
private final class TodayHTTPRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
struct TodayURLTransport: TodayHTTPTransport {
    private let session: URLSession
    init() {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil; config.httpCookieStorage = nil; config.timeoutIntervalForResource = 25
        session = URLSession(configuration: config, delegate: TodayHTTPRedirectPolicy(), delegateQueue: nil)
    }
    func data(_ url: URL) async throws -> Data {
        try Task.checkCancellation()
        guard url.scheme == "https", ["api.open-meteo.com", "geocoding-api.open-meteo.com"].contains(url.host ?? "") else { throw TodayContextError.unavailable }
        do {
            let (bytes, response) = try await session.bytes(for: URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 18))
            defer { bytes.task.cancel() }
            guard let response = response as? HTTPURLResponse else { throw TodayContextError.invalidData }
            if response.statusCode == 429 { throw TodayContextError.rateLimited }
            guard response.statusCode == 200, response.expectedContentLength <= 512_000 else { throw TodayContextError.network }
            var data = Data()
            for try await byte in bytes {
                guard data.count < 512_000 else { throw TodayContextError.invalidData }
                data.append(byte)
            }
            return data
        } catch is CancellationError { throw CancellationError() }
        catch let error as TodayContextError { throw error }
        catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw error.code == .timedOut ? TodayContextError.timeout : TodayContextError.network
        } catch { throw TodayContextError.network }
    }
}

protocol TodayWeatherProviding: Sendable {
    func weather(location: TodayLocation, now: Date) async throws -> TodayWeatherContext
}
actor TodayOpenMeteoProvider: TodayWeatherProviding {
    private let transport: any TodayHTTPTransport
    init(transport: any TodayHTTPTransport = TodayURLTransport()) { self.transport = transport }
    func weather(location: TodayLocation, now: Date) async throws -> TodayWeatherContext {
        guard location.isValid else { throw TodayContextError.locationRequired }
        var url = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        url.queryItems = [
            .init(name: "latitude", value: String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), location.latitude)),
            .init(name: "longitude", value: String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), location.longitude)),
            .init(name: "current", value: "temperature_2m,apparent_temperature,weather_code,precipitation_probability"),
            .init(name: "hourly", value: "temperature_2m,precipitation_probability,weather_code"),
            .init(name: "daily", value: "temperature_2m_max,temperature_2m_min,precipitation_probability_max"),
            .init(name: "temperature_unit", value: "celsius"), .init(name: "timezone", value: "auto"),
            .init(name: "timeformat", value: "unixtime"), .init(name: "forecast_days", value: "2"), .init(name: "forecast_hours", value: "12")]
        return try Self.decode(try await transport.data(url.url!), location: location, now: now)
    }

    static func decode(_ data: Data, location: TodayLocation, now: Date) throws -> TodayWeatherContext {
        struct Payload: Decodable {
            struct Current: Decodable { let time: Double; let temperature_2m: Double?; let apparent_temperature: Double?; let weather_code: Int?; let precipitation_probability: Double? }
            struct Daily: Decodable { let time: [Double]; let temperature_2m_max: [Double?]?; let temperature_2m_min: [Double?]?; let precipitation_probability_max: [Double?]? }
            struct Hourly: Decodable { let time: [Double]; let temperature_2m: [Double?]?; let precipitation_probability: [Double?]?; let weather_code: [Int?]? }
            let timezone: String; let current: Current; let daily: Daily?; let hourly: Hourly?
        }
        guard data.count <= 512_000, let payload = try? JSONDecoder().decode(Payload.self, from: data),
              TimeZone(identifier: payload.timezone) != nil, payload.current.time.isFinite,
              abs(Date(timeIntervalSince1970: payload.current.time).timeIntervalSince(now)) < 21_600 else { throw TodayContextError.invalidData }
        func value<T>(_ values: [T?]?, _ index: Int) -> T? { guard let values, values.indices.contains(index) else { return nil }; return values[index] }
        var hours: [TodayWeatherContext.Hour] = []
        if let hourly = payload.hourly {
            guard hourly.time.count <= 72 else { throw TodayContextError.invalidData }
            for (index, time) in hourly.time.enumerated() where time >= now.timeIntervalSince1970 && time < now.addingTimeInterval(12 * 3600).timeIntervalSince1970 {
                hours.append(.init(timestamp: Date(timeIntervalSince1970: time), temperatureCelsius: value(hourly.temperature_2m, index),
                                   precipitationProbability: value(hourly.precipitation_probability, index).map { $0 / 100 }, conditionCode: value(hourly.weather_code, index)))
            }
        }
        let weather = TodayWeatherContext(source: .weather, provider: "Open-Meteo", locationName: location.name, timeZoneIdentifier: payload.timezone,
                                          collectedAt: now, validAt: Date(timeIntervalSince1970: payload.current.time),
                                          temperatureCelsius: payload.current.temperature_2m, apparentTemperatureCelsius: payload.current.apparent_temperature,
                                          highCelsius: value(payload.daily?.temperature_2m_max, 0), lowCelsius: value(payload.daily?.temperature_2m_min, 0),
                                          precipitationProbability: payload.current.precipitation_probability.map { $0 / 100 },
                                          todayPrecipitationProbability: value(payload.daily?.precipitation_probability_max, 0).map { $0 / 100 },
                                          conditionCode: payload.current.weather_code, nearTerm: Array(hours.prefix(12)), alerts: nil,
                                          attribution: "Weather data by Open-Meteo · CC BY 4.0. Model forecasts; alerts are not supplied.")
        let numbers = [weather.temperatureCelsius, weather.apparentTemperatureCelsius, weather.highCelsius, weather.lowCelsius] + weather.nearTerm.map(\.temperatureCelsius)
        guard numbers.compactMap({ $0 }).allSatisfy({ $0.isFinite && (-150...100).contains($0) }),
              ([weather.precipitationProbability, weather.todayPrecipitationProbability] + hours.map(\.precipitationProbability)).compactMap({ $0 }).allSatisfy({ (0...1).contains($0) }),
              weather.temperatureCelsius != nil || !weather.nearTerm.isEmpty else { throw TodayContextError.invalidData }
        return weather
    }

    func cities(_ query: String) async throws -> [TodayLocation] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...100).contains(query.count) else { return [] }
        var url = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        url.queryItems = [.init(name: "name", value: query), .init(name: "count", value: "6"), .init(name: "language", value: Locale.current.language.languageCode?.identifier ?? "en"), .init(name: "format", value: "json")]
        struct Response: Decodable {
            struct City: Decodable { let name: String; let latitude: Double; let longitude: Double; let country: String?; let admin1: String? }
            let results: [City]?
        }
        let data = try await transport.data(url.url!)
        guard let result = try? JSONDecoder().decode(Response.self, from: data) else { throw TodayContextError.invalidData }
        var seen = Set<String>()
        return (result.results ?? []).prefix(6).map { city -> TodayLocation in
            .init(name: [city.name, city.admin1, city.country].compactMap { $0 }.joined(separator: ", "), latitude: city.latitude, longitude: city.longitude)
        }.filter { $0.isValid && seen.insert($0.id).inserted }
    }
}

actor TodayWeatherSource: TodayDataSource {
    nonisolated let id = TodaySourceID.weather
    private let provider: any TodayWeatherProviding
    private let locationProvider: any TodayLocationProviding
    private var cached: (key: String, weather: TodayWeatherContext)?
    private var generation = 0
    private var retryNotBefore: Date?
    private var configuration: TodayPrivacySettings?
    init(provider: any TodayWeatherProviding, location: any TodayLocationProviding) { self.provider = provider; self.locationProvider = location }
    func clear() async { generation += 1; cached = nil; retryNotBefore = nil }
    func configure(_ policy: TodayPrivacySettings, revision: Int) async {
        if !policy.enabled(id) || configuration?.manualLocation != policy.manualLocation || configuration?.locationMode != policy.locationMode || configuration?.weatherProviderConsent != policy.weatherProviderConsent { await clear() }
        configuration = policy
    }
    func collect(_ request: TodaySourceRequest) async -> TodaySourceResult {
        guard !Task.isCancelled else { return .status(id, .unavailable, "Weather refresh canceled.") }
        guard request.policy.weatherProviderConsent else { return .status(id, .permissionRequired, "Confirm Open-Meteo use for personal, non-commercial weather in Today settings.") }
        if request.policy.locationMode == .manual, cached?.key != request.policy.manualLocation?.id { cached = nil }
        if request.policy.locationMode == .approximateDevice, await locationProvider.permission() != .authorized {
            cached = nil
            return .status(id, .permissionRequired, "Location is not granted. Choose a city instead, or change access in System Settings.")
        }
        do {
            let location: TodayLocation
            if request.policy.locationMode == .manual {
                guard let manual = request.policy.manualLocation, manual.isValid else { throw TodayContextError.locationRequired }; location = manual
            } else { location = try await locationProvider.locationIfAuthorized() }
            let key = location.id
            if cached?.key != key { cached = nil }
            if let cached, cached.key == key {
                let age = request.now.timeIntervalSince(cached.weather.collectedAt)
                var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: cached.weather.timeZoneIdentifier) ?? .gmt
                if age >= 0 && age < Double(request.policy.weatherRefreshMinutes * 60) && !request.forceRefresh && calendar.isDate(cached.weather.collectedAt, inSameDayAs: request.now) {
                    return result(cached.weather, stale: false)
                }
            }
            if let retryNotBefore, request.now < retryNotBefore {
                if let cached, cached.key == key, (0...21_600).contains(request.now.timeIntervalSince(cached.weather.collectedAt)) { return result(cached.weather, stale: true) }
                return .status(id, .failed, "Weather refresh is paused briefly after a provider or network error. Try later.")
            }
            let expected = generation
            let weather = try await provider.weather(location: location, now: request.now)
            try Task.checkCancellation()
            guard expected == generation else { throw CancellationError() }
            cached = (key, weather); retryNotBefore = nil
            return result(weather, stale: false)
        } catch {
            if error is CancellationError { return .status(id, .unavailable, "Weather refresh canceled.") }
            retryNotBefore = request.now.addingTimeInterval((error as? TodayContextError) == nil ? 60 : 300)
            if let cached, (0...21_600).contains(request.now.timeIntervalSince(cached.weather.collectedAt)) { return result(cached.weather, stale: true) }
            let message = (error as? TodayContextError)?.localizedDescription ?? "Weather is unavailable. Other sources can still work."
            return .status(id, error as? TodayContextError == .locationRequired ? .permissionRequired : .failed, message)
        }
    }
    private func result(_ weather: TodayWeatherContext, stale: Bool) -> TodaySourceResult {
        var result = TodaySourceResult.status(id, stale ? .stale : .ready, stale ? "Cached forecast; the latest refresh did not succeed. Check its timestamp." : "Open-Meteo model forecast. Weather alerts are not supplied.", now: weather.collectedAt, count: 1)
        result.weather = weather; return result
    }
}

enum TodayWeatherCondition {
    static func display(_ code: Int?) -> (name: String, symbol: String) {
        switch code {
        case 0: ("Clear", "sun.max.fill")
        case 1, 2: ("Partly cloudy", "cloud.sun.fill")
        case 3: ("Overcast", "cloud.fill")
        case 45, 48: ("Fog", "cloud.fog.fill")
        case 51, 53, 55: ("Drizzle", "cloud.drizzle.fill")
        case 56, 57, 66, 67: ("Freezing rain", "cloud.sleet.fill")
        case 61, 63, 65, 80, 81, 82: ("Rain", "cloud.rain.fill")
        case 71, 73, 75, 77, 85, 86: ("Snow", "cloud.snow.fill")
        case 95, 96, 99: ("Thunderstorm", "cloud.bolt.rain.fill")
        default: ("Conditions not supplied", "thermometer.medium")
        }
    }
}
