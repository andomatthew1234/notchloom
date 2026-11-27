//
//  BoringViewModel.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 04/08/24.
//

import AppKit
import Combine
import Defaults
import SwiftUI

class BoringViewModel: NSObject, ObservableObject {
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @ObservedObject var detector = FullscreenMediaDetector.shared

    let animationLibrary: BoringAnimations = .init()
    let animation: Animation?

    @Published var contentType: ContentType = .normal
    @Published private(set) var notchState: NotchState = .closed

    @Published var dragDetectorTargeting: Bool = false
    @Published var generalDropTargeting: Bool = false
    @Published var dropZoneTargeting: Bool = false
    @Published var convertDropTargeting: Bool = false
    @Published var dropEvent: Bool = false
    @Published var anyDropZoneTargeting: Bool = false
    var cancellables: Set<AnyCancellable> = []
    
    @Published var hideOnClosed: Bool = true

    @Published var edgeAutoOpenActive: Bool = false
    @Published var isHoveringCalendar: Bool = false
    @Published var isBatteryPopoverActive: Bool = false

    @Published var screenUUID: String?

    @Published var notchSize: CGSize = getClosedNotchSize()
    @Published var closedNotchSize: CGSize = getClosedNotchSize()
    @Published var windowContentSize: CGSize = windowSize
    @Published private(set) var conversionExpanded = false
    @Published private(set) var todayExpanded = false
    @Published private(set) var powerExpanded = false
    private var powerPreferredContentHeight: CGFloat?
    private var powerContractionTask: Task<Void, Never>?
    @Published private(set) var todayPermissionWaiting = false
    private var todayPreferredContentHeight: CGFloat?
    private var todayPermissionPreviousHiding: Bool?
    private var todayContractionTask: Task<Void, Never>?
    weak var hostWindow: NSWindow?
    
    let webcamManager = WebcamManager.shared
    @Published var isCameraExpanded: Bool = false
    @Published var isRequestingAuthorization: Bool = false
    
    deinit {
        destroy()
    }

    func destroy() {
        todayContractionTask?.cancel()
        powerContractionTask?.cancel()
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
    }

    init(screenUUID: String? = nil) {
        animation = animationLibrary.animation

        super.init()
        
        self.screenUUID = screenUUID
        notchSize = getClosedNotchSize(screenUUID: screenUUID)
        closedNotchSize = notchSize

        Publishers.CombineLatest4($dropZoneTargeting, $convertDropTargeting, $dragDetectorTargeting, $generalDropTargeting)
            .map { share, convert, drag, general in
                share || convert || drag || general
            }
            .assign(to: \.anyDropZoneTargeting, on: self)
            .store(in: &cancellables)
        
        setupDetectorObserver()
    }
    
