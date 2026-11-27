import AppKit
import SwiftUI

actor TestCalendar: TodayCalendarProviding {
    var state: TodayPermissionState = .authorized
    var reads = 0; var prompts = 0; var calendarListReads = 0
    var items: [TodayCalendarItem] = []
    func permission() -> TodayPermissionState { state }
    func requestPermission() -> TodayPermissionState { prompts += 1; return state }
    func calendars() -> [TodayCalendarOption] { calendarListReads += 1; return [.init(id: "work", title: "Work"), .init(id: "personal", title: "Personal")] }
    func events(_ request: TodaySourceRequest) -> [TodayCalendarItem] { reads += 1; return items }
    func setState(_ state: TodayPermissionState) { self.state = state }
    func setItems(_ items: [TodayCalendarItem]) { self.items = items }
}
actor TestLocation: TodayLocationProviding {
    var state: TodayPermissionState = .denied
    var fixes = 0; var prompts = 0
    func permission() -> TodayPermissionState { state }
    func requestPermission() -> TodayPermissionState { prompts += 1; return state }
    func locationIfAuthorized() throws -> TodayLocation { fixes += 1; guard state == .authorized else { throw TodayContextError.permission }; return .init(name: "Test city", latitude: 52.52, longitude: 13.41) }
    func setState(_ state: TodayPermissionState) { self.state = state }
}
actor TestWeather: TodayWeatherProviding {
    var calls = 0; var fail = false
    func setFail(_ value: Bool) { fail = value }
    func weather(location: TodayLocation, now: Date) throws -> TodayWeatherContext {
        calls += 1; if fail { throw TodayContextError.network }
        return try TodayOpenMeteoProvider.decode(weatherFixture(now), location: location, now: now)
    }
}
actor TestTransport: TodayHTTPTransport {
    var urls: [URL] = []
    let payload: Data
    init(_ payload: Data) { self.payload = payload }
    func data(_ url: URL) -> Data { urls.append(url); return payload }
}
actor CountSource: TodayDataSource {
    nonisolated let id: TodaySourceID
    var calls = 0; var clears = 0
    let delay: Int
    init(_ id: TodaySourceID, delay: Int = 0) { self.id = id; self.delay = delay }
    func collect(_ request: TodaySourceRequest) async -> TodaySourceResult {
        calls += 1
        if delay > 0 { try? await Task.sleep(for: .milliseconds(delay)) }
        if id == .dateTime { return await TodayDateTimeSource().collect(request) }
        return .status(id, .failed, "Synthetic source failure")
    }
    func clear() async { clears += 1 }
}
actor UpdateCount { var value = 0; func add() { value += 1 } }
func weatherFixture(_ now: Date, temperature: Double = 18.5) -> Data {
    let seconds = now.timeIntervalSince1970
    return try! JSONSerialization.data(withJSONObject: ["timezone": "Europe/Berlin", "current": ["time": seconds, "temperature_2m": temperature, "apparent_temperature": 17.0, "weather_code": 61, "precipitation_probability": 30], "daily": ["time": [seconds], "temperature_2m_max": [21], "temperature_2m_min": [12], "precipitation_probability_max": [65]], "hourly": ["time": [seconds + 3600, seconds + 7200], "temperature_2m": [19, 20], "precipitation_probability": [40, 60], "weather_code": [61, 3]]])
}
func testPolicy() -> TodayPrivacySettings { var policy = TodayPrivacySettings(); policy.collectionEnabled = true; policy.setupCompleted = true; return policy }
func request(_ policy: TodayPrivacySettings, now: Date) -> TodaySourceRequest { .init(policy: policy, now: now, timeZoneIdentifier: "Europe/Berlin", localeIdentifier: "en_GB") }
func event(_ id: String, now: Date, offset: Double, calendar: String = "work", allDay: Bool = false, recurring: Bool = false) -> TodayCalendarItem {
    .init(id: id, source: .calendar, collectedAt: now, eventIdentifier: id, title: "Synthetic event " + id, start: now.addingTimeInterval(offset), end: now.addingTimeInterval(offset + 3600), isAllDay: allDay, calendarName: "Work", calendarID: calendar, location: nil, meetingURL: nil, timeZoneIdentifier: "Europe/Berlin", updatedAt: now, recurring: recurring)
}

