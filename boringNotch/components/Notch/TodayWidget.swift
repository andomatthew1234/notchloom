import SwiftUI

struct TodayInvitationButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.86), value: configuration.isPressed)
    }
}

struct TodaySkyExpansion: ViewModifier {
    let namespace: Namespace.ID?
    let isSource: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if let namespace { content.matchedGeometryEffect(id: "today-sky", in: namespace, isSource: isSource) }
        else { content }
    }
}

/// Native display content; the sample is reserved for explicit design previews.
struct TodayWidgetContent {
    let day: String
    let weekday: String
    let date: String
    static let designSample = Self(day: "19", weekday: "Thursday", date: "19 November")
}

/// Plans against actual occupied widths, including cards spanning multiple slots.
struct DashboardSlotPlan {
    static let side: CGFloat = 112
    static let spacing: CGFloat = 10
    let slots: Int
    let width: CGFloat
    let gap: CGFloat

    init(availableWidth: CGFloat, occupiedWidths: [CGFloat]) {
        let remaining = availableWidth - occupiedWidths.reduce(0, +)
            - CGFloat(occupiedWidths.count) * Self.spacing
        slots = min(3, max(0, Int(floor((remaining + Self.spacing) / (Self.side + Self.spacing)))))
        width = slots == 0 ? 0 : min(remaining, 3 * Self.side + 2 * Self.spacing)
        gap = slots > 0 ? Self.spacing : max(0, min(Self.spacing,
            (availableWidth - occupiedWidths.reduce(0, +)) / CGFloat(max(1, occupiedWidths.count - 1))))
    }
}

struct TodayWidget: View {
    let slots: Int
    var content: TodayWidgetContent = .designSample
    var expansionNamespace: Namespace.ID?
    var isPreview = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var hovered = false

