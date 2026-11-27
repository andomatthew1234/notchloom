import Foundation

enum TodayValidationError: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        if case .invalid(let field) = self { return "The Today response failed validation: \(field)." }
        return nil
    }
}

struct TodayReport: Codable, Sendable, Equatable {
    enum BlockType: String, Codable, Sendable, CaseIterable { case heading, paragraph, highlight, informationCard, divider }
    enum PartType: String, Codable, Sendable { case text, widgetReference, sourceReference }
    enum WidgetType: String, Codable, Sendable, CaseIterable { case information, calendarEvent, weather, notificationSummary }
    enum SourceType: String, Codable, Sendable, CaseIterable { case calendarEvent, weather, notificationSummary, suppliedContext }
    enum Delivery: String, Codable, Sendable, CaseIterable { case quiet, standard }
    struct Source: Codable, Sendable, Hashable { let type: SourceType; let id: String }
    struct Part: Codable, Sendable, Equatable {
        let type: PartType
        let value: String?
        let widgetID: String?
        let sourceReference: Source?
        init(type: PartType, value: String? = nil, widgetID: String? = nil, sourceReference: Source? = nil) {
            self.type = type; self.value = value; self.widgetID = widgetID; self.sourceReference = sourceReference
        }
    }
    struct Block: Codable, Sendable, Equatable { let id: String; let type: BlockType; let parts: [Part] }
    struct Widget: Codable, Sendable, Equatable {
        let id: String; let type: WidgetType; let sourceReference: Source?
    }
    struct ScheduledInsight: Codable, Sendable, Equatable {
        let id: String; let triggerAt: String; let title: String; let body: String
        let sourceReference: Source; let delivery: Delivery
    }
    let version: Int
    let title: String
    let blocks: [Block]
    let widgets: [Widget]
    let scheduledInsights: [ScheduledInsight]
}

/// Future callers explicitly provide their own verified references. This type collects nothing.
struct TodayValidationContext: Sendable {
    var widgets: [String: TodayReport.WidgetType] = [:]
    var sources: Set<TodayReport.Source> = []
}

/// Only the validator can create the value a future renderer accepts.
struct ValidatedTodayReport: Sendable {
    let report: TodayReport
    fileprivate init(_ report: TodayReport) { self.report = report }
}

enum TodayReportValidator {
    static func validate(_ data: Data, context: TodayValidationContext = .init()) throws -> ValidatedTodayReport {
        guard data.count <= 128_000 else { throw TodayValidationError.invalid("response size") }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TodayValidationError.invalid("JSON object required")
        }
        // Codable ignores unknown keys by default; reject them explicitly at every object boundary.
        try keys(object, required: ["version", "title", "blocks", "widgets", "scheduledInsights"])
        for block in object["blocks"] as? [[String: Any]] ?? [] {
            try keys(block, required: ["id", "type", "parts"])
            for part in block["parts"] as? [[String: Any]] ?? [] {
                try keys(part, required: ["type"], optional: ["value", "widgetID", "sourceReference"])
                if let source = part["sourceReference"] as? [String: Any] { try keys(source, required: ["id", "type"]) }
            }
        }
        for widget in object["widgets"] as? [[String: Any]] ?? [] {
            try keys(widget, required: ["id", "type"], optional: ["sourceReference"])
            if let source = widget["sourceReference"] as? [String: Any] { try keys(source, required: ["id", "type"]) }
        }
        for insight in object["scheduledInsights"] as? [[String: Any]] ?? [] {
            try keys(insight, required: ["id", "triggerAt", "title", "body", "sourceReference", "delivery"])
            if let source = insight["sourceReference"] as? [String: Any] { try keys(source, required: ["id", "type"]) }
        }
        guard let report = try? JSONDecoder().decode(TodayReport.self, from: data) else {
            throw TodayValidationError.invalid("missing, malformed or unsupported fields")
        }
        guard report.version == 1 else { throw TodayValidationError.invalid("unsupported schema version") }
        guard (1...120).contains(report.title.count), !report.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              report.blocks.count <= 24, report.widgets.count <= 12, report.scheduledInsights.count <= 12 else {
            throw TodayValidationError.invalid("report limits")
        }
        var ids = Set<String>()
        func register(_ id: String) throws {
            guard validID(id), ids.insert(id).inserted else { throw TodayValidationError.invalid("invalid or duplicate identifier") }
        }
        func verify(_ source: TodayReport.Source) throws {
            guard validID(source.id), context.sources.contains(source) else { throw TodayValidationError.invalid("unverified source reference") }
        }
        for widget in report.widgets {
            try register(widget.id)
            guard context.widgets[widget.id] == widget.type else { throw TodayValidationError.invalid("unverified widget") }
            if let source = widget.sourceReference { try verify(source) }
            if widget.type != .information {
                guard let source = widget.sourceReference, source.type.rawValue == widget.type.rawValue else {
                    throw TodayValidationError.invalid("widget source type")
                }
            }
        }
        let declaredWidgets = Set(report.widgets.map(\.id))
        var contentLength = report.title.count
        for block in report.blocks {
            try register(block.id)
            if block.type == .divider {
                guard block.parts.isEmpty else { throw TodayValidationError.invalid("divider must have no parts") }
                continue
            }
            guard (1...24).contains(block.parts.count) else { throw TodayValidationError.invalid("block parts limit") }
            for part in block.parts {
                switch part.type {
                case .text:
                    guard let value = part.value, (1...4000).contains(value.count), part.widgetID == nil, part.sourceReference == nil else {
                        throw TodayValidationError.invalid("text part")
                    }
                    contentLength += value.count
                case .widgetReference:
                    guard part.value == nil, part.sourceReference == nil, let id = part.widgetID, declaredWidgets.contains(id) else {
                        throw TodayValidationError.invalid("unknown widget reference")
                    }
                case .sourceReference:
                    guard part.value == nil, part.widgetID == nil, let source = part.sourceReference else {
                        throw TodayValidationError.invalid("source reference part")
                    }
                    try verify(source)
                }
            }
        }
        for insight in report.scheduledInsights {
            try register(insight.id)
            try verify(insight.sourceReference)
            guard (1...120).contains(insight.title.count), (1...2000).contains(insight.body.count),
                  validTimestamp(insight.triggerAt) else { throw TodayValidationError.invalid("scheduled insight fields or timestamp") }
            contentLength += insight.title.count + insight.body.count
        }
        guard contentLength <= 32_000 else { throw TodayValidationError.invalid("total content length") }
        return ValidatedTodayReport(report)
    }

    private static func keys(_ object: [String: Any], required: Set<String>, optional: Set<String> = []) throws {
        let actual = Set(object.keys)
        guard required.isSubset(of: actual), actual.isSubset(of: required.union(optional)) else {
            throw TodayValidationError.invalid("missing or unknown properties")
        }
    }
    private static func validID(_ value: String) -> Bool {
        value.range(of: "^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$", options: .regularExpression) != nil
    }
    private static func validTimestamp(_ value: String) -> Bool {
        guard value.count <= 40, value.range(of: "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}(\\.\\d{1,6})?(Z|[+-]\\d{2}:\\d{2})$", options: .regularExpression) != nil else { return false }
        let dateParts = value.prefix(19).split(whereSeparator: { "-T:".contains($0) }).compactMap { Int($0) }
        guard dateParts.count == 6, dateParts[0] > 0, (1...12).contains(dateParts[1]),
              (0...23).contains(dateParts[3]), (0...59).contains(dateParts[4]), (0...59).contains(dateParts[5]) else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(year: dateParts[0], month: dateParts[1], day: 1)
        guard let month = calendar.date(from: components), let days = calendar.range(of: .day, in: .month, for: month), days.contains(dateParts[2]) else { return false }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if formatter.date(from: value) != nil { return true }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value) != nil
    }
}

