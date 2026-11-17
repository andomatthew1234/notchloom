//
//  SettingsView.swift
//  boringNotch
//
//  Created by Richard Kunkli on 07/08/2024.
//

import AVFoundation
import Defaults
import EventKit
import KeyboardShortcuts
import LaunchAtLogin
import Sparkle
import SwiftUI

private enum NotchloomTheme {
    static let cyan = Color(red: 0.20, green: 0.91, blue: 0.96)
    static let ink = Color(red: 0.055, green: 0.065, blue: 0.11)
    static let settingsHeader = Color(red: 0.125, green: 0.13, blue: 0.15)
    static let settingsSidebar = Color(red: 0.145, green: 0.15, blue: 0.17)
}

private struct NotchloomSettingsHeader: View {
    let title: String
    let description: String
    let symbol: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(NotchloomTheme.cyan)
                .frame(width: 34, height: 34)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                Text(description)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NotchloomTheme.settingsHeader)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.white.opacity(0.09))
                .frame(height: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

private enum SettingsCategory: String {
    case general, appearance, notchContent, app

    var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .notchContent: "Choose what shows in the notch"
        case .app: "App"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintbrush.pointed"
        case .notchContent: "rectangle.topthird.inset.filled"
        case .app: "app"
        }
    }

    var firstPage: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .notchContent: "QuickApps"
        case .app: "Shortcuts"
        }
    }
}

struct SettingsView: View {
    @State private var selectedTab = "General"
    @State private var expandedCategory: SettingsCategory? = .general
    @State private var accentColorUpdateTrigger = UUID()

    let updaterController: SPUStandardUpdaterController?

    init(updaterController: SPUStandardUpdaterController? = nil) {
        self.updaterController = updaterController
    }

