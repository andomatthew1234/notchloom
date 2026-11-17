//
//  PanGesture.swift
//  boringNotch
//
//  Created by Richard Kunkli on 21/08/2024.
//

import AppKit
import SwiftUI

enum PanDirection {
    case left, right, up, down

    var isHorizontal: Bool { self == .left || self == .right }
    var sign: CGFloat { (self == .right || self == .down) ? 1 : -1 }

    func signed(from translation: CGSize) -> CGFloat { (isHorizontal ? translation.width : translation.height) * sign }
    func signed(deltaX: CGFloat, deltaY: CGFloat) -> CGFloat { (isHorizontal ? deltaX : deltaY) * sign }
}

/// A scrollable child owns wheel and trackpad events inside its actual AppKit bounds.
/// The notch monitors observe events without consuming them, so the child's native
/// NSScrollView still receives momentum, mouse-wheel and precise trackpad events.
@MainActor private final class ScrollGestureOwnership {
    static let shared = ScrollGestureOwnership()
    private let regions = NSHashTable<NSView>.weakObjects()

    func add(_ view: NSView) { regions.add(view) }
    func remove(_ view: NSView) { regions.remove(view) }
    func owns(_ event: NSEvent) -> Bool {
        guard let window = event.window else { return false }
        return regions.allObjects.contains { view in
            view.window === window && view.bounds.contains(view.convert(event.locationInWindow, from: nil))
        }
    }
}

struct ScrollGestureExclusionArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        ScrollGestureOwnership.shared.add(view)
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
    static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        ScrollGestureOwnership.shared.remove(nsView)
    }
}

extension View {
    func panGesture(direction: PanDirection, threshold: CGFloat = 4, action: @escaping (CGFloat, NSEvent.Phase) -> Void) -> some View {
        self
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let s = direction.signed(from: value.translation)
                        guard s > 0, s.magnitude >= threshold else { return }
                        action(s.magnitude, .changed)
                    }
                    .onEnded { _ in action(0, .ended) }
            )
            .background(ScrollMonitor(direction: direction, threshold: threshold, action: action))
    }
}

private struct ScrollMonitor: NSViewRepresentable {
    let direction: PanDirection
    let threshold: CGFloat
    let action: (CGFloat, NSEvent.Phase) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.installMonitor(on: view)
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) { coordinator.removeMonitor() }

    func makeCoordinator() -> Coordinator { 
        Coordinator(direction: direction, threshold: threshold, action: action) 
    }

    @MainActor final class Coordinator: NSObject {
        private let direction: PanDirection
        private let threshold: CGFloat
        private let action: (CGFloat, NSEvent.Phase) -> Void
        private var monitor: Any?
        private var accumulated: CGFloat = 0
        private var active = false
            private var endTask: Task<Void, Never>?
        private let noiseThreshold: CGFloat = 0.2

        init(direction: PanDirection, threshold: CGFloat, action: @escaping (CGFloat, NSEvent.Phase) -> Void) {
            self.direction = direction
            self.threshold = threshold
            self.action = action
        }

        private func scheduleEndTimeout() {
            // Cancel any existing scheduled end and schedule a new one.
            endTask?.cancel()
            endTask = Task { @MainActor in
                // If no new scroll event arrives within this window, consider the gesture ended.
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                if active {
                    action(accumulated.magnitude, .ended)
                } else {
                    action(0, .ended)
                }
                active = false
                accumulated = 0
            }
        }

        func installMonitor(on view: NSView) {
            removeMonitor()
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { [weak self, weak view] event in
                guard let self = self, event.window === view?.window else { return event }
                if ScrollGestureOwnership.shared.owns(event) {
                    self.cancelGesture()
                    return event
                }
                self.handleScroll(event)
                return event
            }
        }

        private func cancelGesture() {
            endTask?.cancel()
            endTask = nil
            if active { action(0, .ended) }
            active = false
            accumulated = 0
        }

        func removeMonitor() {
            if let monitor = monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            accumulated = 0
            active = false
            endTask?.cancel()
            endTask = nil
        }

        private func handleScroll(_ event: NSEvent) {
            if event.phase == .ended || event.momentumPhase == .ended {
                if active {
                    action(accumulated.magnitude, .ended)
                } else {
                    action(0, .ended)
                }
                active = false
                accumulated = 0
                return
            }

            // Only consider scroll events that are primarily along the configured axis.
            let absDX = abs(event.scrollingDeltaX)
            let absDY = abs(event.scrollingDeltaY)
            // Require the movement along the gesture axis to be at least 1.5x the orthogonal axis.
            let axisDominanceFactor: CGFloat = 1.5
            let isAxisDominant: Bool = direction.isHorizontal ? (absDX >= axisDominanceFactor * absDY) : (absDY >= axisDominanceFactor * absDX)
            guard isAxisDominant else { return }

            // Scale non-precise (mouse wheel) scrolling deltas so they feel similar to
            // trackpad gestures.
            let raw = direction.signed(deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY)
            let scale: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 8
            let s = raw * scale
            guard s.magnitude > noiseThreshold else { return }
            accumulated = s > 0 ? accumulated + s : 0

            if !active && accumulated >= threshold {
                active = true
                action(accumulated.magnitude, .began)
            } else if active {
                action(accumulated.magnitude, .changed)
            }
            // Schedule a timeout to end the gesture if no further scroll events arrive.
            scheduleEndTimeout()
        }
    }
}

/// Trackpad-only page navigation. A SwiftUI DragGesture here would compete with
/// the music scrubber and other controls inside the open notch.
struct HorizontalTabSwipeMonitor: NSViewRepresentable {
    let onSwipe: (PanDirection) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.install(on: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onSwipe = onSwipe
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.remove()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onSwipe: onSwipe) }

    @MainActor final class Coordinator {
        var onSwipe: (PanDirection) -> Void
        private var monitor: Any?
        private var resetTask: Task<Void, Never>?
        private var distance: CGFloat = 0
        private var handled = false

        init(onSwipe: @escaping (PanDirection) -> Void) { self.onSwipe = onSwipe }

        func install(on view: NSView) {
            remove()
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self, weak view] event in
                guard let self, let view, event.window === view.window,
                      view.bounds.contains(view.convert(event.locationInWindow, from: nil)),
                      event.hasPreciseScrollingDeltas else { return event }
                if ScrollGestureOwnership.shared.owns(event) {
                    self.reset()
                    return event
                }
                self.handle(event)
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
            distance = 0
            handled = false
        }

        private func handle(_ event: NSEvent) {
            if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
                reset()
                return
            }
            guard event.momentumPhase.isEmpty, !handled else { return }
            let dx = event.scrollingDeltaX
            let dy = event.scrollingDeltaY
            guard abs(dx) >= abs(dy) * 1.5, abs(dx) > 0.2 else { return }
            if event.phase.contains(.began) { distance = 0 }
            if distance != 0 && (distance > 0) != (dx > 0) { distance = 0 }
            distance += dx
            if abs(distance) >= 42 {
                handled = true
                onSwipe(distance < 0 ? .left : .right)
            }
            resetTask?.cancel()
            resetTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                reset()
            }
        }
    }
}
