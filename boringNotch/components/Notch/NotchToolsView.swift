import Defaults
import SwiftUI

/// Overview keeps its tools inside the open notch, with a stable bottom tab bar.
struct NotchToolsView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var vm: BoringViewModel
    @ObservedObject private var focus = FocusTimerManager.shared
    @ObservedObject private var apps = QuickAppsManager.shared
    @ObservedObject private var music = MusicManager.shared
    @ObservedObject private var coordinator = BoringViewCoordinator.shared
    @ObservedObject private var webcam = WebcamManager.shared
    @ObservedObject private var battery = BatteryStatusViewModel.shared
    @StateObject private var shelf = ShelfStateViewModel.shared
    @Default(.boringShelf) private var shelfEnabled
    @Default(.showCalendar) private var showCalendar
    @Default(.showMirror) private var showMirror
    @Default(.showBatteryIndicator) private var showBattery
    @State private var panel: OverviewPanel = .dashboard
    @State private var isHoveringArtwork = false
    @State private var isHoveringIntelligence = false
    @Namespace private var todayExpansion
    @ObservedObject private var todayData = TodayAppData.controller

    private enum OverviewPanel: Equatable {
        case dashboard
        case calendar
        case focus
        case power
        case mirror
    }

    private var showsOverviewArtwork: Bool {
        music.overviewMusicVisible && !music.songTitle.isEmpty
            && music.songTitle != "I'm Handsome"
    }

    var body: some View {
        ZStack(alignment: .top) {
            if vm.todayExpanded {
                TodayDataPageHost(controller: todayData, expansionNamespace: reduceMotion ? nil : todayExpansion,
                                  onBack: returnToDashboard, onClose: closeToday, onSources: {
                    closeToday()
                    SettingsWindowController.shared.showTodaySources()
                }, briefings: TodayAppData.briefings, onModels: {
                    closeToday()
                    SettingsWindowController.shared.showIntelligenceModels()
                }, prepareLocationPermission: { await vm.prepareTodayLocationPermission(reduceMotion: reduceMotion) })
                .frame(width: max(0, vm.todayNotchSize.width - 2 * ((Defaults[.cornerRadiusScaling] ? cornerRadiusInsets.opened.top : cornerRadiusInsets.opened.bottom) + 12)),
                       height: max(0, vm.todayNotchSize.height - TodayPageGeometry.chromeHeight(closedNotchHeight: vm.effectiveClosedNotchHeight)), alignment: .top)
                .onPreferenceChange(TodayPreferredContentHeightKey.self) { height in
                    vm.updateTodayContentHeight(height, reduceMotion: reduceMotion)
                }
                .background(TodayNotchInteraction(containsScreenPoint: { vm.isMouseHovering(position: $0) }, onClose: closeToday,
                                                 canDismissOutside: { !todayData.requestingPermission }, suspended: vm.todayPermissionWaiting))
                .opacity(vm.todayPermissionWaiting ? 0 : 1)
                .allowsHitTesting(!vm.todayPermissionWaiting)
                .accessibilityHidden(vm.todayPermissionWaiting)
                .frame(width: vm.todayPermissionWaiting ? 0 : nil, height: vm.todayPermissionWaiting ? 0 : nil)
                .clipped()
                .transition(.identity)
                .zIndex(1)
            } else { overviewContent.transition(.opacity.animation(.easeOut(duration: 0.08))) }
        }
        .onPreferenceChange(PowerContentHeightKey.self) { height in
            vm.updatePowerContentHeight(height, reduceMotion: reduceMotion)
        }
        .onDisappear {
            stopMirror()
            vm.setPowerExpanded(false)
        }
        .onChange(of: todayData.locationPermissionHandoff) { _, pending in
            if !pending { vm.restoreTodayAfterLocationPermission(reduceMotion: reduceMotion) }
        }
    }

    private var overviewContent: some View {
        VStack(spacing: 8) {
            panelContent
                .frame(height: panel == .power ? vm.powerContentHeight : 132, alignment: .top)
                .frame(maxWidth: .infinity)

            ViewThatFits(in: .horizontal) {
                overviewTabs.labelStyle(.titleAndIcon)
                overviewTabs.labelStyle(.titleOnly)
            }
            .font(.system(size: 11, weight: .semibold))
            .frame(height: 29)
            .padding(.horizontal, 18)
        }
        .padding(.top, 4)
        .frame(maxWidth: .infinity, alignment: .top)
        .buttonStyle(.plain)
        .onChange(of: showMirror) { _, enabled in
            if !enabled && panel == .mirror {
                stopMirror()
                panel = .dashboard
            }
        }
        .onChange(of: webcam.authorizationStatus) { _, status in
            if status == .authorized && panel == .mirror && webcam.cameraAvailable && !webcam.isSessionRunning {
                vm.toggleCameraPreview()
            }
        }
        .onChange(of: webcam.cameraAvailable) { _, available in
            if available && panel == .mirror && webcam.authorizationStatus == .authorized && !webcam.isSessionRunning {
                vm.toggleCameraPreview()
            }
        }
    }

    private var overviewTabs: some View {
        HStack(spacing: 3) {
                panelButton("Dashboard", icon: "square.grid.2x2.fill", for: .dashboard)
                panelButton("Calendar", icon: "calendar", for: .calendar)
                panelButton("Focus Timer", icon: "timer", for: .focus)
                if showMirror {
                    panelButton("Mirror", icon: "web.camera", for: .mirror)
                }

                panelButton("Power usage", icon: "bolt.fill", for: .power)
                Spacer(minLength: 0)
                if showBattery {
                    BoringBatteryView(
                        batteryWidth: 30,
                        isCharging: battery.isCharging,
                        isInLowPowerMode: battery.isInLowPowerMode,
                        isPluggedIn: battery.isPluggedIn,
                        levelBattery: battery.levelBattery,
                        maxCapacity: battery.maxCapacity,
                        timeToFullCharge: battery.timeToFullCharge,
                        isForNotification: false
                    )
                    .frame(width: 30, height: 28)
                    .help("Battery in Overview")
                }
                intelligenceButton
            }
    }

    private func openToday() {
        withAnimation(reduceMotion ? .easeOut(duration: 0.14) : .spring(response: 0.46, dampingFraction: 0.91)) {
            vm.setTodayExpanded(true)
        }
    }

    private var intelligenceButton: some View {
        Button {
            stopMirror()
            IntelligenceCoordinator.shared.activate(on: vm)
        } label: {
            Label("Intelligence", systemImage: "sparkles")
                .padding(.horizontal, 11)
                .frame(height: 27)
                .background(.white.opacity(isHoveringIntelligence ? 0.10 : 0.035), in: Capsule())
                .overlay {
                    Capsule().strokeBorder(
                        AngularGradient(colors: [.red, .orange, .yellow, .green, .cyan, .blue, .purple, .pink, .red], center: .center),
                        lineWidth: isHoveringIntelligence ? 1.5 : 1.15
                    )
                }
                .contentShape(Capsule())
        }
        .foregroundStyle(.white.opacity(0.95))
        .fixedSize()
        .buttonStyle(TodayInvitationButtonStyle())
        .shadow(color: .purple.opacity(isHoveringIntelligence ? 0.20 : 0), radius: 7)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: isHoveringIntelligence)
        .onHover { isHoveringIntelligence = $0 }
        .help("Open Notchloom Intelligence")
        .accessibilityLabel("Open Intelligence")
    }
    private func returnToDashboard() {
        withAnimation(reduceMotion ? .easeOut(duration: 0.14) : .spring(response: 0.42, dampingFraction: 0.95), completionCriteria: .logicallyComplete) {
            panel = .dashboard
            vm.setTodayExpanded(false)
        } completion: { vm.finishTodayContraction() }
    }
    private func closeToday() {
        withAnimation(reduceMotion ? .easeOut(duration: 0.14) : .spring(response: 0.42, dampingFraction: 1)) { vm.close() }
    }

    @ViewBuilder
    private var panelContent: some View {
        switch panel {
        case .dashboard:
            GeometryReader { geometry in
                let occupiedWidths: [CGFloat] = (showsOverviewArtwork ? [112] : [])
                    + (focus.phase == .running ? [136] : [])
                    + (shelfEnabled && !shelf.isEmpty ? [150] : []) + [230]
                let plan = DashboardSlotPlan(availableWidth: geometry.size.width, occupiedWidths: occupiedWidths)
                HStack(spacing: plan.gap) {
                    if showsOverviewArtwork { nowPlayingSlot }
                    if plan.slots > 0 {
                        Button(action: openToday) {
                            TodayWidget(slots: plan.slots,
                                        content: TodayContextPresentation.dashboardContent(todayData.localDate),
                                        expansionNamespace: reduceMotion ? nil : todayExpansion, isPreview: false)
                        }
                            .buttonStyle(TodayInvitationButtonStyle())
                            .frame(width: plan.width)
                            .transition(.opacity)
                            .accessibilityLabel("Open Today")
                    }
                    if focus.phase == .running {
                        focusDashboardCard
                            .transition(.opacity.combined(with: .scale(scale: 0.94)))
                    }
                    if shelfEnabled && !shelf.isEmpty {
                        shelfDashboardCard
                            .transition(.opacity.combined(with: .scale(scale: 0.94)))
                    }
                    appsSection.frame(width: 230, alignment: .topLeading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 112, alignment: .top)
                .animation(reduceMotion ? nil : .smooth(duration: 0.4), value: occupiedWidths)
                .animation(reduceMotion ? nil : .smooth(duration: 0.4), value: plan.slots)
            }
            .padding(.horizontal, 18)
        case .calendar:
            if showCalendar {
                CalendarView()
                    .frame(width: 570, height: 120)
                    .onHover { vm.isHoveringCalendar = $0 }
            } else {
                VStack(spacing: 7) {
                    Image(systemName: "calendar")
                        .font(.system(size: 25, weight: .light))
                        .foregroundStyle(.cyan)
                    Text("Calendar is off")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Turn on events and reminders in Settings.")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.58))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .power:
            PowerUsageView()
        case .focus:
            focusSection
                .frame(maxWidth: 570)
                .padding(.horizontal, 28)
        case .mirror:
            HStack(spacing: 16) {
                CameraPreviewView(webcamManager: webcam)
                    .frame(width: 120, height: 120)
                VStack(alignment: .leading, spacing: 5) {
                    Label("Mirror", systemImage: "web.camera")
                        .font(.system(size: 15, weight: .semibold))
                    Text(webcam.isSessionRunning
                         ? "Select the preview to turn off the camera."
                         : "Select the preview to turn on the camera.")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 22)
        }
    }

    private func panelButton(_ title: String, icon: String, for target: OverviewPanel) -> some View {
        Button {
            if panel == .mirror && target != .mirror { stopMirror() }
            if target == .mirror && panel != .mirror { vm.toggleCameraPreview() }
            withAnimation(reduceMotion ? .easeOut(duration: 0.14) : .snappy(duration: 0.25, extraBounce: 0)) {
                panel = target
                vm.setPowerExpanded(target == .power)
            }
        } label: {
            Label(title, systemImage: icon)
                .padding(.horizontal, 8)
                .frame(height: 27)
                .background(panel == target ? .white.opacity(0.16) : .clear, in: Capsule())
                .contentShape(Capsule())
        }
        .fixedSize()
        .foregroundStyle(panel == target ? .white : .white.opacity(0.62))
        .accessibilityAddTraits(panel == target ? .isSelected : [])
    }

    private func stopMirror() {
        if vm.isCameraExpanded || webcam.isSessionRunning {
            webcam.stopSession()
            vm.isCameraExpanded = false
        }
    }

    private var nowPlayingSlot: some View {
        ZStack {
            if showsOverviewArtwork {
                artworkControl
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
            }
        }
        .frame(width: 112, height: 112)
        .animation(.smooth(duration: 0.3), value: showsOverviewArtwork)
    }

    private var artworkControl: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(nsImage: music.albumArt)
                .resizable()
                .scaledToFill()
                .frame(width: 112, height: 112)
                .saturation(music.isPlaying ? 1 : 0.55)
                .brightness(music.isPlaying ? 0 : -0.12)
                .scaleEffect(isHoveringArtwork ? 1.05 : 1)
                .blur(radius: isHoveringArtwork ? 6 : 0)
                .accessibilityHidden(true)

            Color.black.opacity(isHoveringArtwork ? 0.36 : 0)
                .allowsHitTesting(false)

            HStack(spacing: 4) {
                artworkButton("backward.fill", label: "Previous track") {
                    music.previousTrack()
                }
                artworkButton(music.isPlaying ? "pause.fill" : "play.fill",
                              label: music.isPlaying ? "Pause" : "Play") {
                    music.playPause()
                }
                artworkButton("forward.fill", label: "Next track") {
                    music.nextTrack()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(isHoveringArtwork ? 1 : 0)
            .scaleEffect(isHoveringArtwork ? 1 : 0.92)
            .allowsHitTesting(isHoveringArtwork)

            Group {
                if music.isPlaying {
                    AudioSpectrumView(isPlaying: $music.isPlaying)
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 16, height: 16)
                }
            }
            .foregroundStyle(.white)
            .frame(width: 27, height: 27)
            .background(.black.opacity(0.86), in: Circle())
            .padding(7)
            .opacity(isHoveringArtwork ? 0 : 1)
            .accessibilityHidden(true)
        }
        .frame(width: 112, height: 112)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onHover { isHoveringArtwork = $0 }
        .animation(.easeInOut(duration: 0.25), value: isHoveringArtwork)
        .animation(.easeInOut(duration: 0.25), value: music.isPlaying)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Now Playing: \(music.songTitle) by \(music.artistName)")
    }

    private func artworkButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 31, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
    }

    private var focusDashboardCard: some View {
        Button {
            withAnimation(.snappy(duration: 0.25, extraBounce: 0)) {
                panel = .focus
            }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                Label("Focus", systemImage: "timer")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.cyan)
                Spacer(minLength: 0)
                Text(focus.timeLabel)
                    .font(.system(size: 25, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(.white)
                ProgressView(value: focus.progress)
                    .tint(.cyan)
                    .controlSize(.mini)
                    .padding(.top, 6)
            }
            .padding(12)
            .frame(width: 136, height: 112)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .accessibilityLabel("Focus in progress, \(focus.timeLabel) remaining. Open Focus Timer")
        .help("Open Focus Timer")
    }

    private var shelfDashboardCard: some View {
        Button {
            withAnimation(.snappy(duration: 0.28, extraBounce: 0)) {
                coordinator.currentView = .shelf
            }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                Label("Shelf ready", systemImage: "tray.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.cyan)
                Spacer(minLength: 0)
                HStack(alignment: .bottom, spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(shelf.items.count.formatted())
                            .font(.system(size: 23, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                        Text(shelf.items.count == 1 ? "item" : "items")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.58))
                    }
                    Spacer(minLength: 2)
                    HStack(spacing: -8) {
                        ForEach(Array(shelf.items.prefix(2))) { item in
                            ShelfDashboardThumbnail(item: item)
                        }
                    }
                }
            }
            .padding(12)
            .frame(width: 150, height: 112)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .accessibilityLabel("Shelf ready, \(shelf.items.count) \(shelf.items.count == 1 ? "item" : "items"). Open Shelf")
        .help("Open Shelf")
    }

    private var focusSection: some View {
        VStack(spacing: 9) {
            HStack {
                Label("Focus Timer", systemImage: "timer")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.cyan)
                Spacer()
                Menu {
                    Button("5 minutes") { focus.start(minutes: 5) }
                    Button("15 minutes") { focus.start(minutes: 15) }
                    Button("25 minutes") { focus.start(minutes: 25) }
                    Button("50 minutes") { focus.start(minutes: 50) }
                } label: {
                    Label("Duration", systemImage: "ellipsis.circle")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                }
                .menuStyle(.borderlessButton)
                .help("Choose a focus duration")
            }

            HStack(alignment: .center, spacing: 12) {
                Text(focus.phase == .finished ? "Done" : focus.timeLabel)
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                Spacer(minLength: 0)
                if focus.phase == .running || focus.phase == .paused {
                    Button { focus.reset() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.68))
                            .frame(width: 32, height: 32)
                            .background(.white.opacity(0.1), in: Circle())
                    }
                    .help("Reset focus timer")
                }
                Button {
                    switch focus.phase {
                    case .idle, .finished: focus.start(minutes: Int(focus.duration / 60))
                    case .running: focus.pause()
                    case .paused: focus.resume()
                    }
                } label: {
                    Image(systemName: focus.phase == .running ? "pause.fill" : "play.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 38, height: 38)
                        .background(.cyan, in: Circle())
                }
                .help(focus.phase == .running ? "Pause focus timer" : "Start focus timer")
            }

            ProgressView(value: focus.progress)
                .tint(.cyan)
                .controlSize(.mini)
                .accessibilityLabel("Focus session progress")
        }
    }

    private var appsSection: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 5) {
                Image(systemName: "square.grid.2x2.fill").foregroundStyle(.cyan)
                Text("Quick apps").foregroundStyle(.white)
                Spacer(minLength: 0)
                if apps.favorites.count < QuickAppsManager.limit {
                    Button { apps.chooseApps() } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(width: 28, height: 28)
                    }
                    .help("Add a favorite app")
                }
            }
            .font(.system(size: 12, weight: .semibold))

            HStack(spacing: 8) {
                ForEach(apps.favorites, id: \.self) { bundleID in
                    Button { apps.launch(bundleID) } label: {
                        Group {
                            if let icon = apps.icon(for: bundleID) {
                                Image(nsImage: icon).resizable().scaledToFit()
                            } else {
                                Image(systemName: "app.dashed").resizable().scaledToFit()
                            }
                        }
                        .frame(width: 35, height: 35)
                    }
                    .help("Open \(apps.name(for: bundleID))")
                    .disabled(apps.appURL(for: bundleID) == nil)
                }
            }
            if let message = apps.message {
                Text(message).font(.system(size: 11))
                    .foregroundStyle(.orange).lineLimit(2)
            }
        }
        .frame(height: 108, alignment: .top)
        .padding(.horizontal, 14)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 17))
    }
}

private struct ShelfDashboardThumbnail: View {
    let item: ShelfItem
    @State private var thumbnail: NSImage?

    var body: some View {
        Image(nsImage: thumbnail ?? item.icon)
            .resizable()
            .scaledToFill()
            .frame(width: 32, height: 32)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(.black.opacity(0.8), lineWidth: 1.5)
            }
            .accessibilityHidden(true)
            .task(id: item.id) {
                guard let url = item.fileURL else { return }
                thumbnail = await ThumbnailService.shared.thumbnail(
                    for: url, size: CGSize(width: 48, height: 48))
            }
    }
}