    private var pageInfo: (title: String, description: String, symbol: String) {
        switch selectedTab {
        case "General": return ("General", "Choose where Notchloom appears and how it opens.", "gearshape")
        case "Appearance": return ("Appearance", "Adjust the look of the notch and music player.", "paintbrush.pointed")
        case "Media": return ("Now playing", "Pick your music source, controls, and playback behavior.", "music.note")
        case "NotchHeight": return ("Notch height", "Match the physical notch or choose your own height for each display.", "arrow.up.and.down")
        case "QuickApps": return ("Quick apps", "Choose the apps one click away in the notch.", "square.grid.2x2")
        case "Notifications": return ("Notifications", "See new app banners emerge from the notch.", "bell.badge")
        case "Calendar": return ("Calendar", "Choose which events and reminders appear in the notch.", "calendar")
        case "HUD": return ("Volume, battery & system HUDs", "Choose how system changes appear around the notch.", "slider.horizontal.3")
        case "Battery": return ("Battery notch widget", "Show your Mac’s battery beside the notch and choose its details.", "battery.100.bolt")
        case "Shelf": return ("File shelf", "Keep files handy and choose how to share them.", "square.stack.3d.up")
        case "Shortcuts": return ("Shortcuts", "Set keyboard shortcuts for quick actions.", "keyboard")
        case "Advanced": return ("Advanced", "Fine-tune colors, windows, and display behavior.", "gearshape.2")
        default: return ("About", "Version, updates, and project information.", "info.circle")
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            List {
                HStack(spacing: 10) {
                    Image("NotchloomIcon")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 36, height: 36)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Notchloom")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Your notch, woven in")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
                .accessibilityElement(children: .combine)
                categoryRow(.general)
                categoryRow(.appearance)
                if expandedCategory == .appearance {
                    pageRow("Media", title: "Now playing", symbol: "music.note")
                    pageRow("NotchHeight", title: "Notch height", symbol: "arrow.up.and.down")
                    pageRow("HUD", title: "Volume, battery & system HUDs", symbol: "slider.horizontal.3")
                    pageRow("Battery", title: "Battery notch widget", symbol: "battery.100.bolt")
                }
                categoryRow(.notchContent)
                if expandedCategory == .notchContent {
                    pageRow("QuickApps", title: "Quick apps", symbol: "square.grid.2x2")
                    pageRow("Notifications", title: "Notifications", symbol: "bell.badge")
                    pageRow("Calendar", title: "Calendar", symbol: "calendar")
                    pageRow("Shelf", title: "File shelf", symbol: "square.stack.3d.up")
                }
                categoryRow(.app)
                if expandedCategory == .app {
                    pageRow("Shortcuts", title: "Shortcuts", symbol: "keyboard")
                    pageRow("Advanced", title: "Advanced", symbol: "gearshape.2")
                    pageRow("About", title: "About", symbol: "info.circle")
                }
            }
            .listStyle(SidebarListStyle())
            .scrollContentBackground(.hidden)
            .background(NotchloomTheme.settingsSidebar)
            .safeAreaInset(edge: .bottom) {
                Label("Changes save automatically", systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(NotchloomTheme.settingsSidebar)
            }
            .tint(NotchloomTheme.cyan)
            .accentColor(NotchloomTheme.cyan)
            .frame(width: 265)
            Divider()
            VStack(spacing: 0) {
                NotchloomSettingsHeader(
                    title: pageInfo.title,
                    description: pageInfo.description,
                    symbol: pageInfo.symbol)
                Group {
                switch selectedTab {
                case "General":
                    GeneralSettings()
                case "Appearance":
                    Appearance()
                case "Media":
                    Media()
                case "NotchHeight":
                    NotchHeightSettings()
                case "QuickApps":
                    QuickAppsSettings()
                case "Notifications":
                    NotificationsSettings()
                case "Calendar":
                    CalendarSettings()
                case "HUD":
                    HUD()
                case "Battery":
                    BatteryNotchSettings()
                case "Shelf":
                    Shelf()
                case "Shortcuts":
                    Shortcuts()
                case "Advanced":
                    Advanced()
                case "About":
                    if let controller = updaterController {
                        About(updaterController: controller)
                    } else {
                        // Fallback with a default controller
                        About(
                            updaterController: SPUStandardUpdaterController(
                                startingUpdater: false, updaterDelegate: nil,
                                userDriverDelegate: nil))
                    }
                default:
                    GeneralSettings()
                }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(selectedTab)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .formStyle(.grouped)
        .controlSize(.small)
        .environment(\.defaultMinListRowHeight, 28)
        .frame(minWidth: 900, idealWidth: 940, minHeight: 620, idealHeight: 680)
        .background(NotchloomTheme.ink)
        .tint(NotchloomTheme.cyan)
        .accentColor(NotchloomTheme.cyan)
        .preferredColorScheme(.dark)
        .id(accentColorUpdateTrigger)
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("AccentColorChanged"))) { _ in
            accentColorUpdateTrigger = UUID()
        }
    }

    private func categoryRow(_ category: SettingsCategory) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                expandedCategory = expandedCategory == category ? nil : category
                selectedTab = category.firstPage
            }
        } label: {
            HStack(spacing: 10) {
                Label(category.title, systemImage: category.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if category != .general {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .rotationEffect(.degrees(expandedCategory == category ? 90 : 0))
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 3)
        .listRowBackground(expandedCategory == category ? NotchloomTheme.cyan.opacity(0.10) : Color.clear)
        .accessibilityLabel(category.title)
        .accessibilityHint(category == .general ? "Open General settings" : "Expand settings category")
    }

    private func pageRow(_ page: String, title: String, symbol: String) -> some View {
        Button {
            selectedTab = page
        } label: {
            Label(title, systemImage: symbol)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.leading, 16)
        .padding(.vertical, 3)
        .listRowBackground(selectedTab == page ? NotchloomTheme.cyan.opacity(0.14) : Color.clear)
        .accessibilityAddTraits(selectedTab == page ? .isSelected : [])
    }
}

struct GeneralSettings: View {
    @State private var screens: [(uuid: String, name: String)] = NSScreen.screens.compactMap { screen in
        guard let uuid = screen.displayUUID else { return nil }
        return (uuid, screen.localizedName)
    }
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var coordinator = BoringViewCoordinator.shared

    @Default(.mirrorShape) var mirrorShape
    @Default(.showEmojis) var showEmojis
    @Default(.gestureSensitivity) var gestureSensitivity
    @Default(.minimumHoverDuration) var minimumHoverDuration
    @Default(.showOnAllDisplays) var showOnAllDisplays
    @Default(.automaticallySwitchDisplay) var automaticallySwitchDisplay
    @Default(.enableGestures) var enableGestures
    @Default(.openNotchOnHover) var openNotchOnHover
    

    var body: some View {
        Form {
            NotchBehaviour()

            Section {
                Toggle(isOn: Binding(
                    get: { Defaults[.menubarIcon] },
                    set: { Defaults[.menubarIcon] = $0 }
                )) {
                    Text("Show Notchloom in the menu bar")
                }
                .tint(NotchloomTheme.cyan)
                LaunchAtLogin.Toggle("Launch Notchloom at login")
                Defaults.Toggle(key: .showOnAllDisplays) {
                    Text("Show on all displays")
                }
                .onChange(of: showOnAllDisplays) {
                    NotificationCenter.default.post(
                        name: Notification.Name.showOnAllDisplaysChanged, object: nil)
                }
                if !showOnAllDisplays {
                    Picker("Preferred display", selection: $coordinator.preferredScreenUUID) {
                        ForEach(screens, id: \.uuid) { screen in
                            Text(screen.name).tag(screen.uuid as String?)
                        }
                    }
                    .onChange(of: NSScreen.screens) {
                        screens = NSScreen.screens.compactMap { screen in
                            guard let uuid = screen.displayUUID else { return nil }
                            return (uuid, screen.localizedName)
                        }
                    }
                    Defaults.Toggle(key: .automaticallySwitchDisplay) {
                        Text("Follow the active display")
                    }
                    .onChange(of: automaticallySwitchDisplay) {
                        NotificationCenter.default.post(
                            name: Notification.Name.automaticallySwitchDisplayChanged, object: nil)
                    }
                }
            } header: {
                Text("Launch and displays")
            } footer: {
                Text(showOnAllDisplays
                     ? "Turn off Show on all displays to choose a preferred display."
                     : "Choose a preferred display, or follow the active display automatically.")
            }

            gestureControls()
        }
        .tint(NotchloomTheme.cyan)
        .onChange(of: openNotchOnHover) {
            if !openNotchOnHover {
                enableGestures = true
            }
        }
    }

    @ViewBuilder
    func gestureControls() -> some View {
        Section {
            Defaults.Toggle(key: .enableGestures) {
                Text("Enable gestures")
            }
            if enableGestures {
                Defaults.Toggle(key: .closeGestureEnabled) {
                    Text("Swipe up to close the notch")
                }
                Picker("Gesture sensitivity", selection: $gestureSensitivity) {
                    Text("High").tag(CGFloat(100))
                    Text("Medium").tag(CGFloat(200))
                    Text("Low").tag(CGFloat(300))
                }
            }
        } header: {
            HStack {
                Text("Trackpad gestures")
                customBadge(text: "Beta")
            }
        } footer: {
            Text("Swipe left or right across the open notch to move between Home, Overview, and Shelf when enabled. Swipe up to close it. When hover opening is off, swipe down to open it.")
        }
    }

    @ViewBuilder
    func NotchBehaviour() -> some View {
        Section {
            Defaults.Toggle(key: .openNotchOnHover) {
                Text("Open when the pointer reaches the notch")
            }
            Defaults.Toggle(key: .extendHoverArea) {
                Text("Use a wider hover area")
            }
            Defaults.Toggle(key: .enableHaptics) {
                Text("Use haptic feedback")
            }
            Toggle("Reopen the last tab", isOn: $coordinator.openLastTabByDefault)
            if openNotchOnHover {
                Picker("Hover delay", selection: $minimumHoverDuration) {
                    Text("Instant").tag(TimeInterval(0))
                    ForEach(1...10, id: \.self) { tenths in
                        Text("\(Double(tenths) / 10, specifier: "%.1f") seconds")
                            .tag(TimeInterval(tenths) / 10)
                    }
                }
            }
        } header: {
            Text("Opening and closing")
        } footer: {
            Text("Notchloom opens as soon as you hover by default. Raise the delay if it opens by accident.")
        }
    }
}

struct NotchHeightSettings: View {
    @Default(.notchHeight) private var notchHeight
    @Default(.notchHeightMode) private var notchHeightMode
    @Default(.nonNotchHeight) private var nonNotchHeight
    @Default(.nonNotchHeightMode) private var nonNotchHeightMode

    var body: some View {
        Form {
            Section {
                Picker(
                    selection: $notchHeightMode,
                    label: Text("On a Mac with a notch")
                ) {
                    Text("Match real notch height")
                        .tag(WindowHeightMode.matchRealNotchSize)
                    Text("Match menu bar height")
                        .tag(WindowHeightMode.matchMenuBar)
                    Text("Custom height")
                        .tag(WindowHeightMode.custom)
                }
                .onChange(of: notchHeightMode) {
                    switch notchHeightMode {
                    case .matchRealNotchSize:
                        notchHeight = 38
                    case .matchMenuBar:
                        notchHeight = 44
                    case .custom:
                        notchHeight = 38
                    }
                    NotificationCenter.default.post(
                        name: Notification.Name.notchHeightChanged, object: nil)
                }
                if notchHeightMode == .custom {
                    Slider(value: $notchHeight, in: 15...45, step: 1) {
                        Text("Height: \(notchHeight, specifier: "%.0f") pt")
                    }
                    .onChange(of: notchHeight) {
                        NotificationCenter.default.post(
                            name: Notification.Name.notchHeightChanged, object: nil)
                    }
                }
                Picker("On other displays", selection: $nonNotchHeightMode) {
                    Text("Match menu bar height")
                        .tag(WindowHeightMode.matchMenuBar)
                    Text("Match real notch height")
                        .tag(WindowHeightMode.matchRealNotchSize)
                    Text("Custom height")
                        .tag(WindowHeightMode.custom)
                }
                .onChange(of: nonNotchHeightMode) {
                    switch nonNotchHeightMode {
                    case .matchMenuBar:
                        nonNotchHeight = 24
                    case .matchRealNotchSize:
                        nonNotchHeight = 32
                    case .custom:
                        nonNotchHeight = 32
                    }
                    NotificationCenter.default.post(
                        name: Notification.Name.notchHeightChanged, object: nil)
                }
                if nonNotchHeightMode == .custom {
                    Slider(value: $nonNotchHeight, in: 0...40, step: 1) {
                        Text("Height: \(nonNotchHeight, specifier: "%.0f") pt")
                    }
                    .onChange(of: nonNotchHeight) {
                        NotificationCenter.default.post(
                            name: Notification.Name.notchHeightChanged, object: nil)
                    }
                }
            } header: {
                Text("Notch height")
            } footer: {
                Text("Automatic sizes match the physical notch or menu bar. Choose Custom height to set your own size.")
            }
        }
        .tint(NotchloomTheme.cyan)
    }
}

struct BatteryNotchSettings: View {
    @Default(.showBatteryIndicator) private var showBatteryIndicator

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .showBatteryIndicator) {
                    Text("Show battery beside the notch")
                }
            } header: {
                Text("Battery notch widget")
            } footer: {
                Text("This small battery indicator sits beside the MacBook notch while Notchloom is open. Charging alerts have their own setting under Volume, battery & system HUDs.")
            }
            if showBatteryIndicator {
                Section {
                    Defaults.Toggle(key: .showBatteryPercentage) {
                        Text("Show battery percentage")
                    }
                    Defaults.Toggle(key: .showPowerStatusIcons) {
                        Text("Show charging status icon")
                    }
                } header: {
                    Text("Widget details")
                }
            }
        }
        .tint(NotchloomTheme.cyan)
    }
}

