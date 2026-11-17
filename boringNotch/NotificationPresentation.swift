import AppKit
import SwiftUI

struct NotchNotification: Decodable, Identifiable, Equatable {
    enum Kind { case standard, clockAlarm, clockTimer, clock }
    let id: String
    let source: String
    let title: String
    let body: String

    var fingerprint: String { "\(source)|\(title)|\(body)" }
    var isLocal: Bool { source == "Notchloom" }
    var isClock: Bool { source.localizedCaseInsensitiveCompare("Clock") == .orderedSame }
    var kind: Kind {
        guard isClock else { return .standard }
        let content = "\(title) \(body)"
        if content.localizedCaseInsensitiveContains("alarm") { return .clockAlarm }
        if content.localizedCaseInsensitiveContains("timer") { return .clockTimer }
        return .clock
    }

    var appURL: URL? {
        if let url = NSWorkspace.shared.runningApplications.first(where: {
            $0.localizedName?.localizedCaseInsensitiveCompare(source) == .orderedSame
        })?.bundleURL { return url }
        let knownApps = ["Messages": "com.apple.MobileSMS", "Clock": "com.apple.clock",
                         "Mail": "com.apple.mail", "Calendar": "com.apple.iCal",
                         "Reminders": "com.apple.reminders"]
        guard let id = knownApps[source] else { return nil }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
    }
}

/// Owns presentation only. The capture adapter never changes notch/window geometry.
@MainActor
class NotificationPresentation: ObservableObject {
    enum Phase: String { case idle, expanding, displaying, collapsing }
    struct Timing {
        var leadIn = 0.016
        var contentDelay = 0.10
        var expansion = 0.42
        var fadeOut = 0.14
        var contraction = 0.46
        var display = 6.0
        var clockDisplay = 10.0
        var settle = 0.48
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var current: NotchNotification?
    @Published private(set) var surfaceExpanded = false
    @Published private(set) var contentVisible = false
    @Published private(set) var receivedAt = Date()
    private(set) var queued: [NotchNotification] = []
    private var blockedSurfaces: Set<String> = []
    @Published private(set) var hoveringSurfaces: Set<String> = []
    private var surfaces: [String: CGRect] = [:]
    private var sequence: Task<Void, Never>?
    private var settling: Task<Void, Never>?
    private var dismissal: Task<Void, Never>?
    private var deadline: TimeInterval?
    private var remaining = 0.0
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?
    private let timing: Timing
    private let monitorClicks: Bool

    init(timing: Timing = Timing(), monitorClicks: Bool = true) {
        self.timing = timing
        self.monitorClicks = monitorClicks
    }

    private var reducedMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    private var expansionAnimation: Animation {
        reducedMotion ? .easeInOut(duration: 0.18) : .spring(response: 0.42, dampingFraction: 0.9)
    }
    private var contractionAnimation: Animation {
        reducedMotion ? .easeInOut(duration: 0.18) : .spring(response: 0.46, dampingFraction: 1)
    }

    func updateSurface(_ id: String, frame: CGRect, blocked: Bool) {
        surfaces[id] = frame
        let wasBlocked = !blockedSurfaces.isEmpty
        if blocked { blockedSurfaces.insert(id) } else { blockedSurfaces.remove(id) }
        if blocked {
            settling?.cancel()
            settling = nil
            if current != nil { dismiss(requeue: true) }
        } else if wasBlocked && blockedSurfaces.isEmpty {
            // Let the original hover/close spring finish before starting another morph.
            settling = Task { [weak self] in
                guard let self, await self.wait(self.timing.settle) else { return }
                self.settling = nil
                self.presentNext()
            }
        }
        presentNext()
    }

    func removeSurface(_ id: String) {
        surfaces.removeValue(forKey: id)
        blockedSurfaces.remove(id)
        setHovered(false, on: id)
        presentNext()
    }

    func setHovered(_ hovered: Bool, on id: String) {
        guard hoveringSurfaces.contains(id) != hovered else { return }
        if hovered { hoveringSurfaces.insert(id) } else { hoveringSurfaces.remove(id) }
        if !hoveringSurfaces.isEmpty {
            if let deadline { remaining = max(0, deadline - ProcessInfo.processInfo.systemUptime) }
            dismissal?.cancel()
            dismissal = nil
            deadline = nil
        } else if phase == .displaying {
            scheduleDismissal()
        }
    }

