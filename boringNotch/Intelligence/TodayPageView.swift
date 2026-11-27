import SwiftUI

enum TodayPalette {
    static let ink = Color(red: 0.88, green: 0.91, blue: 0.95)
    static let secondary = Color(red: 0.59, green: 0.64, blue: 0.70)
    static let paper = Color(red: 0.035, green: 0.043, blue: 0.055)
    static let blue = Color(red: 0.44, green: 0.82, blue: 0.90)
    static let violet = Color(red: 0.68, green: 0.61, blue: 0.96)
}

/// Reports natural scroll content, never the viewport or an animated visual transform.
struct TodayPreferredContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat? = nil
    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        if let next = nextValue(), next.isFinite, next > 0 { value = max(value ?? 0, next) }
    }
}

private struct TodayPreferredContentHeight: ViewModifier {
    let extra: CGFloat
    func body(content: Content) -> some View {
        content.background(GeometryReader { geometry in
            Color.clear.preference(key: TodayPreferredContentHeightKey.self, value: ceil(geometry.size.height + extra))
        })
    }
}

extension View {
    func todayPreferredContentHeight(extra: CGFloat) -> some View { modifier(TodayPreferredContentHeight(extra: extra)) }
}

private struct TodayAnimationsEnabledKey: EnvironmentKey { static let defaultValue = true }
extension EnvironmentValues {
    var todayAnimationsEnabled: Bool {
        get { self[TodayAnimationsEnabledKey.self] }
        set { self[TodayAnimationsEnabledKey.self] = newValue }
    }
}

enum TodayMotion {
    static func allowed(enabled: Bool, reduced: Bool) -> Bool { enabled && !reduced }
    static func arrival(_ index: Int) -> Animation {
        .spring(response: 0.52, dampingFraction: 0.86).delay(min(0.30, Double(max(0, index)) * 0.045))
    }
    static func transition(animated: Bool) -> AnyTransition {
        animated ? .asymmetric(insertion: .opacity.combined(with: .offset(y: 12)).combined(with: .scale(scale: 0.985)),
                               removal: .opacity.combined(with: .offset(y: -5))) : .opacity
    }
}

private struct TodayArrival: ViewModifier {
    let index: Int
    @State private var appeared = false
    @Environment(\.todayAnimationsEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduced
    private var animate: Bool { TodayMotion.allowed(enabled: enabled, reduced: reduced) }
    func body(content: Content) -> some View {
        content.opacity(appeared || !animate ? 1 : 0)
            .offset(y: appeared || !animate ? 0 : 14)
            .scaleEffect(appeared || !animate ? 1 : 0.985, anchor: .top)
            .task(id: animate) {
                guard animate else { withTransaction(Transaction(animation: nil)) { appeared = true }; return }
                await Task.yield()
                guard !Task.isCancelled else { return }
                withAnimation(TodayMotion.arrival(index)) { appeared = true }
            }
            .onDisappear { withTransaction(Transaction(animation: nil)) { appeared = false } }
    }
}

private struct TodayHover: ViewModifier {
    let accent: Color
    @State private var hovered = false
    @Environment(\.todayAnimationsEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduced
    func body(content: Content) -> some View {
        let animate = TodayMotion.allowed(enabled: enabled, reduced: reduced)
        content.scaleEffect(hovered && animate ? 1.012 : 1)
            .offset(y: hovered && animate ? -2 : 0)
            .shadow(color: accent.opacity(hovered ? 0.09 : 0), radius: hovered ? 12 : 0, y: 4)
            .animation(animate ? .spring(response: 0.30, dampingFraction: 0.78) : nil, value: hovered)
            .onHover { hovered = $0 }
    }
}

extension View {
    func todayArrival(_ index: Int = 0) -> some View { modifier(TodayArrival(index: index)) }
    func todayHover(accent: Color = TodayPalette.blue) -> some View { modifier(TodayHover(accent: accent)) }
}

struct TodayMotionButtonStyle: ButtonStyle {
    @Environment(\.todayAnimationsEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduced
    func makeBody(configuration: Configuration) -> some View {
        let animate = TodayMotion.allowed(enabled: enabled, reduced: reduced)
        configuration.label.scaleEffect(configuration.isPressed && animate ? 0.93 : 1)
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(animate ? .spring(response: 0.25, dampingFraction: 0.68) : nil, value: configuration.isPressed)
    }
}

struct TodayPageView: View {
    let document: TodayPageDocument
    var expansionNamespace: Namespace.ID?
    var animationsEnabled = true
    var onBack: () -> Void = {}
    var onClose: () -> Void = {}
    var onRefresh: (() -> Void)? = nil
    var onInspect: (() -> Void)? = nil
    var onSources: (() -> Void)? = nil
    var isRefreshing = false
    var notice: String? = nil
    var noticeIsError = false
    var onCancelRefresh: (() -> Void)? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var links = TodayLinkInteraction()
    @AccessibilityFocusState private var focusedWidget: String?

