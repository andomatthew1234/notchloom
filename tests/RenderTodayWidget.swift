import AppKit
import SwiftUI

private struct TodayReview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top, spacing: 22) {
                ForEach(1...3, id: \.self) { span in
                    VStack(alignment: .leading, spacing: 10) {
                        Text("\(span) square\(span == 1 ? "" : "s")")
                            .font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                        TodayWidget(slots: span)
                            .frame(width: CGFloat(span) * 112 + CGFloat(span - 1) * 10)
                    }
                }
            }.frame(width: 746, alignment: .leading)
            ForEach(0..<4) { combination in
                let music = combination & 1 != 0
                let apps = combination & 2 != 0
                let occupied: [CGFloat] = (music ? [112] : []) + (apps ? [230] : [])
                let plan = DashboardSlotPlan(availableWidth: 668, occupiedWidths: occupied)
                VStack(alignment: .leading, spacing: 9) {
                    Text("Now Playing \(music ? "visible" : "hidden") · Quick Apps \(apps ? "visible" : "hidden")")
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                    HStack(spacing: 10) {
                        if music {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(LinearGradient(colors: [.indigo, .pink.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .overlay(Image(systemName: "waveform").font(.system(size: 24)).foregroundStyle(.white))
                                .frame(width: 112, height: 112)
                        }
                        if plan.slots > 0 { TodayWidget(slots: plan.slots).frame(width: plan.width) }
                        if apps {
                            VStack(alignment: .leading, spacing: 16) {
                                Label("Quick apps", systemImage: "square.grid.2x2.fill")
                                    .font(.system(size: 12, weight: .semibold))
                                HStack(spacing: 10) {
                                    ForEach(["face.smiling", "safari", "music.note", "square.grid.3x3"], id: \.self) { symbol in
                                        Image(systemName: symbol)
                                            .font(.system(size: 22)).frame(width: 35, height: 35)
                                    }
                                }
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .frame(width: 230, height: 112, alignment: .topLeading)
                            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 17))
                        }
                    }.frame(width: 668, height: 112)
                }
            }
        }
        .padding(26)
        .background(Color(white: 0.025))
    }
}

@MainActor private final class TransitionState: ObservableObject {
    @Published var slots = 1
}
private struct TransitionReview: View {
    @ObservedObject var state: TransitionState
    var body: some View {
        TodayWidget(slots: state.slots)
            .frame(width: CGFloat(state.slots) * 112 + CGFloat(state.slots - 1) * 10)
            .animation(.spring(response: 0.48, dampingFraction: 0.88), value: state.slots)
            .frame(width: 400, height: 144, alignment: .leading)
            .padding(16)
            .background(.black)
    }
}

@main struct RenderTodayWidget {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        let directory = CommandLine.arguments.dropFirst().first ?? "/tmp/notchloom-today-review"
        for (widths, expected) in [([CGFloat](), 3), ([112], 3), ([230], 3), ([112,230], 2), ([112,136,150,230], 0)] {
            let plan = DashboardSlotPlan(availableWidth: 668, occupiedWidths: widths)
            precondition(plan.slots == expected)
            precondition(plan.width + widths.reduce(0,+) + CGFloat(widths.count) * 10 <= 668 || plan.slots == 0)
        }
        precondition(DashboardSlotPlan(availableWidth: 490, occupiedWidths: [112,230]).slots == 1)
        let busyWidths: [CGFloat] = [112, 136, 150, 230]
        let busy = DashboardSlotPlan(availableWidth: 646, occupiedWidths: busyWidths)
        precondition(busy.slots == 0 && busyWidths.reduce(0, +) + busy.gap * 3 <= 646)
        let renderer = ImageRenderer(content: TodayReview())
        renderer.scale = 2
        guard let image = renderer.cgImage else { fatalError("No rendered review") }
        try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
            .write(to: URL(fileURLWithPath: directory).appendingPathComponent("today-compositions.png"))
        for span in 1...3 {
            let renderer = ImageRenderer(content: TodayWidget(slots: span)
                .frame(width: CGFloat(span) * 112 + CGFloat(span - 1) * 10))
            renderer.scale = 3
            guard let image = renderer.cgImage else { fatalError("No rendered widget") }
            try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
                .write(to: URL(fileURLWithPath: directory).appendingPathComponent("today-\(span).png"))
        }
        let state = TransitionState()
        let host = NSHostingView(rootView: TransitionReview(state: state))
        let window = NSWindow(contentRect: CGRect(x: -2000, y: -2000, width: 432, height: 176),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        for (from, to) in [(1, 2), (2, 3), (3, 1)] {
            state.slots = to
            for frame in 0..<8 {
                try await Task.sleep(for: .milliseconds(80))
                host.layoutSubtreeIfNeeded()
                let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
                host.cacheDisplay(in: host.bounds, to: rep)
                try rep.representation(using: .png, properties: [:])!
                    .write(to: URL(fileURLWithPath: directory).appendingPathComponent("transition-\(from)-\(to)-\(frame).png"))
            }
        }
        window.close()
        print("PASS slot allocation, all sizes, four dashboard compositions rendered")
    }
}
