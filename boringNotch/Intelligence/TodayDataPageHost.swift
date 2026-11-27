import SwiftUI

struct TodayDataPageHost: View {
    @ObservedObject var controller: TodayContextController
    var expansionNamespace: Namespace.ID?
    var onBack: () -> Void
    var onClose: () -> Void
    var onSources: () -> Void
    var briefings: TodayBriefingCoordinator? = nil
    var onModels: () -> Void = {}
    var prepareLocationPermission: (@MainActor () async -> Void)? = nil
    @State private var locationPresenterID = UUID()
    @State private var inspecting = false
    var body: some View {
        Group {
            if let briefings {
                TodayBriefingPage(controller: controller, briefings: briefings, expansionNamespace: expansionNamespace,
                                  onBack: onBack, onClose: onClose, onSources: onSources, onModels: onModels)
            } else if controller.showingSetup {
                TodaySetupView(controller: controller).padding(8)
            } else if inspecting {
                TodayContextInspector(controller: controller, onBack: { inspecting = false }, onClose: onClose)
            } else if controller.configured {
                if let document = try? TodayContextPresentation.document(snapshot: controller.snapshot, settings: controller.settings, busy: controller.busy, message: controller.message) {
                    TodayPageView(document: document, expansionNamespace: expansionNamespace, onBack: onBack, onClose: onClose,
                                  onRefresh: { controller.refresh(force: true) }, onInspect: { inspecting = true }, onSources: onSources, isRefreshing: controller.busy)
                } else { TodayUnavailableView(onBack: onBack) }
            } else {
                VStack(spacing: 10) {
                    HStack {
                        Text(controller.settings.setupCompleted ? "Local collection is off." : "Connect your day when you’re ready.").font(.system(size: 12)).foregroundStyle(.secondary)
                        Spacer()
                        Button(controller.settings.setupCompleted ? "Data sources" : "Set up Today") {
                            if controller.settings.setupCompleted { onSources() } else { controller.showingSetup = true }
                        }.buttonStyle(.bordered)
                    }.padding(.horizontal, 8)
                    if case .success(let document) = TodayPreviewContent.standard {
                        TodayPageView(document: document, expansionNamespace: expansionNamespace, onBack: onBack, onClose: onClose, onSources: onSources)
                    } else { TodayUnavailableView(onBack: onBack) }
                }
            }
        }
        .onAppear {
            if let prepareLocationPermission { controller.registerLocationPresenter(locationPresenterID, prepare: prepareLocationPermission) }
            controller.beginPresentation(); briefings?.open()
        }
        .onDisappear {
            controller.unregisterLocationPresenter(locationPresenterID)
            briefings?.close(); controller.endPresentation(); controller.showingSetup = false; controller.cancelCitySearch()
        }
    }
}

struct TodayContextInspector: View {
    @ObservedObject var controller: TodayContextController
    var onBack: () -> Void
    var onClose: (() -> Void)? = nil
    var briefings: TodayBriefingCoordinator? = nil
    @State private var showsOutgoing = false
    private var json: String { controller.snapshot.flatMap { try? $0.encoded() }.flatMap { String(data: $0, encoding: .utf8) } ?? "No local snapshot collected. Refresh selected sources to inspect them." }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button(action: onBack) { Label("Back", systemImage: "chevron.left") }
                Spacer()
                Button("Refresh") { controller.refresh(force: true) }.disabled(controller.busy || !controller.configured)
                if let onClose { Button(action: onClose) { Image(systemName: "xmark") }.accessibilityLabel("Close Today") }
            }.buttonStyle(.bordered)
            Label("Collected on this Mac", systemImage: "lock.doc").font(.system(size: 23, weight: .medium, design: .rounded))
            Text(showsOutgoing ? "This is the bounded JSON context used for Gemini generation. Preparing this preview makes no Gemini request." : "Local source snapshot. No API keys are included; outgoing Gemini context is minimized separately.").font(.system(size: 12)).foregroundStyle(.secondary)
            if let briefings {
                HStack {
                    Picker("Inspect", selection: $showsOutgoing) { Text("Local sources").tag(false); Text("Outgoing context").tag(true) }.pickerStyle(.segmented)
                    if showsOutgoing { Button("Prepare preview") { briefings.previewOutgoing() }.disabled(briefings.busy) }
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !showsOutgoing { ForEach(TodaySourceID.allCases, id: \.self) { source in
                        let status = controller.snapshot?.sourceStatus[source]
                        VStack(alignment: .leading, spacing: 4) {
                            Text(source.title + " · " + (status?.state.displayName ?? "Not collected") + " · \(status?.itemCount ?? 0) items").fontWeight(.semibold)
                            if let status { Text(status.message); if let time = status.collectedAt { Text("Collected " + time.formatted(date: .abbreviated, time: .standard)) } }
                        }.font(.system(size: 11)).frame(maxWidth: .infinity, alignment: .leading)
                    } }
                    Divider()
                    Text(showsOutgoing ? briefings?.outgoing.map { String(decoding: $0, as: UTF8.self) } ?? "Press Prepare preview to inspect the outgoing context. No Gemini request is made." : json)
                        .font(.system(size: 10, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }.padding(16)
            }.background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 16)).background(ScrollGestureExclusionArea())
        }.foregroundStyle(.white).preferredColorScheme(.dark)
    }
}