//struct Downloads: View {
//    @Default(.selectedDownloadIndicatorStyle) var selectedDownloadIndicatorStyle
//    @Default(.selectedDownloadIconStyle) var selectedDownloadIconStyle
//    var body: some View {
//        Form {
//            warningBadge("We don't support downloads yet", "It will be supported later on.")
//            Section {
//                Defaults.Toggle(key: .enableDownloadListener) {
//                    Text("Show download progress")
//                }
//                    .disabled(true)
//                Defaults.Toggle(key: .enableSafariDownloads) {
//                    Text("Enable Safari Downloads")
//                }
//                    .disabled(!Defaults[.enableDownloadListener])
//                Picker("Download indicator style", selection: $selectedDownloadIndicatorStyle) {
//                    Text("Progress bar")
//                        .tag(DownloadIndicatorStyle.progress)
//                    Text("Percentage")
//                        .tag(DownloadIndicatorStyle.percentage)
//                }
//                Picker("Download icon style", selection: $selectedDownloadIconStyle) {
//                    Text("Only app icon")
//                        .tag(DownloadIconStyle.onlyAppIcon)
//                    Text("Only download icon")
//                        .tag(DownloadIconStyle.onlyIcon)
//                    Text("Both")
//                        .tag(DownloadIconStyle.iconAndAppIcon)
//                }
//
//            } header: {
//                HStack {
//                    Text("Download indicators")
//                    comingSoonTag()
//                }
//            }
//            Section {
//                List {
//                    ForEach([].indices, id: \.self) { index in
//                        Text("\(index)")
//                    }
//                }
//                .frame(minHeight: 96)
//                .overlay {
//                    if true {
//                        Text("No excluded apps")
//                            .foregroundStyle(Color(.secondaryLabelColor))
//                    }
//                }
//                .actionBar(padding: 0) {
//                    Group {
//                        Button {
//                        } label: {
//                            Image(systemName: "plus")
//                                .frame(width: 25, height: 16, alignment: .center)
//                                .contentShape(Rectangle())
//                                .foregroundStyle(.secondary)
//                        }
//
//                        Divider()
//                        Button {
//                        } label: {
//                            Image(systemName: "minus")
//                                .frame(width: 20, height: 16, alignment: .center)
//                                .contentShape(Rectangle())
//                                .foregroundStyle(.secondary)
//                        }
//                    }
//                }
//            } header: {
//                HStack(spacing: 4) {
//                    Text("Exclude apps")
//                    comingSoonTag()
//                }
//            }
//        }
//        .navigationTitle("Downloads")
//    }
//}

struct HUD: View {
    @EnvironmentObject var vm: BoringViewModel
    @Default(.inlineHUD) var inlineHUD
    @Default(.enableGradient) var enableGradient
    @Default(.optionKeyAction) var optionKeyAction
    @Default(.hudReplacement) var hudReplacement
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @State private var accessibilityAuthorized = false
    
    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .showPowerStatusNotifications) {
                    Text("Show power status notifications")
                }
            } header: {
                Text("Battery power alerts")
            } footer: {
                Text("Show a brief notch alert when the Mac starts or stops charging. This works independently of the battery notch widget and system HUD replacement.")
            }

            Section {
                Defaults.Toggle(key: .hudReplacement) {
                    Text("Replace system HUD")
                }
                if !accessibilityAuthorized {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Accessibility access is required to replace the system HUD.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            Button("Request Accessibility") {
                                XPCHelperClient.shared.requestAccessibilityAuthorization()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(.top, 6)
                }
            } header: {
                Text("System HUD replacement")
            } footer: {
                Text("Replace the macOS volume and brightness overlays with Notchloom’s HUD.")
            }
            
            Section {
                Picker("Option + media key action", selection: $optionKeyAction) {
                    ForEach(OptionKeyAction.allCases) { opt in
                        Text(opt.rawValue).tag(opt)
                    }
                }
                
                Picker("Progress bar style", selection: $enableGradient) {
                    Text("Hierarchical")
                        .tag(false)
                    Text("Gradient")
                        .tag(true)
                }
                Defaults.Toggle(key: .systemEventIndicatorShadow) {
                    Text("Enable glowing effect")
                }
                Defaults.Toggle(key: .systemEventIndicatorUseAccent) {
                    Text("Tint progress bar with accent color")
                }
            } header: {
                Text("HUD appearance")
            } footer: {
                Text("Choose what happens when you hold Option while pressing a volume or brightness key.")
            }
            .disabled(!hudReplacement)
            
            Section {
                Defaults.Toggle(key: .showOpenNotchHUD) {
                    Text("Show HUD in open notch")
                }
                Defaults.Toggle(key: .showOpenNotchHUDPercentage) {
                    Text("Show percentage")
                }
                .disabled(!Defaults[.showOpenNotchHUD])
            } header: {
                HStack {
                    Text("When the notch is open")
                    customBadge(text: "Beta")
                }
            }
            .disabled(!hudReplacement)
            
            Section {
                Picker("HUD style", selection: $inlineHUD) {
                    Text("Default")
                        .tag(false)
                    Text("Inline")
                        .tag(true)
                }
                .onChange(of: Defaults[.inlineHUD]) {
                    if Defaults[.inlineHUD] {
                        withAnimation {
                            Defaults[.systemEventIndicatorShadow] = false
                            Defaults[.enableGradient] = false
                        }
                    }
                }
                
                Defaults.Toggle(key: .showClosedNotchHUDPercentage) {
                    Text("Show percentage")
                }
            } header: {
                Text("When the notch is closed")
            }
            .disabled(!Defaults[.hudReplacement])
        }
        .tint(NotchloomTheme.cyan)
        .task {
            accessibilityAuthorized = await XPCHelperClient.shared.isAccessibilityAuthorized()
        }
        .onAppear {
            XPCHelperClient.shared.startMonitoringAccessibilityAuthorization()
        }
        .onDisappear {
            if !Defaults[.hudReplacement] {
                XPCHelperClient.shared.stopMonitoringAccessibilityAuthorization()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .accessibilityAuthorizationChanged)) { notification in
            if let granted = notification.userInfo?["granted"] as? Bool {
                accessibilityAuthorized = granted
            }
        }
    }
}