    private var widgets: [TodayLinkedWidget] { document.registry.widgets(for: document.report) }
    private var ids: Set<String> { Set(widgets.map(\.id)) }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 14) {
                navigation
                if let notice {
                    TodayPageNotice(message: notice, isError: noticeIsError, working: isRefreshing, onCancel: onCancelRefresh)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { noticeHeight = $0 }
                        .transition(TodayMotion.transition(animated: !reduceMotion && animationsEnabled))
                }
                ScrollViewReader { scroll in
                    ScrollView(.vertical) {
                        VStack(spacing: 18) {
                            hero(width: geometry.size.width, short: geometry.size.height < 420)
                            reportBody(width: geometry.size.width, select: { id in
                                guard links.select(id, registeredIDs: ids) else { return }
                                focusedWidget = id
                                withAnimation(reduceMotion || !animationsEnabled ? nil : .easeInOut(duration: 0.32)) { scroll.scrollTo(id, anchor: .center) }
                            })
                            if document.isPreview {
                                Label("Fictional examples. Your accounts aren't connected to this preview.", systemImage: "info.circle")
                                    .font(.system(size: 10))
                                    .foregroundStyle(TodayPalette.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 24).padding(.bottom, 22)
                            }
                            if let footer = document.footerText {
                                VStack(alignment: .leading, spacing: 7) {
                                    Text(footer)
                                    if let url = document.footerURL { Link("Weather data · Open-Meteo", destination: url) }
                                }.font(.system(size: 10)).foregroundStyle(TodayPalette.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 24).padding(.bottom, 22)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .todayPreferredContentHeight(extra: 32 + 14 + (notice == nil ? 0 : noticeHeight + 14))
                    }
                    .scrollIndicators(.hidden)
                    .background(ScrollGestureExclusionArea())
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
        }
        .onExitCommand(perform: onClose)
        .environment(\.todayAnimationsEnabled, animationsEnabled)
        .animation(reduceMotion || !animationsEnabled ? nil : .spring(response: 0.40, dampingFraction: 0.9), value: notice != nil)
        .onDisappear { links.reset() }
    }

    private var navigation: some View {
        TodayPageToolbar(onBack: onBack, onClose: onClose, onRefresh: onRefresh, onInspect: onInspect,
                         onSources: onSources, isRefreshing: isRefreshing,
                         statusLabel: document.isPreview ? "DESIGN PREVIEW" : document.statusLabel)
            .todayArrival()
    }

    @State private var noticeHeight: CGFloat = 0

    private func hero(width: CGFloat, short: Bool) -> some View {
        TodayHero(title: document.report.report.title, eyebrow: document.eyebrow, subtitle: document.subtitle,
                  narrow: width < 500, short: short, working: isRefreshing,
                  expansionNamespace: expansionNamespace)
    }

    private func reportBody(width: CGFloat, select: @escaping (String) -> Void) -> some View {
        let inner = max(0, width - 4)
        return Group {
            if let columns = TodayPageGeometry.columns(width: inner), !widgets.isEmpty {
                HStack(alignment: .top, spacing: 26) {
                    briefing(select: select).padding(20).frame(width: columns.main, alignment: .leading)
                        .background(TodayPalette.paper, in: RoundedRectangle(cornerRadius: 20))
                        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.065)))
                    widgetColumn().frame(width: columns.widgets)
                }
            } else {
                VStack(alignment: .leading, spacing: 27) {
                    briefing(select: select).padding(width < 500 ? 18 : 22)
                        .background(TodayPalette.paper, in: RoundedRectangle(cornerRadius: 20))
                        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.065)))
                    if !widgets.isEmpty { widgetColumn() }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 2)
    }