    private func setupDetectorObserver() {
        // Publisher for the user’s fullscreen detection setting
        let enabledPublisher = Defaults
            .publisher(.hideNotchOption)
            .map(\.newValue)
            .map { $0 != .never }
            .removeDuplicates()

        // Publisher for the current screen UUID (non-nil, distinct)
        let screenPublisher = $screenUUID
            .compactMap { $0 }
            .removeDuplicates()

        // Publisher for fullscreen status dictionary
        let fullscreenStatusPublisher = detector.$fullscreenStatus
            .removeDuplicates()

        // Combine all three: screen UUID, fullscreen status, and enabled setting
        Publishers.CombineLatest3(screenPublisher, fullscreenStatusPublisher, enabledPublisher)
            .map { screenUUID, fullscreenStatus, enabled in
                let isFullscreen = fullscreenStatus[screenUUID] ?? false
                return enabled && isFullscreen
            }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] shouldHide in
                withAnimation(.smooth) {
                    self?.hideOnClosed = shouldHide
                }
            }
            .store(in: &cancellables)
    }

    // Computed property for effective notch height
    var effectiveClosedNotchHeight: CGFloat {
        let currentScreen = screenUUID.flatMap { NSScreen.screen(withUUID: $0) }
        let noNotchAndFullscreen = hideOnClosed && (currentScreen?.safeAreaInsets.top ?? 0 <= 0 || currentScreen == nil)
        return noNotchAndFullscreen ? 0 : closedNotchSize.height
    }

    var chinHeight: CGFloat {
        if !Defaults[.hideTitleBar] {
            return 0
        }

        guard let currentScreen = screenUUID.flatMap({ NSScreen.screen(withUUID: $0) }) else {
            return 0
        }

        if notchState == .open { return 0 }

        let menuBarHeight = currentScreen.frame.maxY - currentScreen.visibleFrame.maxY
        let currentHeight = effectiveClosedNotchHeight

        if currentHeight == 0 { return 0 }

        return max(0, menuBarHeight - currentHeight)
    }

    func toggleCameraPreview() {
        if isRequestingAuthorization {
            return
        }

        switch webcamManager.authorizationStatus {
        case .authorized:
            if webcamManager.isSessionRunning {
                webcamManager.stopSession()
                isCameraExpanded = false
            } else if webcamManager.cameraAvailable {
                webcamManager.startSession()
                isCameraExpanded = true
            }

        case .denied, .restricted:
            DispatchQueue.main.async {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)

                let alert = NSAlert()
                alert.messageText = "Camera Access Required"
                alert.informativeText = "Please allow camera access in System Settings."
                alert.addButton(withTitle: "Open Settings")
                alert.addButton(withTitle: "Cancel")

                if alert.runModal() == .alertFirstButtonReturn {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                        NSWorkspace.shared.open(url)
                    }
                }

                NSApp.setActivationPolicy(.accessory)
                NSApp.deactivate()
            }

        case .notDetermined:
            isRequestingAuthorization = true
            webcamManager.checkAndRequestVideoAuthorization()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self.isRequestingAuthorization = false
            }

        default:
            break
        }
    }
    
    func isMouseHovering(position: NSPoint = NSEvent.mouseLocation) -> Bool {
        let screenFrame = getScreenFrame(screenUUID)
        if let frame = screenFrame {
            
            let baseY = frame.maxY - notchSize.height
            let baseX = frame.midX - notchSize.width / 2
            
            return position.y >= baseY && position.y <= frame.maxY && position.x >= baseX && position.x <= baseX + notchSize.width
        }
        
        return false
    }

    func open() {
        self.notchSize = todayExpanded ? (todayPermissionWaiting ? todayPermissionSize : todayNotchSize) : conversionExpanded ? getConvertNotchSize(screenUUID: screenUUID) : powerExpanded ? powerNotchSize : openNotchSize
        self.notchState = .open
        
        // Force music information update when notch is opened
        MusicManager.shared.forceUpdate()
    }

    @MainActor func showIntelligence(size: CGSize) {
        powerExpanded = false
        todayExpanded = false
        finishTodayPermissionWaiting()
        todayContractionTask?.cancel()
        // The response and a growing multiline prompt can be taller than the
        // normal transparent host. Grow it before animating the notch surface.
        let content = CGSize(width: max(windowSize.width, size.width),
                             height: max(windowContentSize.height, size.height + shadowPadding))
        if windowContentSize != content {
            windowContentSize = content
            resizeHostWindow(to: content)
        }
        notchState = .open
        notchSize = size
    }

    @MainActor func restoreFromIntelligence(wasOpen: Bool) {
        notchSize = wasOpen ? openNotchSize : getClosedNotchSize(screenUUID: screenUUID)
        notchState = wasOpen ? .open : .closed
    }

    @MainActor func finishIntelligenceContraction() {
        guard !conversionExpanded, !todayExpanded, !powerExpanded else { return }
        windowContentSize = windowSize
        resizeHostWindow(to: windowSize)
    }

    func close() {
        // Do not close while a share picker or sharing service is active
        if SharingStateManager.shared.preventNotchClose {
            return
        }
        if powerExpanded { setPowerExpanded(false) }
        if conversionExpanded {
            setConversionExpanded(false)
            finishConversionContraction()
        }
        if todayExpanded {
            todayExpanded = false
            finishTodayPermissionWaiting()
            scheduleTodayHostContraction()
        }
        self.notchSize = getClosedNotchSize(screenUUID: self.screenUUID)
        self.closedNotchSize = self.notchSize
        self.notchState = .closed
        self.isBatteryPopoverActive = false
        self.coordinator.sneakPeek.show = false
        self.edgeAutoOpenActive = false

        // Set the current view to shelf if it contains files and the user enables openShelfByDefault
        // Otherwise, open Overview unless the user prefers the last tab.
    if !ShelfStateViewModel.shared.isEmpty && Defaults[.openShelfByDefault] {
            coordinator.currentView = .shelf
        } else if !coordinator.openLastTabByDefault {
            coordinator.currentView = .tools
        }
    }

    @MainActor func setConversionExpanded(_ expanded: Bool, compact: Bool = false, permissionWaiting: Bool = false) {
        let full = getConvertNotchSize(screenUUID: screenUUID)
        let target = expanded
            ? (permissionWaiting ? CGSize(width: min(374, full.width), height: min(68, full.height))
                : compact ? CGSize(width: min(540, full.width), height: min(336, full.height)) : full)
            : openNotchSize
        let content = CGSize(width: full.width, height: full.height + shadowPadding)
        guard conversionExpanded != expanded || (expanded && notchSize != target) else { return }
        // Grow the transparent host first. On exit keep it large until SwiftUI has
        // finished drawing the shrinking surface; resizing it sooner clips and
        // relocates the animated notch above the display edge.
        if expanded && windowContentSize != content {
            windowContentSize = content
            resizeHostWindow(to: content)
        }
        conversionExpanded = expanded
        if notchState == .open { notchSize = target }
    }

    @MainActor func finishConversionContraction() {
        guard !conversionExpanded, !todayExpanded, !powerExpanded else { return }
        windowContentSize = windowSize
        resizeHostWindow(to: windowSize)
    }

    @MainActor private func resizeHostWindow(to content: CGSize) {
        guard let window = hostWindow else { return }
        let screen = screenUUID.flatMap { NSScreen.screen(withUUID: $0) } ?? window.screen ?? NSScreen.main
        guard let screen else { return }
        var frame = window.frame
        frame.size = content
        frame.origin.x = screen.frame.midX - content.width / 2
        frame.origin.y = screen.frame.maxY - content.height
        window.setFrame(frame, display: true)
    }

    private var powerChromeHeight: CGFloat { PowerUsageLayout.chromeHeight(closedHeight: effectiveClosedNotchHeight) }
    var powerContentHeight: CGFloat { max(0, powerNotchSize.height - powerChromeHeight) }
    var powerNotchSize: CGSize {
        let screen = screenUUID.flatMap { NSScreen.screen(withUUID: $0) } ?? hostWindow?.screen ?? NSScreen.main
        return PowerUsageLayout.panelSize(screen: screen?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900),
                                          visibleFrame: screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 864),
                                          contentHeight: powerPreferredContentHeight, closedHeight: effectiveClosedNotchHeight)
    }
    @MainActor func updatePowerContentHeight(_ height: CGFloat, reduceMotion: Bool) {
        guard powerExpanded, height.isFinite, height > 0 else { return }
        let next = ceil(height)
        guard powerPreferredContentHeight != next else { return }
        powerPreferredContentHeight = next
        refreshPowerLayout(reduceMotion: reduceMotion)
    }
    @MainActor func refreshPowerLayout(reduceMotion: Bool) {
        guard powerExpanded, notchState == .open, !IntelligenceCoordinator.shared.isActive else { return }
        let target = powerNotchSize
        let content = CGSize(width: max(windowContentSize.width, target.width), height: max(windowContentSize.height, target.height + shadowPadding))
        if content != windowContentSize { windowContentSize = content; resizeHostWindow(to: content) }
        withAnimation(reduceMotion ? .easeOut(duration: 0.14) : .spring(response: 0.35, dampingFraction: 1)) { notchSize = target }
    }
    @MainActor func setPowerExpanded(_ expanded: Bool) {
        guard powerExpanded != expanded else { return }
        powerContractionTask?.cancel()
        powerExpanded = expanded
        if expanded {
            powerPreferredContentHeight = nil
            let size = powerNotchSize
            let content = CGSize(width: max(windowContentSize.width, size.width), height: max(windowContentSize.height, size.height + shadowPadding))
            windowContentSize = content
            resizeHostWindow(to: content)
            if notchState == .open { notchSize = size }
        } else {
            // Do not replace another page's geometry during an outgoing view transition.
            if notchState == .open && !todayExpanded && !conversionExpanded && !IntelligenceCoordinator.shared.isActive {
                notchSize = openNotchSize
            }
            powerContractionTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(520))
                guard !Task.isCancelled, let self, !self.powerExpanded else { return }
                self.finishTodayContraction()
            }
        }
    }

    var todayNotchSize: CGSize {
        let screen = screenUUID.flatMap { NSScreen.screen(withUUID: $0) } ?? hostWindow?.screen ?? NSScreen.main
        return TodayPageGeometry.panelSize(screen: screen?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900),
                                           visibleFrame: screen?.visibleFrame ?? CGRect(x: 0, y: 50, width: 1440, height: 825),
                                           preferredContentHeight: todayPreferredContentHeight,
                                           closedNotchHeight: effectiveClosedNotchHeight)
    }

    @MainActor func updateTodayContentHeight(_ height: CGFloat?, reduceMotion: Bool) {
        guard todayExpanded, !todayPermissionWaiting else { return }
        let next = height.flatMap { $0.isFinite && $0 > 0 ? ceil($0) : nil }
        guard next != todayPreferredContentHeight else { return }
        todayPreferredContentHeight = next
        let target = todayNotchSize
        // Keep the transparent host large while the visible surface contracts. Its
        // existing pointer region continues to pass clicks through below the panel.
        let content = CGSize(width: max(windowContentSize.width, target.width),
                             height: max(windowContentSize.height, target.height + shadowPadding))
        if content != windowContentSize {
            windowContentSize = content
            resizeHostWindow(to: content)
        }
        guard notchSize != target else { return }
        withAnimation(reduceMotion ? .easeOut(duration: 0.14) : .spring(response: 0.40, dampingFraction: 0.95)) {
            notchSize = target
        }
    }

    @MainActor func setTodayExpanded(_ expanded: Bool) {
        guard todayExpanded != expanded else { return }
        todayContractionTask?.cancel()
        if expanded {
            guard !conversionExpanded else { return }
            let target = todayNotchSize
            let content = CGSize(width: max(windowSize.width, target.width), height: max(windowSize.height, target.height + shadowPadding))
            windowContentSize = content
            resizeHostWindow(to: content)
            todayExpanded = true
            notchSize = target
        } else {
            todayExpanded = false
            finishTodayPermissionWaiting()
            notchSize = notchState == .open ? openNotchSize : getClosedNotchSize(screenUUID: screenUUID)
        }
    }

    @MainActor func finishTodayContraction() {
        guard !todayExpanded, !conversionExpanded, !powerExpanded, !IntelligenceCoordinator.shared.isActive else { return }
        windowContentSize = windowSize
        resizeHostWindow(to: windowSize)
    }

    @MainActor func refreshTodayLayout() {
        guard todayExpanded else { return }
        let full = todayNotchSize
        notchSize = todayPermissionWaiting ? todayPermissionSize : full
        windowContentSize = CGSize(width: max(windowSize.width, full.width), height: max(windowSize.height, full.height + shadowPadding))
        resizeHostWindow(to: windowContentSize)
    }

    private var todayPermissionSize: CGSize {
        TodayLocationPermissionGeometry.panelSize(full: todayNotchSize, closed: CGSize(width: closedNotchSize.width, height: effectiveClosedNotchHeight))
    }
    @MainActor func prepareTodayLocationPermission(reduceMotion: Bool) async {
        guard todayExpanded else { return }
        if todayPermissionPreviousHiding == nil { todayPermissionPreviousHiding = hostWindow?.hidesOnDeactivate }
        hostWindow?.hidesOnDeactivate = false
        (hostWindow as? BoringNotchSkyLightWindow)?.suspendsPointerInput = true
        await withCheckedContinuation { continuation in
            withAnimation(reduceMotion ? .easeOut(duration: 0.14) : .spring(response: 0.38, dampingFraction: 0.94), completionCriteria: .logicallyComplete) {
                todayPermissionWaiting = true
                notchSize = todayPermissionSize
            } completion: { continuation.resume() }
        }
    }
    @MainActor func restoreTodayAfterLocationPermission(reduceMotion: Bool) {
        guard todayExpanded, todayPermissionWaiting else { return }
        // Keep the setup mounted, hidden and unfocused until the surface has expanded again.
        withAnimation(reduceMotion ? .easeOut(duration: 0.14) : .spring(response: 0.42, dampingFraction: 0.96), completionCriteria: .logicallyComplete) {
            notchSize = todayNotchSize
        } completion: { [weak self] in if self?.todayExpanded == true { self?.finishTodayPermissionWaiting() } }
    }
    private func finishTodayPermissionWaiting() {
        todayPermissionWaiting = false
        if let previous = todayPermissionPreviousHiding { hostWindow?.hidesOnDeactivate = previous }
        todayPermissionPreviousHiding = nil
    }

    @MainActor private func scheduleTodayHostContraction() {
        todayContractionTask?.cancel()
        todayContractionTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(520))
            guard !Task.isCancelled else { return }
            self?.finishTodayContraction()
        }
    }

    func closeHello() {
        Task { @MainActor in
            withAnimation(animationLibrary.animation) {
                coordinator.helloAnimationRunning = false
                close()
            }
        }
    }
}
