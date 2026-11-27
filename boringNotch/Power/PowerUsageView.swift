import SwiftUI
import Charts

enum PowerUsageLayout {
    static func chromeHeight(closedHeight: CGFloat) -> CGFloat {
        max(36, closedHeight) + 61 + (closedHeight == 0 ? 10 : 0)
    }
    static func panelSize(screen: CGRect, visibleFrame: CGRect, contentHeight: CGFloat?, closedHeight: CGFloat) -> CGSize {
        let content = contentHeight.flatMap { $0.isFinite && $0 > 0 ? ceil($0) : nil } ?? 256
        let availableHeight = max(0, screen.maxY - max(screen.minY, visibleFrame.minY) - 24)
        return CGSize(width: min(744, max(0, screen.width - 24)),
                      height: min(max(224, content + chromeHeight(closedHeight: closedHeight)), min(420, availableHeight)))
    }
}

struct PowerContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct PowerUsageView: View {
    @EnvironmentObject private var vm: BoringViewModel
    @ObservedObject private var monitor = PowerMonitorService.shared
    @State private var consumer = UUID()

    var body: some View {
        PowerUsageContent(reading: monitor.reading, history: monitor.history,
                          onInfoChanged: { vm.isBatteryPopoverActive = $0 })
            .onAppear { monitor.start(consumer) }
            .onDisappear { monitor.stop(consumer); vm.isBatteryPopoverActive = false }
    }
}