enum TodayReportSchema {
    static let syntheticPrompt = "Return a version 1 Today report titled Hello, with one paragraph block (id intro) saying This is a synthetic connection test. Use a text part. widgets and scheduledInsights must be empty arrays. No real personal data or invented references."

    static func data() throws -> Data {
        // Array bounds and identifier regexes multiply Gemini's constrained-decoding grammar.
        // Keep the wire grammar structural; all limits remain mandatory in the local validator.
        func string(_ max: Int) -> [String: Any] { ["type": "string"] }
        func enumeration(_ values: [String]) -> [String: Any] { ["type": "string", "enum": values] }
        func object(_ properties: [String: Any], _ required: [String]) -> [String: Any] {
            ["type": "object", "properties": properties, "required": required, "additionalProperties": false]
        }
        func array(_ item: [String: Any], _ max: Int) -> [String: Any] { ["type": "array", "items": item] }
        let id: [String: Any] = ["type": "string"]
        let source = object(["type": enumeration(TodayReport.SourceType.allCases.map(\.rawValue)), "id": id], ["type", "id"])
        let textPart = object(["type": enumeration(["text"]), "value": string(4000)], ["type", "value"])
        let widgetPart = object(["type": enumeration(["widgetReference"]), "widgetID": id], ["type", "widgetID"])
        let sourcePart = object(["type": enumeration(["sourceReference"]), "sourceReference": source], ["type", "sourceReference"])
        let part: [String: Any] = ["anyOf": [textPart, widgetPart, sourcePart]]
        let block = object(["id": id, "type": enumeration(TodayReport.BlockType.allCases.map(\.rawValue)),
                            "parts": array(part, 24)], ["id", "type", "parts"])
        let widget = object(["id": id, "type": enumeration(TodayReport.WidgetType.allCases.map(\.rawValue)),
                             "sourceReference": source], ["id", "type"])
        let insight = object(["id": id, "triggerAt": ["type": "string", "format": "date-time"],
                              "title": string(120), "body": string(2000), "sourceReference": source,
                              "delivery": enumeration(TodayReport.Delivery.allCases.map(\.rawValue))],
                             ["id", "triggerAt", "title", "body", "sourceReference", "delivery"])
        return try JSONSerialization.data(withJSONObject: object([
            "version": ["type": "integer", "enum": [1]], "title": string(120),
            "blocks": array(block, 24), "widgets": array(widget, 12), "scheduledInsights": array(insight, 12)
        ], ["version", "title", "blocks", "widgets", "scheduledInsights"]), options: [.sortedKeys])
    }
}
