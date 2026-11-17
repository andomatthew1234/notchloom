import SwiftUI

struct NotchToolsView: View {
    @ObservedObject private var focus = FocusTimerManager.shared
    @ObservedObject private var apps = QuickAppsManager.shared
    @ObservedObject private var audio = AudioOutputManager.shared

    var body: some View {
        HStack(spacing: 10) {
            focusCard
            appsCard
            audioCard
        }
        .padding(.top, 5)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var focusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "timer")
                    .foregroundStyle(.cyan)
                Text("Focus")
                    .fontWeight(.semibold)
                Spacer(minLength: 0)
                Menu {
                    Button("5 minutes") { focus.start(minutes: 5) }
                    Button("15 minutes") { focus.start(minutes: 15) }
                    Button("25 minutes") { focus.start(minutes: 25) }
                    Button("50 minutes") { focus.start(minutes: 50) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.white.opacity(0.65))
                }
                .menuStyle(.borderlessButton)
                .frame(width: 20)
                .help("Choose a focus duration")
            }
            .font(.system(size: 12))

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(focus.phase == .finished ? "Done" : focus.timeLabel)
                    .font(.system(size: 25, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                Spacer(minLength: 0)
                if focus.phase == .running || focus.phase == .paused {
                    Button {
                        focus.reset()
                    } label: {
                        Image(systemName: "xmark")
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
                        .frame(width: 27, height: 27)
                        .background(.cyan, in: Circle())
                        .foregroundStyle(.black)
                }
                .help(focus.phase == .running ? "Pause focus timer" : "Start focus timer")
            }

            ProgressView(value: focus.progress)
                .tint(.cyan)
                .controlSize(.mini)
            Text(focus.phase == .finished ? "Nice work. Take a break." : "A little time for one thing.")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
        }
        .toolCard(width: 192)
    }

    private var appsCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 5) {
                Image(systemName: "square.grid.2x2.fill")
                    .foregroundStyle(.cyan)
                Text("Quick apps")
                    .fontWeight(.semibold)
                Spacer(minLength: 0)
                if apps.favorites.count < QuickAppsManager.limit {
                    Button {
                        apps.chooseApps()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help("Add a favorite app")
                }
            }
            .font(.system(size: 12))

            HStack(spacing: 5) {
                ForEach(apps.favorites, id: \.self) { bundleID in
                    Button {
                        apps.launch(bundleID)
                    } label: {
                        if let icon = apps.icon(for: bundleID) {
                            Image(nsImage: icon)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 31, height: 31)
                        } else {
                            Image(systemName: "app.dashed")
                                .frame(width: 31, height: 31)
                        }
                    }
                    .help("Open \(apps.name(for: bundleID))")
                    .disabled(apps.appURL(for: bundleID) == nil)
                }
            }
            .frame(height: 36, alignment: .leading)

            Spacer(minLength: 0)
            Text(apps.message ?? "Your favorites, one click away.")
                .font(.system(size: 10))
                .foregroundStyle(apps.message == nil ? .white.opacity(0.55) : .orange)
                .lineLimit(1)
        }
        .toolCard(width: 182)
    }

    private var audioCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 5) {
                Image(systemName: "speaker.wave.2.fill")
                    .foregroundStyle(.cyan)
                Text("Sound output")
                    .fontWeight(.semibold)
            }
            .font(.system(size: 12))

            Menu {
                ForEach(audio.devices) { device in
                    Button {
                        audio.select(device)
                    } label: {
                        Label(device.name, systemImage: device.id == audio.selectedID
                            ? "checkmark" : device.symbol)
                    }
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: audio.selectedDevice?.symbol ?? "speaker.slash")
                        .font(.system(size: 16))
                        .frame(width: 25)
                    Text(audio.selectedDevice?.name ?? "No output")
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .frame(maxWidth: .infinity, minHeight: 36)
            }
            .menuStyle(.borderlessButton)
            .disabled(audio.devices.isEmpty)
            .help("Choose sound output")

            Spacer(minLength: 0)
            Text(audio.message ?? "Switch speakers instantly.")
                .font(.system(size: 10))
                .foregroundStyle(audio.message == nil ? .white.opacity(0.55) : .orange)
                .lineLimit(1)
        }
        .toolCard(width: 184)
    }
}

private extension View {
    func toolCard(width: CGFloat) -> some View {
        self
            .padding(12)
            .frame(width: width, height: 124, alignment: .topLeading)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1))
            .buttonStyle(.plain)
    }
}
