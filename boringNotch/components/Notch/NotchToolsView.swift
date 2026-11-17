import SwiftUI

/// Overview shares Home's continuous black surface and content top edge.
struct NotchToolsView: View {
    @ObservedObject private var focus = FocusTimerManager.shared
    @ObservedObject private var apps = QuickAppsManager.shared
    @ObservedObject private var audio = AudioOutputManager.shared

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            focusSection.frame(width: 184, alignment: .topLeading)
            sectionDivider
            appsSection.frame(width: 182, alignment: .topLeading)
            sectionDivider
            audioSection.frame(width: 170, alignment: .topLeading)
        }
        .frame(height: 133, alignment: .top)
        .padding(.top, 5)
        .frame(maxWidth: .infinity, alignment: .top)
        .buttonStyle(.plain)
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