struct Media: View {
    @Default(.waitInterval) var waitInterval
    @Default(.mediaController) var mediaController
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @Default(.hideNotchOption) var hideNotchOption
    @Default(.enableSneakPeek) private var enableSneakPeek
    @Default(.sneakPeekStyles) var sneakPeekStyles

    @Default(.enableLyrics) var enableLyrics

    var body: some View {
        Form {
            Section {
                Picker("Music source", selection: $mediaController) {
                    ForEach(availableMediaControllers) { controller in
                        Text(controller.rawValue).tag(controller)
                    }
                }
                .onChange(of: mediaController) { _, _ in
                    NotificationCenter.default.post(
                        name: Notification.Name.mediaControllerChanged,
                        object: nil
                    )
                }
            } header: {
                Text("Playback source")
            } footer: {
                if MusicManager.shared.isNowPlayingDeprecated {
                    HStack {
                        Text("YouTube Music requires this third-party app to be installed: ")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Link(
                            "https://github.com/pear-devs/pear-desktop",
                            destination: URL(string: "https://github.com/pear-devs/pear-desktop")!
                        )
                        .font(.caption)
                        .foregroundColor(.blue)  // Ensures it's visibly a link
                    }
                } else {
                    Text("Now Playing receives playback information from supported media apps.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                }
            }
            
            Section {
                Toggle(
                    "Show music live activity",
                    isOn: $coordinator.musicLiveActivityEnabled.animation()
                )
                Toggle("Show sneak peek on playback changes", isOn: $enableSneakPeek)
                if enableSneakPeek {
                    Picker("Sneak Peek style", selection: $sneakPeekStyles) {
                        ForEach(SneakPeekStyle.allCases) { style in
                            Text(style.rawValue).tag(style)
                        }
                    }
                }
                Stepper(value: $waitInterval, in: 0...10, step: 1) {
                    HStack {
                        Text("Media inactivity timeout")
                        Spacer()
                        Text("\(waitInterval, specifier: "%.0f") seconds")
                            .foregroundStyle(.secondary)
                    }
                }
                Picker(
                    selection: $hideNotchOption,
                    label:
                        HStack {
                            Text("Full screen behavior")
                            customBadge(text: "Beta")
                        }
                ) {
                    Text("Hide for all apps").tag(HideNotchOption.always)
                    Text("Hide for media app only").tag(
                        HideNotchOption.nowPlayingOnly)
                    Text("Never hide").tag(HideNotchOption.never)
                }
            } header: {
                Text("Playback display")
            } footer: {
                Text("Sneak Peek briefly shows the song and artist when playback changes.")
            }
            
            Section {
                MusicSlotConfigurationView()
                Defaults.Toggle(key: .enableLyrics) {
                    HStack {
                        Text("Show lyrics below artist name")
                        customBadge(text: "Beta")
                    }
                }
            } header: {
                Text("Media controls")
            }  footer: {
                Text("Customize which controls appear in the music player. Volume expands when active.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .tint(NotchloomTheme.cyan)
    }

    // Only show controller options that are available on this macOS version
    private var availableMediaControllers: [MediaControllerType] {
        if MusicManager.shared.isNowPlayingDeprecated {
            return MediaControllerType.allCases.filter { $0 != .nowPlaying }
        } else {
            return MediaControllerType.allCases
        }
    }
}

struct QuickAppsSettings: View {
    @ObservedObject private var apps = QuickAppsManager.shared

    var body: some View {
        Form {
            Section {
                ForEach(apps.favorites, id: \.self) { bundleID in
                    HStack(spacing: 10) {
                        if let icon = apps.icon(for: bundleID) {
                            Image(nsImage: icon)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 25, height: 25)
                        }
                        Text(apps.name(for: bundleID))
                        Spacer()
                        Button {
                            apps.move(bundleID, by: -1)
                        } label: {
                            Image(systemName: "arrow.up")
                        }
                        .disabled(apps.favorites.first == bundleID)
                        .help("Move up")
                        Button {
                            apps.move(bundleID, by: 1)
                        } label: {
                            Image(systemName: "arrow.down")
                        }
                        .disabled(apps.favorites.last == bundleID)
                        .help("Move down")
                        Button {
                            apps.remove(bundleID)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .help("Remove \(apps.name(for: bundleID))")
                    }
                    .buttonStyle(.borderless)
                }
                if apps.favorites.count < QuickAppsManager.limit {
                    Button("Add app…") { apps.chooseApps() }
                }
                Button("Restore default apps") { apps.restoreDefaults() }
                if let message = apps.message {
                    Text(message).foregroundStyle(.orange)
                }
            } header: {
                Text("Favorites in the notch")
            } footer: {
                Text("Keep up to four apps here. Open the notch and choose Overview to launch them.")
            }
        }
        .tint(NotchloomTheme.cyan)
    }
}

struct NotificationsSettings: View {
    @Default(.showNotificationBanners) private var showNotificationBanners
    @State private var accessibilityGranted = false

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .showNotificationBanners) {
                    Text("Show app notifications from the notch")
                }
            } header: {
                Text("Notification banners")
            } footer: {
                Text("Notchloom mirrors banners that macOS shows on screen. Original banners and their actions stay available; hidden notifications are never opened.")
            }

            if showNotificationBanners {
                Section {
                    HStack(spacing: 12) {
                        Button("Preview in the notch") {
                            NotificationMirror.shared.preview()
                        }
                        Menu("More previews") {
                            Button("Clock timer") { NotificationMirror.shared.previewClock(timer: true) }
                            Button("Clock alarm") { NotificationMirror.shared.previewClock(timer: false) }
                            Button("Short, long, and queued") { NotificationMirror.shared.previewSequence() }
                        }
                        Spacer()
                    }
                    if !accessibilityGranted {
                        Button("Request Accessibility access") {
                            XPCHelperClient.shared.requestAccessibilityAuthorization()
                        }
                        Text("Accessibility access lets Notchloom see visible notification banners. Notification content stays on this Mac.")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Try it")
                } footer: {
                    Text("The notch shows one notification at a time. Hover to pause dismissal and reveal the close button, or swipe up with two fingers to dismiss. Alerts wait while you use the open notch. Clicking a recognized app opens it; reply, snooze, and other actions remain on the original macOS notification.")
                }
            }
        }
        .tint(NotchloomTheme.cyan)
        .task {
            accessibilityGranted = await XPCHelperClient.shared.isAccessibilityAuthorized()
        }
        .onReceive(NotificationCenter.default.publisher(for: .accessibilityAuthorizationChanged)) { notification in
            if let granted = notification.userInfo?["granted"] as? Bool {
                accessibilityGranted = granted
            }
        }
    }
}

struct CalendarSettings: View {
    @ObservedObject private var calendarManager = CalendarManager.shared
    @Default(.showCalendar) var showCalendar: Bool
    @Default(.hideCompletedReminders) var hideCompletedReminders
    @Default(.hideAllDayEvents) var hideAllDayEvents
    @Default(.autoScrollToNextEvent) var autoScrollToNextEvent

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .showCalendar) {
                    Text("Show events and reminders in the notch")
                }
            } header: {
                Text("Calendar in Notchloom")
            } footer: {
                Text("Turn this on to choose calendars and reminder lists. Calendar and Reminders access is managed in System Settings.")
            }
            if showCalendar {
                Section {
                    Defaults.Toggle(key: .hideCompletedReminders) {
                        Text("Hide completed reminders")
                    }
                    Defaults.Toggle(key: .hideAllDayEvents) {
                        Text("Hide all-day events")
                    }
                    Defaults.Toggle(key: .autoScrollToNextEvent) {
                        Text("Scroll to the next event automatically")
                    }
                    Defaults.Toggle(key: .showFullEventTitles) {
                        Text("Always show full event titles")
                    }
                } header: {
                    Text("Event display")
                }
            Section(header: Text("Calendars")) {
                if calendarManager.calendarAuthorizationStatus != .fullAccess {
                    Text("Allow Calendar access in System Settings to choose which calendars appear.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                    Button("Open Calendar Privacy Settings") {
                        if let settingsURL = URL(
                            string:
                                "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"
                        ) {
                            NSWorkspace.shared.open(settingsURL)
                        }
                    }
                } else {
                    ForEach(calendarManager.eventCalendars, id: \.id) { calendar in
                        Toggle(
                            isOn: Binding(
                                get: { calendarManager.getCalendarSelected(calendar) },
                                set: { isSelected in
                                    Task {
                                        await calendarManager.setCalendarSelected(
                                            calendar, isSelected: isSelected)
                                    }
                                }
                            )
                        ) {
                            Text(calendar.title)
                        }
                        .tint(lighterColor(from: calendar.color))
                    }
                }
            }
            Section(header: Text("Reminders")) {
                if calendarManager.reminderAuthorizationStatus != .fullAccess {
                    Text("Allow Reminders access in System Settings to choose which lists appear.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                    Button("Open Reminders Privacy Settings") {
                        if let settingsURL = URL(
                            string:
                                "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders"
                        ) {
                            NSWorkspace.shared.open(settingsURL)
                        }
                    }
                } else {
                    ForEach(calendarManager.reminderLists, id: \.id) { calendar in
                        Toggle(
                            isOn: Binding(
                                get: { calendarManager.getCalendarSelected(calendar) },
                                set: { isSelected in
                                    Task {
                                        await calendarManager.setCalendarSelected(
                                            calendar, isSelected: isSelected)
                                    }
                                }
                            )
                        ) {
                            Text(calendar.title)
                        }
                        .tint(lighterColor(from: calendar.color))
                    }
                }
            }
            }
        }
        .tint(NotchloomTheme.cyan)
        .onAppear {
            Task {
                await calendarManager.checkCalendarAuthorization()
                await calendarManager.checkReminderAuthorization()
            }
        }
    }
}

