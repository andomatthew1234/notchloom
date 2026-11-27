import Foundation

/// Public documentation example coordinates, never the user's location or preferences.
@main struct TodayWeatherLiveTest {
    static func main() async throws {
        let provider = TodayOpenMeteoProvider()
        let city = TodayLocation(name: "Berlin · public documentation fixture", latitude: 52.52, longitude: 13.41)
        let value = try await provider.weather(location: city, now: Date())
        precondition(value.temperatureCelsius != nil && value.provider == "Open-Meteo" && value.alerts == nil)
        precondition(value.highCelsius != nil && value.lowCelsius != nil && !value.nearTerm.isEmpty)
        let cities = try await provider.cities("Berlin")
        precondition(!cities.isEmpty && cities.allSatisfy(\.isValid))
        print("PASS live Open-Meteo forecast decoded with current, high/low and near-term values; city search decoded. Public Berlin fixture only. No Gemini, local permissions or saved app settings used.")
    }
}