    var body: some View {
        GeometryReader { geometry in
            let compact = slots == 1
            let hero = slots == 3
            let sunSize: CGFloat = compact ? 31 : hero ? 61 : 45
            let sunX = geometry.size.width - (compact ? 28 : hero ? 49 : 34)
            ZStack(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    LinearGradient(stops: [
                        .init(color: Color(red: 0.05, green: 0.37, blue: 0.70), location: 0),
                        .init(color: Color(red: 0.18, green: 0.60, blue: 0.87), location: 0.42),
                        .init(color: Color(red: 0.60, green: 0.82, blue: 0.93), location: 0.79),
                        .init(color: Color(red: 0.89, green: 0.91, blue: 0.80), location: 1)
                    ], startPoint: .bottomLeading, endPoint: .topTrailing)

                    RadialGradient(colors: [Color(red: 1, green: 0.88, blue: 0.49).opacity(0.64), .clear],
                                   center: UnitPoint(x: 0.9, y: 0.18), startRadius: 0,
                                   endRadius: geometry.size.width * 0.65)
                    Ellipse()
                        .fill(.white.opacity(0.18))
                        .frame(width: geometry.size.width * 1.2, height: 64)
                        .blur(radius: 22)
                        .offset(x: geometry.size.width * 0.18, y: 65)

                    TodaySkyCurve(composition: CGFloat(slots))
                        .stroke(.white.opacity(0.15), lineWidth: 10)
                        .blur(radius: 6)
                    TodaySkyCurve(composition: CGFloat(slots))
                        .stroke(.white.opacity(0.85), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))

                    ZStack {
                        Circle()
                            .fill(Color(red: 1, green: 0.83, blue: 0.35).opacity(0.45))
                            .blur(radius: 13)
                            .padding(-12)
                        Circle()
                            .fill(RadialGradient(colors: [Color(red: 1, green: 0.98, blue: 0.78),
                                                         Color(red: 1, green: 0.87, blue: 0.37),
                                                         Color(red: 1, green: 0.73, blue: 0.20)],
                                                 center: .topLeading, startRadius: 0, endRadius: sunSize))
                            .overlay(Circle().strokeBorder(.white.opacity(0.46), lineWidth: 0.7))
                    }
                    .frame(width: sunSize, height: sunSize)
                    .position(x: sunX, y: compact ? 28 : hero ? 42 : 32)

                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .modifier(TodaySkyExpansion(namespace: expansionNamespace, isSource: true))

                Text("TODAY")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(2.1)
                    .foregroundStyle(.white.opacity(0.84))
                    .offset(x: 14, y: 13)

                Text(content.day)
                    .font(.system(size: 45, weight: .medium, design: .rounded))
                    .tracking(-2)
                    .opacity(compact ? 1 : 0)
                    .offset(x: 12, y: 31)

                Text(compact ? content.weekday.uppercased() : content.weekday)
                    .font(.system(size: compact ? 9 : hero ? 36 : 27,
                                  weight: compact ? .semibold : .medium, design: .rounded))
                    .tracking(compact ? 1.2 : -1.2)
                    .lineLimit(1)
                    .offset(x: 14, y: compact ? 88 : hero ? 35 : 40)

                Text(content.date)
                    .font(.system(size: 11, weight: .medium))
                    .tracking(0.15)
                    .opacity(compact ? 0 : 0.9)
                    .offset(x: 15, y: 87)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .foregroundStyle(.white)
            .shadow(color: Color(red: 0.04, green: 0.25, blue: 0.43).opacity(contrast == .increased ? 0.5 : 0.12),
                    radius: 1, y: 1)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(contrast == .increased ? 0.5 : 0.18), lineWidth: 0.7))
        }
        .frame(height: DashboardSlotPlan.side)
        .scaleEffect(hovered && !reduceMotion ? 1.015 : 1)
        .offset(y: hovered && !reduceMotion ? -2 : 0)
        .shadow(color: .cyan.opacity(hovered ? 0.14 : 0), radius: hovered ? 10 : 0, y: 3)
        .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.78), value: hovered)
        .onHover { hovered = $0 }
        .animation(reduceMotion ? nil : .spring(response: 0.48, dampingFraction: 0.88), value: slots)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Today\(isPreview ? " design preview" : ""), \(content.weekday), \(content.date)")
    }
}

/// One continuous path morphs between compact, medium and expansive compositions.
private struct TodaySkyCurve: Shape {
    var composition: CGFloat
    var animatableData: CGFloat {
        get { composition }
        set { composition = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let expansion = min(1, max(0, (composition - 1) / 2))
        let w = rect.width, h = rect.height
        var path = Path()
        path.move(to: CGPoint(x: w * (0.49 + expansion * 0.02), y: h * 1.12))
        path.addCurve(to: CGPoint(x: w * 1.09, y: h * (0.09 - expansion * 0.15)),
                      control1: CGPoint(x: w * (0.94 - expansion * 0.23), y: h * (0.80 + expansion * 0.11)),
                      control2: CGPoint(x: w * (0.53 + expansion * 0.28), y: h * (0.34 - expansion * 0.30)))
        return path
    }
}

#if DEBUG
private struct TodayWidgetPreview: View {
    @State private var slots = 1
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(1...3, id: \.self) { span in
                TodayWidget(slots: span)
                    .frame(width: CGFloat(span) * 112 + CGFloat(span - 1) * 10)
            }
            Picker("Animated size", selection: $slots) {
                ForEach(1...3, id: \.self) { Text("\($0) squares").tag($0) }
            }.pickerStyle(.segmented)
            TodayWidget(slots: slots)
                .frame(width: CGFloat(slots) * 112 + CGFloat(slots - 1) * 10)
                .animation(.spring(response: 0.48, dampingFraction: 0.88), value: slots)
        }
        .padding(24)
        .frame(width: 430, alignment: .leading)
        .background(.black)
    }
}
#Preview("Today · all sizes & transitions") { TodayWidgetPreview() }
#endif
