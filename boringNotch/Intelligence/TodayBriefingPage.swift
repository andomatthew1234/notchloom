import SwiftUI

struct TodayBriefingPage: View {
    @ObservedObject var controller: TodayContextController
    @ObservedObject var briefings: TodayBriefingCoordinator
    var expansionNamespace: Namespace.ID?
    var onBack: () -> Void
    var onClose: () -> Void
    var onSources: () -> Void
    var onModels: () -> Void
    var animationsEnabled = true
    @State private var inspecting = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(spacing: 10) {
            Group {
                if controller.showingSetup {
                    TodaySetupView(controller: controller, onFinished: briefings.resume).padding(8)
                        .transition(pageTransition)
                } else if inspecting {
                    TodayContextInspector(controller: controller, onBack: { inspecting = false }, onClose: onClose, briefings: briefings)
                        .transition(pageTransition)
                } else if let document = briefings.document {
                    report(document)
                } else { introduction.transition(pageTransition) }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onExitCommand(perform: onClose)
        .environment(\.todayAnimationsEnabled, animationsEnabled)
        .animation(motionAnimation, value: inspecting)
        .animation(motionAnimation, value: controller.showingSetup)
        .animation(motionAnimation, value: briefings.state)
        .animation(reduceMotion || !animationsEnabled ? nil : .easeInOut(duration: 0.3), value: briefings.entry?.generatedAt)
    }
    private var motionAnimation: Animation? { reduceMotion || !animationsEnabled ? nil : .spring(response: 0.44, dampingFraction: 0.9) }
    private var pageTransition: AnyTransition { TodayMotion.transition(animated: !reduceMotion && animationsEnabled) }
    private func report(_ document: TodayPageDocument) -> some View {
        VStack(spacing: 8) {
            if briefings.state == .geminiRequired {
                HStack { Text("Gemini needs attention.").font(.system(size: 11)); Spacer(); Button("Models", action: onModels).buttonStyle(.bordered) }
            }
            TodayPageView(document: document, expansionNamespace: expansionNamespace, animationsEnabled: animationsEnabled, onBack: onBack, onClose: onClose,
                          onRefresh: briefings.refresh, onInspect: { inspecting = true }, onSources: onSources, isRefreshing: briefings.busy,
                          notice: reportNotice, noticeIsError: briefings.state == .failed,
                          onCancelRefresh: briefings.busy ? { briefings.cancel() } : nil)
                .id(briefings.entry?.generatedAt).transition(pageTransition)
        }
        .transformPreference(TodayPreferredContentHeightKey.self) { height in
            // This recovery row sits outside the measured page. Keep its full
            // scrollable layout until the user's model configuration is restored.
            if briefings.state == .geminiRequired { height = nil }
        }
    }
    private var reportNotice: String? {
        if let message = briefings.message { return message }
        if briefings.busy { return "Preparing a fresh briefing. Your earlier briefing is below." }
        if briefings.stale { return "Earlier briefing · refresh for the latest information" }
        return nil
    }
    private var introduction: some View {
        VStack(alignment: .leading, spacing: 18) {
            TodayPageToolbar(onBack: onBack, onClose: onClose, onInspect: { inspecting = true }, onSources: onSources)
                .todayArrival()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Label("TODAY", systemImage: "sun.horizon").font(.system(size: 10, weight: .semibold)).tracking(1.8).foregroundStyle(.white.opacity(0.7))
                        Spacer()
                        Text(Date.now, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                            .font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
                    }.padding(.horizontal, 3).todayArrival(1)
                    welcomeCard.id(title).transition(pageTransition).todayArrival(2)
                    if briefings.state == .consentRequired { consentDetails.todayArrival(3); actions.todayArrival(4) }
                    else if briefings.state != .setupRequired { sourceSummary }
                    Label("You choose what goes into your briefing.", systemImage: "lock.shield")
                        .font(.system(size: 10)).foregroundStyle(.white.opacity(0.43))
                        .frame(maxWidth: .infinity).padding(.top, 1)
                }
                .frame(maxWidth: 680)
                .padding(.horizontal, 2).padding(.top, 6).padding(.bottom, 20)
                .frame(maxWidth: .infinity)
                .todayPreferredContentHeight(extra: 32 + 18)
            }.scrollIndicators(.hidden).background(ScrollGestureExclusionArea())
        }.foregroundStyle(.white)
    }
    private var welcomeCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label(briefings.state == .failed ? "READY TO TRY AGAIN" : briefings.busy ? "PREPARING YOUR BRIEFING" : "YOUR DAILY BRIEFING",
                  systemImage: briefings.state == .failed ? "arrow.clockwise" : "sparkle")
                .font(.system(size: 9, weight: .semibold)).tracking(1.5)
                .foregroundStyle(TodayPalette.blue).padding(.bottom, 19)
            Text(title).font(.system(size: 29, weight: .medium, design: .rounded)).tracking(-0.8)
                .contentTransition(.opacity)
                .fixedSize(horizontal: false, vertical: true)
            Text(detail).font(.system(size: 13)).foregroundStyle(TodayPalette.secondary).lineSpacing(4)
                .contentTransition(.opacity)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 11)
                .frame(maxWidth: 450, alignment: .leading)
            if briefings.message != nil || briefings.busy {
                TodayGenerationBanner(state: briefings.state, message: briefings.message, hasReport: false,
                                      stale: false, onCancel: briefings.cancel).padding(.top, 21).transition(pageTransition)
            }
            if !briefings.busy && briefings.state != .consentRequired { actions.padding(.top, 23).transition(pageTransition) }
        }
        .padding(26).frame(maxWidth: .infinity, alignment: .leading)
        .background { TodayAtmosphere(working: briefings.busy) }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.10)))
    }
    private var sourceSummary: some View {
        let selected = TodaySourceID.allCases.filter(controller.settings.enabled)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Included in your briefing").font(.system(size: 11, weight: .medium)).foregroundStyle(TodayPalette.secondary)
                Spacer()
                Button("Edit sources", action: onSources).font(.system(size: 11)).foregroundStyle(TodayPalette.blue).buttonStyle(TodayMotionButtonStyle())
            }
            if selected.isEmpty {
                Text("No sources selected. Add a source to get started.").font(.system(size: 12)).foregroundStyle(TodayPalette.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(Array(selected.enumerated()), id: \.element) { index, source in
                        Label(source.title, systemImage: source.symbol)
                            .font(.system(size: 11)).foregroundStyle(TodayPalette.ink.opacity(0.8))
                            .padding(.horizontal, 12).padding(.vertical, 11)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 11))
                            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(.white.opacity(0.05)))
                            .todayHover().todayArrival(index + 4)
                    }
                }
            }
        }.padding(.horizontal, 3).todayArrival(3)
    }
    private var title: String {
        switch briefings.state {
        case .setupRequired: "Connect your day."
        case .geminiRequired: "Connect your intelligence."
        case .consentRequired: "Your day. Your choice."
        case .empty: "A little room for today."
        case .failed: "Let’s try that again."
        case .collecting, .generating: "Your day is taking shape."
        default: "Your day, at a glance."
        }
    }
    private var detail: String {
        switch briefings.state {
        case .setupRequired: "Choose your local sources first. Each optional source starts off, and permissions are requested one at a time."
        case .geminiRequired: "Add your Gemini key and choose a Today model in Intelligence → Models. Then you’re ready to prepare your first briefing."
        case .consentRequired: "To prepare a personal briefing, Notchloom sends the available information from your selected sources to Google’s Gemini API. An API key alone never grants this permission."
        case .empty: "There isn’t usable context yet. Date and time alone can support a simple briefing; other sources are optional."
        case .failed: "Your sources and preferences are saved. You can retry without setting anything up again."
        case .collecting, .generating: "You can return to your Dashboard or cancel at any time."
        default: "Prepare a concise briefing from the sources you choose. You can inspect the outgoing context first."
        }
    }
    private var consentDetails: some View {
        VStack(alignment: .leading, spacing: 13) {
            ForEach(TodaySourceID.allCases, id: \.self) { source in
                HStack {
                    Label(source.title, systemImage: source.symbol)
                    Spacer()
                    Text(controller.settings.enabled(source) ? "Selected" : "Off").foregroundStyle(.secondary)
                }.font(.system(size: 12))
            }
            Divider()
            Text("Only available, authorized fields are sent: local date/time, a city-level forecast, up to six upcoming events, and up to three short observed-banner excerpts. No calendar notes, native event IDs, meeting links, full histories or precise coordinates are sent to Gemini.")
            Text("One request is made when a new briefing is needed or you press Refresh. Google API usage may incur charges. Reports and the selected native card details are encrypted locally for up to 24 hours; reports involving banner excerpts expire within 30 minutes of those observations. There is no briefing history.")
            Text("You can revoke this consent, disable a source or clear reports in Settings → Today → Data sources. Clearing local reports cannot retract a request already processed by Google.")
            HStack { Button("Inspect outgoing context") { inspecting = true; briefings.previewOutgoing() }; Button("Change sources", action: onSources) }.buttonStyle(.bordered)
        }.font(.system(size: 11)).foregroundStyle(.white.opacity(0.75)).padding(18)
            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 17))
    }
    @ViewBuilder private var actions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { primaryAction; secondaryAction }
            VStack(alignment: .leading, spacing: 12) { primaryAction; secondaryAction }
        }
    }
    @ViewBuilder private var primaryAction: some View {
        Group {
            switch briefings.state {
            case .setupRequired: Button { controller.showingSetup = true } label: { Label("Set up Today", systemImage: "arrow.right") }
            case .geminiRequired: Button(action: onModels) { Label("Choose a model", systemImage: "sparkle") }
            case .consentRequired: Button(action: briefings.allowGeneration) { Label("Allow & prepare Today", systemImage: "sparkle") }
            case .empty: Button(action: onSources) { Label("Choose sources", systemImage: "slider.horizontal.3") }
            case .collecting, .generating: EmptyView()
            case .failed: Button(action: briefings.refresh) { Label("Try again", systemImage: "arrow.clockwise") }
            default: Button(action: briefings.refresh) { Label("Prepare Today", systemImage: "sparkle") }
            }
        }.buttonStyle(TodayPrimaryActionStyle())
            .font(.system(size: 12, weight: .semibold)).disabled(briefings.busy)
    }
    @ViewBuilder private var secondaryAction: some View {
        if briefings.state != .setupRequired && briefings.state != .geminiRequired && briefings.state != .consentRequired && briefings.state != .empty {
            Button { inspecting = true; briefings.previewOutgoing() } label: { Text("Inspect context").font(.system(size: 11)) }
                .buttonStyle(TodayMotionButtonStyle()).foregroundStyle(.white.opacity(0.65))
        }
    }
}

