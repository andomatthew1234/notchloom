import AppKit
import SwiftUI

@MainActor private final class FixtureState: ObservableObject {
    @Published var open = false
    var mounts = 0
    var contentSize: CGSize = .zero
}

private struct SizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

private struct IdentityProbe: NSViewRepresentable {
    let state: FixtureState
    func makeNSView(context: Context) -> NSView { state.mounts += 1; return NSView() }
    func updateNSView(_ view: NSView, context: Context) {}
}

/// Flexible player content detects changes to layout proposals; a persistent
/// AppKit child detects the subtree replacement that broke matched geometry.
private struct PlayerFixture: View {
    @ObservedObject var state: FixtureState
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Color.green.frame(width: state.open ? 90 : 20, height: state.open ? 90 : 20)
                if state.open {
                    GeometryReader { _ in
                        VStack(alignment: .leading) {
                            Text("Now Playing").font(.headline)
                            Text("A track with a long title to exercise flexible sizing")
                            Spacer()
                            Image(systemName: "pause.fill")
                        }
                    }.frame(height: 90)
                } else {
                    Color.clear.frame(width: 185, height: 32)
                    Color.blue.frame(width: 20, height: 20)
                }
            }
            if state.open { Color.clear.frame(height: 40) }
        }
        .padding(state.open ? 12 : 0)
        .background(IdentityProbe(state: state))
        .background(GeometryReader { Color.clear.preference(key: SizeKey.self, value: $0.size) })
        .onPreferenceChange(SizeKey.self) { state.contentSize = $0 }
    }
}

private struct FixtureHost: View {
    @ObservedObject var state: FixtureState
    let presentation: NotificationPresentation
    let wrapped: Bool
    var body: some View {
        Group {
            if wrapped {
                PlayerFixture(state: state)
                    .modifier(NotificationNotchSurface(presentation: presentation, screenID: "fixture",
                        screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900), topInset: 32,
                        blocked: state.open, normalShape: NotchShape(), normalShadow: false))
            } else {
                PlayerFixture(state: state)
            }
        }
        .frame(width: 640, height: 210, alignment: .top)
    }
}

@main struct NotchLayoutRegressionTests {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        let original = FixtureState(), wrapped = FixtureState()
        let presentation = NotificationPresentation(monitorClicks: false)
        let baseline = NSHostingView(rootView: FixtureHost(state: original, presentation: presentation, wrapped: false))
        let actual = NSHostingView(rootView: FixtureHost(state: wrapped, presentation: presentation, wrapped: true))
        let hosts = [baseline, actual]
        for host in hosts { host.frame = CGRect(x: 0, y: 0, width: 640, height: 210) }

        func settle() async throws {
            for host in hosts { host.layoutSubtreeIfNeeded() }
            try await Task.sleep(for: .milliseconds(40))
            for host in hosts { host.layoutSubtreeIfNeeded() }
        }
        try await settle()
        precondition(wrapped.mounts == 1, "Probe must mount to make identity checks meaningful")
        for index in 0..<12 {
            original.open = index.isMultiple(of: 2)
            wrapped.open = original.open
            try await settle()
            precondition(wrapped.contentSize == original.contentSize,
                "Notification wrapper changed normal player sizing: \(wrapped.contentSize) vs \(original.contentSize)")
            precondition(wrapped.mounts == 1, "Opening the menu rebuilt persistent player content")
        }
        let closedSize = wrapped.contentSize
        presentation.enqueue(.init(id: "layout-test", source: "Notchloom", title: "Ready", body: "Layout regression check"))
        try await Task.sleep(for: .milliseconds(1100))
        try await settle()
        precondition(presentation.phase == .displaying, "Notification must actually expand")
        precondition(wrapped.contentSize == closedSize, "Notification size leaked into the hidden player")
        precondition(wrapped.mounts == 1, "Notification replaced the persistent player")
        presentation.dismiss()
        try await Task.sleep(for: .milliseconds(750))
        try await settle()
        precondition(presentation.phase == .idle)
        precondition(wrapped.contentSize == closedSize && wrapped.mounts == 1,
            "Dismissal did not preserve the original player")
        print("PASS: 12 open/close transitions retain player identity and original sizing; notification expansion/dismissal preserves both")
    }
}