@main struct TodayContextTests {
    @MainActor static func main() async throws {
        var checks = 0
        func check(_ value: Bool, _ label: String) { precondition(value, label); checks += 1 }
        func rejects(_ label: String, _ body: () throws -> Void) { do { try body(); preconditionFailure(label) } catch { checks += 1 } }
        let iso = ISO8601DateFormatter()
        let now = iso.date(from: "2026-11-20T11:00:00Z")!
        let berlin = TimeZone(identifier: "Europe/Berlin")!
        let ny = TimeZone(identifier: "America/New_York")!
        let london = TimeZone(identifier: "Europe/London")!
        let locale = Locale(identifier: "en_GB")
        let beforeDST = TodayDateTimeContext.make(now: iso.date(from: "2026-03-08T06:59:00Z")!, zone: ny, locale: locale)
        let afterDST = TodayDateTimeContext.make(now: iso.date(from: "2026-03-08T07:01:00Z")!, zone: ny, locale: locale)
        check(beforeDST.localTime == "01:59:00" && afterDST.localTime == "03:01:00", "DST skips nonexistent local hour")
        check(beforeDST.utcOffsetSeconds == -18000 && afterDST.utcOffsetSeconds == -14400, "DST offsets change")
        let repeated = TodayDateTimeContext.make(now: iso.date(from: "2026-11-01T06:30:00Z")!, zone: ny, locale: locale)
        check(repeated.localISO8601.hasSuffix("-05:00"), "Repeated autumn hour carries offset")
        let local = TodayDateTimeContext.make(now: now, zone: berlin, locale: locale)
        check(local.localDate == "2026-11-20" && local.weekday == "Friday", "Local date and weekday")
        check(local.localTime == "12:00:00" && local.period == .afternoon, "Time classification")
        check(TodayDateTimeContext.make(now: now, zone: ny, locale: locale).localTime != local.localTime, "Time zone changes honored")
        check(TodayDateTimeContext.make(now: now, zone: berlin, locale: Locale(identifier: "fr_FR")).weekday == "vendredi", "Locale changes honored")
        check(TodayDateTimeContext.make(now: iso.date(from: "2026-11-20T23:30:00Z")!, zone: berlin, locale: locale).localDate == "2026-11-21", "Midnight rollover")
        let springWindow = TodayContextValidator.eventWindow(now: iso.date(from: "2026-03-08T12:00:00Z")!, zone: ny, lookahead: 0)
        check(springWindow.duration == 23 * 3600, "Calendar day is 23 hours across spring DST")
        check(TodayContextValidator.eventWindow(now: now, zone: london, lookahead: 99).duration == 36 * 3600, "Lookahead bounded at 12 hours")
        var policy = testPolicy()
        check(!TodayPrivacySettings().collectionEnabled && !TodayPrivacySettings().notificationsEnabled, "No collection and notification opt-in by default")
        check(policy.authorizedSources == [.dateTime], "Only date enabled initially")
        var bounds = policy; bounds.lookaheadHours = 99; bounds.weatherRefreshMinutes = 1
        check(bounds.bounded.lookaheadHours == 12 && bounds.bounded.weatherRefreshMinutes == 15, "Preference bounds")
        let city = TodayLocation(name: "Berlin · test fixture", latitude: 52.523456, longitude: 13.414567)
        check(city.latitude == 52.52 && city.longitude == 13.41, "Coordinates minimized before storage")
        check(!TodayLocation(name: "Invalid", latitude: 100, longitude: 0).isValid, "Invalid coordinates rejected")
        let weather = try TodayOpenMeteoProvider.decode(weatherFixture(now), location: city, now: now)
        check(weather.temperatureCelsius == 18.5 && weather.apparentTemperatureCelsius == 17, "Weather values decoded")
        check(weather.precipitationProbability == 0.3 && weather.todayPrecipitationProbability == 0.65, "Current and daily probabilities distinguished")
        check(weather.highCelsius == 21 && weather.lowCelsius == 12 && weather.nearTerm.count == 2, "High low near-term forecast")
        check(weather.alerts == nil, "Unavailable alerts not fabricated")
        check(TodayWeatherCondition.display(61).symbol == "cloud.rain.fill", "Weather glyph matches actual condition")
        check(TodayWeatherCondition.display(nil).name == "Conditions not supplied", "Unknown condition honest")
        rejects("Malformed weather rejected") { _ = try TodayOpenMeteoProvider.decode(Data("{}".utf8), location: city, now: now) }
        rejects("Impossible temperature rejected") { _ = try TodayOpenMeteoProvider.decode(weatherFixture(now, temperature: 500), location: city, now: now) }
        rejects("Old current forecast rejected") { _ = try TodayOpenMeteoProvider.decode(weatherFixture(now.addingTimeInterval(-7*3600)), location: city, now: now) }
        let transport = TestTransport(weatherFixture(now)); let provider = TodayOpenMeteoProvider(transport: transport)
        _ = try await provider.weather(location: city, now: now)
        let urls = await transport.urls
        check(urls.count == 1 && urls[0].host == "api.open-meteo.com", "Weather endpoint isolated from Gemini")
        check(urls[0].query?.contains("latitude=52.52") == true && urls[0].query?.contains("unixtime") == true, "Coarse coordinates and DST-safe timestamps sent")
        do { _ = try await TodayURLTransport().data(URL(string: "https://generativelanguage.googleapis.com/v1beta/models")!); preconditionFailure("Google transport allowed") } catch { checks += 1 }
        let location = TestLocation(); let weatherBackend = TestWeather()
        let source = TodayWeatherSource(provider: weatherBackend, location: location)
        policy.weatherEnabled = true; policy.weatherProviderConsent = true; policy.manualLocation = city
        await source.configure(policy, revision: 1)
        let first = await source.collect(request(policy, now: now))
        check(first.status.state == .ready && first.weather != nil, "Weather collection works")
        _ = await source.collect(request(policy, now: now.addingTimeInterval(60)))
        check(await weatherBackend.calls == 1, "Fresh cache prevents duplicate network work")
        await weatherBackend.setFail(true)
        let stale = await source.collect(request(policy, now: now.addingTimeInterval(1900)))
        check(stale.status.state == .stale && stale.weather != nil, "Provider failure labels cached weather stale")
        let expired = await source.collect(request(policy, now: now.addingTimeInterval(7*3600)))
        check(expired.status.state == .failed && expired.weather == nil, "Too-old weather removed")
        await weatherBackend.setFail(false); await source.clear()
        _ = await source.collect(request(policy, now: now))
        check(await weatherBackend.calls == 4, "Clear removes cache and backoff")
        var noConsent = policy; noConsent.weatherProviderConsent = false
        let deniedWeather = await source.collect(request(noConsent, now: now))
        check(deniedWeather.status.state == .permissionRequired && deniedWeather.weather == nil, "Provider consent enforced")
        var devicePolicy = policy; devicePolicy.locationMode = .approximateDevice
        let deniedLocation = await source.collect(request(devicePolicy, now: now))
        check(deniedLocation.status.state == .permissionRequired, "Denied location handled")
        let locationFixes = await location.fixes; let locationPrompts = await location.prompts
        check(locationFixes == 0 && locationPrompts == 0, "Collectors never prompt or get unauthorized fixes")
        let forcedBackend = TestWeather(); let forced = TodayWeatherSource(provider: forcedBackend, location: location)
        await forced.configure(policy, revision: 1)
        _ = await forced.collect(request(policy, now: now))
        var forcedRequest = request(policy, now: now.addingTimeInterval(30)); forcedRequest.forceRefresh = true
        _ = await forced.collect(forcedRequest)
        check(await forcedBackend.calls == 2, "Explicit refresh bypasses fresh cache")
        var changed = policy; changed.manualLocation = .init(name: "New city", latitude: 50, longitude: 10)
        await forced.configure(changed, revision: 2)
        let changedCity = await forced.collect(request(changed, now: now))
        check(changedCity.weather?.locationName == "New city", "Location change does not show old city's weather")
        let calendar = TestCalendar()
        var calPolicy = testPolicy(); calPolicy.calendarEnabled = true
        let occurrences = [event("late", now: now, offset: 7200), event("recurring-2", now: now, offset: 3600, recurring: true), event("all-day", now: now, offset: -1800, allDay: true), event("recurring-1", now: now, offset: 0, recurring: true), event("past", now: now, offset: -7200), event("far-future", now: now, offset: 30*86400)]
        await calendar.setItems(occurrences + [occurrences[0]])
        let calendarSource = TodayCalendarSource(provider: calendar)
        let events = await calendarSource.collect(request(calPolicy, now: now))
        check(events.events.map(\.id) == ["all-day", "recurring-1", "recurring-2", "late"], "Occurrences sorted, deduplicated and bounded")
        check(events.events[0].isAllDay && events.events[1].recurring && events.events[2].recurring, "All-day and separate recurring occurrences retained")
        var selected = calPolicy; selected.allCalendars = false
        check(await calendarSource.collect(request(selected, now: now)).events.isEmpty, "Empty selection means no events")
        selected.selectedCalendarIDs = ["work"]
        check(await calendarSource.collect(request(selected, now: now)).events.count == 4, "Selected calendars included")
        await calendar.setState(.denied)
        let deniedCalendar = await calendarSource.collect(request(calPolicy, now: now))
        check(deniedCalendar.status.state == .permissionRequired && deniedCalendar.events.isEmpty, "Calendar denial returns no data")
        check(await calendar.prompts == 0, "No automatic calendar permission prompt")
        let notifications = TodayNotificationSource()
        var notifPolicy = testPolicy(); notifPolicy.notificationsEnabled = true
        await notifications.configure(notifPolicy, revision: 1)
        let unsupported = await notifications.collect(request(notifPolicy, now: now))
        check(unsupported.status.state == .unavailable && unsupported.notifications.isEmpty, "Unsupported banner reader reported honestly")
        await notifications.updateCapability(.visibleBanners, revision: 1)
        for i in 0..<25 {
            await notifications.record(identifier: "synthetic-\(i)", applicationIdentifier: "test.app", applicationName: String(repeating: "a", count: 100), title: String(repeating: "t", count: 200), body: String(repeating: "b", count: 1000), observedAt: now.addingTimeInterval(Double(i)), capabilityRevision: 1, policyRevision: 1)
        }
        let minimized = await notifications.collect(request(notifPolicy, now: now.addingTimeInterval(30)))
        check(minimized.notifications.count == 20, "Notification count capped")
        check(minimized.notifications.allSatisfy { $0.title.count == 120 && $0.body.count == 240 && $0.applicationName.count == 64 && !$0.id.contains("synthetic") }, "Excerpts minimized and identifiers hashed")
        await notifications.record(identifier: "synthetic-24", applicationIdentifier: nil, applicationName: "test", title: "duplicate", body: "", observedAt: now.addingTimeInterval(25))
        check(await notifications.collect(request(notifPolicy, now: now.addingTimeInterval(30))).notifications.count == 20, "Banner duplicate ignored")
        check(await notifications.collect(request(notifPolicy, now: now.addingTimeInterval(1900))).notifications.isEmpty, "Expired banners not returned")
        await notifications.record(identifier: "new", applicationIdentifier: nil, applicationName: "test", title: "", body: "", observedAt: now)
        await notifications.updateCapability(.permissionRequired, revision: 2)
        check(await notifications.collect(request(notifPolicy, now: now)).notifications.isEmpty, "Permission loss purges banners")
        await notifications.updateCapability(.visibleBanners, revision: 3)
        var off = notifPolicy; off.notificationsEnabled = false
        await notifications.configure(off, revision: 2); await notifications.configure(notifPolicy, revision: 3)
        await notifications.record(identifier: "late", applicationIdentifier: nil, applicationName: "test", title: "late", body: "", observedAt: now, capabilityRevision: 3, policyRevision: 1)
        check(await notifications.collect(request(notifPolicy, now: now)).notifications.isEmpty, "Old opt-in epoch cannot record after disable and re-enable")
        let countedDate = CountSource(.dateTime); let countedWeather = CountSource(.weather)
        let engine = TodayContextService(sources: [countedDate, countedWeather])
        let datePolicy = testPolicy(); await engine.configure(datePolicy, revision: 1)
        let updates = UpdateCount()
        let snapshot = try await engine.snapshot(now: now, zone: berlin, locale: locale, revision: 1, onUpdate: { _ in await updates.add() })
        let dateCalls = await countedDate.calls; let weatherCalls = await countedWeather.calls
        check(dateCalls == 1 && weatherCalls == 0, "Disabled sources not invoked")
        check(await updates.value == 1, "Partial update publishes available source")
        check(snapshot.dateTime != nil && !snapshot.externalTransmissionAllowed, "Snapshot local and versioned")
        let encoded = try snapshot.encoded(); let decoded = try TodayContextSnapshot.decode(encoded)
        check(decoded == snapshot, "Snapshot ISO8601 round trip")
        let object = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        check(object["sourceStatus"] is [String: Any] && object["generatedAt"] is String, "JSON status object and ISO date")
        func tampered(_ key: String, _ value: Any) throws { var json = object; json[key] = value; let altered = try TodayContextSnapshot.decode(JSONSerialization.data(withJSONObject: json)); try TodayContextValidator.validate(altered, policy: datePolicy) }
        rejects("Version rejected") { try tampered("version", 9) }
        rejects("External transmission rejected") { try tampered("externalTransmissionAllowed", true) }
        rejects("Authorization mismatch rejected") { try tampered("authorizedSources", ["weather"]) }
        rejects("Missing statuses rejected") { try tampered("sourceStatus", [:]) }
        rejects("Oversized payload rejected") { _ = try TodayContextSnapshot.decode(Data(repeating: 0, count: 256001)) }
        let missing = TodayContextService(sources: [TodayDateTimeSource()]); var missingPolicy = datePolicy; missingPolicy.weatherEnabled = true
        await missing.configure(missingPolicy, revision: 1)
        let missingResult = try await missing.snapshot(now: now, zone: berlin, revision: 1)
        check(missingResult.dateTime != nil && missingResult.sourceStatus[.weather]?.state == .unavailable, "Missing source isolated")
        let slowDate = CountSource(.dateTime, delay: 100)
        let racing = TodayContextService(sources: [slowDate]); await racing.configure(datePolicy, revision: 1)
        let pending = Task { try await racing.snapshot(now: now, revision: 1) }
        try await Task.sleep(for: .milliseconds(15))
        var disabled = datePolicy; disabled.collectionEnabled = false
        await racing.configure(disabled, revision: 2)
        do { _ = try await pending.value; preconditionFailure("Disabled in-flight context published") } catch { checks += 1 }
        let cleared = try await racing.snapshot(now: now, revision: 2)
        check(cleared.dateTime == nil && cleared.authorizedSources.isEmpty, "Disable clears whole context")
        let coalesced = TodayContextService(sources: [CountSource(.dateTime, delay: 50)]); await coalesced.configure(datePolicy, revision: 1)
        async let a = coalesced.snapshot(now: now, revision: 1)
        async let b = coalesced.snapshot(now: now, revision: 1)
        check(try await a == b, "Concurrent refreshes coalesce")
        // Controller persistence and permission revocation use synthetic providers, never the user's grants.
        let suite = "notchloom.today.tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let ctlCal = TestCalendar(); let ctlLoc = TestLocation()
        let ctlService = TodayContextService(sources: [TodayDateTimeSource(), TodayCalendarSource(provider: ctlCal)])
        let controller = TodayContextController(service: ctlService, calendar: ctlCal, location: ctlLoc, defaults: defaults)
        try await Task.sleep(for: .milliseconds(30))
        let initialReads = await ctlCal.reads; let initialPrompts = await ctlCal.prompts; let initialFixes = await ctlLoc.fixes
        check(initialReads == 0 && initialPrompts == 0 && initialFixes == 0, "Controller initialization never collects private data or prompts")
        await controller.loadCalendarOptions(allowSetup: true)
        check(await ctlCal.calendarListReads == 0, "Disabled collection never reads calendar names")
        await ctlCal.setItems([event("controller-event", now: Date(), offset: 1800)])
        controller.update(calPolicy); controller.beginPresentation()
        for _ in 0..<100 { if controller.snapshot != nil && !controller.busy { break }; try await Task.sleep(for: .milliseconds(10)) }
        check(controller.snapshot?.dateTime != nil && controller.calendarPermission == .authorized && controller.snapshot?.calendarEvents.count == 1, "Configured controller publishes selected local facts")
        let saved = try JSONDecoder().decode(TodayPrivacySettings.self, from: defaults.data(forKey: TodayContextController.settingsKey)!)
        check(saved == calPolicy && !String(data: defaults.data(forKey: TodayContextController.settingsKey)!, encoding: .utf8)!.contains("calendarEvents"), "Only preferences persist")
        await ctlCal.setState(.denied); await controller.refreshPermissions()
        check(controller.snapshot == nil && controller.calendars.isEmpty, "Permission revocation removes published context immediately")
        controller.clearCachedData()
        check(controller.settings == calPolicy && controller.snapshot == nil, "Clearing preserves source choices")
        controller.endPresentation()
        check(controller.snapshot == nil, "Closing releases snapshot")
        controller.refresh(force: true)
        try await Task.sleep(for: .milliseconds(30))
        check(controller.snapshot == nil && !controller.busy, "Late permission callbacks cannot refresh a closed page")
        let localDoc = try TodayContextPresentation.document(snapshot: snapshot, settings: datePolicy, busy: false)
        check(!localDoc.isPreview && localDoc.statusLabel == "LOCAL DATA" && localDoc.footerText!.contains("not been sent"), "Real context explicitly local, no AI text")
        check(TodayContextPresentation.temperature(nil, unit: .celsius) == "Not supplied", "No fabricated missing temperature")
        check(TodayContextPresentation.temperature(0, unit: .fahrenheit) == "32°F", "User temperature units respected")
        check(TodayContextPresentation.dashboardContent(local).weekday == "Friday", "Dashboard date uses real context")
        await renderScreens(controller: controller, document: localDoc)
        print("PASS \(checks) Today context checks. Synthetic providers only; no permission prompts or Gemini requests.")
    }
    @MainActor static func renderScreens(controller: TodayContextController, document: TodayPageDocument) async {
        _ = NSApplication.shared
        let folder = URL(fileURLWithPath: "/tmp/notchloom-today-phase3-review", isDirectory: true)
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for step in [0, 1, 2, 3, 4] {
            let root = TodaySetupView(controller: controller, initialStep: step).padding(20).frame(width: 600, height: 610).background(.black)
            await render(root, name: "setup-\(step)", width: 600, height: 610, folder: folder)
        }
        await render(TodayPageView(document: document, animationsEnabled: false).padding(16).background(.black).preferredColorScheme(.dark), name: "local-page", width: 682, height: 620, folder: folder)
        await render(TodayDataSettingsView(controller: controller).background(Color(white: 0.1)).preferredColorScheme(.dark), name: "data-settings", width: 675, height: 650, folder: folder)
        await render(TodayContextInspector(controller: controller, onBack: {}).padding(20).background(.black), name: "context-inspector", width: 650, height: 580, folder: folder)
        let fixtureTime = Date()
        let cal = TestCalendar(); await cal.setItems([event("example-occurrence", now: fixtureTime, offset: 1800)])
        let banners = TodayNotificationSource(); var policy = testPolicy(); policy.calendarEnabled = true; policy.weatherEnabled = true; policy.notificationsEnabled = true; policy.weatherProviderConsent = true
        policy.manualLocation = .init(name: "Berlin · synthetic example", latitude: 52.52, longitude: 13.41)
        await banners.configure(policy, revision: 1); await banners.updateCapability(.visibleBanners)
        await banners.record(identifier: "synthetic", applicationIdentifier: "test.app", applicationName: "Example app", title: "Synthetic banner", body: "A bounded, local excerpt.", observedAt: fixtureTime)
        let rich = TodayContextService(sources: [TodayDateTimeSource(), TodayCalendarSource(provider: cal), TodayWeatherSource(provider: TestWeather(), location: TestLocation()), banners])
        await rich.configure(policy, revision: 1)
        let snapshot = try! await rich.snapshot(now: fixtureTime, zone: TimeZone(identifier: "Europe/Berlin")!, revision: 1)
        let richDoc = try! TodayContextPresentation.document(snapshot: snapshot, settings: policy, busy: false)
        precondition(richDoc.registry.widgets(for: richDoc.report).count == 3)
        await render(TodayPageView(document: richDoc, animationsEnabled: false).padding(16).background(.black).preferredColorScheme(.dark), name: "all-sources", width: 714, height: 660, folder: folder)
        await render(TodayPageView(document: richDoc, animationsEnabled: false).padding(16).background(.black).preferredColorScheme(.dark), name: "all-sources-narrow", width: 380, height: 550, folder: folder)
        controller.update(policy)
        await render(TodayDataSettingsView(controller: controller).background(Color(white: 0.1)).preferredColorScheme(.dark), name: "all-source-settings", width: 675, height: 650, folder: folder)
        await render(TodaySetupView(controller: controller, initialStep: 2).padding(20).frame(width: 600, height: 610).background(.black), name: "weather-permissions", width: 600, height: 610, folder: folder)
    }
    @MainActor static func render<V: View>(_ view: V, name: String, width: CGFloat, height: CGFloat, folder: URL) async {
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: .init(x: -5000, y: -5000, width: width, height: height), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        host.layoutSubtreeIfNeeded(); try? await Task.sleep(for: .milliseconds(100)); host.layoutSubtreeIfNeeded()
        let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try! bitmap.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent(name + ".png"))
        window.close()
    }
}