private struct TodayPrimaryActionStyle: ButtonStyle {
    @State private var hovered = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.todayAnimationsEnabled) private var motionEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.padding(.horizontal, 16).padding(.vertical, 10)
            .foregroundStyle(Color(red: 0.025, green: 0.10, blue: 0.13))
            .background(Color(red: 0.44, green: 0.82, blue: 0.90).opacity(enabled ? 1 : 0.45), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.2)))
            .shadow(color: TodayPalette.blue.opacity(hovered && enabled ? 0.18 : 0), radius: hovered ? 12 : 0, y: 3)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(!reduceMotion && motionEnabled && enabled ? configuration.isPressed ? 0.96 : hovered ? 1.035 : 1 : 1)
            .animation(reduceMotion || !motionEnabled ? nil : .spring(response: 0.28, dampingFraction: 0.7), value: configuration.isPressed)
            .animation(reduceMotion || !motionEnabled ? nil : .spring(response: 0.30, dampingFraction: 0.8), value: hovered)
            .onHover { hovered = $0 }
    }
}

struct TodayGenerationBanner: View {
    let state: TodayGenerationState
    let message: String?
    let hasReport: Bool
    let stale: Bool
    var onCancel: () -> Void
    var body: some View {
        TodayPageNotice(message: state == .generating ? "Preparing your Today…" : state == .collecting ? "Gathering selected sources…" : message ?? (stale ? "Earlier briefing · refresh for the latest information" : hasReport ? "Your briefing is ready" : "A little clarity for your day"),
                        isError: state == .failed, working: state.busy, onCancel: state.busy ? onCancel : nil)
    }
}