func lighterColor(from nsColor: NSColor, amount: CGFloat = 0.14) -> Color {
    let srgb = nsColor.usingColorSpace(.sRGB) ?? nsColor
    var (r, g, b, a): (CGFloat, CGFloat, CGFloat, CGFloat) = (0,0,0,0)
    srgb.getRed(&r, green: &g, blue: &b, alpha: &a)

    func lighten(_ c: CGFloat) -> CGFloat {
        let increased = c + (1.0 - c) * amount
        return min(max(increased, 0), 1)
    }

    let nr = lighten(r)
    let ng = lighten(g)
    let nb = lighten(b)

    return Color(red: Double(nr), green: Double(ng), blue: Double(nb), opacity: Double(a))
}

struct About: View {
    @State private var showBuildNumber: Bool = false
    let updaterController: SPUStandardUpdaterController
    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Release name")
                    Spacer()
                    Text(Defaults[.releaseName])
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Version")
                    Spacer()
                    Text(Bundle.main.releaseVersionNumber ?? "unknown")
                        .foregroundStyle(.secondary)
                    if showBuildNumber {
                        Text("(\(Bundle.main.buildVersionNumber ?? ""))")
                            .foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation {
                        showBuildNumber.toggle()
                    }
                }
            } header: {
                Text("Version")
            }

            UpdaterSettingsView(updater: updaterController.updater)

            Section {
                CheckForUpdatesView(updater: updaterController.updater)
                Button {
                    if let url = URL(string: "https://github.com/andomatthew1234/notchloom") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("View Notchloom on GitHub", systemImage: "arrow.up.right.square")
                }
            } header: {
                Text("More")
            } footer: {
                Text("Notchloom is based on Boring Notch by TheBoredTeam.")
            }
        }
        .tint(NotchloomTheme.cyan)
    }
}

struct Shelf: View {
    @Default(.boringShelf) private var shelfEnabled
    @Default(.shelfTapToOpen) var shelfTapToOpen: Bool
    @Default(.quickShareProvider) var quickShareProvider
    @Default(.expandedDragDetection) var expandedDragDetection: Bool
    @StateObject private var quickShareService = QuickShareService.shared

