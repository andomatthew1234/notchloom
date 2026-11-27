import Foundation

/// Only values with known units cross the IOKit boundary. Adapter ratings are never input measurements.
struct PowerReading: Equatable, Sendable {
    var external: Bool?
    var charging = false
    var full = false
    var percentage: Double?
    var voltage: Double?
    var current: Double? // signed amperes, positive into the battery
    var remainingMAh: Double?
    var capacityMAh: Double?
    var adapterVoltage: Double?
    var adapterCurrent: Double?
    var adapterWatts: Double?
    var inputWatts: Double?
    var loadWatts: Double? // whole-machine load, including display/accessories
    var railBatteryWatts: Double?
    var adapterLossWatts: Double?
    var osMinutesToFull: Double?

    static func signedCurrent(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber else { return nil }
        let raw = number.uint64Value
        let signed: Int64
        // Registry versions encode negative current as signed, uint64 or uint32.
        if raw > UInt64(Int64.max) { signed = Int64(bitPattern: raw) }
        else if raw > UInt64(Int32.max), raw <= UInt64(UInt32.max) {
            signed = Int64(Int32(bitPattern: UInt32(raw)))
        } else { signed = number.int64Value }
        guard abs(Double(signed)) <= 100_000 else { return nil }
        return Double(signed) / 1000
    }

    static func parse(_ root: [String: Any]) -> Self {
        let battery = root["BatteryData"] as? [String: Any] ?? [:]
        let adapter = root["AdapterDetails"] as? [String: Any] ?? [:]
        let power = root["PowerTelemetryData"] as? [String: Any] ?? [:]
        func number(_ value: Any?, _ range: ClosedRange<Double>) -> Double? {
            guard let value = (value as? NSNumber)?.doubleValue, value.isFinite, range.contains(value) else { return nil }
            return value
        }
        func capacity(_ keys: [String]) -> Double? {
            for key in keys {
                if let value = number(root[key], 1...100_000) ?? number(battery[key], 1...100_000) { return value }
            }
            return nil
        }
        var result = Self()
        result.external = (root["ExternalConnected"] as? NSNumber)?.boolValue
        result.charging = (root["IsCharging"] as? NSNumber)?.boolValue ?? false
        result.full = (root["FullyCharged"] as? NSNumber)?.boolValue ?? false
        result.voltage = number(root["Voltage"], 1000...30_000).map { $0 / 1000 }
        result.current = signedCurrent(root["InstantAmperage"]) ?? signedCurrent(root["Amperage"])
        result.capacityMAh = capacity(["AppleRawMaxCapacity", "FullChargeCapacity", "NominalChargeCapacity"])
        result.remainingMAh = number(root["AppleRawCurrentCapacity"], 0...100_000)
            ?? number(battery["AppleRawCurrentCapacity"], 0...100_000)
            ?? number(battery["RemainingCapacity"], 0...100_000)
        // Older hardware reports mAh here; modern Macs use 0–100. Never treat 100 as mAh.
        if result.capacityMAh == nil, let max = number(root["MaxCapacity"], 101...100_000),
           let current = number(root["CurrentCapacity"], 0...max) {
            result.capacityMAh = max; result.remainingMAh = current
        }
        if let current = number(root["CurrentCapacity"], 0...100_000),
           let max = number(root["MaxCapacity"], 1...100_000), current <= max {
            result.percentage = 100 * current / max
        }
        if let remaining = result.remainingMAh, let capacity = result.capacityMAh {
            if remaining > capacity * 1.05 { result.remainingMAh = nil }
            else if result.percentage == nil { result.percentage = min(100, 100 * remaining / capacity) }
        }
        if result.external == true {
            result.adapterVoltage = number(adapter["AdapterVoltage"], 1000...60_000).map { $0 / 1000 }
            result.adapterCurrent = number(adapter["Current"], 1...10_000).map { $0 / 1000 }
            result.adapterWatts = number(adapter["Watts"], 1...500)
            result.inputWatts = number(power["SystemPowerIn"], 1...500_000).map { $0 / 1000 }
            result.loadWatts = number(power["SystemLoad"], 1...500_000).map { $0 / 1000 }
            result.railBatteryWatts = number(power["BatteryPower"], 0...500_000).map { $0 / 1000 }
            result.adapterLossWatts = number(power["AdapterEfficiencyLoss"], 0...50_000).map { $0 / 1000 }
        }
        result.osMinutesToFull = number(root["AvgTimeToFull"] ?? root["TimeRemaining"], 1...10_080)
        return result
    }