struct TodayBriefingPrivacyControls: View {
    @ObservedObject var briefings: TodayBriefingCoordinator
    var body: some View {
        TodaySettingsCard("Gemini briefings", symbol: "sparkle") {
            Label(briefings.hasConsent ? "Allowed for the current source choices" : "Consent required in Today", systemImage: briefings.hasConsent ? "checkmark.shield" : "hand.raised")
            Text("Google processes the minimized context when a briefing is needed. An API key does not grant consent. Changing source scope requires a new choice in Today. API usage may incur charges.").foregroundStyle(.secondary)
            Text("One encrypted report is stored locally for up to 24 hours, with only selected native card details. Reports involving observed banners expire within 30 minutes of the observations. No raw source snapshot, complete prompt or briefing history is saved.").foregroundStyle(.secondary)
            HStack {
                Button("Revoke Gemini consent", action: briefings.revokeConsent).disabled(!briefings.hasConsent)
                Button("Clear cached briefings", action: briefings.clearReports)
            }
            if let entry = briefings.entry {
                Text("Last briefing: " + entry.generatedAt.formatted(date: .abbreviated, time: .shortened) + " · " + entry.model).foregroundStyle(.secondary)
                if let usage = entry.usage { Text("Reported tokens: \(usage.totalTokenCount.map(String.init) ?? "not supplied"). This is usage metadata, not a bill.").foregroundStyle(.secondary) }
            }
        }
    }
}
