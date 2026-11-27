import AppKit
import SwiftUI

actor PowerTestReader {
    var reads = 0
    func read() -> PowerReading { reads += 1; return PowerReading.parse(PowerUsageTests.fixture) }
}
@MainActor private final class PowerLayoutState: ObservableObject {
    @Published var contentHeight: CGFloat?
    var updates = 0
}
private struct PowerLayoutFixture: View {
    @ObservedObject var state: PowerLayoutState
    let reading: PowerReading
    let screen: CGRect
    private var size: CGSize {
        PowerUsageLayout.panelSize(screen: screen, visibleFrame: screen, contentHeight: state.contentHeight, closedHeight: 36)
    }
    var body: some View {
        VStack(spacing: 8) {
            Color.clear.frame(height: 36)
            VStack(spacing: 8) {
                PowerUsageContent(reading: reading)
                    .frame(height: max(0, size.height - PowerUsageLayout.chromeHeight(closedHeight: 36)))
                Text("Overview navigation").font(.system(size: 11)).frame(height: 29)
            }.padding(.top, 4)
        }
        .padding(.horizontal, 36).padding(.bottom, 12)
        .frame(width: size.width, height: size.height, alignment: .top)
        .background(.black, in: UnevenRoundedRectangle(bottomLeadingRadius: 24, bottomTrailingRadius: 24))
        .onPreferenceChange(PowerContentHeightKey.self) { height in
            guard height > 0, state.contentHeight != ceil(height) else { return }
            state.updates += 1; state.contentHeight = ceil(height)
        }
        .frame(width: 744, height: 420, alignment: .top)
    }
}
@main struct PowerUsageTests {
    static func historyFixture(_ reading: PowerReading) -> PowerHistory {
        var history = PowerHistory()
        for second in 0..<60 {
            var sample = reading
            let factor = 0.85 + Double(second % 9) / 30
            sample.loadWatts = reading.loadWatts.map { $0 * factor }
            sample.inputWatts = reading.inputWatts.map { $0 * factor }
            sample.current = reading.current.map { $0 * factor }
            history.append(sample, at: Double(second))
        }
        return history
    }
    static var fixture: [String: Any] { [
        "Voltage": 11847, "InstantAmperage": 3961, "ExternalConnected": true, "IsCharging": true,
        "CurrentCapacity": 54, "MaxCapacity": 100,
        "BatteryData": ["AppleRawCurrentCapacity": 2160, "AppleRawMaxCapacity": 4000, "DesignCapacity": 5000],
        "AdapterDetails": ["Watts": 96, "AdapterVoltage": 20000, "Current": 4800],
        "PowerTelemetryData": ["SystemPowerIn": 60000, "SystemLoad": 15000, "BatteryPower": 45000, "AdapterEfficiencyLoss": 2000],
        "AvgTimeToFull": 70
    ] }
    @MainActor static func main() async throws {
        var count = 0
        func check(_ value: Bool, _ message: String) { precondition(value, message); count += 1 }
        func near(_ a: Double?, _ b: Double) -> Bool { a.map { abs($0 - b) < 0.001 } ?? false }
        let charging = PowerReading.parse(fixture)
        check(near(charging.batteryWatts, 46.926), "Measured battery voltage × signed current")
        check(charging.capacityMAh == 4000, "Use worn effective capacity, not design or percent")
        check(charging.chargeTargets.map(\.percent) == [75, 100], "Reached charging milestones hidden")
        check(charging.chargeTargets.last?.minutes == 70, "Full ETA preserves taper-aware OS estimate")
        check(near(charging.distribution?.system, 0.25), "Input share uses measured 60W, not 96W")
        check(near(charging.distribution?.battery, 0.75), "Matching telemetry charging share")
        check(charging.runtimeMinutes == nil, "No discharge runtime on AC")
        for raw: NSNumber in [NSNumber(value: -2000), NSNumber(value: UInt64.max - 1999), NSNumber(value: UInt32.max - 1999)] {
            check(near(PowerReading.signedCurrent(raw), -2), "Signed and unsigned current representations")
        }
        check(PowerReading.signedCurrent(NSNumber(value: UInt64.max / 2)) == nil, "Reject huge current")
        var raw = fixture
        raw["ExternalConnected"] = false; raw["IsCharging"] = false; raw["InstantAmperage"] = NSNumber(value: UInt64.max - 1999)
        let discharge = PowerReading.parse(raw)
        check(near(discharge.batteryWatts, -23.694), "Discharge V×I")
        check(near(discharge.runtimeMinutes, 64.8), "Runtime uses remaining mAh / discharge mA")
        check(discharge.inputWatts == nil && discharge.adapterWatts == nil && discharge.distribution == nil, "Ignore stale AC telemetry unplugged")
        check(discharge.chargeTargets.isEmpty, "No charge estimates on battery")
        raw["ExternalConnected"] = true
        let insufficient = PowerReading.parse(raw)
        check(insufficient.status.contains("assisting") && insufficient.runtimeMinutes != nil && insufficient.distribution == nil, "Insufficient supply while battery discharges")
        raw = fixture; raw["InstantAmperage"] = 0; raw["IsCharging"] = false
        let held = PowerReading.parse(raw)
        check(held.status.contains("paused") && held.chargeTargets.isEmpty && held.runtimeMinutes == nil, "Zero current and hold handled")
        check(held.distribution == nil, "Reject stale positive charging rail during hold")
        raw["FullyCharged"] = true; raw["CurrentCapacity"] = 100
        raw["PowerTelemetryData"] = ["SystemPowerIn": 12000, "SystemLoad": 12000, "BatteryPower": 0]
        let full = PowerReading.parse(raw)
        check(full.status.contains("Fully charged") && full.chargeTargets.isEmpty, "Fully charged state")
        check(full.distribution?.system == 1 && full.distribution?.battery == 0, "Full battery is 100% operation")
        raw = fixture; raw.removeValue(forKey: "PowerTelemetryData")
        let partial = PowerReading.parse(raw)
        check(partial.adapterWatts == 96 && partial.inputWatts == nil && partial.distribution == nil, "Adapter rating never substitutes for input")
        raw["BatteryData"] = [:]
        check(PowerReading.parse(raw).capacityMAh == nil, "Percentage is not absolute capacity")
        check(PowerReading.parse(raw).chargeTargets.isEmpty, "No time estimates without capacity")
        raw["MaxCapacity"] = 4000; raw["CurrentCapacity"] = 2000
        check(PowerReading.parse(raw).remainingMAh == 2000, "Legacy absolute-capacity fallback")
        raw = fixture; raw["PowerTelemetryData"] = ["SystemPowerIn": 50000, "SystemLoad": 50000, "BatteryPower": 45000]
        check(PowerReading.parse(raw).distribution == nil, "Reject incoherent power budget")
        raw["PowerTelemetryData"] = ["SystemPowerIn": 45000, "SystemLoad": 0, "BatteryPower": 45000]
        check(PowerReading.parse(raw).distribution == nil, "Zero system load is not a credible running-Mac reading")
        raw["PowerTelemetryData"] = ["SystemPowerIn": -1, "SystemLoad": Double.nan]
        check(PowerReading.parse(raw).inputWatts == nil && PowerReading.parse(raw).loadWatts == nil, "Invalid sensor values rejected")
        raw = fixture; raw["InstantAmperage"] = 1; raw["AvgTimeToFull"] = 65535
        check(PowerReading.parse(raw).chargeTargets.isEmpty, "Near-zero current does not yield huge estimates")
        raw["InstantAmperage"] = 3961
        check(PowerReading.parse(raw).chargeTargets.last?.source == .minimum, "No OS ETA means honest lower bound above 80%")
        raw = fixture; raw["CurrentCapacity"] = 24; raw["BatteryData"] = ["RemainingCapacity": 960, "FullChargeCapacity": 4000]
        check(PowerReading.parse(raw).chargeTargets.map(\.percent) == [25, 50, 75, 100], "Nested alternate capacity fields and milestones")
        for percent in [25, 50, 75, 100] {
            raw["CurrentCapacity"] = percent
            raw["BatteryData"] = ["RemainingCapacity": percent * 40, "FullChargeCapacity": 4000]
            check(PowerReading.parse(raw).chargeTargets.allSatisfy { $0.percent > percent }, "Exact reached boundary")
        }
        check(PowerReading.parse([:]).status == "Telemetry unavailable", "Absent hardware")
        check(PowerReading.duration(.infinity) == "Unavailable" && PowerReading.duration(-1) == "Unavailable", "Invalid times safe")
        check(PowerReading.duration(64.8) == "1h 5m", "Hours/minutes formatting")
        var average = PowerRollingAverage()
        _ = average.append(charging)
        var lower = charging; lower.current = 2
        check(near(average.append(lower).current, 2.9805), "Rolling average")
        check(average.append(discharge).current == -2, "Direction/source change resets smoothing")
        check(average.append(PowerReading()).current == nil, "Missing telemetry clears stale values")
        average.reset()
        for i in 1...10 { var sample = charging; sample.current = Double(i); _ = average.append(sample) }
        var sample = charging; sample.current = 11
        check(average.append(sample).current == 9, "Average bounded to five samples")

        for screenSize in [CGSize(width: 1024, height: 640), CGSize(width: 1280, height: 800), CGSize(width: 1470, height: 956), CGSize(width: 1728, height: 1117)] {
            let screen = CGRect(origin: CGPoint(x: -1728, y: 100), size: screenSize)
            let visible = CGRect(x: screen.minX + 47, y: screen.minY + 60, width: screen.width - 47, height: screen.height - 92)
            for height: CGFloat in [140, 312, 1200] {
                let size = PowerUsageLayout.panelSize(screen: screen, visibleFrame: visible, contentHeight: height, closedHeight: 36)
                check(size.width <= screen.width - 24 && size.height <= screen.maxY - visible.minY - 24, "Power page stays inside display bounds")
                check(size.height <= 420 && size.height >= 224, "Power page bounded, with scrolling for overflow")
            }
        }
        let size = PowerUsageLayout.panelSize(screen: CGRect(x: 0, y: 0, width: 1440, height: 900), visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 864), contentHeight: .nan, closedHeight: 0)
        check(size.height.isFinite && size.height <= 420, "Invalid height and notchless displays handled")

