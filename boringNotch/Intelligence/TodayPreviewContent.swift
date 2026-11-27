import Foundation

/// Controlled Phase 2 demonstration. Kept outside the real Gemini request/data pipeline.
enum TodayPreviewContent {
    static let standard: Result<TodayPageDocument, Error> = Result { try makeStandard() }

    static func makeStandard() throws -> TodayPageDocument {
        let widgets: [TodayLinkedWidget] = [
            .init(id: "preview-meeting", title: "Project catch-up", linkLabel: "project catch-up",
                  source: .init(type: .calendarEvent, id: "sample-event"),
                  content: .event(time: "2:30 PM", duration: "30 min", location: "Video call · with Alex")),
            .init(id: "preview-weather", title: "A little more sunshine", linkLabel: "a warmer afternoon",
                  source: .init(type: .weather, id: "sample-weather"),
                  content: .weather(temperature: "24°", condition: "Mostly sunny", range: "High 25°  ·  Low 16°")),
            .init(id: "preview-message", title: "A note from Jordan", linkLabel: "Jordan's message",
                  source: .init(type: .notificationSummary, id: "sample-message"),
                  content: .message(sender: "Jordan", excerpt: "Found a lovely spot for Saturday. I'll send you the details later.")),
            .init(id: "preview-list", title: "Make a little space", linkLabel: "your reading list",
                  source: .init(type: .suppliedContext, id: "sample-reminder"),
                  content: .reminder(detail: "Set aside a few minutes for the next chapter.", due: "Whenever you're ready"))
        ]
        let registry = try TodayWidgetRegistry(widgets)
        let blocks: [TodayReport.Block] = [
            .init(id: "intro", type: .paragraph, parts: [
                .init(type: .text, value: "There's a little breathing room in your day. Your "),
                .init(type: .widgetReference, widgetID: "preview-meeting"),
                .init(type: .text, value: " with Alex is this afternoon, leaving the morning open for something that matters to you.")]),
            .init(id: "heading", type: .heading, parts: [.init(type: .text, value: "A good day to step outside.")]),
            .init(id: "outside", type: .paragraph, parts: [
                .init(type: .text, value: "Expect "), .init(type: .widgetReference, widgetID: "preview-weather"),
                .init(type: .text, value: ". A short walk before your call could be a lovely way to reset.")]),
            .init(id: "highlight", type: .highlight, parts: [.init(type: .text, value: "One thing at a time. You don't have to fill every moment to make today a good one.")]),
            .init(id: "divider", type: .divider, parts: []),
            .init(id: "catch-up", type: .paragraph, parts: [
                .init(type: .widgetReference, widgetID: "preview-message"),
                .init(type: .text, value: " has a weekend idea waiting for you. There's no rush — it'll still be there after you've had a moment to yourself.")]),
            .init(id: "reading", type: .informationCard, parts: [
                .init(type: .text, value: "Something just for you\n"),
                .init(type: .text, value: "A few quiet minutes with "), .init(type: .widgetReference, widgetID: "preview-list"),
                .init(type: .text, value: " might be a nice way to finish the day.")]),
            .init(id: "source", type: .paragraph, parts: [.init(type: .sourceReference, sourceReference: widgets[0].source)])
        ]
        return try document(title: "Hey, Matthew!", blocks: blocks, widgets: widgets, registry: registry)
    }

    private static func document(title: String, blocks: [TodayReport.Block], widgets: [TodayLinkedWidget], registry: TodayWidgetRegistry) throws -> TodayPageDocument {
        let report = TodayReport(version: 1, title: title, blocks: blocks,
                                 widgets: widgets.map { .init(id: $0.id, type: $0.type, sourceReference: $0.source) }, scheduledInsights: [])
        let validated = try TodayReportValidator.validate(JSONEncoder().encode(report), context: registry.validationContext)
        return .init(report: validated, registry: registry, eyebrow: "A LITTLE CLARITY FOR YOUR DAY", subtitle: "Here's what matters today.", isPreview: true)
    }

    #if DEBUG
    enum Scenario: String, CaseIterable, Identifiable {
        case linked = "Linked briefing", short = "Short", long = "Long", noWidgets = "No widgets"
        case paragraphs = "Multiple paragraphs", longTitle = "Long title", empty = "Empty"
        case invalidReference = "Invalid reference", unsupported = "Unsupported block"
        var id: String { rawValue }
    }
    static func make(_ scenario: Scenario) throws -> TodayPageDocument {
        if scenario == .linked { return try makeStandard() }
        if scenario == .invalidReference || scenario == .unsupported {
            let payload = scenario == .invalidReference
                ? #"{"version":1,"title":"Preview","blocks":[{"id":"one","type":"paragraph","parts":[{"type":"widgetReference","widgetID":"invented"}]}],"widgets":[],"scheduledInsights":[]}"#
                : #"{"version":1,"title":"Preview","blocks":[{"id":"one","type":"arbitraryExecutableUI","parts":[]}],"widgets":[],"scheduledInsights":[]}"#
            let validated = try TodayReportValidator.validate(Data(payload.utf8))
            return .init(report: validated, registry: try .init(), eyebrow: "PREVIEW", subtitle: "", isPreview: true)
        }
        let text = "A slower morning can be a good beginning. Leave a little room for the unexpected, make time for the people you care about, and choose one meaningful thing to move forward."
        let count = scenario == .empty ? 0 : scenario == .long ? 18 : scenario == .paragraphs ? 5 : 1
        let blocks = (0..<count).map { index in
            TodayReport.Block(id: "paragraph-\(index)", type: index % 4 == 3 ? .highlight : .paragraph,
                              parts: [.init(type: .text, value: scenario == .long ? String(repeating: text + " ", count: 3) : text)])
        }
        return try document(title: scenario == .longTitle ? "A little perspective for a wonderfully full day ahead" : "A fresh perspective.",
                            blocks: blocks, widgets: [], registry: .init())
    }
    #endif
}
