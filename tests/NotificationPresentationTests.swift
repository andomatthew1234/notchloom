import AppKit
import SwiftUI

@main
struct NotificationPresentationTests {
    @MainActor static func main() async throws {
        let timing = NotificationPresentation.Timing(leadIn: 0.02, contentDelay: 0.04, expansion: 0.12,
                                                     fadeOut: 0.03, contraction: 0.08, display: 0.2, clockDisplay: 0.3, settle: 0.04)
        let p = NotificationPresentation(timing: timing, monitorClicks: false)
        let frame = CGRect(x: 500, y: 750, width: 390, height: 120)
        func item(_ id: String, local: Bool = true) -> NotchNotification {
            .init(id: id, source: local ? "Notchloom" : "Clock", title: id, body: "Test")
        }
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message)
            print("PASS: \(message)")
        }
        func wait(_ seconds: Double) async throws { try await Task.sleep(for: .seconds(seconds)) }

        p.enqueue(item("one"))
        check(p.phase == .idle, "No alert is consumed before a notch surface exists")
        p.updateSurface("built-in", frame: frame, blocked: true)
        check(p.current == nil, "Open notch defers queued notifications")
        p.updateSurface("built-in", frame: frame, blocked: false)
        check(p.phase == .idle, "Queue waits for the original notch close animation to settle")
        try await wait(0.045)
        check(p.phase == .expanding && !p.surfaceExpanded && !p.contentVisible, "Begin from the existing collapsed silhouette")
        try await wait(0.035)
        check(p.surfaceExpanded && !p.contentVisible, "Expansion leads content reveal")
        try await wait(0.13)
        check(p.phase == .displaying && p.contentVisible, "Reveal content after expansion begins")
        p.enqueue(item("two"))
        p.enqueue(item("three"))
        p.setHovered(true, on: "built-in")
        try await wait(1.05)
        check(p.current?.id == "one" && p.phase == .displaying, "Hover pauses dismissal without replacing current content")
        p.setHovered(false, on: "built-in")
        p.dismiss()
        check(!p.contentVisible && p.surfaceExpanded && p.phase == .collapsing, "Dismissal fades content before shrinking")
        try await wait(0.05)
        check(!p.surfaceExpanded && p.current?.id == "one", "Keep old content identity throughout contraction")
        try await wait(0.10)
        check(p.current?.id == "two", "Next queued notification starts only after contraction")
        p.updateSurface("built-in", frame: frame, blocked: true)
        try await wait(0.15)
        check(p.phase == .idle && p.queued.map(\.id) == ["two", "three"], "Opening other notch features requeues the interrupted alert")
        p.updateSurface("external", frame: frame, blocked: false)
        check(p.phase == .idle, "A second display cannot bypass an active notch interaction")
        p.updateSurface("built-in", frame: frame, blocked: false)
        try await wait(0.21)
        p.setHovered(true, on: "built-in")
        p.setHovered(true, on: "external")
        p.setHovered(false, on: "built-in")
        try await wait(1.0)
        check(p.current?.id == "two", "Hover on either display keeps the notification readable")
        p.reset()
        try await wait(0.2)
        check(p.current == nil && p.phase == .idle && !p.surfaceExpanded, "Reset cancels pending animation tasks")
        p.updateSurface("built-in", frame: frame, blocked: true)
        p.enqueue(item("clock", local: false))
        p.enqueue(item("local"))
        p.discardMirroredNotifications()
        check(p.queued.map(\.id) == ["local"], "Disabling mirroring preserves local focus completion alerts")
        for index in 0..<10 { p.enqueue(item("bounded-\(index)")) }
        check(p.queued.count == 5, "Notification bursts remain bounded")
        p.reset()
        p.updateSurface("built-in", frame: frame, blocked: false)
        p.enqueue(item("resume"))
        try await wait(0.21)
        p.setHovered(true, on: "built-in")
        try await wait(0.1)
        p.setHovered(false, on: "built-in")
        try await wait(1.05)
        check(p.phase == .idle && p.current == nil, "Leaving the notification resumes automatic dismissal")
        let long = NotchNotification(id: "long", source: "Messages", title: "Long title", body: String(repeating: "Message ", count: 30))
        for screenWidth: CGFloat in [320, 1024, 1440, 2560, 3840] {
            for topInset: CGFloat in [0, 24, 32, 38] {
                let size = NotificationSurfaceMetrics(notification: long, screenWidth: screenWidth, topInset: topInset).size
                check(size.width <= 390 && size.width <= screenWidth - 32 && size.height <= 130,
                      "Compact surface fits screen \(Int(screenWidth)), top inset \(Int(topInset))")
            }
        }
        let shortSize = NotificationSurfaceMetrics(notification: item("short"), screenWidth: 1440, topInset: 32).size
        check(shortSize.width == 360, "Short notifications use the compact width")

        var swipe = NotificationDismissSwipeAccumulator()
        check(!swipe.feed(deltaX: 25, deltaY: -10, precise: true, phase: .began, momentumPhase: []),
              "Horizontal trackpad motion does not dismiss")
        check(!swipe.feed(deltaX: 0, deltaY: 60, precise: true, phase: .changed, momentumPhase: []),
              "Downward motion does not dismiss")
        check(!swipe.feed(deltaX: 0, deltaY: -40, precise: false, phase: .changed, momentumPhase: []),
              "Mouse wheel scrolling does not dismiss")
        check(!swipe.feed(deltaX: 0, deltaY: -30, precise: true, phase: .changed, momentumPhase: []),
              "A short upward scroll does not dismiss")
        check(swipe.feed(deltaX: 0, deltaY: -30, precise: true, phase: .changed, momentumPhase: []),
              "A deliberate upward trackpad swipe dismisses")
        check(!swipe.feed(deltaX: 0, deltaY: -30, precise: true, phase: .changed, momentumPhase: []),
              "One gesture dismisses at most once")
        check(!swipe.feed(deltaX: 0, deltaY: 0, precise: true, phase: .ended, momentumPhase: []),
              "Ending a gesture resets recognition")
        print("All notification presentation checks passed.")
    }
}