    func enqueue(_ notification: NotchNotification) {
        // Bounded FIFO; an alert already being read is never replaced mid-animation.
        guard !queued.contains(where: { $0.id == notification.id }), current?.id != notification.id else { return }
        if queued.count == 5 { queued.removeFirst() }
        queued.append(notification)
        presentNext()
    }

    private func presentNext() {
        guard phase == .idle, !queued.isEmpty, blockedSurfaces.isEmpty, settling == nil, !surfaces.isEmpty else { return }
        current = queued.removeFirst()
        receivedAt = Date()
        phase = .expanding
        remaining = current?.isClock == true ? timing.clockDisplay : timing.display
        installClickMonitors()
        sequence = Task { [weak self] in
            guard let self else { return }
            guard await self.wait(self.timing.leadIn) else { return }
            withAnimation(self.expansionAnimation) { self.surfaceExpanded = true }
            guard await self.wait(self.timing.contentDelay) else { return }
            withAnimation(.easeOut(duration: self.reducedMotion ? 0.12 : 0.20)) { self.contentVisible = true }
            guard await self.wait(max(0, self.timing.expansion - self.timing.contentDelay)) else { return }
            self.phase = .displaying
            self.scheduleDismissal()
        }
    }

    func dismiss(requeue: Bool = false) {
        guard phase == .expanding || phase == .displaying else { return }
        if requeue, let current { queued.insert(current, at: 0) }
        sequence?.cancel()
        dismissal?.cancel()
        deadline = nil
        phase = .collapsing
        withAnimation(.easeOut(duration: timing.fadeOut)) { contentVisible = false }
        sequence = Task { [weak self] in
            guard let self else { return }
            guard await self.wait(self.timing.fadeOut) else { return }
            withAnimation(self.contractionAnimation) { self.surfaceExpanded = false }
            guard await self.wait(self.timing.contraction) else { return }
            self.current = nil
            self.phase = .idle
            self.hoveringSurfaces.removeAll()
            self.removeClickMonitors()
            self.presentNext()
        }
    }

    func activateSource() {
        guard let url = current?.appURL else { return }
        // Captured banners do not expose their deep link. Explicit user clicks may open the source app.
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
        dismiss()
    }

    func discardMirroredNotifications() {
        queued.removeAll { !$0.isLocal }
        if let current, !current.isLocal { dismiss() }
    }

    func reset() {
        sequence?.cancel()
        settling?.cancel()
        settling = nil
        dismissal?.cancel()
        current = nil
        queued.removeAll()
        hoveringSurfaces.removeAll()
        surfaceExpanded = false
        contentVisible = false
        phase = .idle
        deadline = nil
        removeClickMonitors()
    }

    private func scheduleDismissal() {
        guard hoveringSurfaces.isEmpty, phase == .displaying, dismissal == nil else { return }
        let duration = max(0.8, remaining)
        deadline = ProcessInfo.processInfo.systemUptime + duration
        dismissal = Task { [weak self] in
            guard let self, await self.wait(duration) else { return }
            self.dismissal = nil
            self.dismiss()
        }
    }

    private func wait(_ seconds: Double) async -> Bool {
        do { try await Task.sleep(for: .seconds(seconds)); return !Task.isCancelled }
        catch { return false }
    }

    private func installClickMonitors() {
        guard monitorClicks, globalClickMonitor == nil else { return }
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.dismissIfOutside() }
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            Task { @MainActor in self?.dismissIfOutside() }
            return event
        }
    }

    private func dismissIfOutside() {
        guard !surfaces.values.contains(where: { $0.contains(NSEvent.mouseLocation) }) else { return }
        dismiss()
    }

    private func removeClickMonitors() {
        if let globalClickMonitor { NSEvent.removeMonitor(globalClickMonitor) }
        if let localClickMonitor { NSEvent.removeMonitor(localClickMonitor) }
        globalClickMonitor = nil
        localClickMonitor = nil
    }
}

struct NotchNotificationContent: View {
    let notification: NotchNotification
    let receivedAt: Date

