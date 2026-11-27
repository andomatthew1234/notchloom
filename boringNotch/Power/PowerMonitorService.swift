import AppKit
import Combine
import IOKit

actor NativePowerReader {
    func read() -> PowerReading {
        let entry = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard entry != IO_OBJECT_NULL else { return PowerReading() }
        defer { IOObjectRelease(entry) }
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(entry, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let properties else { return PowerReading() }
        return PowerReading.parse(properties.takeRetainedValue() as NSDictionary as? [String: Any] ?? [:])
    }
}

/// Shared across display windows. No polling or workspace observers without a visible consumer.
@MainActor final class PowerMonitorService: ObservableObject {
    static let shared = PowerMonitorService()
    @Published private(set) var reading: PowerReading?
    @Published private(set) var history = PowerHistory()
    private var consumers: Set<UUID> = []
    private var task: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var average = PowerRollingAverage()
    private let reader: @Sendable () async -> PowerReading
    private var sleeping = false
    private var generation = 0

    init(reader: (@Sendable () async -> PowerReading)? = nil) {
        let native = NativePowerReader()
        self.reader = reader ?? { await native.read() }
    }
    func start(_ consumer: UUID) {
        guard consumers.insert(consumer).inserted else { return }
        if consumers.count == 1 {
            let center = NSWorkspace.shared.notificationCenter
            observers = [center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.setSleeping(true) }
            }, center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.setSleeping(false) }
            }]
            beginPolling()
        }
    }
    func stop(_ consumer: UUID) {
        consumers.remove(consumer)
        guard consumers.isEmpty else { return }
        cancelPolling()
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll()
        sleeping = false
    }
    func setSleeping(_ value: Bool) {
        sleeping = value
        cancelPolling()
        if !value && !consumers.isEmpty { beginPolling() }
    }
    private func cancelPolling() {
        generation += 1
        task?.cancel(); task = nil
        average.reset(); reading = nil; history = PowerHistory()
    }
    private func beginPolling() {
        guard !sleeping, !consumers.isEmpty else { return }
        let reader = reader
        let generation = generation
        task = Task { [weak self] in
            while !Task.isCancelled {
                let sample = await reader()
                guard !Task.isCancelled, self?.accept(sample, generation: generation) == true else { return }
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
    }
    private func accept(_ sample: PowerReading, generation: Int) -> Bool {
        guard self.generation == generation else { return false }
        let next = average.append(sample)
        if reading != next { reading = next }
        history.append(next, at: ProcessInfo.processInfo.systemUptime)
        return true
    }
    deinit {
        task?.cancel()
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
    }
}
