import AppKit
import SwiftUI

@MainActor private final class TodayMotionState: ObservableObject {
    @Published var expanded = false
    var reportedFrame = CGRect.zero
}

private struct TodayMotionFixture: View {
    @ObservedObject var state: TodayMotionState
    let document: TodayPageDocument
    @Namespace private var expansion
    var body: some View {
        VStack(spacing: 8) {
            Color.clear.frame(height: 38)
            ZStack(alignment: .top) {
              if state.expanded {
                TodayPageView(document: document, expansionNamespace: expansion)
                    .padding(.horizontal, 31).padding(.bottom, 18)
                    .transition(.identity)
                    .zIndex(1)
            } else {
              VStack {
                HStack {
                    TodayWidget(slots: 3, expansionNamespace: expansion).frame(width: 364)
                    Spacer(minLength: 0)
                }.padding(.horizontal, 31)
                Spacer(minLength: 0)
              }.transition(.opacity.animation(.easeOut(duration: 0.08)))
            }
            }
        }
        .frame(width: 744, height: state.expanded ? 728 : 224, alignment: .top)
        .background(NotchShape(topCornerRadius: 19, bottomCornerRadius: 24).fill(.black))
        .clipShape(NotchShape(topCornerRadius: 19, bottomCornerRadius: 24))
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("motion-host")) } action: { state.reportedFrame = $0 }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .coordinateSpace(name: "motion-host")
        .background(Color(white: 0.13))
    }
}

@MainActor private final class TodayEffectsState: ObservableObject {
    @Published var working = true
    @Published var emphasized = false
    @Published var reduced = false
    @Published var enabled = true
}

private struct TodayEffectsFixture: View {
    @ObservedObject var state: TodayEffectsState
    let widget: TodayLinkedWidget
    var body: some View {
        VStack(spacing: 18) {
            TodayAtmosphere(working: state.working).frame(height: 160).clipShape(RoundedRectangle(cornerRadius: 22))
            TodayPageNotice(message: state.working ? "Preparing a synthetic briefing…" : "Your briefing is ready", working: state.working)
            TodayLinkedWidgetCard(widget: widget, emphasized: state.emphasized, hovered: state.emphasized)
                .frame(width: 260)
        }.padding(20).frame(width: 560, height: 510).background(.black)
            // SwiftUI's OS preference is read-only. Exercise its effective disabled-motion policy
            // locally without changing the user's Accessibility settings.
            .environment(\.todayAnimationsEnabled, state.enabled && !state.reduced)
    }
}

enum TodayMotionReview {
    @MainActor static func render(folder: URL, document: TodayPageDocument) async throws -> Int {
        let state = TodayMotionState()
        let host = NSHostingView(rootView: TodayMotionFixture(state: state, document: document).preferredColorScheme(.dark))
        let window = NSWindow(contentRect: CGRect(x: -5000, y: -5000, width: 800, height: 756), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(120))
        var checks = 0
        for opening in [true, false] {
            withAnimation(.spring(response: 0.46, dampingFraction: 0.91)) { state.expanded = opening }
            for frame in 0..<6 {
                try await Task.sleep(for: .milliseconds(90))
                host.layoutSubtreeIfNeeded()
                precondition(abs(state.reportedFrame.minY) < 1 && abs(state.reportedFrame.midX - 400) < 1, "Today surface stays at top center")
                checks += 1
                try TodayPresentationTests.snapshot(host, path: folder.appendingPathComponent("\(opening ? "open" : "back")-\(frame).png"))
            }
        }
        window.close()
        checks += try await effects(folder: folder, widget: document.registry.widgets(for: document.report)[0])
        return checks
    }

    @MainActor private static func effects(folder: URL, widget: TodayLinkedWidget) async throws -> Int {
        let state = TodayEffectsState()
        let host = NSHostingView(rootView: TodayEffectsFixture(state: state, widget: widget).preferredColorScheme(.dark))
        let window = NSWindow(contentRect: .init(x: -5000, y: -5000, width: 560, height: 510), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; host.layoutSubtreeIfNeeded()
        for frame in 0..<12 {
            if frame == 4 { state.emphasized = true }
            if frame == 8 { state.emphasized = false }
            try await Task.sleep(for: .milliseconds(75))
            host.layoutSubtreeIfNeeded()
            try TodayPresentationTests.snapshot(host, path: folder.appendingPathComponent("effects-\(frame).png"))
        }
        func pixels() -> Data {
            host.layoutSubtreeIfNeeded()
            let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: bitmap)
            return Data(bytes: bitmap.bitmapData!, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
        }
        var checks = 0
        // A working indicator must settle under the reduced/disabled-motion policy and after work ends.
        for mode in ["reduced", "disabled", "idle"] {
            state.reduced = mode == "reduced"
            state.enabled = mode != "disabled"
            state.working = mode != "idle"
            try await Task.sleep(for: .milliseconds(1100))
            let before = pixels()
            try TodayPresentationTests.snapshot(host, path: folder.appendingPathComponent("motion-\(mode)-before.png"))
            try await Task.sleep(for: .milliseconds(220))
            try TodayPresentationTests.snapshot(host, path: folder.appendingPathComponent("motion-\(mode)-after.png"))
            precondition(before == pixels(), "\(mode) Today artwork and indicators must settle without continuous animation")
            checks += 1
            try TodayPresentationTests.snapshot(host, path: folder.appendingPathComponent("motion-\(mode).png"))
        }
        window.close()
        return checks
    }
}
