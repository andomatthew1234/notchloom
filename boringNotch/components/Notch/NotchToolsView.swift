import Defaults
import SwiftUI

/// Overview contains the non-music tools on the same continuous notch surface.
struct NotchToolsView: View {
    @EnvironmentObject private var vm: BoringViewModel
    @ObservedObject private var focus = FocusTimerManager.shared
    @ObservedObject private var apps = QuickAppsManager.shared
    @ObservedObject private var audio = AudioOutputManager.shared
    @ObservedObject private var webcam = WebcamManager.shared
    @ObservedObject private var battery = BatteryStatusViewModel.shared
    @Default(.showCalendar) private var showCalendar
    @Default(.showMirror) private var showMirror
    @Default(.showBatteryIndicator) private var showBattery
    @Default(.settingsIconInNotch) private var showSettings
    @State private var panel: OverviewPanel = .tools

    private enum OverviewPanel: Equatable {
        case tools
        case calendar
        case mirror
    }

    var body: some View {
        VStack(spacing: 7) {
            panelContent
                .frame(height: 133, alignment: .top)
                .frame(maxWidth: .infinity, alignment: .top)

            HStack(spacing: 5) {
                panelButton("Tools", icon: "square.grid.2x2.fill", for: .tools)
                if showCalendar {
                    panelButton("Calendar", icon: "calendar", for: .calendar)
                }
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
                if showSettings {
                    Button {
                        SettingsWindowController.shared.showWindow()
                    } label: {
                        Image(systemName: "gearshape")
                            .frame(width: 28, height: 28)
                            .contentShape(Circle())
                    }
                    .help("Notchloom Settings")
                }
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(0.78))
            .frame(height: 29)
            .padding(.horizontal, 10)
        }
        .padding(.top, 4)
        .frame(maxWidth: .infinity, alignment: .top)
        .buttonStyle(.plain)
        .onChange(of: showCalendar) { _, enabled in
            if !enabled && panel == .calendar { panel = .tools }
        }
        .onChange(of: showMirror) { _, enabled in
            if !enabled && panel == .mirror {
                stopMirror()
                panel = .tools
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
        case .tools:
            HStack(alignment: .top, spacing: 0) {
                focusSection.frame(width: 184, alignment: .topLeading)
                sectionDivider
                appsSection.frame(width: 182, alignment: .topLeading)
                sectionDivider
                audioSection.frame(width: 170, alignment: .topLeading)
            }
            .padding(.top, 5)
        case .calendar:
            CalendarView()
                .frame(width: 570, height: 120)
                .onHover { vm.isHoveringCalendar = $0 }
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
                .padding(.horizontal, 9)
                .frame(height: 27)
                .background(panel == target ? .white.opacity(0.16) : .clear, in: Capsule())
                .contentShape(Capsule())
        }
        .accessibilityAddTraits(panel == target ? .isSelected : [])
    }

    private func stopMirror() {
        if vm.isCameraExpanded || webcam.isSessionRunning {
            webcam.stopSession()
            vm.isCameraExpanded = false
        }
    }

    private var sectionDivider: some View {
        Rectangle()
            .fill(.white.opacity(0.13))
            .frame(width: 1, height: 106)
            .padding(.horizontal, 10)
            .padding(.top, 5)
            .accessibilityHidden(true)
    }

    private var focusSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 5) {
                Image(systemName: "timer").foregroundStyle(.cyan)
                Text("Focus").foregroundStyle(.white)
                Spacer(minLength: 0)
                Menu {
                    Button("5 minutes") { focus.start(minutes: 5) }
                    Button("15 minutes") { focus.start(minutes: 15) }
                    Button("25 minutes") { focus.start(minutes: 25) }
                    Button("50 minutes") { focus.start(minutes: 50) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(width: 28, height: 28)
                        .contentShape(Circle())
                }
                .menuStyle(.borderlessButton)
                .help("Choose a focus duration")
            }
            .font(.system(size: 13, weight: .semibold))

            HStack(alignment: .center, spacing: 7) {
                Text(focus.phase == .finished ? "Done" : focus.timeLabel)
                    .font(.system(size: 27, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                if focus.phase == .running || focus.phase == .paused {
                    Button { focus.reset() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.68))
                            .frame(width: 28, height: 28)
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
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 30, height: 30)
                        .background(.cyan, in: Circle())
                }
                .help(focus.phase == .running ? "Pause focus timer" : "Start focus timer")
            }

            ProgressView(value: focus.progress)
                .tint(.cyan)
                .controlSize(.mini)
                .accessibilityLabel("Focus session progress")
            if focus.phase == .finished {
                Text("Session complete")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.65))
            }
        }
    }

    private var appsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
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
            .font(.system(size: 13, weight: .semibold))

            HStack(spacing: 6) {
                ForEach(apps.favorites, id: \.self) { bundleID in
                    Button { apps.launch(bundleID) } label: {
                        Group {
                            if let icon = apps.icon(for: bundleID) {
                                Image(nsImage: icon).resizable().scaledToFit()
                            } else {
                                Image(systemName: "app.dashed").resizable().scaledToFit()
                            }
                        }
                        .frame(width: 32, height: 32)
                        .frame(width: 36, height: 36)
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
    }

    private var audioSection: some View {
        VStack(alignment: .leading, spacing: 13) {
            Label("Sound output", systemImage: "speaker.wave.2.fill")
                .labelStyle(.titleAndIcon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)

            Menu {
                ForEach(audio.devices) { device in
                    Button { audio.select(device) } label: {
                        Label(device.name, systemImage: device.id == audio.selectedID
                            ? "checkmark" : device.symbol)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: audio.selectedDevice?.symbol ?? "speaker.slash")
                        .font(.system(size: 15)).frame(width: 20)
                    Text(audio.selectedDevice?.name ?? "No output")
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .frame(height: 42)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 11))
            }
            .menuStyle(.borderlessButton)
            .disabled(audio.devices.isEmpty)
            .help(audio.selectedDevice?.name ?? "Choose sound output")

            if let message = audio.message {
                Text(message).font(.system(size: 11))
                    .foregroundStyle(.orange).lineLimit(2)
            }
        }
    }
}
