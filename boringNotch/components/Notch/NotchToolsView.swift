import Defaults
import SwiftUI

/// Overview keeps its tools inside the open notch, with a stable bottom tab bar.
struct NotchToolsView: View {
    @EnvironmentObject private var vm: BoringViewModel
    @ObservedObject private var focus = FocusTimerManager.shared
    @ObservedObject private var apps = QuickAppsManager.shared
    @ObservedObject private var music = MusicManager.shared
    @ObservedObject private var webcam = WebcamManager.shared
    @ObservedObject private var battery = BatteryStatusViewModel.shared
    @Default(.showCalendar) private var showCalendar
    @Default(.showMirror) private var showMirror
    @Default(.showBatteryIndicator) private var showBattery
    @State private var panel: OverviewPanel = .dashboard

    private enum OverviewPanel: Equatable {
        case dashboard
        case calendar
        case focus
        case mirror
    }

    private var hasTrack: Bool {
        music.isPlaying || (!music.songTitle.isEmpty && music.songTitle != "I'm Handsome")
    }

    var body: some View {
        VStack(spacing: 8) {
            panelContent
                .frame(height: 132, alignment: .top)
                .frame(maxWidth: .infinity)

            HStack(spacing: 5) {
                panelButton("Dashboard", icon: "square.grid.2x2.fill", for: .dashboard)
                panelButton("Calendar", icon: "calendar", for: .calendar)
                panelButton("Focus Timer", icon: "timer", for: .focus)
                if showMirror {
                    panelButton("Mirror", icon: "web.camera", for: .mirror)
                }

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
        .onDisappear { stopMirror() }
    }

    @ViewBuilder
    private var panelContent: some View {
        switch panel {
        case .dashboard:
            HStack(spacing: 12) {
                nowPlayingCard.frame(maxWidth: .infinity)
                appsSection.frame(width: 230, alignment: .topLeading)
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
            withAnimation(.snappy(duration: 0.25, extraBounce: 0)) { panel = target }
        } label: {
            Label(title, systemImage: icon)
                .padding(.horizontal, 10)
                .frame(height: 27)
                .background(panel == target ? .white.opacity(0.16) : .clear, in: Capsule())
                .contentShape(Capsule())
        }
        .foregroundStyle(panel == target ? .white : .white.opacity(0.62))
        .accessibilityAddTraits(panel == target ? .isSelected : [])
    }

    private func stopMirror() {
        if vm.isCameraExpanded || webcam.isSessionRunning {
            webcam.stopSession()
            vm.isCameraExpanded = false
        }
    }

    private var nowPlayingCard: some View {
        HStack(spacing: 12) {
            Group {
                if !hasTrack {
                    Image(systemName: "music.note")
                        .font(.system(size: 25, weight: .light))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(width: 76, height: 76)
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 13))
                } else {
                    Image(nsImage: music.albumArt)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 76, height: 76)
                        .clipShape(RoundedRectangle(cornerRadius: 13))
                }
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Label("Now Playing", systemImage: "play.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.cyan)
                Text(hasTrack ? music.songTitle : "Nothing playing")
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(hasTrack ? music.artistName : "Your music will appear here.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
                if hasTrack {
                    HStack(spacing: 13) {
                        Button { music.previousTrack() } label: {
                            Image(systemName: "backward.fill")
                        }
                        .help("Previous track")
                        Button { music.playPause() } label: {
                            Image(systemName: music.isPlaying ? "pause.fill" : "play.fill")
                        }
                        .help(music.isPlaying ? "Pause" : "Play")
                        Button { music.nextTrack() } label: {
                            Image(systemName: "forward.fill")
                        }
                        .help("Next track")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.88))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 108)
        .padding(.horizontal, 14)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 17))
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
