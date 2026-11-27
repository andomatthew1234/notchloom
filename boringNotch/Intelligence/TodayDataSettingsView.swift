import SwiftUI
import AppKit

extension Notification.Name { static let todaySettingsRequested = Self("NotchloomTodaySettingsRequested") }
extension Notification.Name { static let todayModelsSettingsRequested = Self("NotchloomTodayModelsSettingsRequested") }

enum TodayPermissionLinks {
    static func open(_ source: TodaySourceID) {
        let anchor = source == .calendar ? "Privacy_Calendars" : source == .notifications ? "Privacy_Accessibility" : "Privacy_LocationServices"
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?" + anchor) { NSWorkspace.shared.open(url) }
    }
}

struct TodayAlignedSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 16) {
            configuration.label
            Spacer(minLength: 12)
            Toggle(isOn: configuration.$isOn) { EmptyView() }.labelsHidden().toggleStyle(.switch)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TodayDataSettingsView: View {
    @ObservedObject var controller: TodayContextController
    var briefings: TodayBriefingCoordinator? = nil
    @State private var inspecting = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                TodaySettingsCard("Your day, your choice", symbol: "sun.horizon") {
                    Text("Bring together selected local information. Sending it to Gemini requires separate briefing consent.").foregroundStyle(.secondary)
                    Toggle("Use local Today data", isOn: Binding(get: { controller.configured }, set: { enabled in
                        if enabled && !controller.settings.setupCompleted { controller.showingSetup = true }
                        else { controller.edit { $0.collectionEnabled = enabled } }
                    })).toggleStyle(TodayAlignedSwitchStyle())
                    if !controller.settings.setupCompleted { Button("Set up Today…") { controller.showingSetup = true } }
                }
                TodaySourceControls(controller: controller, policy: Binding(get: { controller.settings }, set: controller.update))
                    .disabled(!controller.configured)
                if let briefings { TodayBriefingPrivacyControls(briefings: briefings) }
                TodaySettingsCard("Privacy & local context", symbol: "hand.raised") {
                    Text("Only selected sources are collected. Calendar notes and reminders are never read. Calendar events and notification excerpts stay in memory; closing Today releases its snapshot. Newly observed notification excerpts expire after 30 minutes, with a maximum of 20.")
                    Text("Weather uses Open-Meteo with separate consent. A Gemini briefing sends only a minimized context after you allow it in Today. You can inspect the exact outgoing context before allowing it.").foregroundStyle(.secondary)
                    HStack {
                        Button("Refresh") { controller.refresh(force: true) }.disabled(controller.busy || !controller.configured)
                        Button("View collected context") { inspecting = true }.disabled(!controller.configured)
                        Button("Clear cached data") { controller.clearCachedData() }
                    }
                    if let message = controller.message { Text(message).foregroundStyle(.secondary) }
                }
            }.padding(24).frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
        }
        .background(ScrollGestureExclusionArea())
        .sheet(isPresented: $controller.showingSetup) { TodaySetupView(controller: controller).frame(width: 600, height: 610).padding(20).background(.black) }
        .sheet(isPresented: $inspecting) { TodayContextInspector(controller: controller, onBack: { inspecting = false }, briefings: briefings).frame(width: 680, height: 580).padding(20).background(.black) }
        .onAppear { controller.beginPresentation() }
        .onDisappear { controller.endPresentation(); controller.cancelCitySearch() }
    }
}

struct TodaySettingsCard<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: Content
    init(_ title: String, symbol: String, @ViewBuilder content: () -> Content) { self.title = title; self.symbol = symbol; self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: symbol).font(.system(size: 15, weight: .semibold))
            content.font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 17))
            .overlay(RoundedRectangle(cornerRadius: 17).strokeBorder(.white.opacity(0.07)))
    }
}