        check(charging.adapterVoltage == 20 && charging.adapterCurrent == 4.8, "Negotiated electrical details retain units")
        check(discharge.adapterVoltage == nil && discharge.adapterCurrent == nil, "No stale contract when unplugged")
        check(PowerPresentation(reading: charging).headline?.label == "Incoming power", "Charging prioritises input")
        check(PowerPresentation(reading: discharge).headline?.label == "Battery draw", "Battery prioritises discharge")
        check(PowerPresentation(reading: full).headline?.label == "Mac consumption", "Full prioritises Mac load")
        check(PowerPresentation(reading: held).title == "Charging on hold", "Compact hold presentation")
        check(PowerPresentation(reading: partial).headline?.label == "Battery charging", "Missing input falls back to real battery reading")
        check(PowerPresentation(reading: PowerReading()).headline == nil, "No fabricated zero headline for absent telemetry")
        var history = PowerHistory()
        history.append(charging, at: 100)
        check(history.points.count == 1 && history.points[0].time == 100, "First sample never backfills history")
        history.append(charging, at: 100)
        check(history.points.count == 1, "Ignore duplicate timestamps")
        for second in 101...200 { history.append(charging, at: Double(second)) }
        check(history.points.count == 61 && history.points.first?.time == 140, "History bounded to 60 elapsed seconds")
        check(history.maximum >= max(charging.loadWatts!, charging.batteryWatts!), "Shared axis covers both real series")
        check(history.series == .mac && history.hasGreen && history.hasBlue, "Charging and Mac history distinct")
        history.append(discharge, at: 201)
        check(history.points.count == 1 && history.series == .battery && !history.hasGreen, "Unplug resets history and units")
        history.append(discharge, at: 210)
        check(history.segments(green: false).count == 2, "Missed samples leave a gap")
        history.append(insufficient, at: 211)
        check(history.points.count == 1, "Connected but discharging resets source history")
        history.append(charging, at: 212)
        check(history.points.count == 1 && history.hasGreen, "Charge direction change resets history")
        history.append(full, at: 213)
        check(history.points.count == 1 && !history.hasGreen, "Full charge clears former charging series")
        history.append(charging, at: 10)
        check(history.points.count == 1 && history.points[0].time == 10, "Monotonic clock rollback resets history")
        history.append(charging, at: .infinity)
        check(history.points.count == 1, "Nonfinite time ignored")
        var onlyIncoming = partial; onlyIncoming.inputWatts = 60
        history.append(onlyIncoming, at: 11)
        check(history.series == .incoming && history.points.count == 1, "Input fallback has its own honest legend and segment")
        history.append(PowerReading(), at: 12)
        check(!history.hasBlue && !history.hasGreen && history.maximum == 5, "Missing sensors produce no plotted wattage")