    init() {
        Task { await QuickShareService.shared.discoverAvailableProviders() }
    }
    
    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .boringShelf) {
                    Text("Show the file shelf in the notch")
                }
            } header: {
                Text("File shelf")
            } footer: {
                Text("Keep files at the top of your screen for quick access and sharing.")
            }

            if shelfEnabled {
            Section {
                Defaults.Toggle(key: .openShelfByDefault) {
                    Text("Open shelf by default if items are present")
                }
                Defaults.Toggle(key: .expandedDragDetection) {
                    Text("Expanded drag detection area")
                }
                .onChange(of: expandedDragDetection) {
                    NotificationCenter.default.post(
                        name: Notification.Name.expandedDragDetectionChanged,
                        object: nil
                    )
                }
                Defaults.Toggle(key: .copyOnDrag) {
                    Text("Copy items on drag")
                }
                Defaults.Toggle(key: .autoRemoveShelfItems) {
                    Text("Remove from shelf after dragging")
                }

            } header: {
                Text("Shelf behavior")
            }
            
            Section {
                Picker("Quick Share service", selection: $quickShareProvider) {
                    ForEach(quickShareService.availableProviders, id: \.id) { provider in
                        HStack {
                            Group {
                                if let imgData = provider.imageData, let nsImg = NSImage(data: imgData) {
                                    Image(nsImage: nsImg)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                } else {
                                    Image(systemName: "square.and.arrow.up")
                                }
                            }
                            .frame(width: 16, height: 16)
                            .foregroundColor(.accentColor)
                            Text(provider.id)
                        }
                        .tag(provider.id)
                    }
                }
                .pickerStyle(.menu)
                
            } header: {
                Text("Quick Share")
            } footer: {
                Text("Choose which service to use when sharing files from the shelf. Click the shelf button to select files, or drag files onto it to share immediately.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            }
        }
        .tint(NotchloomTheme.cyan)
    }
}

//struct Extensions: View {
//    @State private var effectTrigger: Bool = false
//    var body: some View {
//        Form {
//            Section {
//                List {
//                    ForEach(extensionManager.installedExtensions.indices, id: \.self) { index in
//                        let item = extensionManager.installedExtensions[index]
//                        HStack {
//                            AppIcon(for: item.bundleIdentifier)
//                                .resizable()
//                                .frame(width: 24, height: 24)
//                            Text(item.name)
//                            ListItemPopover {
//                                Text("Description")
//                            }
//                            Spacer(minLength: 0)
//                            HStack(spacing: 6) {
//                                Circle()
//                                    .frame(width: 6, height: 6)
//                                    .foregroundColor(
//                                        isExtensionRunning(item.bundleIdentifier)
//                                            ? .green : item.status == .disabled ? .gray : .red
//                                    )
//                                    .conditionalModifier(isExtensionRunning(item.bundleIdentifier))
//                                { view in
//                                    view
//                                        .shadow(color: .green, radius: 3)
//                                }
//                                Text(
//                                    isExtensionRunning(item.bundleIdentifier)
//                                        ? "Running"
//                                        : item.status == .disabled ? "Disabled" : "Stopped"
//                                )
//                                .contentTransition(.numericText())
//                                .foregroundStyle(.secondary)
//                                .font(.footnote)
//                            }
//                            .frame(width: 60, alignment: .leading)
//
//                            Menu(
//                                content: {
//                                    Button("Restart") {
//                                        let ws = NSWorkspace.shared
//
//                                        if let ext = ws.runningApplications.first(where: {
//                                            $0.bundleIdentifier == item.bundleIdentifier
//                                        }) {
//                                            ext.terminate()
//                                        }
//
//                                        if let appURL = ws.urlForApplication(
//                                            withBundleIdentifier: item.bundleIdentifier)
//                                        {
//                                            ws.openApplication(
//                                                at: appURL, configuration: .init(),
//                                                completionHandler: nil)
//                                        }
//                                    }
//                                    .keyboardShortcut("R", modifiers: .command)
//                                    Button("Disable") {
//                                        if let ext = NSWorkspace.shared.runningApplications.first(
//                                            where: { $0.bundleIdentifier == item.bundleIdentifier })
//                                        {
//                                            ext.terminate()
//                                        }
//                                        extensionManager.installedExtensions[index].status =
//                                            .disabled
//                                    }
//                                    .keyboardShortcut("D", modifiers: .command)
//                                    Divider()
//                                    Button("Uninstall", role: .destructive) {
//                                        //
//                                    }
//                                },
//                                label: {
//                                    Image(systemName: "ellipsis.circle")
//                                        .foregroundStyle(.secondary)
//                                }
//                            )
//                            .controlSize(.regular)
//                        }
//                        .buttonStyle(PlainButtonStyle())
//                        .padding(.vertical, 5)
//                    }
//                }
//                .frame(minHeight: 120)
//                .actionBar {
//                    Button {
//                    } label: {
//                        HStack(spacing: 3) {
//                            Image(systemName: "plus")
//                            Text("Add manually")
//                        }
//                        .foregroundStyle(.secondary)
//                    }
//                    .disabled(true)
//                    Spacer()
//                    Button {
//                        withAnimation(.linear(duration: 1)) {
//                            effectTrigger.toggle()
//                        } completion: {
//                            effectTrigger.toggle()
//                        }
//                        extensionManager.checkIfExtensionsAreInstalled()
//                    } label: {
//                        HStack(spacing: 3) {
//                            Image(systemName: "arrow.triangle.2.circlepath")
//                                .rotationEffect(effectTrigger ? .degrees(360) : .zero)
//                        }
//                        .foregroundStyle(.secondary)
//                    }
//                }
//                .controlSize(.small)
//                .buttonStyle(PlainButtonStyle())
//                .overlay {
//                    if extensionManager.installedExtensions.isEmpty {
//                        Text("No extension installed")
//                            .foregroundStyle(Color(.secondaryLabelColor))
//                            .padding(.bottom, 22)
//                    }
//                }
//            } header: {
//                HStack(spacing: 0) {
//                    Text("Installed extensions")
//                    if !extensionManager.installedExtensions.isEmpty {
//                        Text(" – \(extensionManager.installedExtensions.count)")
//                            .foregroundStyle(.secondary)
//                    }
//                }
//            }
//        }
//        .tint(NotchloomTheme.cyan)
//        .navigationTitle("Extensions")
//        // TipsView()
//        // .padding(.horizontal, 19)
//    }
//}

struct Appearance: View {
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @Default(.mirrorShape) var mirrorShape
    @Default(.sliderColor) var sliderColor
    @Default(.useMusicVisualizer) var useMusicVisualizer
    @Default(.customVisualizers) var customVisualizers
    @Default(.selectedVisualizer) var selectedVisualizer