/// Shared source controls. Setup edits a draft; Settings edits the persisted policy.
struct TodaySourceControls: View {
    @ObservedObject var controller: TodayContextController
    @Binding var policy: TodayPrivacySettings
    var showChoices = true
    @State private var query = ""
    @State private var coordinateName = ""
    @State private var latitude = ""
    @State private var longitude = ""
    @State private var coordinatesExpanded = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if showChoices {
                TodaySettingsCard("Sources", symbol: "square.stack.3d.up") {
                    Toggle("Date & time · works offline", isOn: $policy.dateTimeEnabled)
                    Toggle("Weather · city-level forecasts", isOn: $policy.weatherEnabled)
                    Toggle("Calendar · upcoming events only", isOn: $policy.calendarEnabled)
                    Toggle("Notifications · newly observed banner excerpts", isOn: $policy.notificationsEnabled)
                    Text("Each optional source starts off. You can use Today with all of them off.").foregroundStyle(.secondary)
                }.toggleStyle(TodayAlignedSwitchStyle())
            }
            if policy.weatherEnabled {
                TodaySettingsCard("Weather", symbol: "cloud.sun") {
                    Text("Open-Meteo’s free endpoint supports personal, noncommercial use. It receives your city search or approximate coordinates to provide forecasts. It does not supply weather alerts here.").foregroundStyle(.secondary)
                    Link("Provider, licence & terms", destination: URL(string: "https://open-meteo.com/en/terms")!)
                    Toggle("Allow weather requests to Open-Meteo", isOn: $policy.weatherProviderConsent).toggleStyle(TodayAlignedSwitchStyle())
                    if policy.weatherProviderConsent { weatherControls }
                }
            }
            if policy.calendarEnabled {
                TodaySettingsCard("Calendar", symbol: "calendar") {
                    permissionRow(source: .calendar, state: controller.calendarPermission, request: { await controller.requestCalendar() })
                    Text("macOS calls this Full Calendar Access; no read-only grant exists on this version. Today only reads events and never changes them or reads notes.").foregroundStyle(.secondary)
                    if controller.calendarPermission == .authorized {
                        Toggle("Use all calendars", isOn: $policy.allCalendars).toggleStyle(TodayAlignedSwitchStyle())
                        if !policy.allCalendars {
                            if controller.calendars.isEmpty { Text("No calendars are available. An empty selection collects no events.").foregroundStyle(.secondary) }
                            ForEach(controller.calendars) { calendar in
                                Toggle(calendar.title, isOn: Binding(get: { policy.selectedCalendarIDs.contains(calendar.id) }, set: { selected in
                                    if selected { policy.selectedCalendarIDs.insert(calendar.id) } else { policy.selectedCalendarIDs.remove(calendar.id) }
                                })).toggleStyle(.checkbox)
                            }
                        }
                    }
                    Picker("Tomorrow lookahead", selection: $policy.lookaheadHours) {
                        Text("Today only").tag(0); Text("Until 6 am tomorrow").tag(6); Text("Until noon tomorrow").tag(12)
                    }
                    Toggle("Include event locations", isOn: $policy.includeEventLocations).toggleStyle(TodayAlignedSwitchStyle())
                    Toggle("Include event website / meeting URLs", isOn: $policy.includeMeetingURLs).toggleStyle(TodayAlignedSwitchStyle())
                    Text("Up to 40 upcoming occurrences, including all-day events. Links never open automatically.").foregroundStyle(.secondary)
                }.task { await controller.loadCalendarOptions(allowSetup: true) }
            }
            if policy.notificationsEnabled {
                TodaySettingsCard("Notifications", symbol: "bell") {
                    Text(notificationDescription).foregroundStyle(.secondary)
                    Text("Today reuses the existing Accessibility reader for visible banners from apps macOS exposes. Some apps and protected content cannot be captured. There is no complete history, database access or screen capture. Only new banners after opt-in are eligible; excerpts stay in memory for 30 minutes.")
                    if controller.notificationCapability == .permissionRequired { Button("Open Accessibility settings") { TodayPermissionLinks.open(.notifications) } }
                    if controller.notificationCapability == .mirroringOff { Text("Enable banner mirroring in Settings → Choose what shows in the notch → Notifications if you want this source. Today will not enable it for you.").foregroundStyle(.secondary) }
                }
            }
        }
    }
    private var weatherControls: some View {
        VStack(alignment: .leading, spacing: 13) {
            Picker("Location", selection: $policy.locationMode) {
                Text("Choose a city").tag(TodayPrivacySettings.LocationMode.manual)
                Text("Approximate device location").tag(TodayPrivacySettings.LocationMode.approximateDevice)
            }.pickerStyle(.segmented)
            if policy.locationMode == .manual {
                if let city = policy.manualLocation { Label(city.name, systemImage: "mappin.and.ellipse").fontWeight(.medium) }
                HStack {
                    TextField("City and country", text: $query).textFieldStyle(.roundedBorder)
                    Button(controller.searching ? "Searching…" : "Search") { controller.searchCity(query, consent: policy.weatherProviderConsent) }.disabled(controller.searching || query.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
                }
                ForEach(controller.cities) { city in Button(city.name) { policy.manualLocation = city; controller.cancelCitySearch() }.buttonStyle(.bordered) }
                DisclosureGroup("Enter approximate coordinates instead", isExpanded: $coordinatesExpanded) {
                    VStack(spacing: 8) {
                        TextField("Location name", text: $coordinateName)
                        HStack { TextField("Latitude", text: $latitude); TextField("Longitude", text: $longitude) }
                        Button("Use location") {
                            if let lat = Double(latitude), let lon = Double(longitude) { let city = TodayLocation(name: coordinateName, latitude: lat, longitude: lon); if city.isValid { policy.manualLocation = city } }
                        }.disabled(manualLocation == nil)
                    }.textFieldStyle(.roundedBorder).padding(.top, 8)
                }
            } else {
                permissionRow(source: .weather, state: controller.locationPermission, request: { await controller.requestLocation() })
                Text("One coarse location fix when weather needs refreshing. Coordinates are rounded to 2 decimal places. No continuous location tracking.").foregroundStyle(.secondary)
            }
            Picker("Temperature", selection: $policy.temperatureUnit) {
                Text("System").tag(TodayPrivacySettings.TemperatureUnit.system); Text("Celsius").tag(TodayPrivacySettings.TemperatureUnit.celsius); Text("Fahrenheit").tag(TodayPrivacySettings.TemperatureUnit.fahrenheit)
            }
            Picker("Weather cache", selection: $policy.weatherRefreshMinutes) { ForEach([15, 30, 60, 120], id: \.self) { Text("\($0) minutes").tag($0) } }
            Text("Refresh happens when needed while Today is open, not on a background timer. Failed refreshes may show a clearly marked cached forecast for up to six hours.").foregroundStyle(.secondary)
            if let message = controller.message { Text(message).foregroundStyle(.secondary) }
        }
        .onChange(of: policy.weatherProviderConsent) { _, allowed in if !allowed { controller.cancelCitySearch() } }
        .onDisappear { controller.cancelCitySearch() }
    }
    private var manualLocation: TodayLocation? {
        guard let lat = Double(latitude), let lon = Double(longitude) else { return nil }
        let city = TodayLocation(name: coordinateName.trimmingCharacters(in: .whitespaces), latitude: lat, longitude: lon)
        return city.isValid ? city : nil
    }
    @ViewBuilder private func permissionRow(source: TodaySourceID, state: TodayPermissionState, request: @escaping () async -> Void) -> some View {
        HStack {
            Label(state == .authorized ? "Connected" : state == .notDetermined ? "Not requested" : "Access not granted", systemImage: state == .authorized ? "checkmark.circle" : "lock")
            Spacer()
            if state == .notDetermined { Button(controller.requestingPermission ? "Waiting for macOS…" : "Allow \(source == .calendar ? "Calendar" : "Location")…") { Task { await request() } }.disabled(controller.requestingPermission) }
            else if state != .authorized { Button("Open System Settings") { TodayPermissionLinks.open(source) } }
        }
    }
    private var notificationDescription: String {
        switch controller.notificationCapability {
        case .visibleBanners: "Available for newly observed visible banners. Coverage is incomplete."
        case .permissionRequired: "Accessibility access is required by the existing banner reader."
        case .mirroringOff: "Unavailable while existing banner mirroring is off."
        case .unavailable: "The visible-banner reader is currently unavailable. Other sources still work."
        }
    }
}