    private func briefing(select: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 19) {
            HStack(spacing: 7) {
                Image(systemName: "sparkle").foregroundStyle(TodayPalette.blue)
                Text(document.sectionLabel ?? "YOUR BRIEFING").tracking(1.6).foregroundStyle(TodayPalette.secondary)
            }.font(.system(size: 9, weight: .semibold))
            if document.report.report.blocks.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "sun.horizon").font(.system(size: 28, weight: .light)).foregroundStyle(TodayPalette.blue)
                    Text("A little room for today.").font(.system(size: 21, weight: .medium))
                    Text("Your briefing will appear here when there's something to share.")
                        .font(.system(size: 14)).foregroundStyle(TodayPalette.secondary)
                }
                .foregroundStyle(TodayPalette.ink)
                .padding(.vertical, 22)
            }
            ForEach(Array(document.report.report.blocks.enumerated()), id: \.element.id) { index, block in
                TodayReportBlockView(block: block, registry: document.registry, allowedIDs: ids,
                                     onHover: { id, active in if let id { links.hover(id, active: active) } }, onSelect: select)
                    .todayArrival(index + 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func widgetColumn() -> some View {
        VStack(spacing: 12) {
            ForEach(Array(widgets.enumerated()), id: \.element.id) { index, widget in
                TodayLinkedWidgetCard(widget: widget, emphasized: links.emphasizedID == widget.id, hovered: links.hoveredID == widget.id)
                    .id(widget.id)
                    .accessibilityFocused($focusedWidget, equals: widget.id)
                    .todayArrival(index + 3)
            }
        }
        .animation(reduceMotion || !animationsEnabled ? nil : .easeOut(duration: 0.25), value: links.emphasizedID)
        .animation(reduceMotion || !animationsEnabled ? nil : .easeOut(duration: 0.18), value: links.hoveredID)
    }
}

/// One compact toolbar for the welcome, failure and completed briefing surfaces.
struct TodayPageToolbar: View {
    var onBack: () -> Void
    var onClose: () -> Void
    var onRefresh: (() -> Void)? = nil
    var onInspect: (() -> Void)? = nil
    var onSources: (() -> Void)? = nil
    var isRefreshing = false
    var statusLabel: String? = nil
    var body: some View {
        HStack(spacing: 6) {
            Button(action: onBack) {
                Label("Dashboard", systemImage: "chevron.left")
                    .font(.system(size: 11, weight: .medium)).padding(.horizontal, 11).frame(height: 30)
                    .background(.white.opacity(0.06), in: Capsule())
            }.accessibilityLabel("Back to Dashboard")
            Spacer(minLength: 6)
            if let statusLabel {
                Text(statusLabel).font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.4))
                    .lineLimit(1).truncationMode(.tail).padding(.trailing, 5).layoutPriority(-1)
            }
            if let onSources { TodayToolbarButton(symbol: "slider.horizontal.3", label: "Today data sources", action: onSources) }
            if let onInspect { TodayToolbarButton(symbol: "doc.text.magnifyingglass", label: "Inspect local context", action: onInspect) }
            if let onRefresh { TodayToolbarButton(symbol: "arrow.clockwise", label: "Refresh selected sources", working: isRefreshing, action: onRefresh).disabled(isRefreshing) }
            Rectangle().fill(.white.opacity(0.12)).frame(width: 1, height: 14).padding(.horizontal, 3).accessibilityHidden(true)
            TodayToolbarButton(symbol: "xmark", label: "Close Today and collapse notch", action: onClose)
        }.buttonStyle(TodayMotionButtonStyle()).foregroundStyle(.white.opacity(0.8)).frame(height: 32).padding(.horizontal, 2)
    }
}

private struct TodayToolbarButton: View {
    let symbol: String
    let label: String
    var working = false
    var action: () -> Void
    @State private var hovered = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.todayAnimationsEnabled) private var motionEnabled
    @Environment(\.accessibilityReduceMotion) private var reduced
    var body: some View {
        Button(action: action) {
            Group {
                if motionEnabled && !reduced {
                    Image(systemName: symbol)
                        .symbolEffect(.bounce, value: hovered && enabled)
                        .symbolEffect(.pulse, options: .repeating, isActive: working)
                } else { Image(systemName: symbol) }
            }.font(.system(size: 11, weight: .medium))
                .frame(width: 30, height: 30)
                .background(.white.opacity(hovered && enabled ? 0.13 : 0.045), in: Circle())
                .contentShape(Circle())
        }.opacity(enabled ? 1 : 0.4)
            .scaleEffect(hovered && enabled && motionEnabled && !reduced ? 1.08 : 1)
            .animation(motionEnabled && !reduced ? .spring(response: 0.28, dampingFraction: 0.7) : nil, value: hovered)
            .onHover { hovered = $0 }.help(label).accessibilityLabel(label)
    }
}