    @State private var selectedListVisualizer: CustomVisualizer? = nil
    @State private var isPresented: Bool = false
    @State private var name: String = ""
    @State private var url: String = ""
    @State private var speed: CGFloat = 1.0
    @State private var showExperimentalVisualizers = false
    var body: some View {
        Form {
            Section {
                Toggle("Always show tabs in the open notch", isOn: $coordinator.alwaysShowTabs)
                Defaults.Toggle(key: .settingsIconInNotch) {
                    Text("Show the Settings button in the notch")
                }

            } header: {
                Text("Notch layout")
            }

            Section {
                Defaults.Toggle(key: .coloredSpectrogram) {
                    Text("Use colors in the music visualizer")
                }
                Defaults
                    .Toggle("Tint the player with album artwork", key: .playerColorTinting)
                Defaults.Toggle(key: .lightingEffect) {
                    Text("Blur behind album artwork")
                }
                Picker("Slider color", selection: $sliderColor) {
                    ForEach(SliderColorEnum.allCases, id: \.self) { option in
                        Text(option.rawValue)
                    }
                }
            } header: {
                Text("Music player")
            }

            Section {
                Defaults.Toggle(key: .showMirror) {
                    Text("Show camera mirror")
                }
                .disabled(!checkVideoInput())
                Picker("Mirror shape", selection: $mirrorShape) {
                    Text("Circle").tag(MirrorShapeEnum.circle)
                    Text("Square").tag(MirrorShapeEnum.rectangle)
                }
                Defaults.Toggle(key: .showNotHumanFace) {
                    Text("Show the idle face animation")
                }
            } header: {
                Text("Mirror and idle view")
            } footer: {
                Text("The mirror needs camera access. Notchloom uses the camera only while the mirror is open.")
            }

            Section {
                Toggle("Show experimental visualizer controls", isOn: $showExperimentalVisualizers)
            } header: {
                Text("Experimental")
            } footer: {
                Text("Custom animation support is still in development.")
            }

            if showExperimentalVisualizers {
            Section {
                Toggle(
                    "Use music visualizer spectrogram",
                    isOn: $useMusicVisualizer.animation()
                )
                .disabled(true)
                if !useMusicVisualizer {
                    if customVisualizers.count > 0 {
                        Picker(
                            "Selected animation",
                            selection: $selectedVisualizer
                        ) {
                            ForEach(
                                customVisualizers,
                                id: \.self
                            ) { visualizer in
                                Text(visualizer.name)
                                    .tag(visualizer)
                            }
                        }
                    } else {
                        HStack {
                            Text("Selected animation")
                            Spacer()
                            Text("No custom animation available")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Custom music live activity animation")
                    customBadge(text: "Coming soon")
                }
            }

            Section {
                List {
                    ForEach(customVisualizers, id: \.self) { visualizer in
                        HStack {
                            LottieView(
                                url: visualizer.url, speed: visualizer.speed,
                                loopMode: .loop
                            )
                            .frame(width: 30, height: 30, alignment: .center)
                            Text(visualizer.name)
                            Spacer(minLength: 0)
                            if selectedVisualizer == visualizer {
                                Text("selected")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.secondary)
                                    .padding(.trailing, 8)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.vertical, 2)
                        .background(
                            selectedListVisualizer != nil
                                ? selectedListVisualizer == visualizer
                                    ? Color.effectiveAccent : Color.clear : Color.clear,
                            in: RoundedRectangle(cornerRadius: 5)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if selectedListVisualizer == visualizer {
                                selectedListVisualizer = nil
                                return
                            }
                            selectedListVisualizer = visualizer
                        }
                    }
                }
                .safeAreaPadding(
                    EdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 0)
                )
                .frame(minHeight: 120)
                .actionBar {
                    HStack(spacing: 5) {
                        Button {
                            name = ""
                            url = ""
                            speed = 1.0
                            isPresented.toggle()
                        } label: {
                            Image(systemName: "plus")
                                .foregroundStyle(.secondary)
                                .contentShape(Rectangle())
                        }
                        Divider()
                        Button {
                            if selectedListVisualizer != nil {
                                let visualizer = selectedListVisualizer!
                                selectedListVisualizer = nil
                                customVisualizers.remove(
                                    at: customVisualizers.firstIndex(of: visualizer)!)
                                if visualizer == selectedVisualizer && customVisualizers.count > 0 {
                                    selectedVisualizer = customVisualizers[0]
                                }
                            }
                        } label: {
                            Image(systemName: "minus")
                                .foregroundStyle(.secondary)
                                .contentShape(Rectangle())
                        }
                    }
                }
                .controlSize(.small)
                .buttonStyle(PlainButtonStyle())
                .overlay {
                    if customVisualizers.isEmpty {
                        Text("No custom visualizer")
                            .foregroundStyle(Color(.secondaryLabelColor))
                            .padding(.bottom, 22)
                    }
                }
                .sheet(isPresented: $isPresented) {
                    VStack(alignment: .leading) {
                        Text("Add new visualizer")
                            .font(.largeTitle.bold())
                            .padding(.vertical)
                        TextField("Name", text: $name)
                        TextField("Lottie JSON URL", text: $url)
                        HStack {
                            Text("Speed")
                            Spacer(minLength: 80)
                            Text("\(speed, specifier: "%.1f")s")
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(.secondary)
                            Slider(value: $speed, in: 0...2, step: 0.1)
                        }
                        .padding(.vertical)
                        HStack {
                            Button {
                                isPresented.toggle()
                            } label: {
                                Text("Cancel")
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }

                            Button {
                                let visualizer: CustomVisualizer = .init(
                                    UUID: UUID(),
                                    name: name,
                                    url: URL(string: url)!,
                                    speed: speed
                                )

                                if !customVisualizers.contains(visualizer) {
                                    customVisualizers.append(visualizer)
                                }

                                isPresented.toggle()
                            } label: {
                                Text("Add")
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                            .buttonStyle(BorderedProminentButtonStyle())
                        }
                    }
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .controlSize(.extraLarge)
                    .padding()
                }
            } header: {
                HStack(spacing: 0) {
                    Text("Custom visualizers (Lottie)")
                    if !Defaults[.customVisualizers].isEmpty {
                        Text(" – \(Defaults[.customVisualizers].count)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            }

        }
        .tint(NotchloomTheme.cyan)
    }

    func checkVideoInput() -> Bool {
        if AVCaptureDevice.default(for: .video) != nil {
            return true
        }

        return false
    }
}

struct Advanced: View {
    @Default(.useCustomAccentColor) var useCustomAccentColor
    @Default(.customAccentColorData) var customAccentColorData
    @Default(.showOnLockScreen) var showOnLockScreen
    @Default(.hideFromScreenRecording) var hideFromScreenRecording
    
    @State private var customAccentColor: Color = .accentColor
    @State private var selectedPresetColor: PresetAccentColor? = nil
    
    // macOS accent colors
    enum PresetAccentColor: String, CaseIterable, Identifiable {
        case blue = "Blue"
        case purple = "Purple"
        case pink = "Pink"
        case red = "Red"
        case orange = "Orange"
        case yellow = "Yellow"
        case green = "Green"
        case graphite = "Graphite"
        
        var id: String { self.rawValue }
        
        var color: Color {
            switch self {
            case .blue: return Color(red: 0.0, green: 0.478, blue: 1.0)
            case .purple: return Color(red: 0.686, green: 0.322, blue: 0.871)
            case .pink: return Color(red: 1.0, green: 0.176, blue: 0.333)
            case .red: return Color(red: 1.0, green: 0.271, blue: 0.227)
            case .orange: return Color(red: 1.0, green: 0.584, blue: 0.0)
            case .yellow: return Color(red: 1.0, green: 0.8, blue: 0.0)
            case .green: return Color(red: 0.4, green: 0.824, blue: 0.176)
            case .graphite: return Color(red: 0.557, green: 0.557, blue: 0.576)
            }
        }
    }
    
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    // Toggle between system and custom
                    Picker("Accent color", selection: $useCustomAccentColor) {
                        Text("System").tag(false)
                        Text("Custom").tag(true)
                    }
                    .pickerStyle(.segmented)
                    
                    if !useCustomAccentColor {
                        // System accent info
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 12) {
                                AccentCircleButton(
                                    isSelected: true,
                                    color: .accentColor,
                                    isSystemDefault: true
                                ) {}
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Using System Accent")
                                        .font(.body)
                                    Text("Your macOS system accent color")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        }
                    } else {
                        // Custom color options
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Color Presets")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                            
                            HStack(spacing: 12) {
                                ForEach(PresetAccentColor.allCases) { preset in
                                    AccentCircleButton(
                                        isSelected: selectedPresetColor == preset,
                                        color: preset.color,
                                        isMulticolor: false
                                    ) {
                                        selectedPresetColor = preset
                                        customAccentColor = preset.color
                                        saveCustomColor(preset.color)
                                        forceUiUpdate()
                                    }
                                }
                                Spacer()
                            }
                            
                            Divider()
                                .padding(.vertical, 4)
                            
                            // Custom color picker
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Pick a Color")
                                        .font(.body)
                                    Text("Choose any color")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                
                                Spacer()
                                
                                ColorPicker(selection: Binding(
                                    get: { customAccentColor },
                                    set: { newColor in
                                        customAccentColor = newColor
                                        selectedPresetColor = nil
                                        saveCustomColor(newColor)
                                        forceUiUpdate()
                                    }
                                ), supportsOpacity: false) {
                                    ZStack {
                                        Circle()
                                            .fill(customAccentColor)
                                            .frame(width: 32, height: 32)
                                        
                                        if selectedPresetColor == nil {
                                            Circle()
                                                .strokeBorder(.primary.opacity(0.3), lineWidth: 2)
                                                .frame(width: 32, height: 32)
                                        }
                                    }
                                }
                                .labelsHidden()
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Accent color")
            } footer: {
                Text("Choose between your system accent color or customize it with your own selection.")
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .onAppear {
                initializeAccentColorState()
            }
            
            Section {
                Defaults.Toggle(key: .enableShadow) {
                    Text("Enable window shadow")
                }
                Defaults.Toggle(key: .cornerRadiusScaling) {
                    Text("Corner radius scaling")
                }
            } header: {
                Text("Window appearance")
            }
            
            Section {
                Defaults.Toggle(key: .hideTitleBar) {
                    Text("Cover the menu bar behind the notch")
                }
                Defaults.Toggle(key: .showOnLockScreen) {
                    Text("Show Notchloom on the lock screen")
                }
                Defaults.Toggle(key: .hideFromScreenRecording) {
                    Text("Hide from screen recording")
                }
            } header: {
                Text("Visibility")
            }
        }
        .tint(NotchloomTheme.cyan)
        .onAppear {
            loadCustomColor()
        }
    }
    
    private func forceUiUpdate() {
        // Force refresh the UI
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Notification.Name("AccentColorChanged"), object: nil)
        }
    }
    
    private func saveCustomColor(_ color: Color) {
        let nsColor = NSColor(color)
        if let colorData = try? NSKeyedArchiver.archivedData(withRootObject: nsColor, requiringSecureCoding: false) {
            Defaults[.customAccentColorData] = colorData
            forceUiUpdate()
        }
    }
    
    private func loadCustomColor() {
        if let colorData = Defaults[.customAccentColorData],
           let nsColor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: colorData) {
            customAccentColor = Color(nsColor: nsColor)
            
            // Check if loaded color matches a preset
            selectedPresetColor = nil
            for preset in PresetAccentColor.allCases {
                if colorsAreEqual(Color(nsColor: nsColor), preset.color) {
                    selectedPresetColor = preset
                    break
                }
            }
        }
    }
    
    private func colorsAreEqual(_ color1: Color, _ color2: Color) -> Bool {
        let nsColor1 = NSColor(color1).usingColorSpace(.sRGB) ?? NSColor(color1)
        let nsColor2 = NSColor(color2).usingColorSpace(.sRGB) ?? NSColor(color2)
        
        return abs(nsColor1.redComponent - nsColor2.redComponent) < 0.01 &&
               abs(nsColor1.greenComponent - nsColor2.greenComponent) < 0.01 &&
               abs(nsColor1.blueComponent - nsColor2.blueComponent) < 0.01
    }
    
    private func initializeAccentColorState() {
        if !useCustomAccentColor {
            selectedPresetColor = nil // Multicolor is selected when useCustomAccentColor is false
        } else {
            loadCustomColor()
        }
    }
}

// MARK: - Accent Circle Button Component
struct AccentCircleButton: View {
    let isSelected: Bool
    let color: Color
    var isSystemDefault: Bool = false
    var isMulticolor: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack {
                // Color circle
                Circle()
                    .fill(color)
                    .frame(width: 32, height: 32)
                
                // Subtle border
                Circle()
                    .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                    .frame(width: 32, height: 32)
                
                // Apple-style highlight ring around the middle when selected
                if isSelected {
                    Circle()
                        .strokeBorder(
                            Color.white.opacity(0.5),
                            lineWidth: 2
                        )
                        .frame(width: 28, height: 28)
                }
            }
        }
        .buttonStyle(.plain)
        .help(isSystemDefault ? "Use your macOS system accent color" : "")
    }
}

