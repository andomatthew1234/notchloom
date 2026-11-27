import AppKit
import SwiftUI

actor PermissionLocationMock: TodayLocationProviding {
    var state: TodayPermissionState = .notDetermined
    var requests = 0
    private var waiter: CheckedContinuation<TodayPermissionState, Never>?
    func permission() -> TodayPermissionState { state }
    func requestPermission() async -> TodayPermissionState {
        requests += 1
        return await withCheckedContinuation { waiter = $0 }
    }
    func resolve(_ value: TodayPermissionState) { state = value; let pending = waiter; waiter = nil; pending?.resume(returning: value) }
    func locationIfAuthorized() throws -> TodayLocation { throw TodayContextError.unavailable }
}
struct PermissionCalendarMock: TodayCalendarProviding {
    func permission() async -> TodayPermissionState { .notDetermined }
    func requestPermission() async -> TodayPermissionState { .notDetermined }
    func calendars() async -> [TodayCalendarOption] { [] }
    func events(_ request: TodaySourceRequest) async throws -> [TodayCalendarItem] { [] }
}
@MainActor final class PermissionAnimationGate {
    var entered = false
    private var waiter: CheckedContinuation<Void, Never>?
    func prepare() async { entered = true; await withCheckedContinuation { waiter = $0 } }
    func finish() { let pending = waiter; waiter = nil; pending?.resume() }
}
@main struct TodayLocationPermissionTests {
    @MainActor static func main() async throws {
        var checks = 0
        func check(_ value: Bool, _ text: String) { precondition(value, text); checks += 1 }
        let suite = "Notchloom.PermissionTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        func controller(_ location: PermissionLocationMock) -> TodayContextController {
            .init(service: TodayContextService(sources: [TodayDateTimeSource()]), calendar: PermissionCalendarMock(), location: location, defaults: defaults)
        }
        for answer in [TodayPermissionState.authorized, .denied] {
            let location = PermissionLocationMock(), gate = PermissionAnimationGate()
            let data = controller(location), id = UUID()
            data.showingSetup = true
            data.registerLocationPresenter(id) { await gate.prepare() }
            let request = Task { await data.requestLocation() }
            for _ in 0..<100 { if gate.entered { break }; try await Task.sleep(for: .milliseconds(5)) }
            check(data.locationPermissionHandoff && data.requestingPermission, "Compact handoff published before native request")
            check(await location.requests == 0, "Native alert waits for the completed contraction")
            await data.requestLocation()
            check(await location.requests == 0, "Duplicate tap cannot start another request")
            gate.finish()
            for _ in 0..<100 { if await location.requests == 1 { break }; try await Task.sleep(for: .milliseconds(5)) }
            check(await location.requests == 1, "Native request begins after animation acknowledgement")
            await location.resolve(answer); await request.value
            check(!data.locationPermissionHandoff && !data.requestingPermission, "Handoff finishes after either OS answer")
            check(data.locationPermission == answer && data.showingSetup, "Grant and denial preserve the current setup")
            data.unregisterLocationPresenter(id)
        }
        let abandoned = PermissionLocationMock(), gate = PermissionAnimationGate(), id = UUID()
        let abandonedController = controller(abandoned)
        abandonedController.registerLocationPresenter(id) { await gate.prepare() }
        let pending = Task { await abandonedController.requestLocation() }
        for _ in 0..<100 { if gate.entered { break }; try await Task.sleep(for: .milliseconds(5)) }
        abandonedController.unregisterLocationPresenter(id); gate.finish(); await pending.value
        check(await abandoned.requests == 0, "Closing before the handoff avoids a stray permission alert")
        check(!abandonedController.locationPermissionHandoff, "Abandoned handoff clears pending state")
        let alreadyDenied = PermissionLocationMock(); await alreadyDenied.resolve(.denied)
        let deniedController = controller(alreadyDenied)
        await deniedController.requestLocation()
        check(await alreadyDenied.requests == 0, "Denied access is not repeatedly requested")
        check(!deniedController.locationPermissionHandoff && deniedController.locationPermission == .denied, "Denied access never flashes an Allow hint")
        let settingsLocation = PermissionLocationMock(), settingsController = controller(PermissionLocationMock())
        _ = settingsController
        let settingsData = controller(settingsLocation)
        let settingsRequest = Task { await settingsData.requestLocation() }
        for _ in 0..<100 { if await settingsLocation.requests == 1 { break }; try await Task.sleep(for: .milliseconds(5)) }
        check(!settingsData.locationPermissionHandoff, "Settings window uses its native permission flow without a notch handoff")
        await settingsLocation.resolve(.authorized); await settingsRequest.value
        for width: CGFloat in [296, 500, 744] {
            for height: CGFloat in [0, 24, 32, 38, 100] {
                let full = CGSize(width: width, height: 640)
                let compact = TodayLocationPermissionGeometry.panelSize(full: full, closed: .init(width: 240, height: height))
                check(compact.width <= full.width && compact.height < full.height, "Compact surface fits the display")
                check(TodayLocationPermissionGeometry.hintTop(closedHeight: height) >= height && TodayLocationPermissionGeometry.hintTop(closedHeight: height) + 16 + 12 <= compact.height, "Inline hint clears the physical camera and bottom edge")
            }
        }
        // Render our own offscreen surface only; no activation, native prompts or permission changes.
        _ = NSApplication.shared
        let size = TodayLocationPermissionGeometry.panelSize(full: .init(width: 744, height: 720), closed: .init(width: 240, height: 32))
        let view = Color.black.overlay(alignment: .top) { TodayLocationPermissionNotice().padding(.top, TodayLocationPermissionGeometry.hintTop(closedHeight: 32)) }
            .frame(width: size.width, height: size.height).clipShape(NotchShape(topCornerRadius: 12, bottomCornerRadius: 24)).padding(16)
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: .init(x: -5000, y: -5000, width: size.width + 32, height: size.height + 32), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; host.layoutSubtreeIfNeeded()
        let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/tmp/notchloom-location-permission-handoff.png"))
        window.close()
        print("PASS \(checks) location-permission handoff checks. Grant/deny mocked; no native OS prompt, location grant or desktop activation performed.")
    }
}