        let reader = PowerTestReader()
        var service: PowerMonitorService? = PowerMonitorService(reader: { await reader.read() })
        let first = UUID(), second = UUID()
        check(await reader.reads == 0, "No reads at creation")
        service!.start(first); service!.start(first); service!.start(second)
        try await Task.sleep(for: .milliseconds(150))
        check(await reader.reads == 1, "Consumers share a single poller")
        check(service!.reading != nil, "Initial sample arrives")
        check(service!.history.points.count == 1, "Visible polling records a real sample")
        service!.stop(first)
        try await Task.sleep(for: .milliseconds(1050))
        check(await reader.reads == 2, "Remaining consumer continues at 1Hz")
        service!.setSleeping(true)
        let asleep = await reader.reads
        try await Task.sleep(for: .milliseconds(1100))
        check(await reader.reads == asleep && service!.reading == nil, "Sleep suspends and clears stale sample")
        service!.setSleeping(false)
        try await Task.sleep(for: .milliseconds(150))
        check(await reader.reads == asleep + 1, "Wake immediately refreshes")
        service!.stop(second)
        let stopped = await reader.reads
        try await Task.sleep(for: .milliseconds(1100))
        check(await reader.reads == stopped && service!.reading == nil, "No hidden polling after last consumer")
        check(service!.history.points.isEmpty, "Hidden page clears history rather than filling a fake gap")
        weak let weakService = service
        service!.start(first)
        try await Task.sleep(for: .milliseconds(100))
        service = nil
        check(weakService == nil, "Poll loop and observers do not retain service")
        let live = await NativePowerReader().read()
        print("Live telemetry: \(live.status); battery \(live.batteryWatts ?? -999) W; input \(live.inputWatts ?? -999) W; contract \(live.adapterWatts ?? -999) W; effective capacity \(live.capacityMAh ?? -1) mAh; distribution supported \(live.distribution != nil)")
        print("PASS: \(count) power calculation and lifecycle checks")
        if CommandLine.arguments.contains("--render") {
            _ = NSApplication.shared
            let directory = "/tmp/notchloom-power-review"
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            for (name, reading) in [("charging", charging), ("battery", discharge), ("full", full), ("paused", held), ("insufficient", insufficient), ("partial", partial), ("unavailable", PowerReading()), ("live", live)] {
                let view = PowerUsageContent(reading: reading, history: historyFixture(reading)).frame(width: 696, height: 312).background(.black)
                let hosting = NSHostingView(rootView: view)
                hosting.frame = CGRect(x: 0, y: 0, width: 696, height: 312)
                let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                window.contentView = hosting
                window.setFrameOrigin(NSPoint(x: -4000, y: -4000))
                window.orderBack(nil)
                try await Task.sleep(for: .milliseconds(150))
                hosting.layoutSubtreeIfNeeded()
                let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds)!
                hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: directory + "/\(name).png"))
                window.orderOut(nil)
            }
            for (name, reading) in [("charging", charging), ("battery", discharge), ("full", full), ("paused", held), ("unavailable", PowerReading())] {
                let state = PowerLayoutState()
                let host = NSHostingView(rootView: PowerLayoutFixture(state: state, reading: reading, screen: CGRect(x: 0, y: 0, width: 1024, height: 640)))
                host.frame = CGRect(x: 0, y: 0, width: 744, height: 420)
                let window = NSPanel(contentRect: host.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                window.contentView = host; window.setFrameOrigin(NSPoint(x: -4000, y: -4000)); window.orderBack(nil)
                try await Task.sleep(for: .milliseconds(400))
                host.layoutSubtreeIfNeeded()
                check(state.contentHeight != nil && state.updates <= 5, "Natural height settles without feedback loop")
                if name == "battery" || name == "unavailable" { check(state.contentHeight! < 210, "Short state does not reserve charging space") }
                if name == "charging" { check(state.contentHeight! <= 323, "Normal charging view fits without scrolling") }
                let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
                host.cacheDisplay(in: host.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: directory + "/fitted-\(name).png"))
                window.orderOut(nil)
            }
            let details = NSHostingView(rootView: PowerTechnicalDetails(reading: charging).preferredColorScheme(.dark))
            details.frame = CGRect(x: 0, y: 0, width: 348, height: 570)
            let detailsWindow = NSPanel(contentRect: details.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            detailsWindow.contentView = details; detailsWindow.setFrameOrigin(NSPoint(x: -4000, y: -4000)); detailsWindow.orderBack(nil)
            try await Task.sleep(for: .milliseconds(200))
            details.layoutSubtreeIfNeeded()
            let detailsBitmap = details.bitmapImageRepForCachingDisplay(in: details.bounds)!
            details.cacheDisplay(in: details.bounds, to: detailsBitmap)
            try detailsBitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: directory + "/details.png"))
            detailsWindow.orderOut(nil)
            print("Rendered eight native states and five fitted layouts in \(directory)")
            print("PASS: \(count) total power checks including fitted layouts")
        }
    }
}