    var discharging: Bool { current.map { $0 < -0.05 } ?? false }
    var activelyCharging: Bool { external == true && charging && !full && (current ?? 0) > 0.05 }
    var batteryWatts: Double? {
        guard let voltage, let current else { return nil }
        return voltage * current
    }
    var status: String {
        guard let external else { return "Telemetry unavailable" }
        if discharging { return external ? "Power connected · battery assisting" : "Running on battery" }
        if external {
            if full { return "Fully charged · external power" }
            if current == nil { return "External power · current unavailable" }
            return activelyCharging ? "Charging" : "External power · charging paused"
        }
        return "On battery · waiting for a discharge reading"
    }
    var runtimeMinutes: Double? {
        guard discharging, let remainingMAh, let current else { return nil }
        return Self.validMinutes(remainingMAh / (-current * 1000) * 60)
    }
    var distribution: PowerDistribution? {
        guard external == true, !discharging, let inputWatts, let loadWatts, let railBatteryWatts,
              inputWatts > 0.1, loadWatts <= inputWatts, railBatteryWatts <= inputWatts,
              abs(inputWatts - loadWatts - railBatteryWatts) <= max(0.1, inputWatts * 0.01),
              activelyCharging || railBatteryWatts <= 0.1 else { return nil }
        // Coherent readings from the same telemetry dictionary, not mixed with instantaneous V×I.
        return PowerDistribution(system: loadWatts / inputWatts, battery: railBatteryWatts / inputWatts)
    }
    var chargeTargets: [PowerChargeTarget] {
        guard activelyCharging, let capacityMAh, let remainingMAh, let current, let percentage else { return [] }
        return [25, 50, 75, 100].compactMap { target in
            guard Double(target) > percentage else { return nil }
            let amount = capacityMAh * Double(target) / 100 - remainingMAh
            guard amount > 0, let minutes = Self.validMinutes(amount / (current * 1000) * 60) else { return nil }
            // macOS's full-charge prediction can reflect taper/holds. Never replace it with a shorter linear ETA.
            if target == 100, let osMinutesToFull {
                return PowerChargeTarget(percent: target, minutes: max(minutes, osMinutesToFull), source: .system)
            }
            return PowerChargeTarget(percent: target, minutes: minutes, source: target > 80 ? .minimum : .rate)
        }
    }
    private static func validMinutes(_ value: Double) -> Double? {
        value.isFinite && value >= 0 && value <= 10_080 ? value : nil
    }
    static func duration(_ minutes: Double) -> String {
        guard minutes.isFinite, minutes >= 0, minutes <= 10_080 else { return "Unavailable" }
        let total = max(1, Int(ceil(minutes)))
        return total < 60 ? "\(total)m" : "\(total / 60)h \(total % 60)m"
    }
}
struct PowerDistribution: Equatable, Sendable { let system: Double; let battery: Double }
struct PowerChargeTarget: Equatable, Sendable {
    enum Source: Sendable { case rate, minimum, system }
    let percent: Int
    let minutes: Double
    let source: Source
}

/// A short average, reset at power-source, direction, charging or capability changes.
struct PowerRollingAverage {
    private var samples: [PowerReading] = []
    mutating func reset() { samples.removeAll() }
    mutating func append(_ reading: PowerReading) -> PowerReading {
        if let last = samples.last,
           last.external != reading.external || last.discharging != reading.discharging ||
            last.activelyCharging != reading.activelyCharging || last.full != reading.full ||
            (last.current == nil) != (reading.current == nil) || (last.voltage == nil) != (reading.voltage == nil) {
            reset()
        }
        samples.append(reading)
        if samples.count > 5 { samples.removeFirst() }
        func mean(_ key: KeyPath<PowerReading, Double?>) -> Double? {
            guard reading[keyPath: key] != nil else { return nil }
            let values = samples.compactMap { $0[keyPath: key] }
            return values.reduce(0, +) / Double(values.count)
        }
        var result = reading
        result.voltage = mean(\.voltage)
        result.current = mean(\.current)
        // Average only coherent tuples together; reject a bad current tuple immediately.
        if reading.distribution != nil {
            let coherent = samples.filter { $0.distribution != nil }
            result.inputWatts = coherent.compactMap(\.inputWatts).reduce(0, +) / Double(coherent.count)
            result.loadWatts = coherent.compactMap(\.loadWatts).reduce(0, +) / Double(coherent.count)
            result.railBatteryWatts = coherent.compactMap(\.railBatteryWatts).reduce(0, +) / Double(coherent.count)
        }
        return result
    }
}