struct PowerUsageContent: View {
    let reading: PowerReading?
    var history = PowerHistory()
    var onInfoChanged: (Bool) -> Void = { _ in }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingInfo = false
    private var tint: Color { reading?.activelyCharging == true || reading?.full == true ? .green : .cyan }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 7) {
                Text("Power usage").font(.system(size: 13, weight: .semibold))
                Button { showingInfo.toggle() } label: {
                    Image(systemName: "info.circle").font(.system(size: 12)).foregroundStyle(.secondary)
                        .frame(width: 24, height: 24).contentShape(Circle())
                }
                .buttonStyle(.plain).accessibilityLabel("Power measurement details")
                .popover(isPresented: $showingInfo, arrowEdge: .top) {
                    PowerTechnicalDetails(reading: reading).preferredColorScheme(.dark)
                }
                Spacer()
                if let reading, reading.external != nil || reading.percentage != nil {
                    Label(PowerPresentation(reading: reading).title, systemImage: PowerPresentation(reading: reading).symbol)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(tint.opacity(0.9))
                }
            }
            if let reading {
                HStack(spacing: 20) {
                    if reading.percentage != nil { batteryRing(reading) }
                    VStack(alignment: .leading, spacing: 4) {
                        if let headline = PowerPresentation(reading: reading).headline {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(headline.watts, format: .number.precision(.fractionLength(1)))
                                    .font(.system(size: 37, weight: .medium, design: .rounded))
                                    .monospacedDigit().contentTransition(.numericText())
                                Text("W").font(.system(size: 16)).foregroundStyle(.secondary)
                            }.lineLimit(1).minimumScaleFactor(0.8)
                            Text(headline.label).font(.system(size: 11)).foregroundStyle(.secondary)
                        } else {
                            Text(reading.percentage == nil ? "No power readings" : "Battery status")
                                .font(.system(size: 16, weight: .medium))
                            Text("Details in ⓘ").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        if let minutes = reading.runtimeMinutes {
                            Text("≈ " + PowerReading.duration(minutes) + " remaining")
                                .font(.system(size: 11, weight: .medium)).foregroundStyle(.cyan)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    if PowerPresentation(reading: reading).headline != nil || history.hasBlue || history.hasGreen {
                        PowerHistoryGraph(history: history)
                            .frame(width: 238, height: 88)
                    }
                }
                if reading.activelyCharging { chargingFlow(reading) }
                else if reading.external == true { externalSummary(reading) }
                if !reading.chargeTargets.isEmpty { chargeTargets(reading) }
            } else {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Reading power…").foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, minHeight: 88)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 4)
        .fixedSize(horizontal: false, vertical: true)
        .background { GeometryReader { geometry in
            Color.clear.preference(key: PowerContentHeightKey.self, value: geometry.size.height)
        } }
        .foregroundStyle(.white).preferredColorScheme(.dark)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: reading)
        .onChange(of: showingInfo) { _, value in onInfoChanged(value) }
        .onDisappear { onInfoChanged(false) }
    }

    private func batteryRing(_ reading: PowerReading) -> some View {
        ZStack {
            Circle().stroke(.white.opacity(0.08), lineWidth: 6)
            if let percent = reading.percentage {
                Circle().trim(from: 0, to: min(1, max(0, percent / 100)))
                    .stroke(AngularGradient(colors: [tint.opacity(0.5), tint, tint.opacity(0.85)], center: .center, startAngle: .degrees(0), endAngle: .degrees(360)),
                            style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: tint.opacity(0.16), radius: 5)
                VStack(spacing: 2) {
                    Text("\(Int(percent.rounded()))%")
                        .font(.system(size: 23, weight: .semibold, design: .rounded))
                        .monospacedDigit().contentTransition(.numericText())
                    Image(systemName: PowerPresentation(reading: reading).symbol)
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(tint)
                }
            } else {
                Image(systemName: "battery.0percent").font(.system(size: 25)).foregroundStyle(.secondary)
            }
        }
        .frame(width: 82, height: 82).padding(5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(reading.percentage.map { "Battery \(Int($0.rounded())) percent, \(PowerPresentation(reading: reading).title)" } ?? "Battery level not reported")
    }
    @ViewBuilder private func chargingFlow(_ reading: PowerReading) -> some View {
        if reading.loadWatts != nil || reading.batteryWatts != nil {
            VStack(spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    if let watts = reading.loadWatts {
                        flowValue("Mac", watts: watts, share: reading.distribution?.system, color: .blue)
                    }
                    Spacer(minLength: 12)
                    if let watts = reading.distribution != nil ? reading.railBatteryWatts : reading.batteryWatts {
                        flowValue("Battery", watts: watts, share: reading.distribution?.battery, color: .green)
                    }
                }
                if let split = reading.distribution {
                    GeometryReader { geo in
                        HStack(spacing: 2) {
                            Capsule().fill(LinearGradient(colors: [.blue.opacity(0.6), .blue], startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(0, (geo.size.width - 2) * split.system))
                            Capsule().fill(LinearGradient(colors: [.green.opacity(0.65), .green], startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(0, (geo.size.width - 2) * split.battery))
                        }
                    }.frame(height: 6).clipped()
                }
            }
            .help("Mac includes the display and accessories. Distribution watts and percentages use matching input and battery-rail sensors. Without a distribution, battery watts use voltage × current. See ⓘ for timing and accuracy.")
        }
    }
    private func flowValue(_ title: String, watts: Double, share: Double?, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(PowerTechnicalDetails.watts(watts)).font(.system(size: 17, weight: .medium, design: .rounded))
                .monospacedDigit().contentTransition(.numericText())
            if let share { Text("\(Int((share * 100).rounded()))%").font(.system(size: 10)).foregroundStyle(color) }
        }
    }
    private func externalSummary(_ reading: PowerReading) -> some View {
        HStack(spacing: 14) {
            if let input = reading.inputWatts { Text("Incoming  " + PowerTechnicalDetails.watts(input)) }
            if let adapter = reading.adapterWatts { Text("Adapter  " + PowerTechnicalDetails.watts(adapter)) }
            Spacer()
            if reading.discharging { Text("Battery supplementing power").foregroundStyle(.cyan) }
        }.font(.system(size: 11)).foregroundStyle(.secondary)
    }
    private func chargeTargets(_ reading: PowerReading) -> some View {
        HStack(spacing: 16) {
            ForEach(reading.chargeTargets, id: \.percent) { target in
                HStack(spacing: 7) {
                    ZStack {
                        Circle().stroke(.white.opacity(0.10), lineWidth: 2)
                        Circle().trim(from: 0, to: min(1, (reading.percentage ?? 0) / Double(target.percent)))
                            .stroke(.green.opacity(0.8), style: StrokeStyle(lineWidth: 2, lineCap: .round)).rotationEffect(.degrees(-90))
                    }.frame(width: 15, height: 15)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Text("\(target.percent)%").foregroundStyle(.secondary)
                            Text((target.source == .minimum ? "≥ " : "≈ ") + PowerReading.duration(target.minutes)).monospacedDigit()
                        }.font(.system(size: 11, weight: .medium))
                        Text(target.source == .system ? "macOS forecast*" : target.source == .minimum ? "Before taper*" : "Current rate")
                            .font(.system(size: 9)).foregroundStyle(.white.opacity(0.4))
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                .help("Estimates, not guarantees. *The macOS forecast is never shorter than the current-rate estimate. Without that forecast, full charge is a lower bound before taper.")
            }
        }.padding(.top, 2)
    }
}

private struct PowerHistoryGraph: View {
    let history: PowerHistory
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 9) {
                if history.hasBlue { legend(history.series.rawValue, .blue) }
                if history.hasGreen { legend("Battery", .green) }
                Spacer(minLength: 0)
                Text("60s").foregroundStyle(.white.opacity(0.4))
            }.font(.system(size: 9))
            Chart {
                ForEach([false, true], id: \.self) { green in
                    ForEach(Array(history.segments(green: green).enumerated()), id: \.offset) { index, segment in
                        ForEach(segment, id: \.time) { point in
                            let watts = (green ? point.green : point.blue) ?? 0
                            let color: Color = green ? .green : .blue
                            let series = "\(green)-\(index)"
                            AreaMark(x: .value("Time", point.time), yStart: .value("Baseline", 0), yEnd: .value("Watts", watts), series: .value("Series", series))
                                .foregroundStyle(LinearGradient(colors: [color.opacity(0.20), color.opacity(0.01)], startPoint: .top, endPoint: .bottom))
                                .interpolationMethod(.monotone)
                            LineMark(x: .value("Time", point.time), y: .value("Watts", watts), series: .value("Series", series))
                                .foregroundStyle(color).lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                                .interpolationMethod(.monotone)
                            if point.time == segment.last?.time {
                                PointMark(x: .value("Time", point.time), y: .value("Watts", watts))
                                    .foregroundStyle(color).symbolSize(10)
                            }
                        }
                    }
                }
            }
            .chartXScale(domain: ((history.points.last?.time ?? 60) - 60)...(history.points.last?.time ?? 60))
            .chartYScale(domain: 0...history.maximum)
            .chartXAxis(.hidden).chartYAxis(.hidden).chartLegend(.hidden)
            .chartPlotStyle { plot in
                plot.background {
                    VStack { Rectangle().frame(height: 0.5); Spacer(); Rectangle().frame(height: 0.5); Spacer(); Rectangle().frame(height: 0.5) }
                        .foregroundStyle(.white.opacity(0.055))
                }
            }
            .frame(height: 48)
            .overlay {
                if !history.hasBlue && !history.hasGreen {
                    Text("Collecting live readings").font(.system(size: 10)).foregroundStyle(.white.opacity(0.35))
                }
            }
            .clipped()
            .contentTransition(.opacity)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: history)
            HStack {
                Text("−60s"); Spacer(); Text("\(Int(history.maximum)) W"); Spacer(); Text("Now")
            }.font(.system(size: 8)).foregroundStyle(.white.opacity(0.35))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Live power history, last 60 seconds. \(history.points.count) recorded samples. Scale zero to \(Int(history.maximum)) watts.")
    }
    private func legend(_ text: String, _ color: Color) -> some View {
        HStack(spacing: 3) { Circle().fill(color).frame(width: 4, height: 4); Text(text).foregroundStyle(.secondary) }
    }
}

