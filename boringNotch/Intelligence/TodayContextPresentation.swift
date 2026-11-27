import Foundation

/// Deterministic presentation of collected facts. No generated summary or model request.
enum TodayContextPresentation {
    static func document(snapshot: TodayContextSnapshot?, settings: TodayPrivacySettings, busy: Bool, message: String? = nil) throws -> TodayPageDocument {
        if let snapshot { try TodayContextValidator.validate(snapshot, policy: settings) }
        var widgets: [TodayLinkedWidget] = []
        var blocks: [TodayReport.Block] = []
        func paragraph(_ id: String, _ text: String) {
            blocks.append(.init(id: id, type: .paragraph, parts: [.init(type: .text, value: text)]))
        }
        paragraph("local-intro", "These are facts from your selected sources, collected locally. A Gemini briefing has not been generated or requested.")
        if let weather = snapshot?.weather {
            let id = "local-weather"
            let status = snapshot?.sourceStatus[.weather]?.state == .stale ? "Stale · " : ""
            var detail = status + "Forecast valid " + weather.validAt.formatted(date: .abbreviated, time: .shortened)
            if let chance = weather.todayPrecipitationProbability { detail += " · Today's rain chance \(Int((chance * 100).rounded()))%" }
            widgets.append(.init(id: id, title: weather.locationName, linkLabel: weather.locationName,
                                 source: .init(type: .weather, id: "open-meteo"),
                                 content: .weather(temperature: temperature(weather.temperatureCelsius, unit: settings.temperatureUnit),
                                                   condition: TodayWeatherCondition.display(weather.conditionCode).name,
                                                   range: "High \(temperature(weather.highCelsius, unit: settings.temperatureUnit)) · Low \(temperature(weather.lowCelsius, unit: settings.temperatureUnit))"),
                                 conditionSymbol: TodayWeatherCondition.display(weather.conditionCode).symbol, detailNote: detail))
        }
        for event in (snapshot?.calendarEvents ?? []).prefix(6) {
            let formatter = DateFormatter(); formatter.timeZone = TimeZone(identifier: snapshot?.timezone ?? "") ?? .current
            formatter.timeStyle = .short
            var calendar = Calendar.current; calendar.timeZone = formatter.timeZone
            let reference = snapshot?.generatedAt ?? event.collectedAt
            let dayPrefix = calendar.isDate(event.start, inSameDayAs: reference) ? "" : "Tomorrow · "
            let time = event.isAllDay ? "All day" : dayPrefix + formatter.string(from: event.start)
            let duration = event.isAllDay ? "All-day event" : "\(max(1, Int(event.end.timeIntervalSince(event.start) / 60))) min"
            widgets.append(.init(id: event.id, title: event.title, linkLabel: event.title,
                                 source: .init(type: .calendarEvent, id: event.id),
                                 content: .event(time: time, duration: duration, location: [event.calendarName, event.location].compactMap { $0 }.joined(separator: " · ")),
                                 detailNote: "Collected " + event.collectedAt.formatted(date: .omitted, time: .shortened)))
        }
        for banner in (snapshot?.notifications ?? []).prefix(3) {
            widgets.append(.init(id: banner.id, title: banner.title.isEmpty ? banner.applicationName : banner.title,
                                 linkLabel: banner.applicationName, source: .init(type: .notificationSummary, id: banner.id),
                                 content: .message(sender: banner.applicationName + (banner.title.isEmpty ? "" : " · " + banner.title), excerpt: banner.body),
                                 detailNote: "Observed " + banner.observedAt.formatted(date: .omitted, time: .shortened)))
        }
        for source in TodaySourceID.allCases {
            let status = snapshot?.sourceStatus[source]
            let title = source.title
            let text = status?.message ?? (settings.enabled(source) ? (busy ? "Collecting this source…" : "Refresh to collect this source.") : "This source is off.")
            paragraph("status-" + source.rawValue, title + " · " + (status?.state.displayName ?? (settings.enabled(source) ? (busy ? "Loading" : "Not collected") : "Off")) + "\n" + text)
            let linked = widgets.filter { widget in
                switch source { case .weather: return widget.type == .weather; case .calendar: return widget.type == .calendarEvent; case .notifications: return widget.type == .notificationSummary; case .dateTime: return false }
            }
            for widget in linked {
                blocks.append(.init(id: "link-" + widget.id, type: .paragraph, parts: [.init(type: .widgetReference, widgetID: widget.id)]))
            }
            if source == .dateTime, let date = snapshot?.dateTime {
                paragraph("local-date", date.weekday + " · " + date.localDate + " · " + date.localTime + "\n" + date.timeZoneIdentifier)
            }
        }
        if let message { paragraph("local-message", message) }
        let registry = try TodayWidgetRegistry(widgets)
        let report = TodayReport(version: 1, title: "Your day, at a glance.", blocks: blocks,
                                 widgets: widgets.map { .init(id: $0.id, type: $0.type, sourceReference: $0.source) }, scheduledInsights: [])
        return .init(report: try TodayReportValidator.validate(JSONEncoder().encode(report), context: registry.validationContext), registry: registry,
                     eyebrow: snapshot?.dateTime?.weekday.uppercased() ?? "YOUR LOCAL SOURCES", subtitle: "Selected information. Always your choice.", isPreview: false,
                     statusLabel: busy ? "REFRESHING" : "LOCAL DATA", footerText: "Selected local data has not been sent to Gemini. " + (snapshot?.weather?.attribution ?? ""),
                     footerURL: snapshot?.weather == nil ? nil : URL(string: "https://open-meteo.com/"))
    }
    static func temperature(_ value: Double?, unit: TodayPrivacySettings.TemperatureUnit, locale: Locale = .current) -> String {
        guard let value else { return "Not supplied" }
        let fahrenheit = unit == .fahrenheit || unit == .system && locale.measurementSystem == .us
        return "\(Int((fahrenheit ? value * 9 / 5 + 32 : value).rounded()))°\(fahrenheit ? "F" : "C")"
    }
    static func dashboardContent(_ date: TodayDateTimeContext?) -> TodayWidgetContent {
        guard let date, let instant = ISO8601DateFormatter().date(from: date.localISO8601) else { return .init(day: "—", weekday: "Your day", date: "Local sources") }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: date.localeIdentifier); formatter.timeZone = TimeZone(identifier: date.timeZoneIdentifier)
        formatter.setLocalizedDateFormatFromTemplate("d MMMM")
        return .init(day: String(date.localDate.suffix(2)).replacingOccurrences(of: "^0", with: "", options: .regularExpression), weekday: date.weekday, date: formatter.string(from: instant))
    }
}
extension TodaySourceID {
    var title: String { switch self { case .dateTime: "Date & time"; case .weather: "Weather"; case .calendar: "Calendar"; case .notifications: "Notifications" } }
    var symbol: String { switch self { case .dateTime: "clock"; case .weather: "cloud.sun"; case .calendar: "calendar"; case .notifications: "bell" } }
}
extension TodaySourceState {
    var displayName: String { switch self { case .disabled: "Off"; case .permissionRequired: "Permission needed"; default: rawValue.capitalized } }
}
