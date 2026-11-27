import AppKit
import SwiftUI

/// Observes dismissal without consuming clicks destined for other apps.
struct TodayNotchInteraction: NSViewRepresentable {
    let containsScreenPoint: (NSPoint) -> Bool
    let onClose: () -> Void
    var canDismissOutside: () -> Bool = { true }
    var suspended = false
    func makeNSView(context: Context) -> NSView {
        let view = TodayWindowAttachment()
        view.onAttach = { [weak coordinator = context.coordinator] window in coordinator?.attach(window) }
        context.coordinator.contains = containsScreenPoint
        context.coordinator.onClose = onClose
        context.coordinator.canDismissOutside = canDismissOutside
        context.coordinator.setSuspended(suspended)
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.contains = containsScreenPoint
        context.coordinator.onClose = onClose
        context.coordinator.canDismissOutside = canDismissOutside
        context.coordinator.setSuspended(suspended)
    }
    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        (nsView as? TodayWindowAttachment)?.onAttach = nil
        coordinator.remove()
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    @MainActor final class Coordinator {
        var contains: (NSPoint) -> Bool = { _ in false }
        var onClose: () -> Void = {}
        var canDismissOutside: () -> Bool = { true }
        private var suspended = false
        private weak var window: NSWindow?
        private var local: Any?
        private var global: Any?
        private var previousApplication: NSRunningApplication?
        func attach(_ window: NSWindow) {
            remove()
            self.window = window
            previousApplication = NSWorkspace.shared.frontmostApplication
            applyFocus()
            local = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
                guard let self else { return event }
                guard !self.suspended else { return event }
                if event.type == .keyDown, event.window === self.window, event.keyCode == 53 {
                    self.onClose(); return nil
                }
                if event.type != .keyDown, self.canDismissOutside(), !self.contains(NSEvent.mouseLocation) { self.onClose() }
                return event
            }
            global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                guard let self, !self.suspended, self.canDismissOutside(), !self.contains(NSEvent.mouseLocation) else { return }
                self.onClose()
            }
        }
        func setSuspended(_ value: Bool) {
            guard suspended != value else { return }
            suspended = value; applyFocus()
        }
        private func applyFocus() {
            guard let window else { return }
            (window as? BoringNotchSkyLightWindow)?.allowsTodayKeyboardFocus = !suspended
            if suspended { window.makeFirstResponder(nil); window.resignKey() }
            else { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
        }
        func remove() {
            if let local { NSEvent.removeMonitor(local) }
            if let global { NSEvent.removeMonitor(global) }
            local = nil; global = nil
            if let window = window as? BoringNotchSkyLightWindow {
                let restoreFocus = window.isKeyWindow && NSApp.keyWindow === window
                    && NSWorkspace.shared.frontmostApplication?.processIdentifier == NSRunningApplication.current.processIdentifier
                    && !IntelligenceCoordinator.shared.isActive
                window.allowsTodayKeyboardFocus = false
                if !window.allowsIntelligenceKeyboardFocus && !window.allowsConverterKeyboardFocus {
                    window.makeFirstResponder(nil)
                    window.resignKey()
                    if restoreFocus { previousApplication?.activate(options: []) }
                }
            }
            window = nil
            previousApplication = nil
        }
    }
}

private final class TodayWindowAttachment: NSView {
    var onAttach: ((NSWindow) -> Void)?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window { DispatchQueue.main.async { [weak self, weak window] in
            if let self, let window, self.window === window { self.onAttach?(window) }
        } }
    }
}