/// Presentation choices never change the underlying measurements or charge forecasts.
struct PowerPresentation {
    let reading: PowerReading
    var title: String {
        if reading.discharging { return reading.external == true ? "Battery assisting" : "On battery" }
        if reading.full && reading.external == true { return "Fully charged" }
        if reading.activelyCharging { return "Charging" }
        if reading.external == true { return reading.current == nil ? "External power" : "Charging on hold" }
        return "Power usage"
    }
    var headline: (label: String, watts: Double)? {
        if reading.discharging, let watts = reading.batteryWatts { return ("Battery draw", abs(watts)) }
        if reading.activelyCharging, let watts = reading.inputWatts { return ("Incoming power", watts) }
        if let watts = reading.loadWatts { return ("Mac consumption", watts) }
        if reading.external == true, let watts = reading.inputWatts { return ("Incoming power", watts) }
        if reading.activelyCharging, let watts = reading.batteryWatts { return ("Battery charging", watts) }
        return nil
    }
    var symbol: String {
        if reading.discharging { return "battery.50percent" }
        if reading.full { return "checkmark" }
        return reading.activelyCharging ? "bolt.fill" : "pause.fill"
    }
}

struct PowerHistoryPoint: Equatable, Sendable {
    let time: TimeInterval // monotonic uptime; never wall-clock time
    let blue: Double?
    let green: Double?
}
struct PowerHistory: Equatable, Sendable {
    enum Series: String, Sendable { case battery = "Battery draw", mac = "Mac", incoming = "Incoming", none = "Power" }
    private(set) var points: [PowerHistoryPoint] = []
    private(set) var series: Series = .none
    private var external: Bool?
    private var charging = false
    private var discharging = false
    var maximum: Double {
        let peak = points.flatMap { [$0.blue, $0.green].compactMap { $0 } }.max() ?? 0
        return max(5, ceil(peak / 5) * 5)
    }
    var hasBlue: Bool { points.contains { $0.blue != nil } }
    var hasGreen: Bool { points.contains { $0.green != nil } }
    mutating func append(_ reading: PowerReading, at time: TimeInterval) {
        guard time.isFinite else { return }
        let next: Series = reading.discharging ? .battery : reading.loadWatts != nil ? .mac : reading.inputWatts != nil ? .incoming : .none
        if next != series || external != reading.external || charging != reading.activelyCharging || discharging != reading.discharging || (points.last.map { time < $0.time } ?? false) {
            points.removeAll()
        }
        series = next; external = reading.external; charging = reading.activelyCharging; discharging = reading.discharging
        guard points.last.map({ time > $0.time }) ?? true else { return }
        let blue: Double?
        switch series {
        case .battery: blue = reading.batteryWatts.map(abs)
        case .mac: blue = reading.loadWatts
        case .incoming: blue = reading.inputWatts
        case .none: blue = nil
        }
        func valid(_ value: Double?) -> Double? { value.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil } }
        points.append(PowerHistoryPoint(time: time, blue: valid(blue), green: reading.activelyCharging ? valid(reading.batteryWatts) : nil))
        points.removeAll { $0.time < time - 60 }
        if points.count > 61 { points.removeFirst(points.count - 61) }
    }
    /// Gaps remain gaps, including missed samples and temporarily missing sensors.
    func segments(green: Bool) -> [[PowerHistoryPoint]] {
        var result: [[PowerHistoryPoint]] = []
        var segment: [PowerHistoryPoint] = []
        for point in points {
            let value = green ? point.green : point.blue
            if value == nil || (segment.last.map { point.time - $0.time > 2.5 } ?? false) {
                if !segment.isEmpty { result.append(segment); segment = [] }
            }
            if value != nil { segment.append(point) }
        }
        if !segment.isEmpty { result.append(segment) }
        return result
    }
}