struct TodayPageNotice: View {
    let message: String
    var isError = false
    var working = false
    var onCancel: (() -> Void)? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.todayAnimationsEnabled) private var motionEnabled
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Group {
                if working && !reduceMotion && motionEnabled { ProgressView().controlSize(.small).scaleEffect(0.75).frame(width: 15, height: 15) }
                else { Image(systemName: isError ? "exclamationmark.circle" : working ? "sparkle" : "info.circle").font(.system(size: 13)).frame(width: 15, height: 15) }
            }.foregroundStyle(isError ? Color.orange.opacity(0.85) : Color.cyan.opacity(0.8)).padding(.top, 1)
            Text(message).font(.system(size: 11)).foregroundStyle(.white.opacity(0.7)).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
            if let onCancel { Button("Cancel", action: onCancel).font(.system(size: 11, weight: .medium)).buttonStyle(TodayMotionButtonStyle()).foregroundStyle(.white.opacity(0.8)).padding(.vertical, 1) }
        }.padding(13).frame(maxWidth: .infinity, alignment: .leading)
            .background(isError ? Color.orange.opacity(0.055) : .white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(isError ? Color.orange.opacity(0.12) : .white.opacity(0.05)))
            .accessibilityElement(children: .contain)
            .todayArrival(1)
    }
}

/// Entrance motion settles; the breathing halo exists only during visible generation.
struct TodayAtmosphere: View {
    var working = false
    @State private var unfurled = false
    @Environment(\.todayAnimationsEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduced
    private var animate: Bool { TodayMotion.allowed(enabled: enabled, reduced: reduced) }
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .trailing) {
                LinearGradient(colors: [Color(red: 0.055, green: 0.095, blue: 0.13), Color(red: 0.07, green: 0.055, blue: 0.12)], startPoint: .leading, endPoint: .trailing)
                RadialGradient(colors: [TodayPalette.blue.opacity(0.12), .clear], center: .bottomTrailing, startRadius: 5, endRadius: geometry.size.width * 0.65)
                ZStack {
                    ForEach(0..<3) { ring in
                        Circle().trim(from: 0.05, to: 0.80)
                            .stroke(AngularGradient(colors: [.clear, TodayPalette.blue.opacity(0.30), TodayPalette.violet.opacity(0.30), .clear], center: .center), style: StrokeStyle(lineWidth: 1, lineCap: .round))
                            .frame(width: CGFloat(100 + ring * 68), height: CGFloat(100 + ring * 68))
                            .rotationEffect(.degrees(unfurled || !animate ? -32 : -65))
                    }
                    Circle().fill(RadialGradient(colors: [TodayPalette.blue.opacity(0.25), .clear], center: .center, startRadius: 0, endRadius: 65))
                        .frame(width: 130, height: 130)
                    if working && animate {
                        Circle().fill(TodayPalette.blue.opacity(0.10)).frame(width: 115, height: 115).blur(radius: 18)
                            .phaseAnimator([false, true]) { content, expanded in
                                content.scaleEffect(expanded ? 1.35 : 0.82).opacity(expanded ? 0.9 : 0.35)
                            } animation: { _ in .easeInOut(duration: 1.6) }
                    }
                    Group {
                        if working && animate {
                            Image(systemName: "sun.horizon.fill").symbolEffect(.pulse, options: .repeating)
                        } else { Image(systemName: "sun.horizon.fill") }
                    }.font(.system(size: 30, weight: .light))
                        .foregroundStyle(LinearGradient(colors: [TodayPalette.blue, TodayPalette.violet], startPoint: .topLeading, endPoint: .bottomTrailing))
                }.frame(width: 244, height: 244).offset(x: 30, y: 12).opacity(geometry.size.width < 440 ? 0.10 : 0.65)
            }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }.allowsHitTesting(false).accessibilityHidden(true)
            .onAppear { withAnimation(animate ? .spring(response: 0.95, dampingFraction: 0.85) : nil) { unfurled = true } }
            .onDisappear { withTransaction(Transaction(animation: nil)) { unfurled = false } }
            .onChange(of: animate) { _, _ in withTransaction(Transaction(animation: nil)) { unfurled = true } }
    }
}

