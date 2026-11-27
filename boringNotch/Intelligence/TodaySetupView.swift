import SwiftUI

/// Explicit opt-in; drafts cannot start collectors or silently prompt for OS access.
struct TodaySetupView: View {
    @ObservedObject var controller: TodayContextController
    var onFinished: () -> Void = {}
    var initialStep = 0
    @State private var step = 0
    @State private var draft = TodayPrivacySettings()
    @State private var movingForward = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.todayAnimationsEnabled) private var motionEnabled
    private let titles = ["A little clarity for your day.", "Choose what belongs here.", "Connect, one source at a time.", "Your information stays yours.", "You’re ready."]
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("TODAY", systemImage: "sun.horizon").font(.system(size: 10, weight: .bold)).tracking(2)
                Spacer()
                Text("\(step + 1) OF 5").font(.system(size: 9, weight: .medium)).tracking(1.5).contentTransition(.numericText())
                Button { finish(cancel: true) } label: { Image(systemName: "xmark").frame(width: 28, height: 28).background(.white.opacity(0.1), in: Circle()) }.buttonStyle(.plain).accessibilityLabel("Cancel Today setup")
            }.foregroundStyle(.white.opacity(0.7))
            HStack(spacing: 5) {
                ForEach(0..<5) { index in
                    Capsule().fill(index <= step ? TodayPalette.blue : .white.opacity(0.08)).frame(height: 3)
                }
            }.accessibilityHidden(true)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(titles[step]).font(.system(size: 27, weight: .medium, design: .rounded)).tracking(-0.7)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(24)
                        .background { TodayAtmosphere() }
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.10)))
                    switch step {
                    case 0: intro
                    case 1: choices
                    case 2:
                        TodaySourceControls(controller: controller, policy: $draft, showChoices: false)
                        if !draft.weatherEnabled && !draft.calendarEnabled && !draft.notificationsEnabled { Text("No optional permissions are needed. You can continue with local date and time, or turn every source off.").foregroundStyle(.secondary) }
                    case 3: privacy
                    default: completion
                    }
                }.padding(.bottom, 8).id(step)
                    .transition(reduceMotion || !motionEnabled ? .opacity : .asymmetric(
                        insertion: .opacity.combined(with: .offset(x: movingForward ? 18 : -18)),
                        removal: .opacity.combined(with: .offset(x: movingForward ? -12 : 12))))
            }.scrollIndicators(.hidden).background(ScrollGestureExclusionArea())
            HStack {
                if step > 0 { Button("Back") { move(-1) }.buttonStyle(.bordered) }
                Spacer()
                Button(step == 4 ? "Open Today" : "Continue") {
                    if step == 4 { var value = draft; value.setupCompleted = true; value.collectionEnabled = true; controller.update(value); finish(cancel: false) }
                    else { move(1) }
                }.buttonStyle(.borderedProminent).tint(Color(red: 0.16, green: 0.65, blue: 0.77))
            }.controlSize(.large)
        }
        .foregroundStyle(.white).preferredColorScheme(.dark)
        .onAppear { draft = controller.settings; step = min(4, max(0, initialStep)); Task { await controller.refreshPermissions() } }
        .onDisappear { controller.cancelCitySearch() }
    }
    private var intro: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Today brings together information from your Mac to create a personalized daily briefing.").font(.system(size: 18)).lineSpacing(5)
            Text("First, choose the local sources you want to connect. Gemini briefings use a separate consent step; this local setup does not send your day to Google.").foregroundStyle(.secondary)
            Label("Optional sources start off", systemImage: "checkmark.shield")
            Label("Permissions are requested individually", systemImage: "hand.raised")
        }.font(.system(size: 13)).padding(.horizontal, 5)
    }
    private var choices: some View {
        VStack(spacing: 12) {
            choice("Date & time", detail: "Your local clock, time zone and day. Works offline.", symbol: "clock", selected: $draft.dateTimeEnabled)
            choice("Weather", detail: "Current conditions and forecast for a chosen city or approximate location.", symbol: "cloud.sun", selected: $draft.weatherEnabled)
            choice("Calendar", detail: "Upcoming events in your selected calendars. No notes or changes.", symbol: "calendar", selected: $draft.calendarEnabled)
            choice("Notifications", detail: "Optional excerpts of new visible banners. Incomplete coverage; no history.", symbol: "bell", selected: $draft.notificationsEnabled)
        }
    }
    private var privacy: some View {
        VStack(alignment: .leading, spacing: 17) {
            Label("Local collection ≠ AI transmission", systemImage: "lock.shield").font(.system(size: 17, weight: .semibold))
            Text("Calendar and notification content stays on your Mac. The snapshot is held in memory, not written to a history file. You can inspect it, clear it or disable any source.")
            Text("Weather is different: with your weather consent, Open-Meteo receives city searches or rounded coordinates. No calendar or notification content is sent there.").foregroundStyle(.secondary)
            Text("AI briefings send selected information to Google’s Gemini API only after you allow it in Today. Completing this local setup does not grant that consent.").foregroundStyle(.secondary)
        }.font(.system(size: 13)).lineSpacing(5).padding(.horizontal, 5)
    }
    private var completion: some View {
        VStack(alignment: .leading, spacing: 15) {
            ForEach(TodaySourceID.allCases, id: \.self) { source in
                HStack {
                    Label(source.title, systemImage: source.symbol)
                    Spacer()
                    Text(connectionStatus(source)).foregroundStyle(.secondary)
                }
            }
            Divider()
            Text("You can continue with missing permissions or every optional source off. Change these choices in Settings → Today → Data sources.").font(.system(size: 13)).foregroundStyle(.secondary)
        }.padding(18).background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 17))
    }
    private func choice(_ title: String, detail: String, symbol: String, selected: Binding<Bool>) -> some View {
        Toggle(isOn: selected) {
            HStack(spacing: 14) {
                Image(systemName: symbol).font(.system(size: 23, weight: .light)).foregroundStyle(.cyan).frame(width: 30)
                VStack(alignment: .leading, spacing: 5) { Text(title).font(.system(size: 14, weight: .semibold)); Text(detail).font(.system(size: 12)).foregroundStyle(.secondary) }
            }
        }.toggleStyle(TodayAlignedSwitchStyle()).padding(16).background(.white.opacity(selected.wrappedValue ? 0.09 : 0.045), in: RoundedRectangle(cornerRadius: 17))
            .overlay(RoundedRectangle(cornerRadius: 17).strokeBorder(TodayPalette.blue.opacity(selected.wrappedValue ? 0.22 : 0.04)))
            .todayHover().todayArrival()
            .animation(reduceMotion || !motionEnabled ? nil : .spring(response: 0.32, dampingFraction: 0.85), value: selected.wrappedValue)
    }
    private func connectionStatus(_ source: TodaySourceID) -> String {
        switch source {
        case .dateTime: return draft.dateTimeEnabled ? "Ready · offline" : "Off"
        case .weather: return !draft.weatherEnabled ? "Off" : !draft.weatherProviderConsent ? "Consent needed" : draft.locationMode == .manual ? (draft.manualLocation == nil ? "Choose a city" : "City selected · ready to fetch") : (controller.locationPermission == .authorized ? "Location authorized · ready to fetch" : "Location not granted")
        case .calendar: return !draft.calendarEnabled ? "Off" : controller.calendarPermission == .authorized ? "Connected" : "Access not granted"
        case .notifications: return !draft.notificationsEnabled ? "Off" : controller.notificationCapability == .visibleBanners ? "New visible banners only" : "Currently unavailable"
        }
    }
    private func move(_ amount: Int) {
        movingForward = amount > 0
        withAnimation(reduceMotion || !motionEnabled ? nil : .spring(response: 0.42, dampingFraction: 0.92)) { step += amount }
    }
    private func finish(cancel: Bool) { controller.cancelCitySearch(); controller.showingSetup = false; onFinished() }
}

/// Read-only handoff hint. The actual macOS permission alert owns focus and clicks.
struct TodayLocationPermissionNotice: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "location.fill").font(.system(size: 10, weight: .medium)).foregroundStyle(.cyan.opacity(0.85))
            Text("Select Allow to continue").font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .allowsHitTesting(false)
    }
}

/// Compact silhouette leaves the physical camera area clear and stays anchored at the screen top.
enum TodayLocationPermissionGeometry {
    static func panelSize(full: CGSize, closed: CGSize) -> CGSize {
        CGSize(width: min(full.width, max(374, closed.width + 96)), height: min(full.height, max(68, closed.height + 34)))
    }
    static func hintTop(closedHeight: CGFloat) -> CGFloat { max(24, closedHeight) + 5 }
}