struct Shortcuts: View {
    var body: some View {
        Form {
            Section {
                KeyboardShortcuts.Recorder("Show or hide Sneak Peek", name: .toggleSneakPeek)
                KeyboardShortcuts.Recorder("Open or close the notch", name: .toggleNotchOpen)
            } header: {
                Text("Keyboard shortcuts")
            } footer: {
                Text("Click a shortcut field, then press the keys you want to use. Sneak Peek briefly shows the current song and artist.")
            }
        }
        .tint(NotchloomTheme.cyan)
    }
}

func proFeatureBadge() -> some View {
    Text("Upgrade to Pro")
        .foregroundStyle(Color(red: 0.545, green: 0.196, blue: 0.98))
        .font(.footnote.bold())
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 4).stroke(
                Color(red: 0.545, green: 0.196, blue: 0.98), lineWidth: 1))
}

func comingSoonTag() -> some View {
    Text("Coming soon")
        .foregroundStyle(.secondary)
        .font(.footnote.bold())
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(Color(nsColor: .secondarySystemFill))
        .clipShape(.capsule)
}

func customBadge(text: String) -> some View {
    Text(text)
        .foregroundStyle(.secondary)
        .font(.footnote.bold())
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(Color(nsColor: .secondarySystemFill))
        .clipShape(.capsule)
}

func warningBadge(_ text: String, _ description: String) -> some View {
    Section {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 22))
                .foregroundStyle(.yellow)
            VStack(alignment: .leading) {
                Text(text)
                    .font(.headline)
                Text(description)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

#Preview {
    HUD()
}