private struct TodayHero: View {
    let title: String
    let eyebrow: String
    let subtitle: String
    let narrow: Bool
    let short: Bool
    let working: Bool
    var expansionNamespace: Namespace.ID?
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label(eyebrow, systemImage: "sun.horizon")
                .font(.system(size: 9, weight: .semibold)).tracking(1.8)
                .foregroundStyle(TodayPalette.blue).padding(.bottom, short ? 13 : 19)
            Text(title)
                .font(.system(size: short ? 27 : narrow ? 29 : 34, weight: .medium, design: .rounded))
                .tracking(-0.8).foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle).font(.system(size: 12))
                .foregroundStyle(TodayPalette.secondary).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 10)
        }
        .padding(narrow ? 22 : 26)
        .padding(.trailing, narrow ? 0 : 104)
        .frame(maxWidth: .infinity, minHeight: short ? 144 : 172, alignment: .leading)
        .background { TodayAtmosphere(working: working).modifier(TodaySkyExpansion(namespace: expansionNamespace, isSource: false)) }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.10)))
        .accessibilityElement(children: .combine)
        .todayArrival(1)
    }
}

struct TodayReportBlockView: View {
    let block: TodayReport.Block
    let registry: TodayWidgetRegistry
    let allowedIDs: Set<String>
    let onHover: (String?, Bool) -> Void
    let onSelect: (String) -> Void
    var body: some View {
        switch block.type {
        case .divider:
            Rectangle().fill(.white.opacity(0.10)).frame(height: 1).padding(.vertical, 2).accessibilityHidden(true)
        case .heading:
            text(size: 19, semibold: true).padding(.top, 3)
        case .paragraph:
            text(size: block.parts.allSatisfy { $0.type == .sourceReference } ? 11 : 14)
        case .highlight:
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sparkle").font(.system(size: 14)).foregroundStyle(TodayPalette.violet).padding(.top, 3)
                text(size: 14)
            }
            .padding(16)
            .background(TodayPalette.violet.opacity(0.075), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(TodayPalette.violet.opacity(0.12)))
        case .informationCard:
            text(size: 14).padding(16)
                .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(TodayPalette.blue.opacity(0.09), lineWidth: 1))
        }
    }
    private func text(size: CGFloat, semibold: Bool = false) -> some View {
        TodayInlineText(parts: block.parts, registry: registry, allowedIDs: allowedIDs, fontSize: size, semibold: semibold, onHover: onHover, onSelect: onSelect)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TodayLinkedWidgetCard: View {
    let widget: TodayLinkedWidget
    let emphasized: Bool
    let hovered: Bool
    @State private var pointerInside = false
    @Environment(\.todayAnimationsEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduced
    private var animate: Bool { TodayMotion.allowed(enabled: enabled, reduced: reduced) }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Group {
                    if animate { Image(systemName: widget.symbol).symbolEffect(.bounce, value: pointerInside || emphasized) }
                    else { Image(systemName: widget.symbol) }
                }.foregroundStyle(accent)
                Text(widget.category).tracking(1.1).foregroundStyle(TodayPalette.secondary)
            }.font(.system(size: 9, weight: .semibold))
            content
            if let note = widget.detailNote { Text(note).font(.system(size: 10)).foregroundStyle(TodayPalette.secondary) }
        }
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(TodayPalette.ink)
        .background(LinearGradient(colors: [surface, TodayPalette.paper], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 17))
        .overlay(RoundedRectangle(cornerRadius: 17).strokeBorder(accent.opacity(emphasized ? 0.8 : hovered || pointerInside ? 0.42 : 0.14), lineWidth: emphasized ? 1.6 : 1))
        .shadow(color: accent.opacity(emphasized ? 0.12 : 0), radius: 10, y: 3)
        .scaleEffect(animate ? emphasized ? 1.025 : pointerInside || hovered ? 1.012 : 1 : 1)
        .offset(y: animate && (pointerInside || hovered) ? -2 : 0)
        .animation(animate ? .spring(response: 0.36, dampingFraction: 0.76) : nil, value: pointerInside || hovered || emphasized)
        .onHover { pointerInside = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(widget.title + (emphasized ? ", highlighted" : ""))
        .accessibilityValue(accessibilityDetail)
    }
    @ViewBuilder private var content: some View {
        switch widget.content {
        case .event(let time, let duration, let location):
            Text(time).font(.system(size: 29, weight: .medium, design: .rounded)).tracking(-0.7).contentTransition(.numericText())
            Text(widget.title).font(.system(size: 14, weight: .semibold))
            Text(location).font(.system(size: 11)).foregroundStyle(TodayPalette.secondary)
            Text(duration).font(.system(size: 10, weight: .medium)).foregroundStyle(accent)
                .padding(.horizontal, 8).padding(.vertical, 4).background(accent.opacity(0.08), in: Capsule())
        case .weather(let temperature, let condition, let range):
            HStack(alignment: .center) {
                Text(temperature).font(.system(size: 41, weight: .light, design: .rounded)).tracking(-1.8).contentTransition(.numericText())
                Spacer(minLength: 8)
                Image(systemName: widget.conditionSymbol ?? "sun.max.fill").font(.system(size: 31)).symbolRenderingMode(.palette)
                    .foregroundStyle(Color(red: 0.91, green: 0.63, blue: 0.13), Color.yellow)
            }
            Text(condition).font(.system(size: 13, weight: .medium))
            Text(range).font(.system(size: 11)).foregroundStyle(TodayPalette.secondary)
        case .message(let sender, let excerpt):
            Text(sender).font(.system(size: 15, weight: .semibold))
            Text(excerpt).font(.system(size: 13)).lineSpacing(4).foregroundStyle(TodayPalette.secondary)
            Text("Observed banner excerpt").font(.system(size: 10)).foregroundStyle(accent)
        case .reminder(let detail, let due):
            Text(widget.title).font(.system(size: 15, weight: .semibold))
            Text(detail).font(.system(size: 13)).lineSpacing(4).foregroundStyle(TodayPalette.secondary)
            Label(due, systemImage: "circle.dotted").font(.system(size: 10)).foregroundStyle(accent)
        case .information(let detail):
            Text(widget.title).font(.system(size: 15, weight: .semibold))
            Text(detail).font(.system(size: 13)).lineSpacing(4).foregroundStyle(TodayPalette.secondary)
        }
    }
    private var accent: Color {
        switch widget.content {
        case .weather: Color(red: 0.94, green: 0.77, blue: 0.40)
        case .message: TodayPalette.violet
        case .reminder: Color(red: 0.47, green: 0.81, blue: 0.67)
        default: TodayPalette.blue
        }
    }
    private var accessibilityDetail: String {
        switch widget.content {
        case .event(let time, let duration, let location): "\(time), \(duration), \(location)"
        case .weather(let temperature, let condition, let range): "\(temperature), \(condition), \(range)"
        case .message(let sender, let excerpt): "\(sender): \(excerpt)"
        case .reminder(let detail, let due): "\(detail), \(due)"
        case .information(let detail): detail
        }
    }
    private var surface: Color {
        switch widget.content {
        case .weather: Color(red: 0.11, green: 0.095, blue: 0.065)
        case .message: Color(red: 0.09, green: 0.075, blue: 0.14)
        case .reminder: Color(red: 0.055, green: 0.105, blue: 0.095)
        default: Color(red: 0.055, green: 0.09, blue: 0.12)
        }
    }
}

struct TodayUnavailableView: View {
    var onBack: () -> Void = {}
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "sun.haze").font(.system(size: 34, weight: .light)).foregroundStyle(.cyan)
            Text("A little pause.").font(.system(size: 27, weight: .medium, design: .rounded))
            Text("This preview couldn't be displayed safely. Return to your Dashboard and try again.")
                .font(.system(size: 14)).foregroundStyle(.secondary)
            Button("Back to Dashboard", action: onBack).buttonStyle(.bordered)
        }
        .padding(28).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

#if DEBUG
private struct TodayPreviewGallery: View {
    @State private var scenario: TodayPreviewContent.Scenario = .linked
    var body: some View {
        VStack {
            Picker("Synthetic report", selection: $scenario) {
                ForEach(TodayPreviewContent.Scenario.allCases) { Text($0.rawValue).tag($0) }
            }.padding(8)
            if let document = try? TodayPreviewContent.make(scenario) { TodayPageView(document: document, animationsEnabled: false).id(scenario) }
            else { TodayUnavailableView() }
        }.padding(20).frame(width: 720, height: 720).background(.black).preferredColorScheme(.dark)
    }
}
#Preview("Today · synthetic report gallery") { TodayPreviewGallery() }
#endif
