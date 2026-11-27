//
//  BoringNotchSkyLightWindow.swift
//  boringNotch
//
//  Created by Alexander on 2025-10-20.
//

import Cocoa
import SkyLightWindow
import Defaults
import Combine

extension SkyLightOperator {
    func undelegateWindow(_ window: NSWindow) {
        typealias F_SLSRemoveWindowsFromSpaces = @convention(c) (Int32, CFArray, CFArray) -> Int32
        
        let handler = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight", RTLD_NOW)
        guard let SLSRemoveWindowsFromSpaces = unsafeBitCast(
            dlsym(handler, "SLSRemoveWindowsFromSpaces"),
            to: F_SLSRemoveWindowsFromSpaces?.self
        ) else {
            return
        }
        
        // Remove the window from the SkyLight space
        _ = SLSRemoveWindowsFromSpaces(
            connection,
            [window.windowNumber] as CFArray,
            [space] as CFArray
        )
    }
}

class BoringNotchSkyLightWindow: NSPanel {
    private var isSkyLightEnabled: Bool = false
    /// Enabled only while the user is typing in Convert's format search.
    var allowsConverterKeyboardFocus = false
    var allowsIntelligenceKeyboardFocus = false
    var allowsTodayKeyboardFocus = false
    
    // SwiftUI reports this in the top-leading coordinate space of the host.
    var pointerRegion = CGRect.zero { didSet { updatePointerRouting() } }
    var suspendsPointerInput = false { didSet { updatePointerRouting() } }
    private var pointerMonitors: [Any] = []

    private func updatePointerRouting() {
        let mouse = NSEvent.mouseLocation
        let local = CGPoint(x: mouse.x - frame.minX, y: frame.maxY - mouse.y)
        let passThrough = suspendsPointerInput || !pointerRegion.contains(local)
        if ignoresMouseEvents != passThrough { ignoresMouseEvents = passThrough }
    }

    // WindowServer chooses the receiving process before SwiftUI hit testing.
    // Observe motion so the transparent host yields to the window beneath it.
    private func observePointer() {
        ignoresMouseEvents = true
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .leftMouseUp]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            self?.updatePointerRouting()
        }) { pointerMonitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            // A drag that started inside the notch owns its events until release.
            if event.type != .leftMouseDragged || event.window !== self { self?.updatePointerRouting() }
            return event
        }) { pointerMonitors.append(local) }
        NotificationCenter.default.publisher(for: NSWindow.didMoveNotification, object: self)
            .sink { [weak self] _ in self?.updatePointerRouting() }
            .store(in: &observers)
    }

    override func close() {
        pointerMonitors.forEach(NSEvent.removeMonitor)
        pointerMonitors.removeAll()
        super.close()
    }

    override init(
        contentRect: NSRect,
        styleMask: NSWindow.StyleMask,
        backing: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: styleMask,
            backing: backing,
            defer: flag
        )
        
        configureWindow()
        setupObservers()
        observePointer()
    }
    
    private func configureWindow() {
        isFloatingPanel = true
        isOpaque = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        backgroundColor = .clear
        isMovable = false
        level = .mainMenu + 3
        hasShadow = false
        isReleasedWhenClosed = false
        
        // Force dark appearance regardless of system setting
        appearance = NSAppearance(named: .darkAqua)
        
        collectionBehavior = [
            .fullScreenAuxiliary,
            .stationary,
            .canJoinAllSpaces,
            .ignoresCycle,
        ]
        
        // Apply initial sharing type setting
        updateSharingType()
    }
    
    private func setupObservers() {
        // Listen for changes to the hideFromScreenRecording setting
        Defaults.publisher(.hideFromScreenRecording)
            .sink { [weak self] _ in
                self?.updateSharingType()
            }
            .store(in: &observers)
    }
    
    private func updateSharingType() {
        if Defaults[.hideFromScreenRecording] {
            sharingType = .none
        } else {
            sharingType = .readWrite
        }
    }
    
    func enableSkyLight() {
        if !isSkyLightEnabled {
            SkyLightOperator.shared.delegateWindow(self)
            isSkyLightEnabled = true
        }
    }
    
    func disableSkyLight() {
        if isSkyLightEnabled {
            SkyLightOperator.shared.undelegateWindow(self)
            isSkyLightEnabled = false
        }
    }
    
    private var observers: Set<AnyCancellable> = []
    
    override var canBecomeKey: Bool { allowsConverterKeyboardFocus || allowsIntelligenceKeyboardFocus || allowsTodayKeyboardFocus }
    override var canBecomeMain: Bool { false }
}
