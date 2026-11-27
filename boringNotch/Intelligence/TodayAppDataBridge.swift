import AppKit
import Combine
import EventKit

@MainActor enum TodayAppData {
    private static let environment = Environment()
    static var controller: TodayContextController { environment.controller }
    static var briefings: TodayBriefingCoordinator { environment.briefings }
    @MainActor private final class Environment {
        let controller: TodayContextController
        let briefings: TodayBriefingCoordinator
        private let notifications: TodayNotificationSource
        private var subscriptions = Set<AnyCancellable>()
        private var capabilityRevision = 0
        init() {
            let calendar = TodayEventKitProvider()
            let location = TodayLocationManager()
            let weather = TodayOpenMeteoProvider()
            notifications = TodayNotificationSource()
            let service = TodayContextService(sources: [TodayDateTimeSource(), TodayWeatherSource(provider: weather, location: location),
                                                        TodayCalendarSource(provider: calendar), notifications])
            controller = TodayContextController(service: service, calendar: calendar, location: location, citySearch: { try await weather.cities($0) })
            let briefingService = TodayBriefingService(context: TodayLiveContextAccess(controller), gemini: TodayLiveGeminiAccess(.shared), cache: TodayBriefingCache())
            briefings = TodayBriefingCoordinator(service: briefingService, context: controller)
            GeminiModelStore.shared.$todayConfigurationRevision.dropFirst().sink { [weak self] _ in self?.briefings.configurationChanged() }.store(in: &subscriptions)
            let mirror = NotificationMirror.shared
            mirror.$captureStatus.removeDuplicates().sink { [weak self] status in
                guard let self else { return }
                self.capabilityRevision += 1
                let revision = self.capabilityRevision
                let capability: TodayNotificationSource.Capability
                switch status {
                case .ready: capability = .visibleBanners
                case .needsAccess: capability = .permissionRequired
                case .off: capability = .mirroringOff
                default: capability = .unavailable
                }
                Task { [weak self] in
                    guard let self else { return }
                    await self.notifications.updateCapability(capability, revision: revision)
                    self.controller.notificationCapabilityChanged(capability)
                }
            }.store(in: &subscriptions)
            mirror.observedBanners.sink { [weak self] banner in
                guard let self, self.controller.settings.enabled(.notifications) else { return }
                let observedAt = Date()
                let revision = self.capabilityRevision
                let policyRevision = self.controller.dataRevision
                let bundle = banner.appURL.flatMap { Bundle(url: $0)?.bundleIdentifier }
                Task { [weak self] in
                    await self?.notifications.record(identifier: banner.deliveryID ?? banner.id, applicationIdentifier: bundle,
                                                     applicationName: banner.source, title: banner.title, body: banner.body,
                                                     observedAt: observedAt, capabilityRevision: revision, policyRevision: policyRevision)
                    self?.controller.notificationArrived()
                }
            }.store(in: &subscriptions)
            for name in [Notification.Name.NSCalendarDayChanged, .NSSystemTimeZoneDidChange, .NSSystemClockDidChange, NSLocale.currentLocaleDidChangeNotification] {
                NotificationCenter.default.publisher(for: name).receive(on: RunLoop.main).sink { [weak self] _ in self?.controller.lifecycleChanged(source: .dateTime) }.store(in: &subscriptions)
            }
            NotificationCenter.default.publisher(for: .EKEventStoreChanged).receive(on: RunLoop.main).sink { [weak self] _ in self?.controller.lifecycleChanged(source: .calendar) }.store(in: &subscriptions)
            NotificationCenter.default.publisher(for: .todayLocationPermissionChanged).receive(on: RunLoop.main).sink { [weak self] _ in self?.controller.lifecycleChanged(source: .weather) }.store(in: &subscriptions)
            NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification).receive(on: RunLoop.main).sink { [weak self] _ in self?.controller.lifecycleChanged() }.store(in: &subscriptions)
            NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification).receive(on: RunLoop.main).sink { [weak self] _ in self?.briefings.pause() }.store(in: &subscriptions)
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification).sink { [weak self] _ in self?.controller.applicationActive(true) }.store(in: &subscriptions)
            NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification).sink { [weak self] _ in self?.controller.applicationActive(false); self?.briefings.pause() }.store(in: &subscriptions)
            NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification).receive(on: RunLoop.main).sink { [weak self] _ in
                Task { await self?.controller.refreshPermissions() }
            }.store(in: &subscriptions)
            controller.applicationActive(NSApp.isActive)
        }
    }
}