struct PowerTechnicalDetails: View {
    let reading: PowerReading?
    static func watts(_ value: Double) -> String { String(format: "%.1f W", value) }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Power details").font(.headline)
            if let reading {
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 7) {
                    row("Negotiated voltage", reading.adapterVoltage, unit: "V")
                    row("Negotiated current", reading.adapterCurrent, unit: "A")
                    row("Adapter capacity (contract)", reading.adapterWatts, unit: "W")
                    row("Battery voltage", reading.voltage, unit: "V")
                    row("Battery current", reading.current, unit: "A")
                    row("Battery power (V × I)", reading.batteryWatts, unit: "W")
                    row("Battery charging rail", reading.railBatteryWatts, unit: "W")
                    row("Effective full capacity", reading.capacityMAh, unit: "mAh")
                    row("Adapter loss (estimated)", reading.adapterLossWatts, unit: "W")
                }.font(.system(size: 11))
            }
            Divider()
            Text("Native IOKit · AppleSmartBattery").font(.system(size: 11, weight: .medium))
            Text("Battery watts use voltage × signed current. Input and Mac load use PowerTelemetryData; Mac includes the display and accessories. An excluding-display-and-accessories sensor is not supported.")
            Text("Read once per second while visible, averaged over five samples. Hardware sensors may refresh at different times; readings are not calibrated against a power meter. Distribution appears only for a consistent sensor budget. History starts when this page opens.")
            Text("Adapter capacity is a negotiated ceiling, not actual input or the charger's printed rating. Adapter losses are a hardware estimate before power reaches the Mac. Negative battery current means discharge.")
            Text("Runtime and milestones are estimates using effective battery capacity and current. Full-charge forecasts use macOS when available, bounded by the current-rate estimate. Holds and taper can extend charging time.")
        }
        .font(.system(size: 10)).foregroundStyle(.secondary)
        .padding(18).frame(width: 348)
    }
    private func row(_ title: String, _ value: Double?, unit: String) -> some View {
        GridRow {
            Text(title)
            Text(value.map { String(format: unit == "mAh" ? "%.0f %@" : "%.2f %@", $0, unit) } ?? "Not reported")
                .foregroundStyle(.primary).monospacedDigit()
        }
    }
}
