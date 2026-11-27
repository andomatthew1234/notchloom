import Foundation
import CoreGraphics
import Combine

/// Native, caller-registered display data. Model strings can never become actions or URLs.
struct TodayLinkedWidget: Identifiable, Sendable, Codable {
    enum Content: Sendable, Codable {
        case event(time: String, duration: String, location: String)
        case weather(temperature: String, condition: String, range: String)
        case message(sender: String, excerpt: String)
        case reminder(detail: String, due: String)
        case information(detail: String)
    }
    let id: String
    let title: String
    let linkLabel: String
    let source: TodayReport.Source?
    let content: Content
    var conditionSymbol: String? = nil
    var detailNote: String? = nil
    var type: TodayReport.WidgetType {
        switch content {
        case .event: return .calendarEvent
        case .weather: return .weather
        case .message: return .notificationSummary
        case .reminder, .information: return .information
        }
    }
    var symbol: String {
        switch content {
        case .event: return "calendar"
        case .weather: return conditionSymbol ?? "sun.max.fill"
        case .message: return "bubble.left.and.bubble.right.fill"
        case .reminder: return "checklist"
        case .information: return "sparkle"
        }
    }
    var category: String {
        switch content {
        case .event: return "UP NEXT"
        case .weather: return "OUTSIDE"
        case .message: return "A LITTLE CATCH-UP"
        case .reminder: return "ON YOUR LIST"
        case .information: return "GOOD TO KNOW"
        }
    }
}

struct TodayWidgetRegistry: Sendable {
    private let entries: [String: TodayLinkedWidget]
    init(_ widgets: [TodayLinkedWidget] = []) throws {
        var registered: [String: TodayLinkedWidget] = [:]
        for widget in widgets {
            guard registered[widget.id] == nil else { throw TodayValidationError.invalid("duplicate registered widget") }
            registered[widget.id] = widget
        }
        entries = registered
    }
    var validationContext: TodayValidationContext {
        .init(widgets: entries.mapValues(\.type), sources: Set(entries.values.compactMap(\.source)))
    }
    func widget(_ id: String) -> TodayLinkedWidget? { entries[id] }
    func widget(for source: TodayReport.Source) -> TodayLinkedWidget? {
        entries.values.filter { $0.source == source }.sorted { $0.id < $1.id }.first
    }
    func widgets(for report: ValidatedTodayReport) -> [TodayLinkedWidget] {
        report.report.widgets.compactMap { item in
            guard let registered = entries[item.id], registered.type == item.type,
                  registered.source == item.sourceReference else { return nil }
            return registered
        }
    }
}

struct TodayPageDocument: Sendable {
    let report: ValidatedTodayReport
    let registry: TodayWidgetRegistry
    let eyebrow: String
    let subtitle: String
    let isPreview: Bool
    var statusLabel: String? = nil
    var footerText: String? = nil
    var footerURL: URL? = nil
    var sectionLabel: String? = nil
}

/// Pure geometry shared by the live notch, previews and regression tests.
struct TodayPageGeometry {
    static let twoColumnThreshold: CGFloat = 600
    static func chromeHeight(closedNotchHeight: CGFloat) -> CGFloat { max(36, closedNotchHeight) + 8 + 12 }
    static func panelSize(screen: CGRect, visibleFrame: CGRect, preferredContentHeight: CGFloat? = nil,
                          closedNotchHeight: CGFloat = 36) -> CGSize {
        let limit = min(728, max(0, screen.maxY - max(screen.minY, visibleFrame.minY) - 24))
        let fitted = preferredContentHeight.flatMap { height -> CGFloat? in
            guard height.isFinite, height > 0 else { return nil }
            return max(224, ceil(height) + chromeHeight(closedNotchHeight: closedNotchHeight))
        } ?? limit
        return CGSize(width: min(744, max(0, screen.width - 24)), height: min(limit, fitted))
    }
    static func columns(width: CGFloat) -> (main: CGFloat, widgets: CGFloat)? {
        guard width >= twoColumnThreshold else { return nil }
        let widgets = max(222, (width - 26) * 0.355)
        return (width - 26 - widgets, widgets)
    }
}

@MainActor
final class TodayLinkInteraction: ObservableObject {
    @Published private(set) var hoveredID: String?
    @Published private(set) var emphasizedID: String?
    private var settle: Task<Void, Never>?
    func hover(_ id: String, active: Bool) {
        if active { hoveredID = id } else if hoveredID == id { hoveredID = nil }
    }
    @discardableResult func select(_ id: String, registeredIDs: Set<String>) -> Bool {
        guard registeredIDs.contains(id) else { return false }
        settle?.cancel()
        emphasizedID = id
        settle = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled else { return }
            self?.emphasizedID = nil
        }
        return true
    }
    func reset() {
        settle?.cancel(); settle = nil; hoveredID = nil; emphasizedID = nil
    }
    deinit { settle?.cancel() }
}