    private var appIcon: NSImage? {
        notification.appURL.map { NSWorkspace.shared.icon(forFile: $0.path) }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Group {
                if let appIcon {
                    Image(nsImage: appIcon).resizable().scaledToFit()
                } else {
                    Image(systemName: notification.isClock ? "alarm.fill" : "bell.fill")
                        .font(.system(size: 21, weight: .medium))
                        .foregroundStyle(notification.isClock ? Color.orange : Color.white.opacity(0.8))
                }
            }
            .frame(width: 32, height: 32)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(notification.source)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text(receivedAt, style: .time)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.45))
                        .fixedSize()
                }
                if !notification.title.isEmpty {
                    Text(notification.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                if !notification.body.isEmpty {
                    Text(notification.body)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.78))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct NotificationSurfaceMetrics {
    let notification: NotchNotification?
    let screenWidth: CGFloat
    let topInset: CGFloat
    var size: CGSize {
        let count = (notification?.title.count ?? 0) + (notification?.body.count ?? 0)
        let width = min(count > 65 ? 390.0 : 360.0, max(0, screenWidth - 32))
        let textHeight = 14.0 + (notification?.title.isEmpty != false ? 0 : 19)
            + (notification?.body.isEmpty != false ? 0 : 33)
        return CGSize(width: width, height: max(0, topInset) + max(32, textHeight) + 24)
    }
}

private struct NotchSurfaceSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

/// Keep the original content's identity and size proposals unchanged. Only the
/// surrounding surface morphs for a notification; its size must never be fed
/// back into the hidden music/menu layout through a frame or GeometryReader.
struct NotificationSurfaceLayout: Layout {
    var progress: CGFloat
    var notificationSize: CGSize

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let content = subviews.first else { return .zero }
        let normal = content.sizeThatFits(proposal)
        return CGSize(
            width: normal.width + (notificationSize.width - normal.width) * progress,
            height: normal.height + (notificationSize.height - normal.height) * progress
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: CGPoint(x: bounds.midX, y: bounds.minY), anchor: .top, proposal: proposal)
    }

    func spacing(subviews: Subviews, cache: inout ()) -> ViewSpacing {
        subviews.first?.spacing ?? ViewSpacing()
    }
}

/// Recognizes one deliberate two-finger upward swipe per trackpad gesture.
struct NotificationDismissSwipeAccumulator {
    private(set) var distance: CGFloat = 0
    private(set) var handled = false

    mutating func reset() {
        distance = 0
        handled = false
    }

    mutating func feed(deltaX: CGFloat, deltaY: CGFloat, precise: Bool,
                       phase: NSEvent.Phase, momentumPhase: NSEvent.Phase) -> Bool {
        if phase.contains(.ended) || phase.contains(.cancelled) {
            reset()
            return false
        }
        guard precise, momentumPhase.isEmpty, !handled else { return false }
        if phase.contains(.began) { distance = 0 }
        guard abs(deltaY) >= abs(deltaX) * 1.5, abs(deltaY) > 0.2 else { return false }
        guard deltaY < 0 else {
            distance = 0
            return false
        }
        distance += -deltaY
        if distance >= 55 {
            handled = true
            return true
        }
        return false
    }
}

private struct NotificationDismissSwipeMonitor: NSViewRepresentable {
    let enabled: Bool
    let onDismiss: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.install(on: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onDismiss = onDismiss
        context.coordinator.enabled = enabled
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.remove()
    }

    func makeCoordinator() -> Coordinator { Coordinator(enabled: enabled, onDismiss: onDismiss) }

    @MainActor final class Coordinator {
        var onDismiss: () -> Void
        var enabled: Bool {
            didSet { if !enabled { reset() } }
        }
        private var monitor: Any?
        private var resetTask: Task<Void, Never>?
        private var swipe = NotificationDismissSwipeAccumulator()

        init(enabled: Bool, onDismiss: @escaping () -> Void) {
            self.enabled = enabled
            self.onDismiss = onDismiss
        }

        func install(on view: NSView) {
            remove()
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self, weak view] event in
                guard let self, self.enabled, let view, event.window === view.window,
                      view.bounds.contains(view.convert(event.locationInWindow, from: nil)) else { return event }
                if self.swipe.feed(deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY,
                                   precise: event.hasPreciseScrollingDeltas,
                                   phase: event.phase, momentumPhase: event.momentumPhase) {
                    self.onDismiss()
                }
                self.resetTask?.cancel()
                self.resetTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(300))
                    guard !Task.isCancelled else { return }
                    self.reset()
                }
                return event
            }
        }

        func remove() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            reset()
        }

        private func reset() {
            resetTask?.cancel()
            resetTask = nil
            swipe.reset()
        }
    }
}

/// Reuses the original notch's content, black fill and animatable NotchShape in its existing NSPanel.
struct NotificationNotchSurface: ViewModifier {
    @ObservedObject var presentation: NotificationPresentation
    let screenID: String
    let screenFrame: CGRect
    let topInset: CGFloat
    let blocked: Bool
    let normalShape: NotchShape
    let normalShadow: Bool
    var normalShadowRadius: CGFloat = 6
    @State private var surfaceSize: CGSize = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var active: Bool { presentation.current != nil }
    private var hovered: Bool { presentation.hoveringSurfaces.contains(screenID) }
    private var expanded: Bool { active && presentation.surfaceExpanded }
    private var metrics: NotificationSurfaceMetrics {
        NotificationSurfaceMetrics(notification: presentation.current, screenWidth: screenFrame.width, topInset: topInset)
    }
    private var width: CGFloat { metrics.size.width }
    private var hitFrame: CGRect {
        CGRect(x: screenFrame.midX - surfaceSize.width / 2, y: screenFrame.maxY - surfaceSize.height,
               width: surfaceSize.width, height: surfaceSize.height)
    }

    func body(content: Content) -> some View {
        NotificationSurfaceLayout(progress: expanded ? 1 : 0, notificationSize: metrics.size) {
            content
                .opacity(active ? 0 : 1)
                .animation(.easeOut(duration: 0.12), value: active)
                .allowsHitTesting(!active)
        }
            .overlay(alignment: .top) {
                if let item = presentation.current {
                    HStack(alignment: .top, spacing: 6) {
                        NotchNotificationContent(notification: item, receivedAt: presentation.receivedAt)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .onTapGesture { presentation.activateSource() }
                            .help(item.appURL == nil ? "Use the original notification for actions" : "Open \(item.source)")
                        Button { presentation.dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.88))
                                .frame(width: 22, height: 22)
                                .background(.white.opacity(0.16), in: Circle())
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .opacity(hovered ? 1 : 0)
                        .allowsHitTesting(hovered && presentation.contentVisible)
                        .accessibilityLabel("Dismiss notification")
                        .accessibilityHidden(!hovered || !presentation.contentVisible)
                    }
                    .frame(width: max(0, width - 40), alignment: .topLeading)
                    .padding(.horizontal, 20)
                    .padding(.top, topInset + 8)
                    .padding(.bottom, 16)
                    .opacity(presentation.contentVisible ? 1 : 0)
                    .scaleEffect(presentation.contentVisible || reduceMotion ? 1 : 0.97, anchor: .top)
                    .offset(y: presentation.contentVisible || reduceMotion ? 0 : -3)
                    .allowsHitTesting(presentation.contentVisible)
                    .animation(.easeOut(duration: 0.14), value: hovered)
                    .contextMenu {
                        if item.appURL != nil {
                            Button("Open \(item.source)") { presentation.activateSource() }
                        }
                        Button("Dismiss from notch") { presentation.dismiss() }
                    }
                }
            }
            .background(Color.black)
            .background(NotificationDismissSwipeMonitor(enabled: active && presentation.contentVisible) {
                presentation.dismiss()
            })
            .clipShape(expanded ? NotchShape(topCornerRadius: 6, bottomCornerRadius: 26) : normalShape)
            .overlay(alignment: .top) {
                Rectangle().fill(.black).frame(height: 1)
                    .padding(.horizontal, expanded ? 6 : normalShape.topCornerRadius)
                    .allowsHitTesting(false)
            }
            .shadow(color: !active && normalShadow ? .black.opacity(0.7) : .clear, radius: normalShadowRadius)
            .background(GeometryReader { proxy in
                Color.clear.preference(key: NotchSurfaceSizeKey.self, value: proxy.size)
            })
            .onPreferenceChange(NotchSurfaceSizeKey.self) { surfaceSize = $0 }
            .onAppear { reportSurface() }
            .onChange(of: blocked) { _, _ in reportSurface() }
            .onChange(of: hitFrame) { _, _ in reportSurface() }
            .onDisappear { presentation.removeSurface(screenID) }
    }

    private func reportSurface() {
        presentation.updateSurface(screenID, frame: hitFrame, blocked: blocked)
    }
}
